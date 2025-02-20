// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPhiAttester {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidFee();
    error InvalidSigner();
    error InvalidSignature();
    error SignatureExpired();
    error InvalidNonce();
    error SchemaNotProvided();
    error NullAddress();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct AttestBoardRequest {
        uint256 expiresAt; // block.timestamp after which signature is invalid
        uint256 nonce; // user-specific nonce for replay
        bytes32 schemaId; // which EAS schema to use
        string boardId; // board ID
        string category; // e.g., "philand", "art", etc.
        string uri; // link to content (Arweave, IPFS, etc.)
        uint64 attestationExpirationTime; // EAS's expirationTime
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BoardAttested(
        address indexed caller,
        bytes32 indexed attestationUID,
        bytes32 schemaId,
        string boardId,
        string uri,
        uint64 attestationExpirationTime
    );

    event AttestationRevoked(bytes32 indexed attestationUID);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(address _eas, address _treasury, address _trustedSigner, address _owner) external;

    function setEAS(address newEAS) external;

    function setTreasuryAddress(address newTreasury) external;

    function setTrustedSigner(address newSigner) external;

    function attestBoard(AttestBoardRequest calldata req, bytes calldata signature) external payable;
}
