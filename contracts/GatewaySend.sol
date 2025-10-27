// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayEVM} from "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IDODORouteProxy} from "./interfaces/IDODORouteProxy.sol";
import "./libraries/SwapDataHelperLib.sol";

contract GatewaySend is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public globalNonce;
    uint256 public gasLimit;
    address public DODORouteProxy;
    address public DODOApprove;
    GatewayEVM public gateway;
    
    event EddyCrossChainRevert(
        bytes32 externalId,
        address token,
        uint256 amount,
        address walletAddress
    );
    event EddyCrossChainSend(
        bytes32 externalId,
        uint32 dstChainId,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        bytes payload
    );
    event EddyCrossChainReceive(
        bytes32 externalId,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        bytes payload
    );
    event DODORouteProxyUpdated(address dodoRouteProxy);
    event GatewayUpdated(address gateway);

    error Unauthorized();
    error RouteProxyCallFailed();

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
     * @param _dodoRouteProxy Address of the DODORouteProxy
     */
    function initialize(
        address payable _gateway,
        address _dodoRouteProxy,
        address _dodoApprove,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayEVM(_gateway);
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = _dodoApprove;
        gasLimit = _gasLimit;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDODORouteProxy(address _dodoRouteProxy) external onlyOwner {
        DODORouteProxy = _dodoRouteProxy;
        emit DODORouteProxyUpdated(_dodoRouteProxy);
    }

    function setGateway(address _gateway) external onlyOwner {
        gateway = GatewayEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function concatBytes(bytes32 a, bytes memory b) public pure returns (bytes memory) {
        bytes memory result = new bytes(32 + b.length);
        uint k = 0;
        for (uint i = 0; i < 32; i++) {
            result[k++] = a[i];
        }
        for (uint i = 0; i < b.length; i++) {
            result[k++] = b[i];
        }
        return result;
    }

    function decodePackedMessage(
        bytes calldata message
    ) internal pure returns (
        bytes32 externalId, 
        uint256 outputAmount, 
        bytes calldata receiver, 
        address fromToken, 
        address toToken, 
        bytes calldata swapDataB
    ) {
        uint16 receiverLen;
        uint16 crossChainDataLen;
        bytes calldata crossChainData;

        assembly {
            externalId := calldataload(message.offset) // first 32 bytes
            outputAmount := calldataload(add(message.offset, 32)) // next 32 bytes
            receiverLen := shr(240, calldataload(add(message.offset, 64))) // 2 bytes
            crossChainDataLen := shr(240, calldataload(add(message.offset, 66))) // 2 bytes
        }

        uint offset = 68; // starting point of receiver
        receiver = message[offset : offset + receiverLen];
        offset += receiverLen;
        crossChainData = message[offset : offset + crossChainDataLen];

        (fromToken, toToken, swapDataB) = decodePackedData(crossChainData);
    }

    function decodePackedData(bytes calldata data) internal pure returns (
        address tokenA,
        address tokenB,
        bytes calldata swapDataB
    ) {
        assembly {
            tokenA := shr(96, calldataload(data.offset))
            tokenB := shr(96, calldataload(add(data.offset, 20)))
        }

        if (data.length > 40) {
            swapDataB = data[40:];
        } else {
            swapDataB = data[0:0]; // empty slice
        }
    }

    function _calcExternalId(address sender) internal view returns (bytes32 externalId) {
        externalId = keccak256(abi.encodePacked(
            address(this), 
            sender, 
            globalNonce, 
            block.timestamp,
            block.chainid
        ));
    }

    function _handleETHDeposit(
        address targetContract,
        uint256 amount,
        bytes memory message,
        RevertOptions memory revertOptions
    ) internal {
        gateway.depositAndCall{value: amount}(
            targetContract,
            message,
            revertOptions
        );
    }

    function _handleERC20Deposit(
        address targetContract,
        uint256 amount,
        address asset,
        bytes memory message,
        RevertOptions memory revertOptions
    ) internal {
        TransferHelper.safeApprove(asset, address(gateway), amount);

        gateway.depositAndCall(
            targetContract,
            amount,
            asset,
            message,
            revertOptions
        );
    }

    function _doMixSwap(
        MixSwapParams memory params
    ) internal returns (uint256 outputAmount) {
        if(params.fromToken != _ETH_ADDRESS_) {
            TransferHelper.safeApprove(params.fromToken, DODOApprove, params.fromTokenAmount);
        }

        return IDODORouteProxy(DODORouteProxy).mixSwap{value: msg.value}(
            params.fromToken,
            params.toToken,
            params.fromTokenAmount,
            params.expReturnAmount,
            params.minReturnAmount,
            params.mixAdapters,
            params.mixPairs,
            params.assetTo,
            params.directions,
            params.moreInfo,
            params.feeData,
            params.deadline
        );
    }

    function depositAndCall(
        address fromToken,
        uint256 amount,
        bytes calldata swapData,
        address targetContract,
        address asset,
        uint32 dstChainId,
        bytes calldata payload
    ) public payable {
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);
        bool fromIsETH = (fromToken == _ETH_ADDRESS_);

        // Handle input token
        if(fromIsETH) {
            require(
                msg.value >= amount, 
                "INSUFFICIENT AMOUNT: ETH NOT ENOUGH"
            );
        } else {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, address(this), amount);
        }

        MixSwapParams memory params = SwapDataHelperLib.decodeCompressedMixSwapParams(swapData);
         
        // Swap on DODO Router
        require(
            (fromToken == params.fromToken) && (asset == params.toToken),
            "INVALID_TOKEN_ADDRESS: TOKEN_NOT_MATCH"
        );
        require(
            amount == params.fromTokenAmount,
            "INVALID_TOKEN_AMOUNT: AMOUNT_NOT_MATCH"
        );
        uint256 outputAmount = _doMixSwap(params);

        // Construct message and revert options
        bytes memory message = concatBytes(externalId, payload);
        RevertOptions memory revertOptions = RevertOptions({
            revertAddress: address(this),
            callOnRevert: true,
            abortAddress: targetContract,
            revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
            onRevertGasLimit: gasLimit
        });

        bool toIsETH = (asset == _ETH_ADDRESS_);
        if (toIsETH) {
            _handleETHDeposit(
                targetContract,
                outputAmount,
                message,
                revertOptions
            );
        } else {
            _handleERC20Deposit(
                targetContract,
                outputAmount,
                asset,
                message,
                revertOptions
            );
        }

        emit EddyCrossChainSend(
            externalId,
            dstChainId,
            fromToken,
            asset,
            amount,
            outputAmount,
            msg.sender,
            message
        );
    }

    function depositAndCall(
        address targetContract,
        uint256 amount,
        address asset,
        uint32 dstChainId,
        bytes calldata payload
    ) public payable {
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);
        bool isETH = (asset == _ETH_ADDRESS_);
        bytes memory message = concatBytes(externalId, payload);

        RevertOptions memory revertOptions = RevertOptions({
            revertAddress: address(this),
            callOnRevert: true,
            abortAddress: targetContract,
            revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
            onRevertGasLimit: gasLimit
        });

        if (isETH) {
            require(msg.value >= amount, "INSUFFICIENT AMOUNT: ETH NOT ENOUGH");
            _handleETHDeposit(
                targetContract, 
                msg.value,
                message, 
                revertOptions
            );
        } else {
            TransferHelper.safeTransferFrom(asset, msg.sender, address(this), amount);

            _handleERC20Deposit(
                targetContract, 
                amount,
                asset, 
                message, 
                revertOptions
            );
        }

        emit EddyCrossChainSend(
            externalId,
            dstChainId,
            asset,
            asset,
            amount,
            amount,
            msg.sender,
            message
        );
    }

    function onCall(
        MessageContext calldata /*context*/,
        bytes calldata message
    ) external payable onlyGateway returns (bytes4) {
        (
            bytes32 externalId, 
            uint256 amount, 
            bytes calldata recipient, 
            address fromToken, 
            address toToken, 
            bytes calldata swapData
        ) = decodePackedMessage(message);

        bool fromIsETH = (fromToken == _ETH_ADDRESS_);
        bool toIsETH = (toToken == _ETH_ADDRESS_);
        address evmWalletAddress = address(bytes20(recipient));

        if(!fromIsETH) {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, address(this), amount);
        }

        MixSwapParams memory params = SwapDataHelperLib.decodeCompressedMixSwapParams(swapData);

        // Swap on DODO Router
        uint256 outputAmount = amount;
        if (swapData.length > 0) {
            require(
                (fromToken == params.fromToken) && (toToken == params.toToken),
                "INVALID_TOKEN_ADDRESS: TOKEN_NOT_MATCH"
            );
            // Handle negative slippage
            if(amount < params.fromTokenAmount) {
                params.fromTokenAmount = amount;
            }
            outputAmount = _doMixSwap(params);
        } else {
            require(
                (fromToken == toToken) && (fromToken != address(0)),
                "INVALID_TOKEN_AMOUNT: TOKEN_NOT_MATCH"
            );
        }

        if(toIsETH) {
            TransferHelper.safeTransferETH(evmWalletAddress, outputAmount);
        } else {
            TransferHelper.safeTransfer(toToken, evmWalletAddress, outputAmount);
        }
        
        emit EddyCrossChainReceive(
            externalId,
            fromToken,
            toToken,
            amount,
            outputAmount,
            evmWalletAddress,
            message
        );

        return "";
    }

    /**
     * @notice Function called by the gateway to revert the cross-chain swap
     * @param context Revert context
     * @dev Only the gateway can call this function
     */
    function onRevert(RevertContext calldata context) external onlyGateway {
        bytes32 externalId = bytes32(context.revertMessage[0:32]);
        address sender = address(uint160(bytes20(context.revertMessage[32:])));

        address asset = context.asset == address(0) ? _ETH_ADDRESS_ : context.asset;
        if(asset == _ETH_ADDRESS_) {
            TransferHelper.safeTransferETH(sender, context.amount);
        } else {
            TransferHelper.safeTransfer(context.asset, sender, context.amount);
        }
    
        emit EddyCrossChainRevert(
            externalId,
            asset,
            context.amount,
            sender
        );
    }

    receive() external payable {}

    fallback() external payable {}
}