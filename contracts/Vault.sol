// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    mapping(address => bool) public bots;

    struct RefundInfo {
        bytes32 externalId;
        address token;
        uint256 amount;
        address to;
    }

    event BotUpdated(address bot, bool allowed);
    event RefundTransferred(bytes32 externalId, address indexed token, uint256 amount, address to);

    modifier onlyBot() {
        require(bots[msg.sender], "Not authorized bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setBot(address bot, bool allowed) external onlyOwner {
        bots[bot] = allowed;
        emit BotUpdated(bot, allowed);
    }

    // ==================== Bot Functions ====================

    function superWithdraw(address token, uint256 amount) external onlyBot {
        if (token == _ETH_ADDRESS_) {
            require(amount <= address(this).balance, "INVALID_AMOUNT");
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            require(amount <= IERC20(token).balanceOf(address(this)), "INVALID_AMOUNT");
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
    }

    /**
     * @notice Transfer refunds in batch for a specific token.
     * @dev Supports both native token and ERC20.
     * @param token The address of the token to transfer (use _ETH_ADDRESS_ for native token).
     * @param infos An array of RefundInfo objects, each containing externalId, token, amount, and recipient.
     */
    function batchTransferRefund(address token, RefundInfo[] calldata infos) external onlyBot {
        require(token != address(0), "INVALID_TOKEN");
        require(infos.length > 0, "EMPTY_INPUT");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < infos.length; i++) {
            RefundInfo calldata info = infos[i];
            require(info.token == token, "TOKEN_MISMATCH");
            require(info.to != address(0), "INVALID_RECIPIENT");

            totalAmount += info.amount;

            // Transfer token or native ETH
            if (token == _ETH_ADDRESS_) {
                require(getBalance(token) >= info.amount, "INSUFFICIENT_ETH");
                TransferHelper.safeTransferETH(info.to, info.amount);
            } else {
                require(getBalance(token) >= info.amount, "INSUFFICIENT_TOKEN");
                TransferHelper.safeTransfer(token, info.to, info.amount);
            }

            // Emit individual refund transferred event
            emit RefundTransferred(
                info.externalId, 
                token, 
                info.amount,
                info.to
            );
        }
    }

    function getBalance(address token) public view returns (uint256 balance) {
        if(token == _ETH_ADDRESS_) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
