// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import {IZRC20} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {IGatewayZEVM, MessageContext} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {UniversalContract} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {BytesHelperLib} from "./libraries/BytesHelperLib.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract GatewayTransferNative is UniversalContract, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public constant WZETA = 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf;
    address private EddyTreasurySafe;
    address public DodoRouteProxy;
    uint256 public feePercent;
    GatewayZEVM public gateway;

    struct DecodedMessage {
        address receiver;
        address targetZRC20;
        bytes swapData;
    }

    error Unauthorized();
    error RouteProxyCallFailed();

    event EddyCrossChainSwap(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );
    event GatewayUpdated(address gateway);
    event FeePercentUpdated(uint256 feePercent);
    event DodoRouteProxyUpdated(address dodoRouteProxy);
    event EddyTreasurySafeUpdated(address EddyTreasurySafe);

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _gateway Gateway contract address
     * @param _EddyTreasurySafe Address of the platform fee wallets
     * @param _dodoRouteProxy Address of the DODORouteProxy
     * @param _feePercent Platform fee percentage in basis points (e.g., 10 = 1%)
     */
    function initialize(
        address payable _gateway,
        address _EddyTreasurySafe,
        address _dodoRouteProxy,
        uint256 _feePercent
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(_gateway);
        EddyTreasurySafe = _EddyTreasurySafe;
        DodoRouteProxy = _dodoRouteProxy;
        feePercent = _feePercent;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDodoRouteProxy(address _dodoRouteProxy) external onlyOwner {
        DodoRouteProxy = _dodoRouteProxy;
        emit DodoRouteProxyUpdated(_dodoRouteProxy);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    function setGateway(address payable _gateway) external onlyOwner {
        gateway = GatewayZEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function setEddyTreasurySafe(address _EddyTreasurySafe) external onlyOwner {
        EddyTreasurySafe = _EddyTreasurySafe;
        emit EddyTreasurySafeUpdated(_EddyTreasurySafe);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function decodeMessage(
        bytes calldata message
    ) internal pure returns (DecodedMessage memory decodedMessage) {
        // 20 bytes(evmAddress) + 20 bytes(taregtZRC20) + 32 bytes(swapData)
        address receiver = BytesHelperLib.bytesToAddress(message, 0); // 20
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 20); // 40
        bytes memory swapData = abi.decode(message[40:72], (bytes)); // 72
        decodedMessage = DecodedMessage({
            receiver: receiver,
            targetZRC20: targetZRC20,
            swapData: swapData
        });
    }

    function _handleFeeTransfer(
        address zrc20,
        uint256 amount
    ) internal returns (uint256 platformFeesForTx) {
        platformFeesForTx = (amount * feePercent) / 1000; // platformFee = 5 <> 0.5%
        TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, platformFeesForTx);
    }

    /**
     * @notice Function called by the gateway to execute the cross-chain swap
     * @param context Message context
     * @param zrc20 ZRC20 token address
     * @param amount Amount
     * @param message Message
     * @dev Only the gateway can call this function
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
        // Decode the message
        DecodedMessage memory decoded = decodeMessage(message);

        // Fee for platform
        uint256 platformFeesForTx = _handleFeeTransfer(zrc20, amount); // platformFee = 5 <> 0.5%

        if (decoded.targetZRC20 == zrc20) {
            // same token
            TransferHelper.safeTransfer(
                decoded.targetZRC20,
                decoded.receiver,
                amount - platformFeesForTx
            );

            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                amount,
                amount - platformFeesForTx,
                decoded.receiver,
                platformFeesForTx
            );
        } else {
            // swap
            IZRC20(zrc20).approve(DodoRouteProxy, amount);
            (bool success, bytes memory returnData) = DodoRouteProxy.call(
                decoded.swapData
            ); // swap on zetachain
            if (!success) {
                revert RouteProxyCallFailed();
            }
            uint256 outputAmount = abi.decode(returnData, (uint256));

            if (decoded.targetZRC20 == WZETA) {
                // withdraw WZETA to get Zeta in 1:1 ratio
                IWETH9(WZETA).withdraw(outputAmount);
                // transfer wzeta
                payable(decoded.receiver).transfer(outputAmount);
            } else {
                TransferHelper.safeTransfer(
                    decoded.targetZRC20,
                    decoded.receiver,
                    outputAmount
                );
            }

            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                amount,
                outputAmount,
                decoded.receiver,
                platformFeesForTx
            );
        }
    }

    receive() external payable {}

    fallback() external payable {}
}