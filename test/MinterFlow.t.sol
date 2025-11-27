// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinterAdapter} from "../contracts/token/MinterAdapter.sol";
import {Minter} from "../contracts/token/Minter.sol";
import {ZRC20Mock} from "../contracts/mocks/ZRC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MinterFlowTest is Test {
    Minter public minter;
    MinterAdapter public adapter;
    ZRC20Mock public token1;
    ZRC20Mock public token2;
    ZRC20Mock public uToken; // replace with utoken

    function setUp() public {
        token1 = new ZRC20Mock("Token1", "TK.1", 6);
        token2 = new ZRC20Mock("Token2", "TK.2", 18);
        uToken = new ZRC20Mock("UnifiedToken", "UTK", 18);

        minter = new Minter();

        // set Minter
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address)",
            address(uToken),
            address(1)
        );
        ERC1967Proxy minterProxy = new ERC1967Proxy(
            address(minter),
            data
        );
        minter = Minter(address(minterProxy));

        adapter = MinterAdapter(address(minter));

        // register asset
        minter.registerAsset(address(token1), true, 0, 0);
        minter.registerAsset(address(token2), true, 0, 0);
        minter.registerAsset(address(uToken), true, 0, 0);

        // set adapter
        minter.setAdapter(address(adapter), true);

        // prepare token
        token1.mint(address(this), 10000e6);
        token2.mint(address(this), 10000e18);
    }

    function test_SellBase() public {
    }

    function test_SellQuote() public {

    }
}