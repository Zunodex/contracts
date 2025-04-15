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
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {BytesHelperLib} from "./libraries/BytesHelperLib.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IDODORouteProxy} from "./interfaces/IDODORouteProxy.sol";

contract GatewayTransferNative is UniversalContract, Initializable, OwnableUpgradeable, UUPSUpgradeable {
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

    struct DecodedNativeMessage {
        address receiver;
        address targetZRC20;
        bytes swapData;
    }

    struct DecodedMessage {
        address targetZRC20;
        bool isTargetZRC20; // true: withdraw, false: withdrawAndCall
        uint32 destChainId;
        bytes swapData;
        bytes contractAddress; // withdrawAndCall target
        bytes crossChainSwapData;
    }

    error Unauthorized();
    error RouteProxyCallFailed();
    error NotEnoughToPayGasFee();
    error IdenticalAddresses();
    error ZeroAddress();

    event EddyCrossChainSwap(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );
    event GatewayUpdated(address gateway);
    event FeePercentUpdated(uint256 feePercent);
    event DodoRouteProxyUpdated(address dodoRouteProxy);
    event EddyTreasurySafeUpdated(address EddyTreasurySafe);

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        uint256 _slippage
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(_gateway);
        EddyTreasurySafe = _EddyTreasurySafe;
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = IDODORouteProxy(_dodoRouteProxy)._DODO_APPROVE_PROXY_();
        feePercent = _feePercent;
        slippage = _slippage;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDodoRouteProxy(address _dodoRouteProxy) external onlyOwner {
        DODORouteProxy = _dodoRouteProxy;
        emit DodoRouteProxyUpdated(_dodoRouteProxy);
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

    // function setUniswapRouter(address _uniswapRouter) external onlyOwner {
    //     UniswapRouter = _uniswapRouter;
    //     UniswapFactory = IUniswapV2Router01(_uniswapRouter).factory();
    // }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
        bytes memory bech32Bytes = new bytes(44);
        for (uint i = 0; i < 44; i++) {
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
    
    function decodeNativeMessage(
        bytes calldata message
    ) internal pure returns (DecodedNativeMessage memory decodedMessage) {
        // 20 bytes(evmAddress) + 20 bytes(targetZRC20) + bytes(swapData)
        address receiver = BytesHelperLib.bytesToAddress(message, 0); // 20
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 20); // 40
        bytes memory swapData = abi.decode(message[40:], (bytes)); 
        decodedMessage = DecodedNativeMessage({
            receiver: receiver,
            targetZRC20: targetZRC20,
            swapData: swapData
        });
    }

    function decodeMessage(bytes calldata message) internal pure returns (DecodedMessage memory) {
        // dest chainId + targetZRC20 address = 4 + 20 = 24
        uint32 chainId = BytesHelperLib.bytesToUint32(message, 0); // 4
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); // 20

        bool isTargetZRC20;
        bytes memory swapData = bytes("");
        bytes memory contractAddress = bytes("");
        bytes memory crossChainSwapData = bytes("");
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
            // 24 bytes + 20 bytes(evmAddress) + 32 bytes(isTargetZRC20) 
            // bytes(swapData) + 20 bytes(contractAddress) + bytes(crossChainSwapData)
            isTargetZRC20 = abi.decode(message[44:76], (bool));
            (swapData, contractAddress, crossChainSwapData) = abi.decode(
                message[76:], (bytes, bytes, bytes)); 
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
            isTargetZRC20: isTargetZRC20,
            destChainId: chainId,
            swapData: swapData,
            contractAddress: contractAddress,
            crossChainSwapData: crossChainSwapData
        });
    }

    function getEvmAddress(bytes calldata message, uint32 chainId) internal view returns(address evmWalletAddress) {
        if (chainId == BITCOIN_EDDY || chainId == SOLANA_EDDY) {
            evmWalletAddress = msg.sender;
        } else {
            evmWalletAddress = BytesHelperLib.bytesToAddress(message, 24);
        }
    }

    function withdrawAndCall(
        bytes memory contractAddress,
        address zrc20,
        address targetZRC20,
        uint256 outputAmount,
        address evmWalletAddress,
        bytes memory swapData
    ) public {
        gateway.withdrawAndCall(
            contractAddress,
            outputAmount,
            targetZRC20,
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

    function _swapAndSendERC20Tokens(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
        uint256 targetAmount,
        address inputToken,
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
                recipient,
                inputToken,
                targetZRC20,
                targetAmount - amounts[0]
            );
        } else {
            withdrawAndCall(
                contractAddress,
                inputToken,
                targetZRC20,
                targetAmount - amounts[0],
                abi.decode(recipient, (address)),
                crossChainSwapData
            );
        }
        
        amountsOut = targetAmount - amounts[0];
    }

    function _handleBTCCase(
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
        uint256 outputAmount;
        if(swapData.length == 0) {
            outputAmount = amount;
        } else {
            IZRC20(zrc20).approve(DODORouteProxy, amount);
            (bool success, bytes memory returnData) = DODORouteProxy.call(swapData); // swap on zetachain
            if(!success) {
                revert RouteProxyCallFailed();
            } 
            outputAmount = abi.decode(returnData, (uint256));
        }
        
        (, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();
        if(outputAmount < gasFee) revert NotEnoughToPayGasFee();
        IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee);
        withdraw(
            recipientAddressBech32,
            zrc20,
            targetZRC20,
            outputAmount - gasFee
        );

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            zrc20,
            targetZRC20,
            amount,
            outputAmount - gasFee,
            _evmWalletAddress,
            platformFeesForTx
        );
    }

    function _handleSolanaCase(
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        bytes memory swapData,
        bytes calldata message,
        uint256 platformFeesForTx
    ) internal {
        address _zrc20 = zrc20;
        bytes memory recipientAddressBech32 = bytesToSolana(message, 24);
        bytes memory contractAddress = abi.decode(message[132:164], (bytes));
        bytes memory crossChainSwapData = abi.decode(message[164:196], (bytes));

        // swap
        uint256 outputAmount;
        if(swapData.length == 0) {
            outputAmount = amount;
        } else {
            IZRC20(zrc20).approve(DODORouteProxy, amount);
            (bool success, bytes memory returnData) = DODORouteProxy.call(swapData); // swap on zetachain
            if(!success) {
                revert RouteProxyCallFailed();
            } 
            outputAmount = abi.decode(returnData, (uint256));
        }
        (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();

        uint256 amountAfterGasFees;
        if(targetZRC20 == gasZRC20) {
            if(gasFee >= outputAmount) revert NotEnoughToPayGasFee();
            IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee);
            amountAfterGasFees = outputAmount - gasFee;

            if(contractAddress.length == 0) {
                withdraw(
                    recipientAddressBech32,
                    _zrc20,
                    targetZRC20,
                    amountAfterGasFees
                );
            } else {
                withdrawAndCall(
                    contractAddress,
                    _zrc20,
                    targetZRC20,
                    amountAfterGasFees,
                    evmWalletAddress,
                    crossChainSwapData
                );
            }
        } else {
            // swap partial output amount to gasZRC20
            amountAfterGasFees = _swapAndSendERC20Tokens(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                _zrc20,
                contractAddress,
                crossChainSwapData
            );
        }

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            zrc20,
            targetZRC20,
            amount,
            amountAfterGasFees,
            _evmWalletAddress, // context.sender
            platformFeesForTx
        );
    }

    function _handleFeeTransfer(
        address zrc20,
        uint256 amount
    ) internal returns (uint256 platformFeesForTx) {
        platformFeesForTx = (amount * feePercent) / 1000; // platformFee = 5 <> 0.5%
        TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, platformFeesForTx);
    }

    /**
     * @notice Function called by the gateway to execute the cross-chain swap
     * @param context Message context
     * @param zrc20 ZRC20 token address
     * @param amount Amount
     * @param message Message
     * @dev Only the gateway can call this function
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
        // Decode the message
        DecodedNativeMessage memory decoded = decodeNativeMessage(message);

        // Fee for platform
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%

        if (decoded.targetZRC20 == zrc20) {
            // same token
            TransferHelper.safeTransfer(
                decoded.targetZRC20,
                decoded.receiver,
                amount - platformFeesForTx
            );

            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                amount,
                amount - platformFeesForTx,
                decoded.receiver,
                platformFeesForTx
            );
        } else {
            // swap
            IZRC20(zrc20).approve(DODORouteProxy, amount);
            (bool success, bytes memory returnData) = DODORouteProxy.call(
                decoded.swapData
            ); // swap on zetachain
            if (!success) {
                revert RouteProxyCallFailed();
            }
            uint256 outputAmount = abi.decode(returnData, (uint256));

            if (decoded.targetZRC20 == WZETA) {
                // withdraw WZETA to get Zeta in 1:1 ratio
                IWETH9(WZETA).withdraw(outputAmount);
                // transfer wzeta
                payable(decoded.receiver).transfer(outputAmount);
            } else {
                TransferHelper.safeTransfer(
                    decoded.targetZRC20,
                    decoded.receiver,
                    outputAmount
                );
            }

            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                amount,
                outputAmount,
                decoded.receiver,
                platformFeesForTx
            );
        }
    }

    function withdrawToNativeChain(
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external {
        require(IZRC20(zrc20).transferFrom(msg.sender, address(this), amount), "INSUFFICIENT ALLOWANCE: TRANSFER FROM FAILED");
        DecodedMessage memory decoded = decodeMessage(message);
        address evmWalletAddress = getEvmAddress(message, decoded.destChainId);

        // Transfer platform fees
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%
        amount = amount - platformFeesForTx;

        address tokenToUse = decoded.targetZRC20;
        (address gasZRC20, uint256 gasFee) = decoded.isTargetZRC20
            ? IZRC20(tokenToUse).withdrawGasFee() 
            : IZRC20(tokenToUse).withdrawGasFeeWithGasLimit(gasLimit);

        if(decoded.destChainId == BITCOIN_EDDY) {
            // EVM to Bitcoin
            _handleBTCCase(
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                decoded.swapData,
                message,
                platformFeesForTx
            );
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
            uint256 outputAmount;
            if(decoded.swapData.length == 0) {
                outputAmount = amount;
            } else {
                IZRC20(zrc20).approve(DODORouteProxy, amount);
                (bool success, bytes memory returnData) = DODORouteProxy.call(decoded.swapData); // swap on zetachain
                if(!success) {
                    revert RouteProxyCallFailed();
                } 
                outputAmount = abi.decode(returnData, (uint256));
            }

            if(decoded.targetZRC20 == gasZRC20) {
                if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);

                if(decoded.contractAddress.length == 0) {
                    // withdraw
                    withdraw(
                        abi.encodePacked(evmWalletAddress),
                        zrc20,
                        decoded.targetZRC20,
                        outputAmount - gasFee
                    );
                } else {
                    // withdraw and call
                    withdrawAndCall(
                        decoded.contractAddress,
                        zrc20,
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
                uint256 amountsOutTarget = _swapAndSendERC20Tokens(
                    decoded.targetZRC20,
                    gasZRC20,
                    gasFee,
                    abi.encode(evmWalletAddress),
                    outputAmount,
                    zrc20,
                    decoded.contractAddress,
                    decoded.crossChainSwapData
                );
                emit EddyCrossChainSwap(
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
        (address senderEvmAddress, address zrc20) = abi.decode(context.revertMessage, (address, address));

        address[] memory path = getPathForTokens(context.asset, zrc20);
        uint[] memory amountsQuote = UniswapV2Library.getAmountsOut(
                UniswapFactory,
                context.amount,
                path
            );

        uint amountOutMin = (amountsQuote[amountsQuote.length - 1]) - (slippage * amountsQuote[amountsQuote.length - 1]) / 1000;
        IZRC20(zrc20).approve(UniswapRouter, context.amount);

        uint256[] memory amounts = IUniswapV2Router01(UniswapRouter)
            .swapExactTokensForTokens(
                context.amount,
                amountOutMin,
                path,
                address(this),
                block.timestamp + MAX_DEADLINE
            );
        
        TransferHelper.safeTransfer(zrc20, senderEvmAddress, amounts[path.length - 1]);
    }

    receive() external payable {}

    fallback() external payable {}
}