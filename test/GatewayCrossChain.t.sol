// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {UniswapV2Library} from "../contracts/libraries/UniswapV2Library.sol";
import {SwapDataHelperLib} from "../contracts/libraries/SwapDataHelperLib.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/console.sol";

/* forge test --fork-url https://zetachain-evm.blockpi.network/v1/rpc/public */
contract GatewayCrossChainTest is BaseTest {
    // A zetachain - B swap: token2A -> token2Z -> token2B -> token1B
    function test_A2Z2BSwap() public {
        address targetContract = address(gatewayCrossChain);
        uint256 amount = 100 ether;
        address asset = address(token2A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = abi.encodePacked(address(gatewaySendB));
        bytes memory fromTokenB = abi.encodePacked(address(token2B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token2B),
            address(token1B),
            98985986959878634903,
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
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(token1B.balanceOf(user2), 24746496739969658725);  
    }

    // A - zetachain swap - B: token2A -> token2Z -> token1Z -> token1B
    function test_A2ZSwap2B() public {
        address targetContract = address(gatewayCrossChain);
        uint256 amount = 100 ether;
        address asset = address(token2A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            99990000000000000000,
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
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory swapDataB = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(token1B.balanceOf(user2), 48995000000000000000);  
    }

    // A - zetachain swap - B: token2A -> token2Z -> token1Z -> token1B -> token2B
    function test_A2ZSwap2BSwap() public {
        address targetContract = address(gatewayCrossChain);
        uint256 amount = 100 ether;
        address asset = address(token2A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            99990000000000000000,
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
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token2B));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token1B),
            address(token2B),
            48995000000000000000,
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
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(token2B.balanceOf(user2), 195980000000000000000);  
    }

    // A swap - zetachain swap - B: token2A -> token1A -> token1Z -> token2Z -> token2B
    function test_ASwap2ZSwap2B() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token2A),
            address(token1A),
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
        
        address targetContract = address(gatewayCrossChain);
        address asset = address(token1A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(token2Z),
            33329999999999999967,
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
        bytes memory fromTokenB = abi.encodePacked(address(token2B));
        bytes memory toTokenB = abi.encodePacked(address(token2B));
        bytes memory swapDataB = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(token2B.balanceOf(user2), 65655986959878634837);  
    }

    // A swap - zetachain swap - B swap: token2A -> token1A -> token1Z -> token2Z -> token2B -> token1B
    function test_ASwap2ZSwap2BSwap() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token2A),
            address(token1A),
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
        address targetContract = address(gatewayCrossChain);
        address asset = address(token1A);
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(token2Z),
            33329999999999999967,
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
        bytes memory fromTokenB = abi.encodePacked(address(token2B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token2B),
            address(token1B),
            65655986959878634837,
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
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(token1B.balanceOf(user2), 16413996739969658709);  
    }

    // BTC - zetachain swap - B swap: btc -> btcZ -> token2Z -> token2B -> token1B
    function test_BTC2ZSwap2BSwap() public {
        bytes32 externalId = keccak256(abi.encodePacked(block.timestamp));
        address zrc20 = address(btcZ);
        uint256 amount = 100 ether;
        uint32 dstChainId = 2;
        address targetZRC20 = address(token2Z);
        bytes memory sender = btcAddress;
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(btcZ),
            address(token2Z),
            99990000000000000000,
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
        bytes memory fromTokenB = abi.encodePacked(address(token2B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token2B),
            address(token1B),
            48990986959878634903,
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
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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

        assertEq(token1B.balanceOf(user2), 12247746739969658725);
    }

    // A swap - zetachain swap - BTC: token2A -> token1A -> token1Z -> btcZ - btc
    function test_ASwap2ZSwap2BTC() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token2A),
            address(token1A),
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
        address asset = address(token1A);
        uint32 dstChainId = 8223;
        address targetZRC20 = address(btcZ);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = btcAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(btcZ),
            33329999999999999967,
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
        bytes memory fromTokenB = abi.encodePacked(address(btc));
        bytes memory toTokenB = abi.encodePacked(address(btc));
        bytes memory swapDataB = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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
        assertEq(btc.balanceOf(user2), 32329999999999999967); 
    }

    // A swap - zetachain swap - SOL: token1A -> token2A -> token2Z -> token1Z -> token1B
    function test_ASwap2ZSwap2SOL() public {
        address fromToken = address(token1A);
        uint256 amount = 100 ether;
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
        address asset = address(token2A);
        uint32 dstChainId = 1399811149;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = solAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            299970000000000000000,
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
        bytes memory contractAddress = solGatewaySendAddress;
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token1B));
        bytes memory swapDataB = "";
        bytes32[] memory publicKeys = new bytes32[](2);
        publicKeys[0] = keccak256(abi.encodePacked(block.timestamp));
        publicKeys[1] = keccak256(abi.encodePacked(block.timestamp));
        bool[] memory isWritables = new bool[](2);
        isWritables[0] = true;
        isWritables[0] = false;
        bytes memory accounts = compressAccounts(publicKeys, isWritables);
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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

        address evmWalletAddress = address(bytes20(solAddress));
        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token1B.balanceOf(evmWalletAddress), 148985000000000000000); 
    }

    // A swap - zetachain swap - SOL swap: token1A -> token2A -> token2Z -> token1Z -> token1B -> token2B
    function test_ASwap2ZSwap2SOLSwap() public {
        address fromToken = address(token1A);
        uint256 amount = 100 ether;
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
        address asset = address(token2A);
        uint32 dstChainId = 1399811149;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = solAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            299970000000000000000,
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
        bytes memory contractAddress = solGatewaySendAddress;
        bytes memory fromTokenB = abi.encodePacked(address(token1B));
        bytes memory toTokenB = abi.encodePacked(address(token2B));
        bytes memory swapDataB = encodeCompressedMixSwapParams(
            address(token1B),
            address(token2B),
            148985000000000000000,
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
        bytes32[] memory publicKeys = new bytes32[](2);
        publicKeys[0] = keccak256(abi.encodePacked(block.timestamp));
        publicKeys[1] = keccak256(abi.encodePacked(block.timestamp));
        bool[] memory isWritables = new bool[](2);
        isWritables[0] = true;
        isWritables[0] = false;
        bytes memory accounts = compressAccounts(publicKeys, isWritables);
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            abi.encodePacked(
                fromTokenB, 
                toTokenB, 
                swapDataB
            ),
            accounts
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

        address evmWalletAddress = address(bytes20(solAddress));
        assertEq(token1A.balanceOf(user1), initialBalance - amount);
        assertEq(token2B.balanceOf(evmWalletAddress), 595940000000000000000);
    }

    // A swap - zetachain - SUI: token2A -> token1A -> token1Z -> token1B
    function test_ASwap2Z2SUI() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token2A),
            address(token1A),
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
        address asset = address(token1A);
        uint32 dstChainId = 105;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = suiAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = "";
        bytes memory contractAddress = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            "",
            accounts
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
        assertEq(token1B.balanceOf(user2), 32329999999999999967); 
    }

    // A swap - zetachain swap - SUI: A swap - token2A -> token1A -> token1Z -> token2Z -> token2B
    function test_ASwap2ZSwap2SUI() public {
        address fromToken = address(token2A);
        uint256 amount = 100 ether;
        bytes memory swapDataA = encodeCompressedMixSwapParams(
            address(token2A),
            address(token1A),
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
        address asset = address(token1A);
        uint32 dstChainId = 105;
        address targetZRC20 = address(token2Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = suiAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token1Z),
            address(token2Z),
            33329999999999999967,
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
        bytes memory contractAddress = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            "",
            accounts
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
        assertEq(token2B.balanceOf(user2), 65655986959878634837); 
    }

    // A swap - zetachain swap - TON: token1A -> token2A -> token2Z -> token1Z -> token1B
    function test_ASwap2ZSwap2TON() public {
        address fromToken = address(token1A);
        uint256 amount = 100 ether;
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
        address asset = address(token2A);
        uint32 dstChainId = 2015140;
        address targetZRC20 = address(token1Z);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = tonAddress;
        address targetContract = address(gatewayCrossChain);
        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            address(token2Z),
            address(token1Z),
            33329999999999999967,
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
        bytes memory contractAddress = "";
        bytes memory accounts = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            "",
            accounts
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
        assertEq(token1B.balanceOf(user2), 15664999999999999983); 
    }

    function test_SuperWithdraw() public {
        token1Z.mint(address(gatewayCrossChain), initialBalance);
        gatewayCrossChain.superWithdraw(address(token1Z), initialBalance);
        assertEq(token1Z.balanceOf(EddyTreasurySafe), initialBalance);

        deal(address(gatewayCrossChain), initialBalance);
        gatewayCrossChain.superWithdraw(_ETH_ADDRESS_, initialBalance);
        assertEq(EddyTreasurySafe.balance, initialBalance);
    }

    function test_ZOnRevert() public {
        token1Z.mint(address(gatewayCrossChain), 2 * initialBalance);

        bytes32 externalId1 = keccak256(abi.encodePacked(block.timestamp));
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onRevert(
            RevertContext({
                sender: address(this),
                asset: address(token1Z),
                amount: initialBalance,
                revertMessage: bytes.concat(externalId1, abi.encodePacked(user2))
            })
        );

        assertEq(token1Z.balanceOf(bot), initialBalance);

        bytes32 externalId2 = keccak256(abi.encodePacked(block.timestamp + 600));
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onRevert(
            RevertContext({
                sender: address(this),
                asset: address(token1Z),
                amount: initialBalance,
                revertMessage: bytes.concat(externalId2, solAddress)
            })
        );

        assertEq(token1Z.balanceOf(bot), 2 * initialBalance);
    }

    function test_ZOnAbort() public {
        token1Z.mint(address(gatewayCrossChain), 2 * initialBalance);

        bytes32 externalId1 = keccak256(abi.encodePacked(block.timestamp));
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onAbort(
            AbortContext({
                sender: abi.encode(address(this)),
                asset: address(token1Z),
                amount: initialBalance,
                outgoing: false,
                chainID: 7000,
                revertMessage: bytes.concat(externalId1, abi.encodePacked(user2))
            })
        );

        assertEq(token1Z.balanceOf(bot), initialBalance);

        bytes32 externalId2 = keccak256(abi.encodePacked(block.timestamp + 600));
        vm.prank(address(gatewayZEVM));
        gatewayCrossChain.onAbort(
            AbortContext({
                sender: abi.encode(address(this)),
                asset: address(token1Z),
                amount: initialBalance,
                outgoing: false,
                chainID: 7000,
                revertMessage: bytes.concat(externalId2, solAddress)
            })
        );

        assertEq(token1Z.balanceOf(bot), 2 * initialBalance);
    }

    function test_Set() public {
        gatewayCrossChain.transferOwnership(user1);

        vm.startPrank(user1);
        gatewayCrossChain.setDODORouteProxy(address(0x111));
        gatewayCrossChain.setDODOApprove(address(0x111));
        gatewayCrossChain.setFeePercent(0);
        gatewayCrossChain.setGateway(payable(address(0x111)));
        gatewayCrossChain.setEddyTreasurySafe(address(0x111));
        gatewayCrossChain.setBot(address(0x111));
        vm.stopPrank();
    }

    function test_Revert() public {
        uint32 dstChainId = 8332;
        address targetZRC20 = address(btcZ);
        bytes memory sender = abi.encodePacked(user1);
        bytes memory receiver = btcAddress;
        bytes memory swapDataZ = "";
        bytes memory contractAddress = "";
        bytes memory swapDataB = "";
        bytes memory payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            swapDataB,
            ""
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

        dstChainId = 1399811149;
        targetZRC20 = address(token2Z);
        receiver = solAddress;
        payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            swapDataB,
            ""
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
        receiver = abi.encodePacked(user2);
        payload = encodeMessage(
            dstChainId,
            targetZRC20,
            sender,
            receiver,
            swapDataZ,
            contractAddress,
            swapDataB,
            ""
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