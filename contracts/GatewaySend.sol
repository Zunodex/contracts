// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayEVM} from "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IDODORouteProxy} from "./interfaces/IDODORouteProxy.sol";

contract GatewaySend is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public DODORouteProxy;
    address public DODOApprove;
    GatewayEVM public gateway;

    event EddyCrossChainSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );
    event DodoRouteProxyUpdated(address dodoRouteProxy);
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
        address _dodoRouteProxy
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayEVM(_gateway);
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = IDODORouteProxy(_dodoRouteProxy)._DODO_APPROVE_PROXY_();
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDodoRouteProxy(address _dodoRouteProxy) external onlyOwner {
        DODORouteProxy = _dodoRouteProxy;
        emit DodoRouteProxyUpdated(_dodoRouteProxy);
    }

    function setGateway(address _gateway) external onlyOwner {
        gateway = GatewayEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function depositAndCall(
        address fromToken,
        uint256 amount,
        bytes calldata swapData,
        address targetContract,
        address asset,
        bytes calldata payload
    ) public {
        // Swap on DODO Router
        IERC20(fromToken).approve(DODORouteProxy, amount);
        (bool success, bytes memory returnData) = DODORouteProxy.call(swapData); // swap on zetachain
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));

        IERC20(asset).approve(address(gateway), outputAmount);
        gateway.depositAndCall(
            targetContract,
            outputAmount,
            asset,
            payload,
            RevertOptions({
                revertAddress: msg.sender,
                callOnRevert: false,
                abortAddress: address(0),
                revertMessage: "",
                onRevertGasLimit: 0
            })
        );
    }

    function depositAndCall(
        address targetContract,
        uint256 amount,
        address asset,
        bytes calldata payload
    ) public {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(gateway), amount);
        gateway.depositAndCall(
            targetContract,
            amount,
            asset,
            payload,
            RevertOptions({
                revertAddress: msg.sender,
                callOnRevert: false,
                abortAddress: address(0),
                revertMessage: "",
                onRevertGasLimit: 0
            })
        );
    }

    function onCall(
        MessageContext calldata /*context*/,
        bytes calldata message
    ) external payable onlyGateway returns (bytes4) {
        (address evmWalletAddress, uint256 amount, bytes memory crossChainSwapData) = abi.decode(
            message, 
            (address, uint256, bytes)
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
            fromToken,
            toToken,
            amount,
            outputAmount,
            evmWalletAddress,
            0
        ); 

        return "";
    }

    receive() external payable {}

    fallback() external payable {}
}