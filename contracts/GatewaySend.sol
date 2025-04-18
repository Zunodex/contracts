// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayEVM} from "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IDODORouteProxy} from "./interfaces/IDODORouteProxy.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract GatewaySend is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public globalNonce;
    uint256 public gasLimit;
    address public DODORouteProxy;
    address public DODOApprove;
    GatewayEVM public gateway;
    
    event EddyCrossChainSwapRevert(
        bytes32 externalId,
        address token,
        uint256 amount,
        address walletAddress
    );
    event EddyCrossChainSwap(
        bytes32 externalId,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress
    );
    event DODORouteProxyUpdated(address dodoRouteProxy);
    event GatewayUpdated(address gateway);

    error Unauthorized();
    error RouteProxyCallFailed();

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

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
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayEVM(_gateway);
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = IDODORouteProxy(_dodoRouteProxy)._DODO_APPROVE_PROXY_();
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

    function _calcExternalId(address sender) internal view returns (bytes32 externalId) {
        externalId = keccak256(abi.encodePacked(address(this), sender, globalNonce, block.timestamp));
    }

    function depositAndCall(
        address fromToken,
        uint256 amount,
        bytes calldata swapData,
        address targetContract,
        address asset,
        bytes calldata payload
    ) public {
        require(IERC20(fromToken).transferFrom(msg.sender, address(this), amount), "INSUFFICIENT ALLOWANCE: TRANSFER FROM FAILED");
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);
        // Swap on DODO Router
        IERC20(fromToken).approve(DODOApprove, amount);
        
        (bool success, bytes memory returnData) = DODORouteProxy.call(swapData);
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));

        IERC20(asset).approve(address(gateway), outputAmount);
        gateway.depositAndCall(
            targetContract,
            outputAmount,
            asset,
            bytes.concat(externalId, payload),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(externalId, asset, amount, msg.sender),
                onRevertGasLimit: gasLimit
            })
        );
        emit EddyCrossChainSwap(
            externalId,
            fromToken,
            asset,
            amount,
            outputAmount,
            msg.sender
        );
    }

    function depositAndCall(
        address targetContract,
        uint256 amount,
        address asset,
        bytes calldata payload
    ) public {
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(gateway), amount);
        gateway.depositAndCall(
            targetContract,
            amount,
            asset,
            bytes.concat(externalId, payload),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(externalId, asset, amount, msg.sender),
                onRevertGasLimit: gasLimit
            })
        );
        emit EddyCrossChainSwap(
            externalId,
            asset,
            asset,
            amount,
            amount,
            msg.sender
        );
    }

    function onCall(
        MessageContext calldata /*context*/,
        bytes calldata message
    ) external payable onlyGateway returns (bytes4) {
        (bytes32 externalId, address evmWalletAddress, uint256 amount, bytes memory crossChainSwapData) = abi.decode(
            message, 
            (bytes32, address, uint256, bytes)
        );
        (address fromToken, address toToken, bytes memory swapData) = abi.decode(
            crossChainSwapData,
            (address, address, bytes)
        );
        IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
        IERC20(fromToken).approve(DODORouteProxy, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(swapData);
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));
        IERC20(toToken).transfer(evmWalletAddress, outputAmount);

        emit EddyCrossChainSwap(
            externalId,
            fromToken,
            toToken,
            amount,
            outputAmount,
            evmWalletAddress
        );

        return "";
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

    receive() external payable {}

    fallback() external payable {}
}