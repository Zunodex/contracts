// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vault is Ownable {
    address public minter;

    event MinterSet(address indexed minter);

    modifier onlyMinter() {
        require(msg.sender == minter, "Vault: NOT_MINTER");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Vault: INVALID_ADDRESS");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function collect(address asset, address from, uint256 amount) external onlyMinter {
        IERC20(asset).transferFrom(from, address(this), amount);
    }

    function payout(address asset, address to, uint256 amount) external onlyMinter {
        IERC20(asset).transfer(to, amount);
    }
}
