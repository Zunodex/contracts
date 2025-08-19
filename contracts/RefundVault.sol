// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import {RevertOptions} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IRefundVault} from "./interfaces/IRefundVault.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract RefundVault is IRefundVault, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public gasLimit;
    mapping(address => bool) public isWhiteListed;
    mapping(address => bool) public bots; 
    mapping(bytes32 => RefundInfo) public refundInfos; // externalId => RefundInfo

    GatewayZEVM public gateway;

    struct RefundInfo {
        bytes32 externalId;
        address token;
        uint256 amount;
        bytes walletAddress;
    }

    error Unauthorized();

    event GatewayUpdated(address gateway);
    event BotUpdated(address bot, bool allowed);
    event RefundSet(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event RefundClaimed(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event BotClaimed(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event RefundRemoved(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event RefundAdded(
        bytes32 externalId, 
        address indexed token, 
        uint256 amount,
        bytes walletAddress
    );
    event RefundConflict(
        bytes32 indexed externalId,
        address indexed oldToken,
        uint256 oldAmount,
        bytes oldWalletAddress,
        address indexed newToken,
        uint256 newAmount,
        bytes newWalletAddress
    );

    modifier onlyWhiteListed {
        if(!isWhiteListed[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlyBot {
        if(!bots[msg.sender]) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(
        address payable _gateway,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(_gateway);
        gasLimit = _gasLimit;
    }

    function setWhiteList(address addr, bool isAllowed) public onlyOwner {
        isWhiteListed[addr] = isAllowed;
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function setGateway(address payable _gateway) external onlyOwner {
        gateway = GatewayZEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function setBot(address bot, bool isAllowd) external onlyOwner {
        bots[bot] = isAllowd;
        emit BotUpdated(bot, isAllowd);
    }

    // ==================== Bot Functions ====================

    function superWithdraw(address token, uint256 amount) external onlyBot {
        if (token == _ETH_ADDRESS_) {
            require(amount <= address(this).balance, "INVALID_AMOUNT");
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            require(amount <= IZRC20(token).balanceOf(address(this)), "INVALID_AMOUNT");
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
    }

    function addRefundInfo(
        bytes32[] calldata externalIds,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes[] calldata walletAddresses
    ) external onlyBot {
        require(
            externalIds.length == tokens.length &&
            tokens.length == amounts.length &&
            amounts.length == walletAddresses.length,
            "ARRAY_LENGTH_MISMATCH"
        );

        for (uint256 i = 0; i < externalIds.length; i++) {
            RefundInfo memory refundInfo = RefundInfo({
                externalId: externalIds[i],
                token: tokens[i],
                amount: amounts[i],
                walletAddress: walletAddresses[i]
            });

            refundInfos[externalIds[i]] = refundInfo;

            emit RefundAdded(externalIds[i], tokens[i], amounts[i], walletAddresses[i]);
        }
    }

    function removeRefundInfo(bytes32[] calldata externalIds) external onlyBot {
        for (uint256 i = 0; i < externalIds.length; i++) {
            bytes32 externalId = externalIds[i];
            RefundInfo storage refundInfo = refundInfos[externalId];
            if (refundInfo.externalId != "") {
                emit RefundRemoved(
                    externalId,
                    refundInfo.token,
                    refundInfo.amount,
                    refundInfo.walletAddress
                );
                delete refundInfos[externalId];
            }
        }
    }

    /**
     * @notice Batch claim refund for a specific token by a bot.
     * @param token The address of the ZRC20 token to claim.
     * @param externalIds List of externalIds to claim, all must match the given token.
     * @param vault The address of the vault to receive the refunds.
     */
    function batchClaimRefund(address token, bytes32[] calldata externalIds, bytes memory vault) external onlyBot {
        require(token != address(0), "INVALID_TOKEN");
        require(externalIds.length > 0, "EMPTY_LIST");
        require(vault.length > 0 , "INVALID_VAULT");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < externalIds.length; i++) {
            bytes32 externalId = externalIds[i];
            RefundInfo storage info = refundInfos[externalId];

            require(info.externalId != "", "REFUND_NOT_EXIST");
            require(info.token == token, "TOKEN_MISMATCH");

            totalAmount += info.amount;

            // Emit individual refund claimed event
            emit BotClaimed(
                externalId,
                token,
                info.amount,
                info.walletAddress
            );

            // Clear refund info after claiming
            delete refundInfos[externalId];
        }

        // Collect gas fee from bot and approve
        (address gasZRC20, uint256 gasFee) = IZRC20(token).withdrawGasFee();
        TransferHelper.safeTransferFrom(gasZRC20, msg.sender, address(this), gasFee);
        if(gasZRC20 == token) {
            TransferHelper.safeApprove(gasZRC20, address(gateway), gasFee + totalAmount);
        } else {
            TransferHelper.safeApprove(gasZRC20, address(gateway), gasFee);
            TransferHelper.safeApprove(token, address(gateway), totalAmount);
        }

        // Withdraw to vault address
        gateway.withdraw(
            vault, // vault will receive the refund
            totalAmount,
            token,
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: false,
                abortAddress: address(0),
                revertMessage: "",
                onRevertGasLimit: gasLimit
            })
        );
    }

    // ==================== WhiteListed Caller Functions ====================

    function setRefundInfo(
        bytes32 externalId, 
        address token, 
        uint256 amount, 
        bytes memory walletAddress
    ) external onlyWhiteListed {
        RefundInfo storage existing = refundInfos[externalId];

        if (existing.externalId != "") {
            // Emit conflict event for bot to review
            emit RefundConflict(
                externalId,
                existing.token,
                existing.amount,
                existing.walletAddress,
                token,
                amount,
                walletAddress
            );
            return;
        }

        RefundInfo memory refundInfo = RefundInfo({
            externalId: externalId,
            token: token,
            amount: amount,
            walletAddress: walletAddress
        });

        refundInfos[externalId] = refundInfo;

        emit RefundSet(
            externalId,
            token,
            amount,
            walletAddress
        );
    }

    // ==================== User Functions ====================

    function claimRefund(bytes32 externalId) external {
        RefundInfo storage refundInfo = refundInfos[externalId];
        require(refundInfo.externalId != "", "REFUND_NOT_EXIST");

        address token = refundInfo.token;
        uint256 amount = refundInfo.amount;
        bytes memory walletAddress = refundInfo.walletAddress;
        delete refundInfos[externalId];

        (address gasZRC20, uint256 gasFee) = IZRC20(token).withdrawGasFee();
        TransferHelper.safeTransferFrom(
            gasZRC20,
            msg.sender,
            address(this),
            gasFee
        );

        TransferHelper.safeApprove(gasZRC20, address(gateway), gasFee);
        TransferHelper.safeApprove(token, address(gateway), amount);
        gateway.withdraw(
            walletAddress,
            amount,
            token,
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: false,
                abortAddress: address(0),
                revertMessage: "",
                onRevertGasLimit: gasLimit
            })
        );

        emit RefundClaimed(
            externalId,
            token,
            amount,
            walletAddress
        );
    }

    function getRefundInfo(bytes32 externalId) external view returns (
        address token,
        uint256 amount,
        bytes memory walletAddress
    ) {
        RefundInfo storage info = refundInfos[externalId];
        require(info.externalId != "", "REFUND_NOT_EXIST");
        return (info.token, info.amount, info.walletAddress);
    }

    function getWithdrawGasFee(address zrc20) external view returns (address gasZRC20, uint256 gasFee) {
        (gasZRC20, gasFee) = IZRC20(zrc20).withdrawGasFee();
    }

    receive() external payable {}

    fallback() external payable {}

}