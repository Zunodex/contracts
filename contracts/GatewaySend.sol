// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatewayEVM} from "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract GatewaySend is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public globalNonce;
    uint256 public gasLimit;
    address public DODORouteProxy;
    address public DODOApprove;
    GatewayEVM public gateway;
    
    event EddyCrossChainRevert(
        bytes32 externalId,
        address token,
        uint256 amount,
        address walletAddress
    );
    event EddyCrossChainSend(
        bytes32 externalId,
        uint32 dstChainId,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        bytes payload
    );
    event EddyCrossChainReceive(
        bytes32 externalId,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        bytes payload
    );
    event DODORouteProxyUpdated(address dodoRouteProxy);
    event GatewayUpdated(address gateway);

    error Unauthorized();
    error RouteProxyCallFailed();

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
     * @param _dodoRouteProxy Address of the DODORouteProxy
     */
    function initialize(
        address payable _gateway,
        address _dodoRouteProxy,
        address _dodoApprove,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayEVM(_gateway);
        DODORouteProxy = _dodoRouteProxy;
        DODOApprove = _dodoApprove;
        gasLimit = _gasLimit;
    }

    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    function setDODORouteProxy(address _dodoRouteProxy) external onlyOwner {
        DODORouteProxy = _dodoRouteProxy;
        emit DODORouteProxyUpdated(_dodoRouteProxy);
    }

    function setGateway(address _gateway) external onlyOwner {
        gateway = GatewayEVM(_gateway);
        emit GatewayUpdated(_gateway);
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function concatBytes(bytes32 a, bytes memory b) public pure returns (bytes memory) {
        bytes memory result = new bytes(32 + b.length);
        uint k = 0;
        for (uint i = 0; i < 32; i++) {
            result[k++] = a[i];
        }
        for (uint i = 0; i < b.length; i++) {
            result[k++] = b[i];
        }
        return result;
    }

    function _calcExternalId(address sender) internal view returns (bytes32 externalId) {
        externalId = keccak256(abi.encodePacked(address(this), sender, globalNonce, block.timestamp));
    }

    function depositAndCall(
        address fromToken,
        uint256 amount,
        bytes calldata swapData,
        address targetContract,
        address asset,
        uint32 dstChainId,
        bytes calldata payload
    ) public payable {
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);

        uint256 swapValue;
        bool fromIsETH = fromToken == _ETH_ADDRESS_ ? true : false;
        if(fromIsETH) {
            require(msg.value >= amount, "INSUFFICIENT AMOUNT: ETH NOT ENOUGH");
            swapValue = amount;
        } else {
            require(IERC20(fromToken).transferFrom(msg.sender, address(this), amount), "INSUFFICIENT AMOUNT: ERC20 TRANSFER FROM FAILED");
            IERC20(fromToken).approve(DODOApprove, amount);
        }
         
        // Swap on DODO Router
        (bool success, bytes memory returnData) = DODORouteProxy.call{value: swapValue}(swapData);
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));

        bool toIsETH = asset == _ETH_ADDRESS_ ? true : false;
        bytes memory message = concatBytes(externalId, payload);
        if(toIsETH) {
            gateway.depositAndCall{value: outputAmount}(
                targetContract,
                message,
                RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: targetContract,
                    revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
                    onRevertGasLimit: gasLimit
                })
            );
        } else {
            IERC20(asset).approve(address(gateway), outputAmount);
            gateway.depositAndCall(
                targetContract,
                outputAmount,
                asset,
                concatBytes(externalId, payload),
                RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: targetContract,
                    revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
                    onRevertGasLimit: gasLimit
                })
            );
        }
        emit EddyCrossChainSend(
            externalId,
            dstChainId,
            fromToken,
            asset,
            amount,
            outputAmount,
            msg.sender,
            message
        );
    }

    function depositAndCall(
        address targetContract,
        uint256 amount,
        address asset,
        uint32 dstChainId,
        bytes calldata payload
    ) public payable {
        globalNonce++;
        bytes32 externalId = _calcExternalId(msg.sender);

        bool isETH = asset == _ETH_ADDRESS_ ? true : false;
        bytes memory message = concatBytes(externalId, payload);
        if(isETH) {
            require(msg.value >= amount, "INSUFFICIENT AMOUNT: ETH NOT ENOUGH");
            gateway.depositAndCall{value: amount}(
                targetContract,
                message,
                RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: targetContract,
                    revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
                    onRevertGasLimit: gasLimit
                })
            );
        } else {
            require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "INSUFFICIENT AMOUNT: ERC20 TRANSFER FROM FAILED");
            IERC20(asset).approve(address(gateway), amount);
            gateway.depositAndCall(
                targetContract,
                amount,
                asset,
                message,
                RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: targetContract,
                    revertMessage: bytes.concat(externalId, bytes20(msg.sender)),
                    onRevertGasLimit: gasLimit
                })
            );
        }
        emit EddyCrossChainSend(
            externalId,
            dstChainId,
            asset,
            asset,
            amount,
            amount,
            msg.sender,
            message
        );
    }

    function onCall(
        MessageContext calldata /*context*/,
        bytes calldata message
    ) external payable onlyGateway returns (bytes4) {
        (bytes32 externalId, address evmWalletAddress, uint256 amount, bytes memory crossChainSwapData) = abi.decode(
            message, 
            (bytes32, address, uint256, bytes)
        );
        (address fromToken, address toToken, bytes memory swapData) = abi.decode(
            crossChainSwapData,
            (address, address, bytes)
        );

        uint256 swapValue;
        bool fromIsETH = fromToken == _ETH_ADDRESS_ ? true : false;
        if(fromIsETH) {
            swapValue = amount;
        } else {
            IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
            IERC20(fromToken).approve(DODOApprove, amount);
        }
        
        // Swap on DODO Router
        (bool success, bytes memory returnData) = DODORouteProxy.call{value: swapValue}(swapData);
        if (!success) {
            revert RouteProxyCallFailed();
        }
        uint256 outputAmount = abi.decode(returnData, (uint256));

        bool toIsETH = toToken == _ETH_ADDRESS_ ? true : false;
        if(toIsETH) {
            payable(evmWalletAddress).transfer(outputAmount);
        } else {
            IERC20(toToken).transfer(evmWalletAddress, outputAmount);
        }
        
        emit EddyCrossChainReceive(
            externalId,
            fromToken,
            toToken,
            amount,
            outputAmount,
            evmWalletAddress,
            message
        );

        return "";
    }

    /**
     * @notice Function called by the gateway to revert the cross-chain swap
     * @param context Revert context
     * @dev Only the gateway can call this function
     */
    function onRevert(RevertContext calldata context) external onlyGateway {
        bytes32 externalId = bytes32(context.revertMessage[0:32]);
        address sender = address(uint160(bytes20(context.revertMessage[32:])));
        TransferHelper.safeTransfer(context.asset, sender, context.amount);
        
        emit EddyCrossChainRevert(
            externalId,
            context.asset,
            context.amount,
            sender
        );
    }

    receive() external payable {}

    fallback() external payable {}
}