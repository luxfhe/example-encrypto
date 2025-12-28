// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract FHERC20SigUtils {
    constructor() {}

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value_hash,uint256 nonce,uint256 deadline)"
        );

    struct Permit {
        address owner;
        address spender;
        uint256 value_hash;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value_hash,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(
        bytes32 _DOMAIN_SEPARATOR,
        Permit memory _permit
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }
}
