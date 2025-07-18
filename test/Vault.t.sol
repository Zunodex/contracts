// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "../contracts/Vault.sol";
import {RefundVaultTest} from "./RefundVault.t.sol";
import {console} from "forge-std/console.sol";

contract VaultTest is RefundVaultTest {

    function test_BatchTransferRefund() public {
        // Withdraw token to the vault on source/target chain
        test_BatchClaimRefund();

        bytes32[] memory externalIds = new bytes32[](2);
        externalIds[0] = keccak256(abi.encodePacked(block.timestamp));
        externalIds[1] = keccak256(abi.encodePacked(block.timestamp + 600));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1B);
        tokens[1] = address(token1B);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 30 ether;

        address[] memory walletAddresses = new address[](2);
        walletAddresses[0] = user1;
        walletAddresses[1] = user2;

        // Set RefundInfo
        Vault.RefundInfo[] memory infos = new Vault.RefundInfo[](2);
        for (uint256 i = 0; i < externalIds.length; i++) {
            infos[i] = Vault.RefundInfo({
                externalId: externalIds[i],
                token: tokens[i],
                amount: amounts[i],
                to: walletAddresses[i]
            });
        }

        vm.prank(bot);
        vault.batchTransferRefund(
            address(token1B),
            infos
        );

        assertEq(token1B.balanceOf(user1), amounts[0]);
        assertEq(token1B.balanceOf(user2), amounts[1]);
    }

    function test_SetVault() public {
        vault.setBot(address(0x111), true);
        assertTrue(vault.bots(address(0x111)));
    }

    function test_SuperWithdrawVault() public{
        uint256 amount = 10 ether;
        token1B.mint(address(vault), amount);
        vm.prank(bot);
        vault.superWithdraw(address(token1B), amount);
        assertEq(token1B.balanceOf(bot), amount);

        // Withdraw native token
        vm.deal(address(vault), amount);
        vm.prank(bot);
        vault.superWithdraw(_ETH_ADDRESS_, amount);
        assertEq(address(bot).balance, amount);
    }
}