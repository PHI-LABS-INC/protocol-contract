// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { IEAS } from "../../src/interfaces/IEAS.sol";

contract MockEAS is IEAS {
    // This is a mock implementation of the attest function, marked as payable
    function attest(AttestationRequest memory request) external payable override returns (bytes32) {
        // Mock logic: simply return a fixed attestation UID
        return 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    }
}
