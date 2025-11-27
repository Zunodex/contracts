// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {MinterFlowTest} from "./MinterFlow.t.sol";
import {Minter} from "../contracts/token/Minter.sol";
import {MinterAdapter} from "../contracts/token/MinterAdapter.sol";
import {ZRC20Mock} from "../contracts/mocks/ZRC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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
        assertEq(minter._UTOKEN_(), address(uToken));
        // assertEq(minter._VAULT_(), address(vault));
    }

    function test_RegisterAsset() public {
        ZRC20Mock token3 = new ZRC20Mock("Token3", "TK.3", 18);

        vm.expectEmit(true, false, false, true);
        emit AssetRegistered(address(token3), true, 100, 1000);
        minter.registerAsset(address(token3), true, 100, 1000);

        (address asset, bool enabled, uint256 minOrder, uint256 maxOrder) = minter.assets(address(token3));
        assertEq(asset, address(token3));
        assertTrue(enabled);
        assertEq(minOrder, 100);
        assertEq(maxOrder, 1000);
    }

    function test_Revert_RegisterZeroAsset() public {
        vm.expectRevert(bytes("Minter: INVALID_ADDRESS"));
        minter.registerAsset(address(0), true, 0, 0);
    }

    function test_UpdateAsset() public {
        (address asset0, bool enabled0, uint256 minOrder0, uint256 maxOrder0) = minter.assets(address(token1));
        assertEq(asset0, address(token1));
        assertTrue(enabled0);
        assertEq(minOrder0, 0);
        assertEq(maxOrder0, 0);

        vm.expectEmit(true, false, false, true);
        emit AssetUpdated(address(token1), false, 10, 20);
        minter.updateAsset(address(token1), false, 10, 20);

        (address asset1, bool enabled1, uint256 minOrder1, uint256 maxOrder1) = minter.assets(address(token1));
        assertEq(asset1, address(token1));
        assertFalse(enabled1);
        assertEq(minOrder1, 10);
        assertEq(maxOrder1, 20);
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

        vm.prank(user);
        vm.expectRevert();
        minter.registerAsset(address(0x2222), true, 0, 0);

        vm.prank(user);
        vm.expectRevert();
        minter.updateAsset(address(0x3333), true, 0, 0);
    }

    function test_ExecuteMintScaleUp() public {
        minter.updateAsset(address(token1), true, 0, 0);

        uint256 amount = 100e6;

        vm.prank(address(adapter));
        minter.execute(true, address(token1), address(uToken), amount, user);
    }

    function test_ExecuteBurnScaleDown() public {
        minter.updateAsset(address(uToken), true, 0, 0);

        uint256 amount = 100e18;

        uToken.mint(address(minter), amount);
        assertEq(uToken.balanceOf(address(minter)), amount);

        vm.prank(address(adapter));
        minter.execute(false, address(uToken), address(token1), amount, user);
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
        minter.updateAsset(address(token1), true, 100, 1000);

        // amount < min -> underflow
        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: UNDERFLOW"));
        minter.execute(true, address(token1), address(uToken), 99, user);

        // amount > max -> overflow
        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: OVERFLOW"));
        minter.execute(true, address(token1), address(uToken), 1001, user);

        // min <= amount <= max -> executed
        vm.prank(address(adapter));
        minter.execute(true, address(token1), address(uToken), 500, user);
    }

    function test_Revert_ExecuteTokenNotMatch() public {
        address otherToken = address(0x1234);

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: TOKEN_ADDRESS_NOT_MATCH"));
        minter.execute(true, address(token1), address(otherToken), 100e6, user);

        vm.prank(address(adapter));
        vm.expectRevert(bytes("Minter: TOKEN_ADDRESS_NOT_MATCH"));
        minter.execute(false, address(otherToken), address(token1), 100e18, user);
    }
}
