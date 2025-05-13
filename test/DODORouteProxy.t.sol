// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
// import { IGatewayEVM, MessageContext } from "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {SwapDataHelperLib} from "../contracts/libraries/SwapDataHelperLib.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

interface IDODORouteProxy {
    function mixSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 expReturnAmount,
        uint256 minReturnAmount,
        address[] memory mixAdapters,
        address[] memory mixPairs,
        address[] memory assetTo,
        uint256 directions,
        bytes[] memory moreInfos,
        bytes memory feeData,
        uint256 deadLine
    ) external payable returns (uint256 returnAmount);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external;
}

interface IGatewayTransferNative {
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external;

    function withdrawToNativeChain(
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external;
}

interface IGatewayCrossChain {
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external;
}

interface IGatewaySend {
    function onCall(
        MessageContext calldata context,
        bytes calldata message
    ) external;
}

interface IERC20Custody {
    function withdrawAndCall(
        MessageContext calldata messageContext,
        address to,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;
}

/* forge test --fork-url https://zetachain-athens-evm.blockpi.network/v1/rpc/public */
contract DODORouteProxyTest is Test {
    IDODORouteProxy routeProxy;
    IGatewayTransferNative gatewayTransferNative;
    IGatewayCrossChain gatewayCrossChain;
    IGatewaySend gatewaySend;
    IERC20Custody custody;
    address DODORouteProxy = 0x026eea5c10f526153e7578E5257801f8610D1142;
    address DODOApprove = 0x143bE32C854E4Ddce45aD48dAe3343821556D0c3;

    function setUp() public {
        routeProxy = IDODORouteProxy(0x026eea5c10f526153e7578E5257801f8610D1142);
        gatewayTransferNative = IGatewayTransferNative(0x056FcE6B76AF3050F54B71Fc9B5fcb7C387BfC1A);
        gatewayCrossChain = IGatewayCrossChain(0xDA89314035264Ade23313f971AaE5393068Ea6F7);
        // custody = IERC20Custody(0xD80BE3710F08D280F51115e072e5d2a778946cd7);
        // gatewaySend = IGatewaySend(0x7C5168756AD5ad9511201Fbc057EaB85B8559E69);
    }

    function test_withdrawAndCall() public {
        bytes32 externalId = 0x718d1982863734e3deb327c06feed362bcc3058b6a6d28b8f33d09fcc453d97b;
        bytes memory message = buildOutputMessage(
            externalId,
            982432,
            abi.encodePacked(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0),
            abi.encodePacked(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, "")
        );
        // vm.prank(0x8531a5aB847ff5B22D855633C25ED1DA3255247e);
        // custody.withdrawAndCall(
        //     MessageContext({
        //         sender: 0x90387d098B8F2a6497c55E13E45f51De423322ab
        //     }),
        //     0x7C5168756AD5ad9511201Fbc057EaB85B8559E69,
        //     0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
        //     982432,
        //     message
        // );

        // vm.prank(0x0c487a766110c85d301D96E33579C5B317Fa4995);
        // gatewaySend.onCall(
        //     MessageContext({
        //         sender: 0x90387d098B8F2a6497c55E13E45f51De423322ab
        //     }),
        //     message
        // );
    }

    // function test_mixSwap() public {
    //     address[] memory mixAdapters = new address[](1);
    //     mixAdapters[0] = 0x0f9053E174c123098C17e60A2B1FAb3b303f9e29;

    //     address[] memory mixPairs = new address[](1);
    //     mixPairs[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;

    //     address[] memory assetTo = new address[](2);
    //     assetTo[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;
    //     assetTo[1] = 0x026eea5c10f526153e7578E5257801f8610D1142;

    //     bytes[] memory moreInfo = new bytes[](1);
    //     moreInfo[0] = "";

    //     vm.prank(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0);
    //     routeProxy.mixSwap(
    //         0xcC683A782f4B30c138787CB5576a86AF66fdc31d, // USDC.SEP
    //         0x4bC32034caCcc9B7e02536945eDbC286bACbA073, // USDC.ARBSEP
    //         1000000,
    //         998753,
    //         950000,
    //         mixAdapters,
    //         mixPairs,
    //         assetTo,
    //         1,
    //         moreInfo,
    //         abi.encode(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0, 0),
    //         block.timestamp + 200
    //     );
    // }

    // function test_OnCall() public {
    //     bytes32 externalId = 0xd0dc2a7a27f737ce25b3ee02c13f8db3a209be0ef152f26c439afb979b121c8b;
    //     address[] memory mixAdapters = new address[](1);
    //     mixAdapters[0] = 0x0f9053E174c123098C17e60A2B1FAb3b303f9e29;

    //     address[] memory mixPairs = new address[](1);
    //     mixPairs[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;

    //     address[] memory assetTo = new address[](2);
    //     assetTo[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;
    //     assetTo[1] = 0x026eea5c10f526153e7578E5257801f8610D1142;

    //     bytes[] memory moreInfo = new bytes[](1);

    //     address targetZRC20 = 0x4bC32034caCcc9B7e02536945eDbC286bACbA073;
    //     bytes memory swapDataZ = abi.encodeWithSelector(
    //         0xff84aafa,
    //         0xcC683A782f4B30c138787CB5576a86AF66fdc31d,
    //         0x4bC32034caCcc9B7e02536945eDbC286bACbA073,
    //         1000000,
    //         998753,
    //         950000,
    //         mixAdapters,
    //         mixPairs,
    //         assetTo,
    //         1,
    //         moreInfo,
    //         abi.encode(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0, 0),
    //         1745510034
    //     );

    //     bytes memory payload = bytes.concat(
    //         bytes20(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0),
    //         bytes20(targetZRC20),
    //         swapDataZ
    //     );
    //     bytes memory revertAddress = abi.encode(externalId, targetZRC20, 1000000, msg.sender);
    //     console.log(revertAddress.length);
    //     console.logBytes(payload);
    //     console.logBytes(swapDataZ);
    //     console.log(payload.length);

    //     deal(0xcC683A782f4B30c138787CB5576a86AF66fdc31d, address(gatewayTransferNative), 1500000);
    //     vm.prank(0x6c533f7fE93fAE114d0954697069Df33C9B74fD7);
    //     gatewayTransferNative.onCall(
    //         MessageContext({
    //             origin: "",
    //             sender: address(this),
    //             chainID: 0
    //         }),
    //         0xcC683A782f4B30c138787CB5576a86AF66fdc31d,
    //         1500000,
    //         bytes.concat(externalId, payload)
    //     );
    // }

    function test_CrossChain() public {
        bytes32 externalId = 0xd0dc2a7a27f737ce25b3ee02c13f8db3a209be0ef152f26c439afb979b121c8b;

        uint32 dstChainId = 421614;
        address targetZRC20 = 0xcC683A782f4B30c138787CB5576a86AF66fdc31d;
        bytes memory evmWalletAddress = abi.encodePacked(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0);
        address[] memory mixAdapters = new address[](1);
        mixAdapters[0] = 0x0f9053E174c123098C17e60A2B1FAb3b303f9e29;

        address[] memory mixPairs = new address[](1);
        mixPairs[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;

        address[] memory assetTo = new address[](2);
        assetTo[0] = 0x4f59b88556c1B133939b2655729Ad53226ed5FAD;
        assetTo[1] = 0x026eea5c10f526153e7578E5257801f8610D1142;

        bytes[] memory moreInfo = new bytes[](1);

        // bytes memory swapDataZ = abi.encodeWithSelector(
        //     0xff84aafa,
        //     0xcC683A782f4B30c138787CB5576a86AF66fdc31d,
        //     0x4bC32034caCcc9B7e02536945eDbC286bACbA073,
        //     1000000,
        //     983200,
        //     950000,
        //     mixAdapters,
        //     mixPairs,
        //     assetTo,
        //     1,
        //     moreInfo,
        //     abi.encode(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0, 0),
        //     1745554791
        // );

        bytes memory swapDataZ = encodeCompressedMixSwapParams(
            0x4bC32034caCcc9B7e02536945eDbC286bACbA073,
            0xcC683A782f4B30c138787CB5576a86AF66fdc31d,
            1000000,
            1047744,
            1000000,
            mixAdapters,
            mixPairs,
            assetTo,
            0,
            moreInfo,
            abi.encode(address(0), 0),
            1845554791
        );
        bytes memory contractAddress = abi.encodePacked(0xa3CC1a1D7e4d2aE02b9D31E63D859f2413D7Cf27);
        bytes memory swapDataB = "";
        bytes memory payload = buildCompressedMessage(
            dstChainId,
            targetZRC20,
            evmWalletAddress,
            swapDataZ,
            contractAddress,
            abi.encodePacked(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, swapDataB)
        );
        console.logBytes(swapDataZ);
        console.logBytes(abi.encode(address(0), 0));
        console.logBytes(payload);
        console.log(payload.length);
        console.log(bytes.concat(externalId, payload).length);

        deal(0x4bC32034caCcc9B7e02536945eDbC286bACbA073, address(gatewayCrossChain), 1500000);
        vm.prank(0x6c533f7fE93fAE114d0954697069Df33C9B74fD7);
        gatewayCrossChain.onCall(
            MessageContext({
                origin: "",
                sender: address(this),
                chainID: 0
            }),
            0x4bC32034caCcc9B7e02536945eDbC286bACbA073,
            1500000,
            bytes.concat(externalId, payload)
        );
    }

    function buildCompressedMessage(
        uint32 dstChainId,
        address targetZRC20,
        bytes memory receiver,
        bytes memory swapDataZ,
        bytes memory contractAddress,
        bytes memory swapDataB
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            bytes4(dstChainId),
            bytes20(targetZRC20),
            uint16(receiver.length),
            uint16(contractAddress.length),
            uint16(swapDataZ.length),
            uint16(swapDataB.length),
            receiver,
            contractAddress,
            swapDataZ,
            swapDataB
        );
    }

    // function test_WithdrawToNativeChain() public {
    //     bytes32 externalId = 0xd0dc2a7a27f737ce25b3ee02c13f8db3a209be0ef152f26c439afb979b121c8b;

    //     address[] memory mixAdapters = new address[](1);
    //     mixAdapters[0] = 0x0f9053E174c123098C17e60A2B1FAb3b303f9e29;

    //     address[] memory mixPairs = new address[](1);
    //     mixPairs[0] = 0x973CAFEDB651D710CD1890ebc5C207D836BA5E9F;

    //     address[] memory assetTo = new address[](2);
    //     assetTo[0] = 0x973CAFEDB651D710CD1890ebc5C207D836BA5E9F;
    //     assetTo[1] = 0x026eea5c10f526153e7578E5257801f8610D1142;

    //     bytes[] memory moreInfo = new bytes[](1);
    //     moreInfo[0] = "";
    //     uint32 dstChainId = 7000;
    //     address targetZRC20 = 0x0246DffDa649e877CFd0951837332B4690fAD1EB;
    //     bytes memory receiver = abi.encodePacked(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0);
    //     bytes memory swapDataZ = abi.encodeWithSelector(
    //         0xff84aafa,
    //         0xdbfF6471a79E5374d771922F2194eccc42210B9F,
    //         0x0246DffDa649e877CFd0951837332B4690fAD1EB,
    //         1000,
    //         99997500140614649,
    //         89997750126553184,
    //         mixAdapters,
    //         mixPairs,
    //         assetTo,
    //         0,
    //         moreInfo,
    //         abi.encode(address(0), 0),
    //         1746702227
    //     );
    //     bytes memory contractAddress = "";
    //     bytes memory swapDataB = "";
    //     bytes memory payload = bytes.concat(
    //         bytes20(0xfa0d8ebcA31a1501144A785a2929e9F91b0571d0),
    //         bytes20(targetZRC20),
    //         swapDataZ
    //     );
    //     console.logBytes(abi.encode(address(0), 0));
    //     console.logBytes(payload);

    //     deal(0xdbfF6471a79E5374d771922F2194eccc42210B9F, address(gatewayTransferNative), 2000);
    //     vm.prank(0x6c533f7fE93fAE114d0954697069Df33C9B74fD7);
    //     gatewayTransferNative.onCall(
    //         MessageContext({
    //             origin: "",
    //             sender: address(this),
    //             chainID: 0
    //         }),
    //         0xdbfF6471a79E5374d771922F2194eccc42210B9F,
    //         2000,
    //         bytes.concat(externalId, payload)
    //     );
    // }

    function encodeCompressedMixSwapParams(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 expReturnAmount,
        uint256 minReturnAmount,
        address[] memory mixAdapters,
        address[] memory mixPairs,
        address[] memory assetTo,
        uint256 directions,
        bytes[] memory moreInfo,
        bytes memory feeData,
        uint256 deadline
    ) public pure returns (bytes memory) {
        bytes memory encoded = abi.encodePacked(
            fromToken,
            toToken,
            fromTokenAmount,
            expReturnAmount,
            minReturnAmount,
            directions,
            deadline
        );

        encoded = bytes.concat(
            encoded,
            encodeAddressArray(mixAdapters),
            encodeAddressArray(mixPairs),
            encodeAddressArray(assetTo),
            encodeBytesArrayWithLens(moreInfo),
            encodeBytesWith2Len(feeData)
        );

        return encoded;
    }

    function encodeAddressArray(address[] memory arr) internal pure returns (bytes memory out) {
        require(arr.length <= 255, "Too many addresses");
        out = abi.encodePacked(uint8(arr.length));
        for (uint i = 0; i < arr.length; i++) {
            out = bytes.concat(out, abi.encodePacked(arr[i]));
        }
    }

    function encodeBytesWith2Len(bytes memory data) internal pure returns (bytes memory out) {
        require(data.length <= 65535, "Too long");
        out = abi.encodePacked(uint16(data.length), data);
    }

    function encodeBytesArrayWithLens(bytes[] memory arr) internal pure returns (bytes memory out) {
        require(arr.length <= 255, "Too many items");
        out = abi.encodePacked(uint8(arr.length));
        for (uint i = 0; i < arr.length; i++) {
            require(arr[i].length <= 65535, "Item too long");
            out = bytes.concat(out, abi.encodePacked(uint16(arr[i].length)));
        }
        for (uint i = 0; i < arr.length; i++) {
            out = bytes.concat(out, arr[i]);
        }
    }

    function buildOutputMessage(
        bytes32 externalId,
        uint256 outputAmount,
        bytes memory receiver,
        bytes memory swapDataB
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            externalId,
            bytes32(outputAmount),
            uint16(receiver.length),
            uint16(swapDataB.length),
            receiver,
            swapDataB
        );
    }
}