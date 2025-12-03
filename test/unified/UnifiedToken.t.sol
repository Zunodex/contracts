// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UnifiedToken} from "../../contracts/unified/UnifiedToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UnifiedTokenTest is Test {
    UnifiedToken public uToken;

    address public minter = address(0x123);
    address public user = address(0x456);

    event MinterSet(address indexed minter);

    function setUp() public {
        uToken = new UnifiedToken();

        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string)",
            "Unified Token",
            "UTK"
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(uToken), data);

        uToken = UnifiedToken(address(proxy));

        // set Minter
        uToken.setMinter(minter);
    }

    function test_Initialize() public view {
        assertEq(uToken.name(), "Unified Token");
        assertEq(uToken.symbol(), "UTK");
        assertEq(uToken.owner(), address(this));
    }

    function test_SetMinter() public {
        vm.prank(user);
        vm.expectRevert();
        uToken.setMinter(minter);

        vm.expectRevert("UnifiedToken: INVALID_ADDRESS");
        uToken.setMinter(address(0));

        vm.expectEmit(true, false, false, true);
        emit MinterSet(minter);
        uToken.setMinter(minter);

        assertEq(uToken.minter(), minter);
    }

    function test_Mint() public {
        uint256 amount = 1_000e18;

        vm.prank(user);
        vm.expectRevert("UnifiedToken: NOT_MINTER");
        uToken.mint(user, amount);

        vm.prank(minter);
        uToken.mint(user, amount);

        assertEq(uToken.balanceOf(user), amount);
        assertEq(uToken.totalSupply(), amount);
    }

    function test_Burn() public {
        uint256 amount = 1_000e18;

        vm.prank(minter);
        uToken.mint(minter, amount);

        assertEq(uToken.balanceOf(minter), amount);
        assertEq(uToken.totalSupply(), amount);

        vm.prank(user);
        vm.expectRevert("UnifiedToken: NOT_MINTER");
        uToken.burn(amount);

        vm.prank(minter);
        uToken.burn(amount);

        assertEq(uToken.balanceOf(minter), 0);
        assertEq(uToken.totalSupply(), 0);
    }
}