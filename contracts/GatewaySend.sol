// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayEVM} from "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import {IGatewayEVM, RevertOptions} from "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract GatewaySend is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public DodoRouteProxy;
    GatewayEVM public gateway;

    event DodoRouteProxyUpdated(address dodoRouteProxy);
    event GatewayUpdated(address gateway);

    error RouteProxyCallFailed();

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
        DodoRouteProxy = _dodoRouteProxy;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDodoRouteProxy(address _dodoRouteProxy) external onlyOwner {
        DodoRouteProxy = _dodoRouteProxy;
        emit DodoRouteProxyUpdated(_dodoRouteProxy);
    }

    function setGateway(address _gateway) external onlyOwner {
        gateway = GatewayEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function depositAndCall(
        address targetContract,
        uint256 amount,
        address fromToken,
        address asset,
        bytes calldata payload,
        bytes calldata swapData
    ) public {
        // Swap on DODO Router
        IERC20(fromToken).approve(DodoRouteProxy, amount);
        (bool success, bytes memory returnData) = DodoRouteProxy.call(swapData); // swap on zetachain
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));

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

    receive() external payable {}

    fallback() external payable {}
}