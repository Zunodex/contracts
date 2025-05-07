// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {UniswapV2Library} from "../contracts/libraries/UniswapV2Library.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";

/* forge test --fork-url https://zetachain-evm.blockpi.network/v1/rpc/public */
contract GatewayCrossChainTest is BaseTest {

    // A - zetachain swap - B: token2A -> token2Z -> token1Z -> token1B
    function test_A2ZSwap2B() public {
        address targetContract = address(gatewayCrossChain);
        uint256 amount = 100 ether;
        address asset = address(token2A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2Z),
            address(token1Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            targetContract,
            amount,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token2A.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 49000000000000000000);  
    }

    // A - zetachain swap - B: token2A -> token2Z -> token1Z -> token1B -> token2B
    function test_A2ZSwap2BSwap() public {
        address targetContract = address(gatewayCrossChain);
        uint256 amount = 100 ether;
        address asset = address(token2A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2Z),
            address(token1Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = abi.encode(
            address(token1B),
            address(token2B),
            abi.encodeWithSignature(
                "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
                address(token1B),
                address(token2B),
                address(0),
                address(0),
                49000000000000000000,
                0,
                "",
                "",
                block.timestamp + 60
            )
        );
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            targetContract,
            amount,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token2A.balanceOf(user1), initialBalance - amount);
        assertEq(token2B.balanceOf(user2), 196000000000000000000);  
    }

    // A swap - zetachain swap - B: token2A -> token1A -> token1Z -> token2Z -> token2B
    function test_ASwap2ZSwap2B() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2A),
            address(token1A),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address targetContract = address(gatewayCrossChain);
        address asset = address(token1A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            address(token2Z),
            address(0),
            address(0),
            33333333333333333300,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            fromToken,
            amount,
            swapDataA,
            targetContract,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token2A.balanceOf(user1), initialBalance - amount);
        assertEq(token2B.balanceOf(user2), 65662653626545301503);  
    }

    // A swap - zetachain swap - B swap: token2A -> token1A -> token1Z -> token2Z -> token2B -> token1B
    function test_ASwap2ZSwap2BSwap() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2A),
            address(token1A),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address targetContract = address(gatewayCrossChain);
        address asset = address(token1A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            address(token2Z),
            address(0),
            address(0),
            33333333333333333300,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = abi.encode(
            address(token2B),
            address(token1B),
            abi.encodeWithSignature(
                "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
                address(token2B),
                address(token1B),
                address(0),
                address(0),
                65662653626545301503,
                0,
                "",
                "",
                block.timestamp + 60
            )
        );
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            fromToken,
            amount,
            swapDataA,
            targetContract,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token2A.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 16415663406636325375);  
    }

    // BTC - zetachain swap - B swap: btc -> btcZ -> token2Z -> token2B -> token1B
    function test_BTC2ZSwap2BSwap() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(btcZ);
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(btcZ),
            address(token2Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = abi.encode(
            address(token2B),
            address(token1B),
            abi.encodeWithSignature(
                "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
                address(token2B),
                address(token1B),
                address(0),
                address(0),
                48995986959878634903,
                0,
                "",
                "",
                block.timestamp + 60
            )
        );
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        btcZ.mint(address(gatewayCrossChain), amount);
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 8332
            }),
            zrc20,
            amount,
            bytes.concat(externalId, payload)
        );

        assertEq(token1B.balanceOf(user2), 12248996739969658725);
    }

    // A swap - zetachain swap - BTC: token2A -> token1A -> token1Z -> btcZ - btc
    function test_ASwap2ZSwap2BTC() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2A),
            address(token1A),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address asset = address(token1A);
        uint32 dstChainId = 8332;
        address targetZRC20 = address(btcZ);
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            address(btcZ),
            address(0),
            address(0),
            33333333333333333300,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            btcAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            fromToken,
            amount,
            swapDataA,
            targetContract,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token2A.balanceOf(user1), initialBalance - amount);
        assertEq(btc.balanceOf(user2), 32333333333333333300); 
    }

    // A swap - zetachain swap - SOL: token1A -> token2A -> token2Z -> token1Z -> token1B
    function test_ASwap2ZSwap2SOL() public {
        address fromToken = address(token1A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1A),
            address(token2A),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address asset = address(token2A);
        uint32 dstChainId = 900;
        address targetZRC20 = address(token1Z);
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2Z),
            address(token1Z),
            address(0),
            address(0),
            33333333333333333300,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token1A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            fromToken,
            amount,
            swapDataA,
            targetContract,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 15666666666666666650); 
    }

    // A swap - zetachain swap - SOL swap: token1A -> token2A -> token2Z -> token1Z -> token1B
    function test_ASwap2ZSwap2SOLSwap() public {
        address fromToken = address(token1A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1A),
            address(token2A),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address asset = address(token2A);
        uint32 dstChainId = 900;
        address targetZRC20 = address(token2Z);
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token2Z),
            address(token1Z),
            address(0),
            address(0),
            33333333333333333300,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory contractAddress = abi.encodePacked("EwUjcjz8jvFeE99kjcZKM5Aojs3eKcyW2JHNKNDP9M4k");
        bytes memory swapDataB = "0x12345678";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        ); 
        vm.startPrank(user1);
        token1A.approve(
            address(gatewaySendA),
            amount
        );
        gatewaySendA.depositAndCall(
            fromToken,
            amount,
            swapDataA,
            targetContract,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(token1A.balanceOf(user1), initialBalance - amount);
    }

    function test_ZOnRevert() public {
        bytes32 externalId = bytes32(0);
        uint256 amount = 100 ether;
        token1Z.mint(address(gatewayCrossChain), amount);

        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onRevert(
            RevertContext({
                sender: address(this),
                asset: address(token1Z),
                amount: amount,
                revertMessage: bytes.concat(externalId, bytes20(user2))
            })
        );

        assertEq(token1Z.balanceOf(user2), amount);
    }

    function test_ZOnAbort() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        uint256 amount = 100 ether;
        token1Z.mint(address(gatewayCrossChain), amount);

        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onAbort(
            AbortContext({
                sender: abi.encode(address(this)),
                asset: address(token1Z),
                amount: amount,
                outgoing: false,
                chainID: 7000,
                revertMessage: bytes.concat(externalId, bytes20(user2))
            })
        );

        vm.expectRevert();
        gatewayCrossChain.claimRefund(externalId);

        vm.expectRevert();
        vm.prank(user2);
        gatewayCrossChain.claimRefund(bytes32(0));

        vm.prank(user2);
        gatewayCrossChain.claimRefund(externalId);

        vm.expectRevert();
        vm.prank(user2);
        gatewayCrossChain.claimRefund(externalId);

        assertEq(token1Z.balanceOf(user2), amount);
    }

    function test_Set() public {
        gatewayCrossChain.setOwner(user1);

        vm.startPrank(user1);
        gatewayCrossChain.setDODORouteProxy(address(0x111));
        gatewayCrossChain.setDODOApprove(address(0x111));
        gatewayCrossChain.setFeePercent(0);
        gatewayCrossChain.setGateway(payable(address(0x111)));
        gatewayCrossChain.setEddyTreasurySafe(address(0x111));
        vm.stopPrank();
    }

    function test_Revert() public {
        uint32 dstChainId = 8332;
        address targetZRC20 = address(btcZ);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            btcAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        ); 
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        uint256 amount = 100 ether;

        token1Z.mint(address(gatewayZEVM), amount);
        vm.startPrank(address(gatewayZEVM));
        token1Z.approve(
            address(gatewayCrossChain),
            amount
        );
        vm.expectRevert();
        gatewayCrossChain.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 1
            }),
            address(token1Z),
            amount,
            bytes.concat(externalId, payload)
        );
        vm.stopPrank();

        dstChainId = 900;
        targetZRC20 = address(token2Z);
        payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        ); 
        token1Z.mint(address(gatewayZEVM), amount);
        vm.startPrank(address(gatewayZEVM));
        token1Z.approve(
            address(gatewayCrossChain),
            amount
        );
        vm.expectRevert();
        gatewayCrossChain.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 1
            }),
            address(token1Z),
            amount,
            bytes.concat(externalId, payload)
        );
        vm.stopPrank();

        dstChainId = 2;
        payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            abi.encodePacked(user2),
            swapDataZ,
            contractAddress,
            swapDataB
        ); 
        token1Z.mint(address(gatewayZEVM), amount);
        vm.startPrank(address(gatewayZEVM));
        token1Z.approve(
            address(gatewayCrossChain),
            amount
        );
        vm.expectRevert();
        gatewayCrossChain.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 1
            }),
            address(token1Z),
            amount,
            bytes.concat(externalId, payload)
        );
        vm.stopPrank();
    }
}