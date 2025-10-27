// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRefundVault {
    function setRefundInfo(
        bytes32 externalId, 
        address token, 
        uint256 amount, 
        bytes calldata walletAddress
    ) external;
}