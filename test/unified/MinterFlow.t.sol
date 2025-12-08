// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinterAdapter} from "../../contracts/unified/MinterAdapter.sol";
import {Minter} from "../../contracts/unified/Minter.sol";
import {UnifiedToken} from "../../contracts/unified/UnifiedToken.sol";
import {Vault} from "../../contracts/unified/Vault.sol";
import {ZRC20Mock} from "../../contracts/mocks/ZRC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MinterFlowTest is Test {
    Minter public minter;
    MinterAdapter public adapter;
    Vault public vault;
    ZRC20Mock public token1;
    ZRC20Mock public token2;
    UnifiedToken public uToken;

    function setUp() public {
        token1 = new ZRC20Mock("Token1", "TK.1", 6);
        token2 = new ZRC20Mock("Token2", "TK.2", 18);

        uToken = new UnifiedToken();
        minter = new Minter();
        vault = new Vault();
        adapter = new MinterAdapter();

        // initialize UnifiedToken
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string)",
            "Unified Token",
            "UTK"
        );
        ERC1967Proxy uTokenProxy = new ERC1967Proxy(
            address(uToken),
            data
        );
        uToken = UnifiedToken(address(uTokenProxy));

        // initialize Minter
        data = abi.encodeWithSignature(
            "initialize(address,address)",
            address(uToken),
            address(vault)
        );
        ERC1967Proxy minterProxy = new ERC1967Proxy(
            address(minter),
            data
        );
        minter = Minter(address(minterProxy));

        // register asset
        address[] memory assetList = new address[](3);
        assetList[0] = address(token1);
        assetList[1] = address(token2);
        assetList[2] = address(uToken);

        bool[] memory enabledList = new bool[](3);
        enabledList[0] = true;
        enabledList[1] = true;
        enabledList[2] = true;

        uint256[] memory minOrderList = new uint256[](3);
        minOrderList[0] = 0;
        minOrderList[1] = 0;
        minOrderList[2] = 0;

        uint256[] memory maxOrderList = new uint256[](3);
        maxOrderList[0] = 0;
        maxOrderList[1] = 0;
        maxOrderList[2] = 0;

        minter.registerAssets(assetList, enabledList, minOrderList, maxOrderList);

        // set adapter
        minter.setAdapter(address(adapter), true);

        // set minter
        vault.setMinter(address(minter));
        uToken.setMinter(address(minter));

        // prepare token
        token1.mint(address(this), 10_000e6);
        token2.mint(address(this), 10_000e18);
        token1.mint(address(vault), 10_000e6);
        token2.mint(address(vault), 10_000e18);
    }

    // token -> uToken
    function test_SellBase() public {
        uint256 amount = 100e6;
        token1.mint(address(adapter), amount);

        assertEq(token1.balanceOf(address(adapter)), amount);

        uint256 vaultBefore = vault.getBalance(address(token1));

        adapter.sellBase(
            address(adapter), 
            address(minter), 
            abi.encode(address(token1), address(uToken))
        );

        assertEq(token1.balanceOf(address(adapter)), 0);
        assertEq(vault.getBalance(address(token1)), vaultBefore + 100e6);
        assertEq(uToken.balanceOf(address(adapter)), 100e18);
        assertEq(uToken.totalSupply(), 100e18);
    }

    // uToken -> token
    function test_SellQuote() public {
        uint256 amount = 100e18;
        vm.prank(address(minter));
        uToken.mint(address(adapter), amount);

        assertEq(uToken.balanceOf(address(adapter)), amount);

        uint256 vaultBefore = vault.getBalance(address(token1));

        adapter.sellQuote(
            address(adapter), 
            address(minter), 
            abi.encode(address(uToken), address(token1))
        );

        assertEq(uToken.balanceOf(address(adapter)), 0);
        assertEq(uToken.totalSupply(), 0);
        assertEq(vault.getBalance(address(token1)), vaultBefore - 100e6);
        assertEq(token1.balanceOf(address(adapter)), 100e6);
    }
}