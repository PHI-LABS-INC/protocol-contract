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
    error BoardLocked();

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
        address referrer; // address of the referrer
        uint64 attestationExpirationTime; // EAS's expirationTime
    }

    struct BoardInfo {
        string title;
        string imageURI;
        string uri;
        bool verified;
        bool locked;
        address creator;
    }

    struct BoardMetadata {
        string title;
        string imageURI;
        bool verified;
        bool locked;
    }

    struct AttestBoardRequestV2 {
        uint256 expiresAt;
        uint256 nonce;
        bytes32 schemaId;
        string boardId;
        string category;
        string uri;
        address referrer;
        uint64 attestationExpirationTime;
        BoardMetadata metadata;
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

    event BoardAttestedV2(
        address indexed attester,
        bytes32 indexed uid,
        bytes32 indexed schemaId,
        string boardId,
        string uri,
        uint64 attestationExpirationTime,
        bool verified,
        bool locked
    );

    event AttestationRevoked(bytes32 indexed attestationUID);

    event AttestFeeUpdated(uint256 oldFee, uint256 newFee);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(address _eas, address _treasury, address _trustedSigner, address _owner) external;

    function setEAS(address newEAS) external;

    function setTreasuryAddress(address newTreasury) external;

    function setTrustedSigner(address newSigner) external;

    function attestBoard(AttestBoardRequest calldata req, bytes calldata signature) external payable;
}
