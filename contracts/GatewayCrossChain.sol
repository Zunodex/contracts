// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {BytesHelperLib} from "./libraries/BytesHelperLib.sol";

contract GatewayCrossChain {
    uint32 constant BITCOIN_EDDY = 9999; // chain Id from eddy db
    uint32 constant SOLANA_EDDY = 88888; // chain Id from eddy db
    uint256 constant BITCOIN = 8332;
    uint256 constant ZETACHAIN = 7000;

    address DODO_ROUTE_PROXY;
    address EddyTreasurySafe; // TODO:
    uint256 public feePercent;
    uint256 public gasLimit;

    GatewayZEVM public gateway;

    struct DecodedMessage {
        address targetZRC20;
        bool isTargetZRC20;
        uint32 destChainId;
        bytes swapData;
        address contractAddress; // withdrawAndCall target
        bytes crossChainSwapData;
    }

    error Unauthorized();
    error RouteProxyCallFailed();
    error NotEnoughToPayGasFee();

    event EddyCrossChainSwap(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );
    
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /**
     * @notice Function to decode solana wallet address
     * @param data Data 
     * @param offset Offset
     */
    function bytesToSolana(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bytes memory) {
        bytes memory bech32Bytes = new bytes(44);
        for (uint i = 0; i < 44; i++) {
            bech32Bytes[i] = data[i + offset];
        }
        return bech32Bytes;
    }

    function getEvmAddress(
        MessageContext calldata context,
        bytes calldata message, 
        uint32 chainId
    ) internal pure returns (address evmWalletAddress) {
        if (chainId == BITCOIN_EDDY || chainId == SOLANA_EDDY) {
            evmWalletAddress = context.sender;
        } else {
            evmWalletAddress = BytesHelperLib.bytesToAddress(message, 24);
        }
    }

    function withdrawAndCall(
        bytes memory contractAddress,
        address zrc20,
        address tokenToUse,
        address targetZRC20,
        uint256 outputAmount,
        address evmWalletAddress,
        bytes memory swapData
    ) private {
        gateway.withdrawAndCall(
            contractAddress,
            outputAmount,
            tokenToUse,
            swapData,
            CallOptions({
                isArbitraryCall: true,
                gasLimit: gasLimit
            }),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(evmWalletAddress, zrc20),
                onRevertGasLimit: gasLimit
            })
        );
    }

    /**
     * @notice - Function to withdraw using gateway
     * @param sender Sender address
     * @param inputToken input token address
     * @param outputToken output token address
     * @param amount amount to withdraw
     */
    function withdraw(
        bytes memory sender,
        address inputToken,
        address outputToken,
        uint256 amount
    ) public {
        gateway.withdraw(
            sender,
            amount,
            outputToken,
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(sender, inputToken),
                onRevertGasLimit: gasLimit
            })
        );
    }

    function decodeMessage(bytes calldata message) internal pure returns (DecodedMessage memory) {
        // dest chainId + targetZRC20 address = 4 + 20 = 24
        uint32 chainId = BytesHelperLib.bytesToUint32(message, 0); // 4
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); // 20

        bool isTargetZRC20;
        bytes memory swapData = bytes("");
        if(chainId == BITCOIN_EDDY) {
            // 24 bytes + 42 bytes(bechdata) + 32 bytes(isTargetZRC20) + 32 bytes(swapData)
            require(message.length >= 98, "Invalid message length for BTC");
            isTargetZRC20 = abi.decode(message[66:98], (bool)); 
            swapData = abi.decode(message[98:130], (bytes));
        } else if(chainId == SOLANA_EDDY) {
            // 24 bytes + 44 bytes(bechdata) + 32 bytes(isTargetZRC20) + 32 bytes(swapData)
            require(message.length >= 100, "Invalid message length for SOLANA");
            isTargetZRC20 = abi.decode(message[68:100], (bool));
            swapData = abi.decode(message[100:132], (bytes));
        } else {
            // 24 bytes + 20 bytes(evmAddress) + 32 bytes(isTargetZRC20) + 32 bytes(swapData)
            isTargetZRC20 = abi.decode(message[44:76], (bool));
            swapData = abi.decode(message[76:108], (bytes)); 
        }

        address contractAddress = address(0);
        bytes memory crossChainSwapData = bytes("");
        if(isTargetZRC20 == false && message.length > 108) {
            // 108 bytes + 20 bytes(contractAddress) + 32 bytes(crossChainSwapData)
            contractAddress = BytesHelperLib.bytesToAddress(message, 108);
            crossChainSwapData = abi.decode(message[140:], (bytes));
        }

        return DecodedMessage({
            targetZRC20: targetZRC20,
            isTargetZRC20: isTargetZRC20,
            destChainId: chainId,
            swapData: swapData,
            contractAddress: contractAddress,
            crossChainSwapData: crossChainSwapData
        });
    }

    function _handleFeeTransfer(address zrc20, uint256 amount) internal returns (uint256 platformFeesForTx) {
        platformFeesForTx = (amount * feePercent) / 1000; // platformFee = 5 <> 0.5%
        TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, platformFeesForTx);
    }

    function _swapAndSendERC20Tokens(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
        uint256 targetAmount,
        address inputToken,
        bool isV3Swap
    ) internal returns(uint256 amountsOut) {}

    function _handleSolanaCase(
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        bytes memory swapData,
        bytes memory message,
        uint256 platformFeesForTx
    ) internal {
        uint256 swapAmount = amount - platformFeesForTx;
        bytes memory recipientAddressBech32 = bytesToSolana(message, 24);

        // swap
        IZRC20(zrc20).approve(DODO_ROUTE_PROXY, amount);
        (bool success, bytes memory returnData) = DODO_ROUTE_PROXY.call(swapData); // swap on zetachain
        if (!success) {
            revert RouteProxyCallFailed();
        } 
        uint256 outputAmount = abi.decode(returnData, (uint256));
        (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();

        uint256 amountAfterGasFees;
        if(targetZRC20 == gasZRC20) {
            if(gasFee >= outputAmount) revert NotEnoughToPayGasFee();
            IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee);
            amountAfterGasFees = outputAmount - gasFee;
            withdraw(
                recipientAddressBech32,
                zrc20,
                targetZRC20,
                amountAfterGasFees
            );
        } else {
            // swap partial output amount to gasZRC20
            amountAfterGasFees = _swapAndSendERC20Tokens(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                zrc20,
                false
            );
        }

        emit EddyCrossChainSwap(
            zrc20,
            targetZRC20,
            amount,
            amountAfterGasFees,
            evmWalletAddress, // context.sender
            platformFeesForTx
        );
    }

    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external onlyGateway {
        DecodedMessage memory decoded = decodeMessage(message);

        // Check if the message is from Bitcoin to Solana
        bool btcToSolana = (context.chainID == BITCOIN && decoded.destChainId == SOLANA_EDDY);
        address evmWalletAddress = getEvmAddress(context, message, decoded.destChainId);

        // Transfer platform fees
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%

        address tokenToUse = decoded.targetZRC20;
        (address gasZRC20, uint256 gasFee) = decoded.isTargetZRC20
            ? IZRC20(tokenToUse).withdrawGasFee() 
            : IZRC20(tokenToUse).withdrawGasFeeWithGasLimit(gasLimit);

        if(btcToSolana) {
            // Bitcoin to Solana
        } else if(decoded.destChainId == BITCOIN_EDDY) {
            // EVM to Bitcoin
        } else if(decoded.destChainId == SOLANA_EDDY) {
            // EVM to Solana
            _handleSolanaCase(
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                decoded.swapData,
                message,
                platformFeesForTx
            );
        } else {
            // EVM to EVM
            // swap
            IZRC20(zrc20).approve(DODO_ROUTE_PROXY, amount);
            (bool success, bytes memory returnData) = DODO_ROUTE_PROXY.call(decoded.swapData); // swap on zetachain
            if (!success) {
                revert RouteProxyCallFailed();
            } 
            uint256 outputAmount = abi.decode(returnData, (uint256));

            if(decoded.targetZRC20 == gasZRC20) {
                if (decoded.isTargetZRC20) {
                    IZRC20(decoded.targetZRC20).transfer(evmWalletAddress, outputAmount);
                } else if(decoded.contractAddress == address(0)) {
                    // withdraw
                    if(gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                    IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);
                    withdraw(
                        abi.encodePacked(evmWalletAddress),
                        zrc20,
                        decoded.targetZRC20,
                        outputAmount - gasFee
                    );
                } else {
                    // withdraw and call
                    if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                    IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);
                    withdrawAndCall(
                        abi.encodePacked(decoded.contractAddress),
                        zrc20,
                        tokenToUse,
                        decoded.targetZRC20,
                        outputAmount - gasFee,
                        evmWalletAddress,
                        decoded.crossChainSwapData
                    );
                }
                emit EddyCrossChainSwap(
                    zrc20,
                    decoded.targetZRC20,
                    amount,
                    outputAmount - gasFee,
                    evmWalletAddress,
                    platformFeesForTx
                );
            } else {
                // TODO: 
                // uint256 amountsOutTarget = _swapAndSendERC20Tokens(
                //     params.targetZRC20,
                //     params.gasZRC20CC,
                //     params.gasFeeCC,
                //     abi.encodePacked(params.sender),
                //     params.targetAmount,
                //     params.inputToken,
                //     decoded.isV3Swap
                // );
            }
        }
    }
}