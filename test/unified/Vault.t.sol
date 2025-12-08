// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../contracts/unified/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../../contracts/unified/Vault.sol";
import {ZRC20Mock} from "../../contracts/mocks/ZRC20Mock.sol";

contract VaultTest is Test {
    Vault public vault;
    ZRC20Mock public token1;
    ZRC20Mock public token2;

    address public minter = address(0x123);
    address public user = address(0x456);
    address public owner = address(this);

    event MinterSet(address indexed minter);

    function setUp() public {
        vault = new Vault(); 
        token1 = new ZRC20Mock("Token1", "TK.1", 6);
        token2 = new ZRC20Mock("Token2", "TK.2", 18);

        // set Minter
        vault.setMinter(minter);

        // prepare token
        token1.mint(minter, 1_000e6);
        token2.mint(minter, 1_000e18);
        token1.mint(address(vault), 1_000e6);
        token2.mint(address(vault), 1_000e18);
    }

    function test_SetMinter() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setMinter(minter);

        vm.expectRevert("Vault: INVALID_ADDRESS");
        vault.setMinter(address(0));

        vm.expectEmit(true, false, false, true);
        emit MinterSet(minter);
        vault.setMinter(minter);

        assertEq(vault.minter(), minter);
    }

    function test_Collect() public {
        uint256 amount = 100e6;

        vm.prank(minter);
        token1.approve(address(vault), amount);

        vm.prank(user);
        vm.expectRevert("Vault: NOT_MINTER");
        vault.collect(address(token1), user, amount);

        uint256 minterBefore = token1.balanceOf(minter);
        uint256 vaultBefore = vault.getBalance(address(token1));

        vm.prank(minter);
        vault.collect(address(token1), minter, amount);

        assertEq(token1.balanceOf(minter), minterBefore - amount);
        assertEq(vault.getBalance(address(token1)), vaultBefore + amount);
    }

    function test_Payout() public {
        uint256 amount = 100e18;

        vm.prank(user);
        vm.expectRevert("Vault: NOT_MINTER");
        vault.payout(address(token2), minter, amount);

        uint256 minterBefore = token2.balanceOf(minter);
        uint256 vaultBefore = vault.getBalance(address(token2));

        vm.prank(minter);
        vault.payout(address(token2), minter, amount);

        assertEq(token2.balanceOf(minter), minterBefore + amount);
        assertEq(vault.getBalance(address(token2)), vaultBefore - amount);
    }

    function test_Withdraw() public {
        uint256 amount1 = 100e6;
        uint256 vaultBefore1 = vault.getBalance(address(token1));
        uint256 ownerBefore1 = token1.balanceOf(owner);

        vm.prank(user);
        vm.expectRevert();
        vault.withdraw(address(token1), user, amount1);

        vault.withdraw(address(token1), owner, amount1);

        assertEq(vault.getBalance(address(token1)), vaultBefore1 - amount1);
        assertEq(token1.balanceOf(owner), ownerBefore1 + amount1);

        uint256 amount2 = 100e18;
        uint256 vaultBefore2 = vault.getBalance(address(token2));
        uint256 ownerBefore2 = token2.balanceOf(owner);

        vault.withdraw(address(token2), owner, amount2);

        assertEq(vault.getBalance(address(token2)), vaultBefore2 - amount2);
        assertEq(token2.balanceOf(owner), ownerBefore2 + amount2);
    }
}

