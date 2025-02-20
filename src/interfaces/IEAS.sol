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

    struct RevocationRequestData {
        bytes32 uid; // The UID of the attestation to revoke.
        uint256 value; // An explicit ETH amount to send to the resolver. This is important to prevent accidental user
            // errors.
    }

    /// @notice A struct representing the full arguments of the revocation request.
    struct RevocationRequest {
        bytes32 schema; // The unique identifier of the schema.
        RevocationRequestData data; // The arguments of the revocation request.
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32);
    function revoke(RevocationRequest calldata request) external payable;
}
