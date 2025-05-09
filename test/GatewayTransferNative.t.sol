// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {UniswapV2Library} from "../contracts/libraries/UniswapV2Library.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";

/* forge test --fork-url https://zetachain-evm.blockpi.network/v1/rpc/public */
contract GatewayTransferNativeTest is BaseTest {
    
    // A - zetachain: token1A -> token1Z
    function test_A2Z() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address asset = address(token1A);
        address targetZRC20 = address(token1Z);
        bytes memory swapDataZ = "";
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        vm.startPrank(user1);
        token1A.approve(
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

        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token1Z.balanceOf(user2), 100000000000000000000);  
    }

    // A - zetachain swap: token1A -> token1Z -> token2Z
    function test_A2ZSwap() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address asset = address(token1A);
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(token2Z),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        vm.startPrank(user1);
        token1A.approve(
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

        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token2Z.balanceOf(user2), 200000000000000000000);  
    }

    // A native token - zetachain swap: ETH -> token3Z -> token2Z
    function test_ANative2ZSwap() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address asset = _ETH_ADDRESS_;
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token3Z),
            address(token2Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        vm.startPrank(user1);
        gatewaySendA.depositAndCall{value: amount}(
            targetContract,
            amount,
            asset,
            dstChainId,
            payload
        );
        vm.stopPrank();

        assertEq(user1.balance, initialBalance - amount);
        assertEq(token2Z.balanceOf(user2), 100000000000000000000);  
    }

    // A native token swap - zetachain swap: token1A -> ETH -> token3Z -> token2Z
    function test_ANativeSwap2ZSwap() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address fromToken = address(token1A);
        address asset = _ETH_ADDRESS_;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1A),
            _ETH_ADDRESS_,
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token3Z),
            address(token2Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
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
        assertEq(token2Z.balanceOf(user2), 100000000000000000000);  
    }

    // A swap - zetachain: token1A -> token2A -> token2Z
    function test_ASwap2Z() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address fromToken = address(token1A);
        address asset = address(token2A);
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token1A),
            address(token2A),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = "";
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
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
        assertEq(token2Z.balanceOf(user2), 300000000000000000000);  
    }

    // A swap - zetachain swap: token1A -> token2A -> token2Z -> token1Z
    function test_ASwap2ZSwap() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
        address fromToken = address(token1A);
        address asset = address(token2A);
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token1A),
            address(token2A),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
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
        assertEq(token2Z.balanceOf(user2), 300000000000000000000);  
    }

    // BTC - zetachain swap: btc -> btcZ -> token1Z
    function test_BTC2ZSwap() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(btcZ);
        uint256 amount = 100 ether;
        address targetZRC20 = address(token1Z);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(btcZ),
            address(token1Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory message = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        btcZ.mint(address(gatewayTransferNative), amount);
        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 8332
            }),
            zrc20,
            amount,
            bytes.concat(externalId, message)
        );

        assertEq(token1Z.balanceOf(user2), 100000000000000000000);
    }

    // SOL - zetachain swap: SOL -> token1Z -> token2Z
    function test_SOL2ZSwap() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(token1Z);
        uint256 amount = 100 ether;
        address targetZRC20 = address(token2Z);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            address(token2Z),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory message = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        token1Z.mint(address(gatewayTransferNative), amount);
        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 900
            }),
            zrc20,
            amount,
            bytes.concat(externalId, message)
        );

        assertEq(token2Z.balanceOf(user2), 200000000000000000000);
    }

    // zatachain - B: token1Z -> token1B
    function test_Z2B() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = "";
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            )
        );

        vm.startPrank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 99000000000000000000); 
    }

    // zetachain swap - B：token1Z -> token2Z -> token2B
    function test_ZSwap2B() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(token2Z),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = "";
        bytes memory fromTokenB = abi.encodePacked(address(token2B));
        bytes memory toTokenB = abi.encodePacked(address(token2B));
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            )
        );

        vm.startPrank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
        assertEq(token2B.balanceOf(user2), 198995986959878634903); 
    }

    // zetachain swap - B swap：token2Z -> token1Z -> token1B -> token2B
    function test_ZSwap2BSwap() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            amount,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token1B),
            address(token2B),
            49000000000000000000,
            0,
            0,
            new address[](1),
            new address[](1),
            new address[](1),
            0,
            new bytes[](1),
            abi.encode(address(0), 0),
            block.timestamp + 600
        );
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token2B));
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            )
        );

        vm.startPrank(user1);
        token2Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token2Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token2Z.balanceOf(user1), initialBalance - amount);
        assertEq(token2B.balanceOf(user2), 196000000000000000000); 
    }

    // zetachain swap - BTC: token1Z -> btcZ -> btc
    function test_ZSwap2BTC() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 8332;
        address targetZRC20 = address(btcZ);
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            address(btcZ),
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
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            btcAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
        assertEq(btc.balanceOf(user2), 99000000000000000000); 
    }

    // zetachain - BTC: btcZ -> btc
    function test_Z2BTC() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 8332;
        address targetZRC20 = address(btcZ);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            btcAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );
        btcZ.mint(user1, initialBalance);
        vm.startPrank(user1);
        btcZ.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(btcZ),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(btcZ.balanceOf(user1), initialBalance - amount);
        assertEq(btc.balanceOf(user2), 99000000000000000000); 
    }

    // zetachain swap - SOL: token2Z -> token1Z -> token1B
    function test_ZSwap2SOL() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 900;
        address targetZRC20 = address(token1Z);
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
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token2Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token2Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token2Z.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 49000000000000000000); 
    }

    // zetachain - SOL: token1Z -> token1B -> token2B
    function test_Z2SOLSwap() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 900;
        address targetZRC20 = address(token1Z);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = abi.encodePacked("EwUjcjz8jvFeE99kjcZKM5Aojs3eKcyW2JHNKNDP9M4k");
        bytes memory swapDataB = "0x12345678";
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
    }

    // zetachain - SOL: token1Z -> token1B
    function test_Z2SOL() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 900;
        address targetZRC20 = address(token1Z);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            solAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        vm.startPrank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            amount
        );
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );
        vm.stopPrank();

        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), 99000000000000000000); 
    }

    // A - Z: tokenWZETAA -> WZETA
    function test_A2ZWZETA() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(token1Z);
        uint256 amount = 100 ether;
        address targetZRC20 = WZETA;
        bytes memory swapDataZ = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1Z),
            WZETA,
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory message = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            swapDataZ
        );

        token1Z.mint(address(gatewayTransferNative), amount);
        deal(WZETA, address(dodoRouteProxyZ), initialBalance);
        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onCall(
            MessageContext({
                origin: "",
                sender: msg.sender,
                chainID: 2
            }),
            zrc20,
            amount,
            bytes.concat(externalId, message)
        );
    }

    function test_ZOnRevert() public {
        bytes32 externalId = bytes32(0);
        uint256 amount = 100 ether;
        token1Z.mint(address(gatewayTransferNative), amount);

        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onRevert(
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
        token1Z.mint(address(gatewayTransferNative), amount);

        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onAbort(
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
        gatewayTransferNative.claimRefund(externalId);

        vm.expectRevert();
        vm.prank(user2);
        gatewayTransferNative.claimRefund(bytes32(0));

        vm.prank(user2);
        gatewayTransferNative.claimRefund(externalId);

        vm.expectRevert();
        vm.prank(user2);
        gatewayTransferNative.claimRefund(externalId);

        assertEq(token1Z.balanceOf(user2), amount);
    }

    function test_Revert() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
        bytes memory swapDataZ = "0x12345678";
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );

        token1Z.mint(user1, 1000 ether);
        vm.prank(user1);
        token1Z.approve(
            address(gatewayTransferNative),
            type(uint256).max
        );

        vm.expectRevert();
        vm.prank(user1);
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );

        vm.expectRevert();
        vm.prank(user1);
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            1e6,
            message
        );

        vm.expectRevert();
        vm.prank(user1);
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            1000 ether,
            message
        );

        dstChainId = 8332;
        message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );
        vm.expectRevert();
        vm.prank(user1);
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );

        dstChainId = 900;
        message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            swapDataB
        );
        vm.expectRevert();
        vm.prank(user1);
        gatewayTransferNative.withdrawToNativeChain(
            address(token1Z),
            amount,
            message
        );

        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        swapDataZ = "";
        message = bytes.concat(
            bytes20(user2),
            bytes20(address(token2Z)),
            swapDataZ
        );
        token1Z.mint(address(gatewayZEVM), amount);
        vm.expectRevert();
        vm.prank(address(gatewayZEVM));
        gatewayTransferNative.onCall(
            MessageContext({
                origin: "",
                sender: address(this),
                chainID: 1
            }),
            address(token1Z),
            amount,
            bytes.concat(externalId, message)
        );
    }

    function test_Set() public {
        gatewayTransferNative.setOwner(user1);

        vm.startPrank(user1);
        gatewayTransferNative.setDODORouteProxy(address(0x111));
        gatewayTransferNative.setDODOApprove(address(0x111));
        gatewayTransferNative.setFeePercent(0);
        gatewayTransferNative.setGasLimit(2000000);
        gatewayTransferNative.setGateway(payable(address(0x111)));
        gatewayTransferNative.setEddyTreasurySafe(address(0x111));
        vm.stopPrank();
    }
}