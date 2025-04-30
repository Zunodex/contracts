// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol" ;
import {UniswapV2Library} from "../contracts/libraries/UniswapV2Library.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";

/* forge test --fork-url https://zetachain-evm.blockpi.network/v1/rpc/public */
contract GatewaySendTest is BaseTest {
    error RouteProxyCallFailed();

    function test_Set() public {
        gatewaySendA.setOwner(user1);

        vm.startPrank(user1);
        gatewaySendA.setDODORouteProxy(address(0x111));
        gatewaySendA.setGateway(address(0x111));
        gatewaySendA.setGasLimit(2000000);
        vm.stopPrank();
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

    function test_Revert() public {
        address targetContract = address(gatewayTransferNative);
        uint256 amount = 100 ether;
        uint32 dstChainId = 7000;
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
            10000 ether
        );
        vm.expectRevert();
        gatewaySendA.depositAndCall(
            _ETH_ADDRESS_,
            amount,
            "",
            targetContract,
            address(token1A),
            dstChainId,
            payload
        );

        vm.expectRevert();
        gatewaySendA.depositAndCall(
            address(token1A),
            10000 ether,
            "",
            targetContract,
            address(token1A),
            dstChainId,
            payload
        );

        vm.expectRevert();
        gatewaySendA.depositAndCall(
            targetContract,
            amount,
            _ETH_ADDRESS_,
            dstChainId,
            payload
        );

        vm.expectRevert();
        gatewaySendA.depositAndCall(
            targetContract,
            10000 ether,
            address(token1A),
            dstChainId,
            payload
        );

        vm.expectRevert();
        gatewaySendA.depositAndCall(
            address(token1A),
            amount,
            "",
            targetContract,
            address(token2A),
            dstChainId,
            payload
        );
        vm.stopPrank();

        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address evmWalletAddress = user2;
        address fromToken = address(token1B);
        address toToken = address(token2B);
        bytes memory swapDataB = "";
        bytes memory crossChainSwapData = abi.encode(fromToken, toToken, swapDataB);
        bytes memory message = abi.encode(externalId, evmWalletAddress, amount, crossChainSwapData);
        
        token1B.mint(address(gatewayB), amount);
        vm.startPrank(address(gatewayB));
        token1B.approve(
            address(gatewaySendB), 
            amount
        );
        vm.expectRevert();
        gatewaySendB.onCall(
            MessageContext({
                sender: address(this)
            }),
            message
        );
        vm.stopPrank();
    }

    function test_OnCallFromTokenIsETH() public {
        uint256 amount = 100 ether;
        address fromToken = _ETH_ADDRESS_;
        address toToken = address(token1B);
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            _ETH_ADDRESS_,
            address(token1B),
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory crossChainSwapData = abi.encode(fromToken, toToken, swapDataA);
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address evmWalletAddress = user2;
        bytes memory message = abi.encode(externalId, evmWalletAddress, amount, crossChainSwapData);

        deal(address(gatewayB), amount);
        vm.prank(address(gatewayB));
        gatewaySendB.onCall{value: amount}(
            MessageContext({
                sender: address(this)
            }),
            message
        );

        assertEq(token1B.balanceOf(user2), amount);
    }

    function test_OnCallToTokenIsETH() public {
        uint256 amount = 100 ether;
        address fromToken = address(token1B);
        address toToken = _ETH_ADDRESS_;
        bytes memory swapDataA = abi.encodeWithSignature(
            "externalSwap(address,address,address,address,uint256,uint256,bytes,bytes,uint256)",
            address(token1B),
            _ETH_ADDRESS_,
            address(0),
            address(0),
            amount,
            0,
            "",
            "",
            block.timestamp + 60
        );
        bytes memory crossChainSwapData = abi.encode(fromToken, toToken, swapDataA);
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address evmWalletAddress = user2;
        bytes memory message = abi.encode(externalId, evmWalletAddress, amount, crossChainSwapData);

        token1B.mint(address(gatewayB), amount);
        vm.startPrank(address(gatewayB));
        token1B.approve(
            address(gatewaySendB), 
            amount
        );
        gatewaySendB.onCall(
            MessageContext({
                sender: address(this)
            }),
            message
        );
        vm.stopPrank();

        assertEq(user2.balance, amount);
    }
}