// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { IEAS } from "../../src/interfaces/IEAS.sol";

contract MockEAS is IEAS {
    function attest(AttestationRequest calldata request) external payable override returns (bytes32) {
        // Mock logic: simply return a fixed attestation UID
        return 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    }

    // [M-02] Add revoke functionality
    function revoke(RevocationRequest calldata request) external payable override {
        // Mock implementation for revoke
    }
}
