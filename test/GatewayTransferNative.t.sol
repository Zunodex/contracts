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
        address asset = address(token1A);
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
            payload
        );
        vm.stopPrank();

        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token2Z.balanceOf(user2), 100000000000000000000);  
    }

    // A swap - zetachain 

    // A swap - zetachain swap

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

        (, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();
        assertEq(token1Z.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(user2), amount - gasFee); 
    }

    // zetachain swap - B：token1Z -> token2Z -> token2B
    function test_ZSwap2B() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
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

    // zetachain swap - B swap：token1Z -> token2Z -> token2B -> token1B
    function test_ZSwap2BSwap() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory evmWalletAddress = abi.encodePacked(user2);
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
                198995986959878634903,
                0,
                "",
                "",
                block.timestamp + 60
            )
        );
        bytes memory message = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
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
        assertEq(token1B.balanceOf(user2), 49748996739969658725); 
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

    // zetachain swap - SOL: token1Z -> token2Z -> token2B
    function test_ZSwap2SOL() public {
        uint256 amount = 100 ether;
        uint32 dstChainId = 900;
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
        assertEq(token2B.balanceOf(user2), 198995986959878634903); 
    }

    function test_AOnRevert() public {
        bytes32 externalId = bytes32(0);
        uint256 amount = 100 ether;
        token1A.mint(address(gatewaySendA), amount);

        vm.prank(address(gatewayA));
        gatewaySendA.onRevert(
            RevertContext({
                sender: address(this),
                asset: address(token1A),
                amount: amount,
                revertMessage: bytes.concat(externalId, bytes20(user2))
            })
        );

        assertEq(token1A.balanceOf(user2), amount);
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
        bytes32 externalId = bytes32(0);
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

        assertEq(token1Z.balanceOf(user2), amount);
    }
}