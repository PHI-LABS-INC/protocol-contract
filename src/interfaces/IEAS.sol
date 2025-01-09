// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IEAS {
    struct AttestationRequestData {
        address recipient;
        uint64 expirationTime; // We can set this from our request
        bool revocable;
        bytes32 refUID;
        bytes data;
    }

    struct AttestationRequest {
        bytes32 schema; // The EAS schema ID
        AttestationRequestData data;
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32);
}
