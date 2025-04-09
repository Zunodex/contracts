// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";

contract GatewayZEVMMock {

    function depositAndCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        address target,
        bytes calldata message
    ) external {
        UniversalContract(target).onCall(context, zrc20, amount, message);
    }
}