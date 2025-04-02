// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEddyStableSwap {
    // Events
    event TokenExchange(address indexed buyer, uint256 sold_id, uint256 tokens_sold, uint256 bought_id, uint256 tokens_bought);
    event AddLiquidity(address indexed provider, uint256[] token_amounts, uint256[] fees, uint256 invariant, uint256 token_supply);
    event RemoveLiquidity(address indexed provider, uint256[] token_amounts, uint256[] fees, uint256 token_supply);
    event RemoveLiquidityOne(address indexed provider, uint256 token_amount, uint256 coin_amount);
    event RemoveLiquidityImbalance(address indexed provider, uint256[] token_amounts, uint256[] fees, uint256 invariant, uint256 token_supply);
    event CommitNewAdmin(uint256 indexed deadline, address indexed admin);
    event NewAdmin(address indexed admin);
    event CommitNewFee(uint256 indexed deadline, uint256 fee, uint256 admin_fee);
    event NewFee(uint256 fee, uint256 admin_fee);
    event RampA(uint256 old_A, uint256 new_A, uint256 initial_time, uint256 future_time);
    event StopRampA(uint256 A, uint256 t);

    // View functions
    function A() external view returns (uint256);
    function A_precise() external view returns (uint256);
    function balances(uint256 i) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function calc_token_amount(uint256[] calldata amounts, bool is_deposit) external view returns (uint256);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
    function coins(uint256 index) external view returns (address);
    
    // External functions
    function add_liquidity(uint256[] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
    function remove_liquidity(uint256 _amount, uint256[] calldata _min_amounts) external returns (uint256[] memory);
}
