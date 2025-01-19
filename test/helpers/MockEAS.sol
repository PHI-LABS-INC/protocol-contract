// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { IEAS } from "../../src/interfaces/IEAS.sol";

contract MockEAS is IEAS {
    bytes32 private lastAttestationUID;

    event Attested(address indexed recipient, address indexed attester, bytes32 uid, bytes32 indexed schemaUID);

    event Revoked(address indexed recipient, address indexed attester, bytes32 uid, bytes32 indexed schemaUID);

    function attest(AttestationRequest calldata request) external payable override returns (bytes32) {
        lastAttestationUID = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        emit Attested(request.data.recipient, msg.sender, lastAttestationUID, request.schema);

        return lastAttestationUID;
    }

    function revoke(RevocationRequest calldata request) external payable override {
        emit Revoked(
            address(0), // recipientは元の証明書から取得する必要があるが、mockなので0アドレスを使用
            msg.sender,
            request.data.uid, // structの構造に合わせて変更
            request.schema
        );
    }

    // テスト用のヘルパー関数
    function getLatestAttestationUID() external view returns (bytes32) {
        return lastAttestationUID;
    }

    // ISemverインターフェースの実装
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
