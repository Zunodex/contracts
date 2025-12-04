// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MinterFlowTest} from "./MinterFlow.t.sol";
import {Minter} from "../../contracts/unified/Minter.sol";
import {MinterAdapter} from "../../contracts/unified/MinterAdapter.sol";
import {ZRC20Mock} from "../../contracts/mocks/ZRC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract MinterTest is MinterFlowTest {
    address public user = address(0x111);

    event AdapterSet(address indexed adapter, bool isAllowd);
    event AssetRegistered(
        address indexed asset, 
        bool enabled, 
        uint256 minOrder, 
        uint256 maxOrder
    );
    event AssetUpdated(        
        address indexed asset,  
        bool enabled, 
        uint256 minOrder, 
        uint256 maxOrder
    );
    event Executed(address indexed fromToken, address indexed toToken, uint256 amount, address to);
    event Paused(bool isOn);

    function test_Revert_InitializeInvalidAddress() public {
        Minter impl = new Minter();
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address)",
            address(0),
            address(0)
        );

        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        new ERC1967Proxy(address(impl), data);
    }

    function test_InitializeSetConfig() public view {
        assertEq(minter.uToken(), address(uToken));
        assertEq(minter.vault(), address(vault));
    }

    function test_RegisterAsset() public {
        ZRC20Mock token3 = new ZRC20Mock("Token3", "TK.3", 18);

        address[] memory assetList = new address[](1);
        assetList[0] = address(token3);

        bool[] memory enabledList = new bool[](1);
        enabledList[0] = true;

        uint256[] memory minOrderList = new uint256[](1);
        minOrderList[0] = 100e18;

        uint256[] memory maxOrderList = new uint256[](1);
        maxOrderList[0] = 1_000e18;

        vm.expectEmit(true, false, false, true);
        emit AssetRegistered(address(token3), true, 100e18, 1_000e18);
        minter.registerAssets(assetList, enabledList, minOrderList, maxOrderList);

        (address asset, bool enabled, uint256 minOrder, uint256 maxOrder) = minter.assets(address(token3));
        assertEq(asset, address(token3));
        assertTrue(enabled);
        assertEq(minOrder, 100e18);
        assertEq(maxOrder, 1_000e18);
    }

    function test_Revert_RegisterZeroAsset() public {
        address[] memory assetList = new address[](1);
        assetList[0] = address(0);

        bool[] memory enabledList = new bool[](1);
        enabledList[0] = true;

        uint256[] memory minOrderList = new uint256[](1);
        minOrderList[0] = 0;

        uint256[] memory maxOrderList = new uint256[](1);
        maxOrderList[0] = 0;

        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        minter.registerAssets(assetList, enabledList, minOrderList, maxOrderList);
    }

    function test_Revert_RegisterAssetLengthNotMatch() public {
        address[] memory assetList = new address[](1);
        assetList[0] = address(0x123);

        bool[] memory enabledList = new bool[](2);
        enabledList[0] = true;
        enabledList[1] = true;

        uint256[] memory minOrderList = new uint256[](1);
        minOrderList[0] = 0;

        uint256[] memory maxOrderList = new uint256[](1);
        maxOrderList[0] = 0;

        vm.expectRevert(bytes("Minter: LENGTH_NOT_MATCH"));
        minter.registerAssets(assetList, enabledList, minOrderList, maxOrderList);
    }

    function test_UpdateAsset() public {
        (address asset0, bool enabled0, uint256 minOrder0, uint256 maxOrder0) = minter.assets(address(token1));
        assertEq(asset0, address(token1));
        assertTrue(enabled0);
        assertEq(minOrder0, 0);
        assertEq(maxOrder0, 0);

        vm.expectEmit(true, false, false, true);
        emit AssetUpdated(address(token1), false, 10e6, 20e6);
        minter.updateAsset(address(token1), false, 10e6, 20e6);

        (address asset1, bool enabled1, uint256 minOrder1, uint256 maxOrder1) = minter.assets(address(token1));
        assertEq(asset1, address(token1));
        assertFalse(enabled1);
        assertEq(minOrder1, 10e6);
        assertEq(maxOrder1, 20e6);
    }

    function test_SetAdapter() public {
        MinterAdapter newAdapter = MinterAdapter(address(minter));

        vm.expectEmit(true, false, false, true);
        emit AdapterSet(address(newAdapter), true);
        minter.setAdapter(address(newAdapter), true);

        assertTrue(minter.isAdapter(address(newAdapter)));

        vm.expectEmit(true, false, false, true);
        emit AdapterSet(address(newAdapter), false);
        minter.setAdapter(address(newAdapter), false);

        assertFalse(minter.isAdapter(address(newAdapter)));
    }

    function test_SetPaused() public {
        vm.expectEmit(false, false, false, true);
        emit Paused(true);
        minter.setPaused(true);

        assertTrue(minter.paused());

        vm.expectEmit(false, false, false, true);
        emit Paused(false);
        minter.setPaused(false);

        assertFalse(minter.paused());
    }

    function test_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        minter.setAdapter(address(0x1111), true);

        vm.prank(user);
        vm.expectRevert();
        minter.setPaused(true);

        address[] memory assetList = new address[](1);
        assetList[0] = address(0x222);

        bool[] memory enabledList = new bool[](1);
        enabledList[0] = true;

        uint256[] memory minOrderList = new uint256[](1);
        minOrderList[0] = 0;

        uint256[] memory maxOrderList = new uint256[](1);
        maxOrderList[0] = 0;

        vm.prank(user);
        vm.expectRevert();
        minter.registerAssets(assetList, enabledList, minOrderList, maxOrderList);

        vm.prank(user);
        vm.expectRevert();
        minter.updateAsset(address(0x3333), true, 0, 0);
    }

    // token1 -> uToken
    function test_ExecuteMintScaleUp() public {
        minter.updateAsset(address(token1), true, 0, 0);

        uint256 amount = 100e6;
        token1.mint(address(adapter), amount);

        assertEq(token1.balanceOf(address(adapter)), amount);

        uint256 vaultBefore = token1.balanceOf(address(vault));

        vm.startPrank(address(adapter));
        token1.transfer(address(minter), amount);
        minter.execute(true, address(token1), address(uToken), amount, user);
        vm.stopPrank();

        assertEq(token1.balanceOf(address(adapter)), 0);
        assertEq(token1.balanceOf(address(vault)), vaultBefore + 100e6);
        assertEq(uToken.balanceOf(user), 100e18);
        assertEq(uToken.totalSupply(), 100e18);
    }

    // uToken -> token2
    function test_ExecuteBurnScaleDown() public {
        minter.updateAsset(address(uToken), true, 0, 0);

        uint256 amount = 100e18;
        vm.prank(address(minter));
        uToken.mint(address(adapter), amount);

        assertEq(uToken.balanceOf(address(adapter)), amount);

        uint256 vaultBefore = token2.balanceOf(address(vault));

        vm.startPrank(address(adapter));
        uToken.transfer(address(minter), amount);
        minter.execute(false, address(uToken), address(token2), amount, user);
        vm.stopPrank();

        assertEq(uToken.balanceOf(address(adapter)), 0);
        assertEq(uToken.totalSupply(), 0);
        assertEq(token2.balanceOf(address(vault)), vaultBefore - 100e18);
        assertEq(token2.balanceOf(user), 100e18);
    }


    function test_Revert_ExecuteNotAdapter() public {
        uint256 amount = 100e6;

        vm.expectRevert(bytes("Minter: NOT_ADAPTER"));
        minter.execute(true, address(token1), address(uToken), amount, user);
    }

    function test_Revert_ExecutePaused() public {
        minter.setPaused(true);

        uint256 amount = 100e6;
        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: PAUSED"));
        minter.execute(true, address(token1), address(uToken), amount, user);
    }

    function test_Revert_ExecuteZeroAddresses() public {
        uint256 amount = 100e6;

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        minter.execute(true, address(0), address(uToken), amount, user);

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        minter.execute(true, address(token1), address(0), amount, user);

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        minter.execute(true, address(token1), address(uToken), amount, address(0));
    }

    function test_Revert_ExecuteAssetDisabled() public {
        minter.updateAsset(address(token1), false, 0, 0);

        uint256 amount = 100e6;

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: ASSET_OFF"));
        minter.execute(true, address(token1), address(uToken), amount, user);
    }

    function test_Revert_ExecuteExceedMinMaxOrder() public {
        // min = 100
        // max = 1000
        minter.updateAsset(address(token1), true, 100e6, 1000e6);

        token1.mint(address(adapter), 2000e6);

        vm.startPrank(address(adapter));

        // amount < min -> underflow
        token1.transfer(address(minter), 99e6);
        vm.expectRevert(bytes("Minter: UNDERFLOW"));
        minter.execute(true, address(token1), address(uToken), 99e6, user);

        // amount > max -> overflow
        token1.transfer(address(minter), 1001e6);
        vm.expectRevert(bytes("Minter: OVERFLOW"));
        minter.execute(true, address(token1), address(uToken), 1001e6, user);

        // min <= amount <= max -> executed
        token1.transfer(address(minter), 500e6);
        minter.execute(true, address(token1), address(uToken), 500e6, user);

        vm.stopPrank();
    }

    function test_Revert_ExecuteTokenNotMatch() public {
        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: TOKEN_ADDRESS_NOT_MATCH"));
        minter.execute(true, address(token1), address(token2), 100e6, user);

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: TOKEN_ADDRESS_NOT_MATCH"));
        minter.execute(false, address(token2), address(token1), 100e18, user);
    }
}
