// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IEAS {
    struct AttestationRequestData {
        address recipient;
        uint64 expirationTime;
        bool revocable;
        bytes32 refUID;
        bytes data;
        uint256 value; // Added missing field
    }

    struct AttestationRequest {
        bytes32 schema;
        AttestationRequestData data;
    }

    // Add RevocationRequest struct
    struct RevocationRequest {
        bytes32 schema;
        bytes32 uid;
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32);

    // Add revoke function
    function revoke(RevocationRequest calldata request) external payable;
}
