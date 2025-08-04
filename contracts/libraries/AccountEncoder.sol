// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

struct Account {
    bytes32 publicKey;
    bool isWritable;
}

struct Input {
    Account[] accounts;
    bytes data;
}

library AccountEncoder {
    function encodeInput(Account[] memory accounts, bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(Input(accounts, data));
    }

    function decompressAccounts(bytes memory input) internal pure returns (Account[] memory accounts) {
        require(input.length >= 2, "Input too short");

        uint16 len = (uint16(uint8(input[0])) << 8) | uint8(input[1]);
        require(input.length == 2 + len * 33, "Invalid input length");

        accounts = new Account[](len);

        uint offset = 2;
        for (uint i = 0; i < len; i++) {
            bytes32 pubkey;

            assembly {
                pubkey := mload(add(add(input, 32), offset))
            }

            bool writable = input[offset + 32] != 0;

            accounts[i] = Account(pubkey, writable);
            offset += 33;
        }

        return accounts;
    }
}