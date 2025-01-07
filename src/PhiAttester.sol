// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* 
   -------------------------------------------------------
   OpenZeppelin Upgradeable Imports
   -------------------------------------------------------
*/
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/* 
   -------------------------------------------------------
   Solady Imports
   -------------------------------------------------------
*/
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

/*
   -------------------------------------------------------
   Minimal IEAS Interface (for demonstration)
   -------------------------------------------------------
   In production, import from "@ethereum-attestation-service/eas-contracts".
*/
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

/**
 * @title BoardAttestorUpgradeable
 * @notice Example upgradeable contract that:
 *  - Uses UUPS + Ownable2StepUpgradeable for ownership
 *  - Uses Solady's SafeTransferLib + ECDSA
 *  - Performs EAS attestations with a fee
 *  - Immediately sends the fee to `treasuryAddress`
 *  - Allows specifying any EAS schemaId within the request
 *  - Includes `attestationExpirationTime` to set EAS’s `expirationTime`
 */
contract BoardAttestorUpgradeable is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev Fee required for each attestation (0.0001 ETH)
    uint256 public constant ATTEST_FEE = 0.0001 ether;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev EAS contract reference
    IEAS public eas;

    /// @dev The address to which fees are forwarded
    address public treasuryAddress;

    /// @dev The address whose signature we trust
    address public trustedSigner;

    /// @dev Nonces to avoid replay (user => nonce)
    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NullAddress();
    error InvalidFee();
    error InvalidSigner();
    error SignatureExpired();
    error InvalidNonce();
    error SchemaNotProvided();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BoardAttested(
        address indexed caller,
        bytes32 indexed attestationUID,
        bytes32 schemaId,
        string category,
        string uri,
        uint64 attestationExpirationTime
    );

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev AttestBoardRequest data, passed to `attestBoard`.
     * Includes `attestationExpirationTime` for EAS.
     */
    struct AttestBoardRequest {
        uint256 expiresAt; // block.timestamp after which signature is invalid
        uint256 nonce; // user-specific nonce for replay
        bytes32 schemaId; // which EAS schema to use
        string category; // e.g., "philand", "art", etc.
        string uri; // link to content (Arweave, IPFS, etc.)
        uint64 attestationExpirationTime; // EAS's expirationTime
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the upgradeable contract
     * @param _eas The address of the EAS contract
     * @param _treasury Where fees are sent
     * @param _trustedSigner The address whose signature we trust
     * @param _owner The initial owner (Ownable2StepUpgradeable)
     */
    function initialize(address _eas, address _treasury, address _trustedSigner, address _owner) external initializer {
        if (_eas == address(0)) revert NullAddress();
        if (_treasury == address(0)) revert NullAddress();
        if (_trustedSigner == address(0)) revert NullAddress();
        if (_owner == address(0)) revert NullAddress();

        __Context_init();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        // Transfer ownership via 2-step or directly:
        _transferOwnership(_owner);

        // Set the references
        eas = IEAS(_eas);
        treasuryAddress = _treasury;
        trustedSigner = _trustedSigner;
    }

    /**
     * @dev UUPS requires an authorization function to protect upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////
                           ONLY-OWNER SETTERS
    //////////////////////////////////////////////////////////////*/

    function setEAS(address newEAS) external onlyOwner {
        if (newEAS == address(0)) revert NullAddress();
        eas = IEAS(newEAS);
    }

    function setTreasuryAddress(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert NullAddress();
        treasuryAddress = newTreasury;
    }

    function setTrustedSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert NullAddress();
        trustedSigner = newSigner;
    }

    /*//////////////////////////////////////////////////////////////
                          MAIN ATTEST FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Collects 0.0001 ETH, verifies signature,
     *         attests `(category, uri)` to the EAS `schemaId` with `attestationExpirationTime`,
     *         and immediately forwards the fee to `treasuryAddress`.
     *
     * @param req The AttestBoardRequest (schemaId, category, uri, etc.)
     * @param signature The off-chain signature from `trustedSigner`.
     */
    function attestBoard(AttestBoardRequest calldata req, bytes calldata signature) external payable {
        // 1. Check the fee
        if (msg.value != ATTEST_FEE) {
            revert InvalidFee();
        }

        // 2. Build hash for signature
        //    We incorporate contract address, caller, expiry, nonce, schemaId, category, uri,
        //    and attestationExpirationTime.
        address caller = _msgSender();
        bytes32 hash_ = keccak256(
            abi.encodePacked(
                address(this),
                caller,
                req.expiresAt,
                req.nonce,
                req.schemaId,
                req.category,
                req.uri,
                req.attestationExpirationTime
            )
        );

        // 3. Recover signer via Solady's ECDSA
        address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(hash_), signature);
        if (signer != trustedSigner) {
            revert InvalidSigner();
        }

        // 4. Check expiration & nonce
        if (block.timestamp > req.expiresAt) {
            revert SignatureExpired();
        }
        if (req.nonce != nonces[caller]) {
            revert InvalidNonce();
        }
        nonces[caller]++;

        // 5. Forward fee to treasury
        treasuryAddress.safeTransferETH(msg.value);

        // 6. Validate schema
        if (req.schemaId == 0) {
            revert SchemaNotProvided();
        }

        // 7. Encode data for EAS.
        //    We assume the EAS schema is "string category,string uri".
        bytes memory encodedData = abi.encode(req.category, req.uri);

        // 8. Build the attestation request with user-specified expirationTime
        IEAS.AttestationRequest memory attRequest = IEAS.AttestationRequest({
            schema: req.schemaId,
            data: IEAS.AttestationRequestData({
                recipient: caller, // use `_msgSender()`
                expirationTime: req.attestationExpirationTime,
                revocable: true,
                refUID: 0,
                data: encodedData
            })
        });

        // 9. Call EAS
        bytes32 attestationUID = eas.attest(attRequest);

        // 10. Emit event
        emit BoardAttested(caller, attestationUID, req.schemaId, req.category, req.uri, req.attestationExpirationTime);
    }
}
