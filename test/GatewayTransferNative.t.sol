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
        bytes memory swapData = "";
        bytes memory payload = bytes.concat(
            bytes20(user2),
            bytes20(targetZRC20),
            abi.encode(swapData)
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
        assertEq(token1Z.balanceOf(user2), amount);  
    }

    // A - zetachain swap: token1A -> token1Z -> token2Z
    function test_A2ZSwap() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        address asset = address(token1A);
        address targetZRC20 = address(token2Z);
        bytes memory swapData = abi.encodeWithSignature(
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
            abi.encode(swapData)
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
        assertEq(token2Z.balanceOf(user2), amount * 2);  
    }


    // A swap - zetachain 

    // A swap - zetachain swap

    // BTC - zetachain swap: btcZ - token1Z
    function test_BTC2ZSwap() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(btcZ);
        uint256 amount = 100 ether;
        address targetZRC20 = address(token1Z);
        bytes memory swapData = abi.encodeWithSignature(
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
            abi.encode(swapData)
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

    // zatachain - B: token1Z -> token1B
    function test_Z2B() public {
        uint256 amount = 100 ether;
        uint32 chainId = 2;
        address targetZRC20 = address(token1Z);
        address evmWalletAddress = user2;
        bytes32 isTargetERC20 = bytes32(uint256(1));
        bytes memory swapData = "";
        bytes memory contractAddress = "";
        bytes memory crossChainSwapData = "";
        bytes memory message = bytes.concat(
            bytes4(chainId),
            bytes20(targetZRC20),
            bytes20(evmWalletAddress),
            isTargetERC20,
            abi.encode(swapData, contractAddress, crossChainSwapData)
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
        uint32 chainId = 2;
        address targetZRC20 = address(token2Z);
        address evmWalletAddress = user2;
        bytes32 isTargetERC20 = bytes32(uint256(1));
        bytes memory swapData = abi.encodeWithSignature(
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
        bytes memory crossChainSwapData = "";
        bytes memory message = bytes.concat(
            bytes4(chainId),
            bytes20(targetZRC20),
            bytes20(evmWalletAddress),
            isTargetERC20,
            abi.encode(swapData, contractAddress, crossChainSwapData)
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
        uint32 chainId = 2;
        address targetZRC20 = address(token2Z);
        address evmWalletAddress = user2;
        bytes32 isTargetERC20 = bytes32(uint256(1));
        bytes memory swapData = abi.encodeWithSignature(
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
        bytes memory contractAddress = abi.encode(address(gatewaySendB));
        bytes memory crossChainSwapData = abi.encode(
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
        bytes memory message = bytes.concat(
            bytes4(chainId),
            bytes20(targetZRC20),
            bytes20(evmWalletAddress),
            isTargetERC20,
            abi.encode(swapData, contractAddress, crossChainSwapData)
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
        uint32 chainId = 8332;
        address targetZRC20 = address(btcZ);
        bytes memory btcAddress = hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234";
        bytes32 isTargetERC20 = bytes32(uint256(1));
        bytes memory swapData = abi.encodeWithSignature(
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
        bytes memory message = bytes.concat(
            bytes4(chainId),
            bytes20(targetZRC20),
            btcAddress, // BTC Address is 42 bytes
            isTargetERC20,
            swapData
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

    // zetachain swap - B(SOL): token1Z -> token2Z -> token2B
    function test_ZSwap2SOL() public {

    }
}