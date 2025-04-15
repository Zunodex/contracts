// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {UniswapV2Library} from "../contracts/libraries/UniswapV2Library.sol";
import {Call} from "../contracts/Multicall.sol";

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
            address(gatewaySend),
            amount
        );
        gatewaySend.depositAndCall(
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
            address(gatewaySend),
            amount
        );
        gatewaySend.depositAndCall(
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

        (, uint256 gasFee) = IZRC20(address(token1Z)).withdrawGasFee();
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
        bytes memory contractAddress = abi.encode(address(multicallB));
        Call[] memory calls = new Call[](2);
        calls[0] = Call(
            address(token2B), 
            abi.encodeWithSignature("approve(address,uint256)", address(dodoRouteProxyB), 198995986959878634903)
        );
        calls[1] = Call(
            address(dodoRouteProxyB), 
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
        bytes memory crossChainSwapData = abi.encodeWithSignature(
            "aggregate((address,bytes)[])",
            calls
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
}