// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IZRC20, IZRC20Metadata} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IUnifiedToken {
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IVault {
    function collect(address asset, address from, uint256 amount) external;
    function payout(address asset, address to, uint256 amount) external;
}

contract Minter is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public _UTOKEN_;
    address public _VAULT_;
    
    struct AssetConfig {
        address asset;
        bool enabled;
        uint256 minOrder;   // MIN_AMOUNT/tx (0=unlimited)
        uint256 maxOrder;   // MAX_AMOUNT/tx (0=unlimited)
    }
    
    mapping(address => bool) public isAdapter;
    mapping(address => AssetConfig) public assets;
    bool public paused;

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

    modifier onlyAdapter() { 
        require(isAdapter[msg.sender], "Minter: NOT_ADAPTER"); 
        _; 
    }
    modifier notPaused() { 
        require(!paused, "Minter: PAUSED"); 
        _; 
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(
        address uToken,
        address vault
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        require(uToken != address(0) && vault != address(0), "Minter: INVALID_ADDRESS");

        _UTOKEN_ = uToken;
        _VAULT_ = vault;
    }

    function registerAsset(
        address asset, 
        bool enabled, 
        uint256 minOrder, 
        uint256 maxOrder
    ) external onlyOwner {
        require(asset != address(0), "Minter: INVALID_ADDRESS");

        assets[asset] = AssetConfig({
            asset: asset, 
            enabled: enabled, 
            minOrder: minOrder, 
            maxOrder: maxOrder
        });

        emit AssetRegistered(asset, enabled, minOrder, maxOrder);
    }

    function updateAsset(
        address asset, 
        bool enabled, 
        uint256 minOrder, 
        uint256 maxOrder
    ) external onlyOwner {
        AssetConfig storage config = assets[asset];
        config.asset = asset; 
        config.enabled = enabled; 
        config.minOrder = minOrder; 
        config.maxOrder = maxOrder;

        emit AssetUpdated(asset, enabled, minOrder, maxOrder);
    }

    function setAdapter(address adapter, bool isAllowd) external onlyOwner { 
        isAdapter[adapter] = isAllowd; 
        emit AdapterSet(adapter, isAllowd); 
    }

    function setPaused(bool isOn) external onlyOwner { 
        paused = isOn; 
        emit Paused(isOn); 
    }


    /// @notice Executes a 1:1 nominal conversion between two tokens using decimals scaling only.
    /// @dev    isMint=true: token -> unified token(mint); isMint=false: unified token(burn) -> token.
    /// @param isMint    True to mint unified token; false to redeem to token.
    /// @param fromToken Input token address.
    /// @param toToken   Output token address.
    /// @param amount    Amount of `fromToken` in its units.
    /// @param to        Recipient address of `toToken`.
    function execute(
        bool isMint, 
        address fromToken, 
        address toToken, 
        uint256 amount, 
        address to
    ) external onlyAdapter notPaused {
        require(fromToken != address(0) && toToken != address(0) && to != address(0), "Minter: INVALID_ADDRESS");
        
        AssetConfig memory config = assets[fromToken];
        require(config.enabled, "Minter: ASSET_OFF");
        if (config.minOrder > 0) require(amount >= config.minOrder, "Minter: UNDERFLOW");
        if (config.maxOrder > 0) require(amount <= config.maxOrder, "Minter: OVERFLOW");

        if (isMint) {
            // Token => UnifiedToken
            require(toToken == _UTOKEN_, "Minter: TOKEN_ADDRESS_NOT_MATCH");

            IZRC20(fromToken).approve(_VAULT_, amount);
            IVault(_VAULT_).collect(fromToken, address(this), amount);

            uint256 amt = _scale(amount, IZRC20Metadata(fromToken).decimals(), IUnifiedToken(_UTOKEN_).decimals());
            IUnifiedToken(_UTOKEN_).mint(to, amt);
        } else {
            require(fromToken == _UTOKEN_, "Minter: TOKEN_ADDRESS_NOT_MATCH");

            IUnifiedToken(_UTOKEN_).approve(_UTOKEN_, amount);
            IUnifiedToken(_UTOKEN_).burn(amount);

            uint256 amt = _scale(amount, IUnifiedToken(_UTOKEN_).decimals(), IZRC20Metadata(toToken).decimals());
            IVault(_VAULT_).payout(toToken, to, amt);
        }
    }

    function _scale(uint256 amount, uint8 inDecimal, uint8 outDecimal) internal pure returns (uint256) {
        if (inDecimal == outDecimal) return amount;

        if (inDecimal < outDecimal) {
            return amount * (10 ** uint256(outDecimal - inDecimal));
        } else {
            return amount / (10 ** uint256(inDecimal - outDecimal));
        }
    }

    receive() external payable {}
}