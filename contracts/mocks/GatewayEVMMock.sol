// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GatewayZEVMMock} from "../mocks/GatewayZEVMMock.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";

contract GatewayEVMMock {
    uint256 chainId = 1;
    mapping(address => address) public toZRC20; // erc20 => zrc20
    GatewayZEVMMock public gatewayZEVM;

    function setGatewayZEVM(address _gatewayEVM) public {
        gatewayZEVM = GatewayZEVMMock(_gatewayEVM);
    }

    function setZRC20(address erc20, address zrc20) public {
        toZRC20[erc20] = zrc20;
    }
    
    function depositAndCall(
        address receiver,
        uint256 amount,
        address asset,
        bytes calldata payload,
        RevertOptions calldata revertOptions
    ) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        gatewayZEVM.depositAndCall(
            MessageContext({
                origin: "",
                sender: tx.origin,
                chainID: chainId
            }),
            toZRC20[asset],
            amount,
            receiver,
            payload
        );
    }
}