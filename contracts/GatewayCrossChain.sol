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

contract GatewayCrossChain is UniversalContract, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public constant WZETA = 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf;
    address public constant UniswapRouter = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address public constant UniswapFactory = 0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c;
    uint32 constant BITCOIN_EDDY = 8332; // chain Id from eddy db
    uint32 constant SOLANA_EDDY = 900; // chain Id from eddy db
    uint32 constant ZETACHAIN = 7000;
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
        uint32 dstChainId;
        bytes receiver; // compatible for btc/sol/evm
        bytes swapDataZ;
        bytes contractAddress; // empty for withdraw, non-empty for withdrawAndCall
        bytes swapDataB;
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
        uint32 dstChainId,
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
    event DODOApproveUpdated(address dodoApprove);
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
        address _dodoApprove,
        uint256 _feePercent,
        uint256 _slippage,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(_gateway);
        EddyTreasurySafe = _EddyTreasurySafe;
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = _dodoApprove;
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

    function setDODOApprove(address _dodoApprove) external onlyOwner {
        DODOApprove = _dodoApprove;
        emit DODOApproveUpdated(_dodoApprove);
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
                revertMessage: bytes.concat(externalId, bytes20(evmWalletAddress)),
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
                revertMessage: bytes.concat(externalId, bytes20(sender)),
                onRevertGasLimit: gasLimit
            })
        );
    }

    function decodeMessage(bytes calldata message) internal pure returns (DecodedMessage memory) {
        require(message.length >= 24, "Invalid message length");
        // dest chainId + targetZRC20 address = 4 + 20 = 24 bytes
        uint32 chainId = BytesHelperLib.bytesToUint32(message, 0); // 4
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); // 20

        (bytes memory receiver, bytes memory swapDataZ, bytes memory contractAddress, bytes memory swapDataB)
            = abi.decode(message[24:], (bytes, bytes, bytes, bytes)); 

        return DecodedMessage({
            targetZRC20: targetZRC20,
            dstChainId: chainId,
            receiver: receiver,
            swapDataZ: swapDataZ,
            contractAddress: contractAddress,
            swapDataB: swapDataB
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

    function _handleBTCCase(
        bytes32 externalId,
        address evmWalletAddress,
        address zrc20,
        uint256 amount,
        DecodedMessage memory decoded,
        uint256 platformFeesForTx
    ) internal {
        bytes memory recipientAddressBech32 = decoded.receiver;
        // swap
        IZRC20(zrc20).approve(DODOApprove, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(decoded.swapDataZ); // swap on zetachain
        if(!success) {
            revert RouteProxyCallFailed();
        } 
        uint256 outputAmount = abi.decode(returnData, (uint256));

        (, uint256 gasFee) = IZRC20(decoded.targetZRC20).withdrawGasFee();
        if(outputAmount < gasFee) revert NotEnoughToPayGasFee();
        IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);
        withdraw(
            externalId,
            recipientAddressBech32,
            decoded.targetZRC20,
            outputAmount - gasFee
        );

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            externalId,
            decoded.dstChainId,
            zrc20,
            decoded.targetZRC20,
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
        uint256 amount,
        DecodedMessage memory decoded,
        uint256 platformFeesForTx
    ) internal {
        bytes memory recipientAddressBech32 = decoded.receiver;

        // swap
        IZRC20(zrc20).approve(DODOApprove, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(decoded.swapDataZ); // swap on zetachain
        if (!success) {
            revert RouteProxyCallFailed();
        } 
        uint256 outputAmount = abi.decode(returnData, (uint256));
        (address gasZRC20, uint256 gasFee) = IZRC20(decoded.targetZRC20).withdrawGasFee();

        uint256 amountAfterGasFees;
        if(decoded.targetZRC20 == gasZRC20) {
            if(gasFee >= outputAmount) revert NotEnoughToPayGasFee();
            IZRC20(decoded.targetZRC20).approve(address(gateway), outputAmount + gasFee);
            amountAfterGasFees = outputAmount - gasFee;

            if(decoded.contractAddress.length == 0) {
                withdraw(
                    externalId,
                    recipientAddressBech32,
                    decoded.targetZRC20,
                    amountAfterGasFees
                );
            } else {
                withdrawAndCall(
                    externalId,
                    decoded.contractAddress,
                    decoded.targetZRC20,
                    amountAfterGasFees,
                    evmWalletAddress,
                    decoded.swapDataB
                );
            }
        } else {
            // swap partial output amount to gasZRC20
            amountAfterGasFees = _swapAndSendERC20Tokens(
                externalId,
                decoded.targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                decoded.contractAddress,
                decoded.swapDataB
            );
        }

        address _evmWalletAddress = evmWalletAddress;
        emit EddyCrossChainSwap(
            externalId,
            decoded.dstChainId,
            zrc20,
            decoded.targetZRC20,
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
        address evmWalletAddress = (decoded.dstChainId == BITCOIN_EDDY || decoded.dstChainId == SOLANA_EDDY)
            ? context.sender
            : address(uint160(bytes20(decoded.receiver)));

        // Transfer platform fees
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%
        amount = amount - platformFeesForTx;

        (address gasZRC20, uint256 gasFee) = (decoded.contractAddress.length == 0)
            ? IZRC20(decoded.targetZRC20).withdrawGasFee() 
            : IZRC20(decoded.targetZRC20).withdrawGasFeeWithGasLimit(gasLimit);

        if(decoded.dstChainId == BITCOIN_EDDY) {
            // to Bitcoin
            _handleBTCCase(
                externalId,
                evmWalletAddress,
                zrc20,
                amount,
                decoded,
                platformFeesForTx
            );
        } else if(decoded.dstChainId == SOLANA_EDDY) {
            // to Solana
            _handleSolanaCase(
                externalId,
                evmWalletAddress,
                zrc20,
                amount,
                decoded,
                platformFeesForTx
            );
        } else {
            // EVM to EVM
            // swap
            IZRC20(zrc20).approve(DODOApprove, amount);
            (bool success, bytes memory returnData) = DODORouteProxy.call(decoded.swapDataZ); // swap on zetachain
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
                        decoded.swapDataB
                    );
                }
                emit EddyCrossChainSwap(
                    externalId,
                    decoded.dstChainId,
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
                    decoded.swapDataB
                );
                emit EddyCrossChainSwap(
                    externalId,
                    decoded.dstChainId,
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
        bytes32 externalId = bytes32(context.revertMessage[0:32]);
        address sender = address(uint160(bytes20(context.revertMessage[32:])));
        TransferHelper.safeTransfer(context.asset, sender, context.amount);
        
        emit EddyCrossChainSwapRevert(
            externalId,
            context.asset,
            context.amount,
            sender
        );
    }

    function onAbort(AbortContext calldata abortContext) external onlyGateway {
        bytes32 externalId = bytes32(abortContext.revertMessage[0:32]);
        address sender = address(uint160(bytes20(abortContext.revertMessage[32:])));
        TransferHelper.safeTransfer(abortContext.asset, sender, abortContext.amount);
        
        emit EddyCrossChainSwapRevert(
            externalId,
            abortContext.asset,
            abortContext.amount,
            sender
        );
    }
}