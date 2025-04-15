// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GatewayZEVMMock} from "../mocks/GatewayZEVMMock.sol";
import {Callable, MessageContext} from "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {CallOptions, RevertOptions} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";

contract GatewayEVMMock {
    uint256 chainId;
    address DODORouteProxy;
    mapping(address => address) public toZRC20; // erc20 => zrc20
    mapping(address => address) public toERC20; // zrc20 => erc20
    GatewayZEVMMock public gatewayZEVM;

    error TargetContractCallFailed();

    function setGatewayZEVM(address _gatewayEVM) public {
        gatewayZEVM = GatewayZEVMMock(_gatewayEVM);
    }

    function setDodoRouteProxy(address _dodoRouteProxy) public {
        DODORouteProxy = _dodoRouteProxy;
    }

    function setZRC20(address erc20, address zrc20) public {
        toZRC20[erc20] = zrc20;
        toERC20[zrc20] = erc20;
    }

    function setChainId(uint256 _chainId) public {
        chainId = _chainId;
    }
    
    function depositAndCall(
        address receiver,
        uint256 amount,
        address asset,
        bytes calldata payload,
        RevertOptions calldata /*revertOptions*/
    ) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        gatewayZEVM.depositAndCall(
            chainId,
            toZRC20[asset],
            amount,
            receiver,
            payload
        );
    }

    function withdraw(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        RevertOptions calldata /*revertOptions*/
    ) external payable {
        address asset = toERC20[zrc20];
        (address to) = abi.decode(receiver, (address));
        IERC20(asset).transfer(to, amount);
    }

    function withdrawAndCall(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        bytes calldata message,
        CallOptions calldata /*callOptions*/,
        RevertOptions calldata /*revertOptions*/
    ) external payable {
        address asset = toERC20[zrc20];
        (address targetContract) = abi.decode(receiver, (address));
        IERC20(asset).approve(targetContract, amount);
        Callable(targetContract).onCall(
            MessageContext({
                sender: address(this)
            }),
            message
        );
    }
}