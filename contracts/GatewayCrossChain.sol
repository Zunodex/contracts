// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {UniversalContract} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {BytesHelperLib} from "./libraries/BytesHelperLib.sol";
import {IDODORouteProxy} from "./interfaces/IDODORouteProxy.sol";

contract GatewayCrossChain is UniversalContract, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public constant WZETA = 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf;
    address public constant UniswapRouter = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address public constant UniswapFactory = 0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c;
    uint32 constant BITCOIN_EDDY = 8332; // chain Id from eddy db
    uint32 constant SOLANA_EDDY = 900; // chain Id from eddy db
    uint256 constant ZETACHAIN = 7000;
    uint256 constant MAX_DEADLINE = 200;
    address private EddyTreasurySafe;
    address public DODORouteProxy;
    address public DODOApprove;
    uint256 public feePercent;
    uint256 public slippage;
    uint256 public gasLimit;

    GatewayZEVM public gateway;

    struct DecodedMessage {
        address targetZRC20;
        uint32 destChainId;
        bytes swapData;
        bytes contractAddress; // empty for withdraw, non-empty for withdrawAndCall
        bytes crossChainSwapData;
    }

    error Unauthorized();
    error RouteProxyCallFailed();
    error NotEnoughToPayGasFee();
    error IdenticalAddresses();
    error ZeroAddress();

    event EddyCrossChainSwapRevert(
        bytes32 externalId,
        address token,
        uint256 amount,
        address walletAddress
    );
    event EddyCrossChainSwap(
        bytes32 externalId,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );
    event GatewayUpdated(address gateway);
    event FeePercentUpdated(uint256 feePercent);
    event DODORouteProxyUpdated(address dodoRouteProxy);
    event EddyTreasurySafeUpdated(address EddyTreasurySafe);
    
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

        /**
     * @dev Initialize the contract
     * @param _gateway Gateway contract address
     * @param _EddyTreasurySafe Address of the platform fee wallets
     * @param _dodoRouteProxy Address of the DODORouteProxy
     * @param _feePercent Platform fee percentage in basis points (e.g., 10 = 1%)
     */
    function initialize(
        address payable _gateway,
        address _EddyTreasurySafe,
        address _dodoRouteProxy,
        uint256 _feePercent,
        uint256 _slippage,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(_gateway);
        EddyTreasurySafe = _EddyTreasurySafe;
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = IDODORouteProxy(_dodoRouteProxy)._DODO_APPROVE_PROXY_();
        feePercent = _feePercent;
        slippage = _slippage;
        gasLimit = _gasLimit;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDODORouteProxy(address _dodoRouteProxy) external onlyOwner {
        DODORouteProxy = _dodoRouteProxy;
        emit DODORouteProxyUpdated(_dodoRouteProxy);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    function setGateway(address payable _gateway) external onlyOwner {
        gateway = GatewayZEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function setEddyTreasurySafe(address _EddyTreasurySafe) external onlyOwner {
        EddyTreasurySafe = _EddyTreasurySafe;
        emit EddyTreasurySafeUpdated(_EddyTreasurySafe);
    }

    // ============== Uniswap Helper ================ 

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
    }

    function uniswapv2PairFor(
        address factory,
        address tokenA,
        address tokenB
    ) public pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

     function _existsPairPool(
        address uniswapV2Factory,
        address zrc20A,
        address zrc20B
    ) internal view returns (bool) {
        address uniswapPool = uniswapv2PairFor(
            uniswapV2Factory,
            zrc20A,
            zrc20B
        );
        return
            IZRC20(zrc20A).balanceOf(uniswapPool) > 0 &&
            IZRC20(zrc20B).balanceOf(uniswapPool) > 0;
    }

    function getPathForTokens(
        address zrc20,
        address targetZRC20
    ) internal view returns(address[] memory path) {
        bool existsPairPool = _existsPairPool(
            UniswapFactory,
            zrc20,
            targetZRC20
        );

        if (existsPairPool) {
            path = new address[](2);
            path[0] = zrc20;
            path[1] = targetZRC20;
        } else {
            path = new address[](3);
            path[0] = zrc20;
            path[1] = WZETA;
            path[2] = targetZRC20;
        }
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
        bytes memory bech32Bytes = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            bech32Bytes[i] = data[i + offset];
        }
        return bech32Bytes;
    }

    function bytesToBTC(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bytes memory) {
        bytes memory bech32Bytes = new bytes(42);
        for (uint i = 0; i < 42; i++) {
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
        bytes32 externalId,
        bytes memory contractAddress,
        address targetZRC20,
        uint256 outputAmount,
        address evmWalletAddress,
        bytes memory swapData
    ) public {
        bytes memory message = abi.encode(externalId, evmWalletAddress, outputAmount, swapData);
        gateway.withdrawAndCall(
            contractAddress,
            outputAmount,
            targetZRC20,
            message,
            CallOptions({
                isArbitraryCall: false,
                gasLimit: gasLimit
            }),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(externalId, targetZRC20, outputAmount, evmWalletAddress),
                onRevertGasLimit: gasLimit
            })
        );
    }

    /**
     * @notice - Function to withdraw using gateway
     * @param sender Sender address
     * @param outputToken output token address
     * @param amount amount to withdraw
     */
    function withdraw(
        bytes32 externalId,
        bytes memory sender,
        address outputToken,
        uint256 amount
    ) private {
        gateway.withdraw(
            sender,
            amount,
            outputToken,
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(externalId, outputToken, amount, sender),
                onRevertGasLimit: gasLimit
            })
        );
    }

    function decodeMessage(bytes calldata message) internal pure returns (DecodedMessage memory) {
        // dest chainId + targetZRC20 address = 4 + 20 = 24
        uint32 chainId = BytesHelperLib.bytesToUint32(message, 0); // 4
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); // 20

        bytes memory swapData = bytes("");
        bytes memory contractAddress = bytes("");
        bytes memory crossChainSwapData = bytes("");
        if(chainId == BITCOIN_EDDY) {
            // 24 bytes + 42 bytes(btcAddress)
            // bytes(swapData)
            require(message.length >= 66, "Invalid message length for BTC");
            swapData = abi.decode(message[66:], (bytes));
        } else if(chainId == SOLANA_EDDY) {
            // 24 bytes + 32 bytes(solAddress)
            // bytes(swapData) + 20 bytes(contractAddress) + bytes(crossChainSwapData)
            require(message.length >= 56, "Invalid message length for SOLANA");
            (swapData, contractAddress, crossChainSwapData) = abi.decode(
                message[56:], (bytes, bytes, bytes)); 
        } else {
            // 24 bytes + 20 bytes(evmAddress)
            // bytes(swapData) + 20 bytes(contractAddress) + bytes(crossChainSwapData)
            (swapData, contractAddress, crossChainSwapData) = abi.decode(
                message[44:], (bytes, bytes, bytes)); 
        }

        // bytes memory contractAddress = bytes("");
        // bytes memory crossChainSwapData = bytes("");
        // if(isTargetZRC20 == false) {
        //     if(chainId == SOLANA_EDDY) {
        //         // to SOLANA
        //         // 132 bytes + 32 bytes(contractAddress) + 32 bytes(crossChainSwapData)
        //         contractAddress = abi.decode(message[132:164], (bytes));
        //         crossChainSwapData = abi.decode(message[164:], (bytes));
        //     } else {
        //         // to EVM
        //         // 108 bytes + 20 bytes(contractAddress) + 32 bytes(crossChainSwapData)
        //         contractAddress = abi.decode(message[108:128], (bytes));
        //         crossChainSwapData = abi.decode(message[128:], (bytes));
        //     }
        // }

        return DecodedMessage({
            targetZRC20: targetZRC20,
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
        bytes32 externalId,
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
        uint256 targetAmount,
        bytes memory contractAddress,
        bytes memory crossChainSwapData
    ) internal returns(uint256 amountsOut) {
        // Get amountOut for Input gasToken
        uint[] memory amountsQuote = UniswapV2Library.getAmountsIn(
            UniswapFactory,
            gasFee,
            getPathForTokens(targetZRC20, gasZRC20) // [targetZRC, gasZRC] or [targetZRC, WZETA, gasZRC]
        );

        uint amountInMax = (amountsQuote[0]) + (slippage * amountsQuote[0]) / 1000;
        IZRC20(targetZRC20).approve(UniswapRouter, amountInMax);

        // Swap TargetZRC20 to gasZRC20
        uint[] memory amounts = IUniswapV2Router01(UniswapRouter)
            .swapTokensForExactTokens(
                gasFee, // Amount of gas token required
                amountInMax,
                getPathForTokens(targetZRC20, gasZRC20), // path[0] = targetZRC20, path[1] = gasZRC20
                address(this),
                block.timestamp + MAX_DEADLINE
        );

        require(IZRC20(gasZRC20).balanceOf(address(this)) >= gasFee, "INSUFFICIENT_GAS_FOR_WITHDRAW");
        require(targetAmount - amountInMax > 0, "INSUFFICIENT_AMOUNT_FOR_WITHDRAW");

        IZRC20(gasZRC20).approve(address(gateway), gasFee);
        IZRC20(targetZRC20).approve(address(gateway), targetAmount - amounts[0]);

        if(contractAddress.length == 0) {
            withdraw(
                externalId,
                recipient,
                targetZRC20,
                targetAmount - amounts[0]
            );
        } else {
            withdrawAndCall(
                externalId,
                contractAddress,
                targetZRC20,
                targetAmount - amounts[0],
                address(bytes20(recipient)),
                crossChainSwapData
            );
        }
        
        amountsOut = targetAmount - amounts[0];
    }

    // function _handleBTCToSolanaCase(
    //     address evmWalletAddress,
    //     address zrc20,
    //     address targetZRC20,
    //     uint256 amount,
    //     bytes memory swapData,
    //     bytes calldata message,
    //     uint256 platformFeesForTx
    // ) internal {
    //     address _zrc20 = zrc20;
    //     bytes memory recipientAddressBech32 = bytesToSolana(message, 24);
    //     bytes memory contractAddress = abi.decode(message[132:164], (bytes));
    //     bytes memory crossChainSwapData = abi.decode(message[164:196], (bytes));
        
    //     // swap
    //     IZRC20(_zrc20).approve(DodoRouteProxy, amount);
    //     (bool success, bytes memory returnData) = DodoRouteProxy.call(swapData); // swap on zetachain
    //     if (!success) {
    //         revert RouteProxyCallFailed();
    //     } 
    //     uint256 outputAmount = abi.decode(returnData, (uint256));
    //     (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();

    //     uint256 amountAfterGasFees;
    //     if(targetZRC20 == gasZRC20) {
    //         if(gasFee >= outputAmount) revert NotEnoughToPayGasFee();
    //         IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee);
    //         amountAfterGasFees = outputAmount - gasFee;
            
    //         if(contractAddress.length == 0) {
    //             withdraw(
    //                 recipientAddressBech32,
    //                 _zrc20,
    //                 targetZRC20,
    //                 amountAfterGasFees
    //             );
    //         } else {
    //             withdrawAndCall(
    //                 contractAddress,
    //                 _zrc20,
    //                 targetZRC20,
    //                 amountAfterGasFees,
    //                 evmWalletAddress,
    //                 crossChainSwapData
    //             );
    //         }
    //     } else {
    //         // swap partial output amount to gasZRC20
    //         amountAfterGasFees = _swapAndSendERC20Tokens(
    //             targetZRC20,
    //             gasZRC20,
    //             gasFee,
    //             recipientAddressBech32,
    //             outputAmount,
    //             _zrc20,
    //             contractAddress,
    //             crossChainSwapData
    //         );
    //     }
    //     emit EddyCrossChainSwap(
    //         zrc20,
    //         targetZRC20,
    //         amount,
    //         amountAfterGasFees,
    //         evmWalletAddress,
    //         platformFeesForTx
    //     );
    // }

    function _handleBTCCase(
        bytes32 externalId,
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        bytes memory swapData,
        bytes memory message,
        uint256 platformFeesForTx
    ) internal {
        bytes memory recipientAddressBech32 = bytesToBTC(message, 24);
        // swap
        IZRC20(zrc20).approve(DODOApprove, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(swapData); // swap on zetachain
        if(!success) {
            revert RouteProxyCallFailed();
        } 
        uint256 outputAmount = abi.decode(returnData, (uint256));

        (, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();
        if(outputAmount < gasFee) revert NotEnoughToPayGasFee();
        IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee);
        withdraw(
            externalId,
            recipientAddressBech32,
            targetZRC20,
            outputAmount - gasFee
        );

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            externalId,
            zrc20,
            targetZRC20,
            amount,
            outputAmount - gasFee,
            _evmWalletAddress,
            platformFeesForTx
        );
    }

    function _handleSolanaCase(
        bytes32 externalId,
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        bytes memory swapData,
        bytes memory contractAddress,
        bytes memory crossChainSwapData,
        bytes calldata message,
        uint256 platformFeesForTx
    ) internal {
        bytes memory recipientAddressBech32 = bytesToSolana(message, 24);

        // swap
        IZRC20(zrc20).approve(DODOApprove, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(swapData); // swap on zetachain
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

            if(contractAddress.length == 0) {
                withdraw(
                    externalId,
                    recipientAddressBech32,
                    targetZRC20,
                    amountAfterGasFees
                );
            } else {
                withdrawAndCall(
                    externalId,
                    contractAddress,
                    targetZRC20,
                    amountAfterGasFees,
                    evmWalletAddress,
                    crossChainSwapData
                );
            }
        } else {
            // swap partial output amount to gasZRC20
            amountAfterGasFees = _swapAndSendERC20Tokens(
                externalId,
                targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                contractAddress,
                crossChainSwapData
            );
        }

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            externalId,
            zrc20,
            targetZRC20,
            amount,
            amountAfterGasFees,
            _evmWalletAddress, // context.sender
            platformFeesForTx
        );
    }

    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external onlyGateway {
        // Decode the message
        // 32 bytes(externalId) + bytes message
        (bytes32 externalId) = abi.decode(message[0:32], (bytes32)); 
        bytes calldata _message = message[32:];
        DecodedMessage memory decoded = decodeMessage(_message);
        // Check if the message is from Bitcoin to Solana
        // bool btcToSolana = (context.chainID == uint256(BITCOIN_EDDY) && decoded.destChainId == SOLANA_EDDY);
        address evmWalletAddress = getEvmAddress(context, _message, decoded.destChainId);

        // Transfer platform fees
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%
        amount = amount - platformFeesForTx;

        (address gasZRC20, uint256 gasFee) = (decoded.contractAddress.length == 0)
            ? IZRC20(decoded.targetZRC20).withdrawGasFee() 
            : IZRC20(decoded.targetZRC20).withdrawGasFeeWithGasLimit(gasLimit);

        // if(btcToSolana) {
        //     // Bitcoin to Solana
        //     _handleBTCToSolanaCase(
        //         evmWalletAddress,
        //         zrc20,
        //         decoded.targetZRC20,
        //         amount,
        //         decoded.swapData,
        //         message,
        //         platformFeesForTx
        //     );
        // } else {}
        
        if(decoded.destChainId == BITCOIN_EDDY) {
            // to Bitcoin
            _handleBTCCase(
                externalId,
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                decoded.swapData,
                _message,
                platformFeesForTx
            );
        } else if(decoded.destChainId == SOLANA_EDDY) {
            // to Solana
            _handleSolanaCase(
                externalId,
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                decoded.swapData,
                decoded.contractAddress,
                decoded.crossChainSwapData,
                _message,
                platformFeesForTx
            );
        } else {
            // EVM to EVM
            // swap
            IZRC20(zrc20).approve(DODOApprove, amount);
            (bool success, bytes memory returnData) = DODORouteProxy.call(decoded.swapData); // swap on zetachain
            if (!success) {
                revert RouteProxyCallFailed();
            } 
            uint256 outputAmount = abi.decode(returnData, (uint256));
            if(decoded.targetZRC20 == gasZRC20) {
                if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);

                if(decoded.contractAddress.length == 0) {
                    // withdraw
                    withdraw(
                        externalId,
                        abi.encodePacked(evmWalletAddress),
                        decoded.targetZRC20,
                        outputAmount - gasFee
                    );
                } else {
                    // withdraw and call
                    withdrawAndCall(
                        externalId,
                        decoded.contractAddress,
                        decoded.targetZRC20,
                        outputAmount - gasFee,
                        evmWalletAddress,
                        decoded.crossChainSwapData
                    );
                }
                emit EddyCrossChainSwap(
                    externalId,
                    zrc20,
                    decoded.targetZRC20,
                    amount,
                    outputAmount - gasFee,
                    evmWalletAddress,
                    platformFeesForTx
                );
            } else {
                uint256 amountsOutTarget = _swapAndSendERC20Tokens(
                    externalId,
                    decoded.targetZRC20,
                    gasZRC20,
                    gasFee,
                    abi.encodePacked(evmWalletAddress),
                    outputAmount,
                    decoded.contractAddress,
                    decoded.crossChainSwapData
                );
                emit EddyCrossChainSwap(
                    externalId,
                    zrc20,
                    decoded.targetZRC20,
                    amount,
                    amountsOutTarget,
                    evmWalletAddress,
                    platformFeesForTx
                );
            }
        }
    }

    /**
     * @notice Function called by the gateway to revert the cross-chain swap
     * @param context Revert context
     * @dev Only the gateway can call this function
     */
    function onRevert(RevertContext calldata context) external onlyGateway {
        (bytes32 externalId, address asset, uint256 amount, address sender) 
            = abi.decode(context.revertMessage, (bytes32, address, uint256, address));
        TransferHelper.safeTransfer(asset, sender, amount);
        
        emit EddyCrossChainSwapRevert(
            externalId,
            asset,
            amount,
            sender
        );
    }
}