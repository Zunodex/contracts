// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";

contract RefundVaultTest is BaseTest {
    error Unauthorized();
    
    event UserClaimedRevert(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event BotClaimedRevert(
        address indexed token,
        uint256 totalAmount
    );

    function test_AddRefundInfo() public {
        bytes32[] memory externalIds = new bytes32[](3);
        externalIds[0] = keccak256(abi.encodePacked(block.timestamp));
        externalIds[1] = keccak256(abi.encodePacked(block.timestamp + 300));
        externalIds[2] = keccak256(abi.encodePacked(block.timestamp + 600));
        
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1Z);
        tokens[1] = address(token2Z);
        tokens[2] = address(token3Z);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        amounts[2] = 30 ether;

        bytes[] memory walletAddresses = new bytes[](3);
        walletAddresses[0] = abi.encodePacked(user2);
        walletAddresses[1] = abi.encodePacked(user2);
        walletAddresses[2] = abi.encodePacked(user2);

        vm.prank(bot);
        refundVault.addRefundInfo(
            externalIds,
            tokens,
            amounts,
            walletAddresses
        );

        (address tokenAddr, uint256 amt, bytes memory wAddr) = refundVault.getRefundInfo(externalIds[0]);
        assertEq(tokenAddr, address(token1Z));
        assertEq(amt, 10 ether);
        assertEq(keccak256(wAddr), keccak256(abi.encodePacked(user2)));

        (tokenAddr, amt, wAddr) = refundVault.getRefundInfo(externalIds[1]);
        assertEq(tokenAddr, address(token2Z));
        assertEq(amt, 20 ether);
        assertEq(keccak256(wAddr), keccak256(abi.encodePacked(user2)));

        (tokenAddr, amt, wAddr) = refundVault.getRefundInfo(externalIds[2]);
        assertEq(tokenAddr, address(token3Z));
        assertEq(amt, 30 ether);
        assertEq(keccak256(wAddr), keccak256(abi.encodePacked(user2)));
    }

    function test_RemoveRefundInfo() public {
        bytes32[] memory externalIds = new bytes32[](3);
        externalIds[0] = keccak256(abi.encodePacked(block.timestamp));
        externalIds[1] = keccak256(abi.encodePacked(block.timestamp + 300));
        externalIds[2] = keccak256(abi.encodePacked(block.timestamp + 600));

        // Set RefundInfo
        test_AddRefundInfo();

        // Remove RefundInfo
        vm.prank(bot);
        refundVault.removeRefundInfo(externalIds);
        (bytes32 externalId, , , ) = refundVault.refundInfos(externalIds[0]);
        assert(externalId == "");

        (externalId, , , ) = refundVault.refundInfos(externalIds[1]);
        assert(externalId == "");

        (externalId, , , ) = refundVault.refundInfos(externalIds[2]);
        assert(externalId == "");
    }

    function test_SetRefundInfoTransferNative() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address token = address(token1Z);
        uint256 amount = 10 ether;
        bytes memory walletAddress = abi.encodePacked(user2);

        token1Z.mint(address(gatewayTransferNative), amount);
        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onAbort(
            AbortContext({
                sender: abi.encode(address(this)),
                asset: token,
                amount: amount,
                outgoing: true,
                chainID: 2,
                revertMessage: bytes.concat(externalId, walletAddress)
            })
        );

        (address tokenAddr, uint256 amt, bytes memory wAddr) = refundVault.getRefundInfo(externalId);
        assertEq(tokenAddr, token);
        assertEq(amt, amount);
        assertEq(keccak256(wAddr), keccak256(walletAddress));
    }

    function test_SetRefundInfoCrossChain() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address token = address(token1Z);
        uint256 amount = 10 ether;
        bytes memory walletAddress = abi.encodePacked(user2);

        token1Z.mint(address(gatewayCrossChain), amount);
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onAbort(
            AbortContext({
                sender: abi.encode(address(this)),
                asset: token,
                amount: amount,
                outgoing: true,
                chainID: 2,
                revertMessage: bytes.concat(externalId, walletAddress)
            })
        );

        (address tokenAddr, uint256 amt, bytes memory wAddr) = refundVault.getRefundInfo(externalId);
        assertEq(tokenAddr, token);
        assertEq(amt, amount);
        assertEq(keccak256(wAddr), keccak256(walletAddress));
    }

    function test_ClaimRefund() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        uint256 amount = 10 ether;
        address token = address(token1Z);
        (, uint256 gasFee) = IZRC20(token).withdrawGasFee();
        token1Z.mint(address(user2), gasFee);

        // Set RefundInfo
        test_SetRefundInfoCrossChain();

        // Claim refund
        vm.startPrank(user2);
        token1Z.approve(address(refundVault), gasFee);
        refundVault.claimRefund(externalId);
        vm.stopPrank();

        assertEq(token1B.balanceOf(user2), amount);
    }

    function test_BatchClaimRefund() public {
        bytes32[] memory externalIds = new bytes32[](3);
        externalIds[0] = keccak256(abi.encodePacked(block.timestamp));
        externalIds[1] = keccak256(abi.encodePacked(block.timestamp + 300));
        externalIds[2] = keccak256(abi.encodePacked(block.timestamp + 600));

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1Z);
        tokens[1] = address(token2Z);
        tokens[2] = address(token1Z);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        amounts[2] = 30 ether;

        bytes[] memory walletAddresses = new bytes[](3);
        walletAddresses[0] = abi.encodePacked(user1);
        walletAddresses[1] = abi.encodePacked(user2);
        walletAddresses[2] = abi.encodePacked(user2);

        // Set RefundInfo
        token1Z.mint(address(gatewayCrossChain), amounts[0] + amounts[2]);
        token2Z.mint(address(gatewayCrossChain), amounts[1]);
        vm.startPrank(address(gatewayZEVM));
        for(uint256 i = 0; i < externalIds.length; i++) {
            gatewayCrossChain.onAbort(
                AbortContext({
                    sender: abi.encode(address(this)),
                    asset: tokens[i],
                    amount: amounts[i],
                    outgoing: true,
                    chainID: 2,
                    revertMessage: bytes.concat(externalIds[i], walletAddresses[i])
                })
            );
        }
        vm.stopPrank();

        (, uint256 gasFee) = token1Z.withdrawGasFee();
        token1Z.mint(address(bot), gasFee);

        // Claim refunds in batch
        vm.startPrank(bot);
        token1Z.approve(address(refundVault), gasFee);
        
        // Withdraw token from the vault on zetachain
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = externalIds[0];
        ids[1] = externalIds[2];
        refundVault.batchClaimRefund(address(token1Z), ids, abi.encodePacked(address(vault)));
        vm.stopPrank();
        
        assertEq(token1B.balanceOf(address(vault)), amounts[0] + amounts[2]);
    }

    function test_Set() public {
        refundVault.transferOwnership(user2);
        assertEq(refundVault.owner(), user2);

        vm.startPrank(user2);
        refundVault.setWhiteList(address(0x111), true);
        refundVault.setGasLimit(100000);
        refundVault.setGateway(payable(address(0x111)));
        refundVault.setBot(address(0x111), true);
        vm.stopPrank();
    }

    function test_SuperWithdraw() public {
        uint256 amount = 10 ether;
        token1Z.mint(address(refundVault), amount);
        vm.prank(bot);
        refundVault.superWithdraw(address(token1Z), amount);
        assertEq(token1Z.balanceOf(bot), amount);

        // Withdraw native token
        vm.deal(address(refundVault), amount);
        vm.prank(bot);
        refundVault.superWithdraw(_ETH_ADDRESS_, amount);
        assertEq(address(bot).balance, amount);
    }

    function test_OnRevert() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address token = address(token1Z);
        uint256 amount = 10 ether;
        bytes memory walletAddress = abi.encodePacked(user2);

        vm.prank(address(gatewayZEVM));
        vm.expectRevert(Unauthorized.selector);
        refundVault.onRevert(
            RevertContext({
                sender: address(this),
                asset: token,
                amount: amount,
                revertMessage: bytes.concat(externalId, walletAddress)
            })
        );

        vm.prank(address(gatewayZEVM));
        vm.expectEmit(true, false, false, true);
        emit UserClaimedRevert(externalId, token, amount, walletAddress);
        refundVault.onRevert(
            RevertContext({
                sender: address(refundVault),
                asset: token,
                amount: amount,
                revertMessage: bytes.concat(externalId, walletAddress)
            })
        );
        (address tokenAddr, uint256 amt, bytes memory wAddr) = refundVault.getRefundInfo(externalId);
        assertEq(tokenAddr, token);
        assertEq(amt, amount);
        assertEq(keccak256(wAddr), keccak256(walletAddress));

        vm.prank(address(gatewayZEVM));
        vm.expectEmit(true, false, false, true);
        emit BotClaimedRevert(token, amount);
        refundVault.onRevert(
            RevertContext({
                sender: address(refundVault),
                asset: token,
                amount: amount,
                revertMessage: ""
            })
        );
    }
}
