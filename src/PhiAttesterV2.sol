// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPhiAttester } from "./interfaces/IPhiAttester.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IEAS } from "./interfaces/IEAS.sol";

contract PhiAttesterV2 is IPhiAttester, Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    using SafeTransferLib for address;

    uint256 public attestFee = 0.0001 ether;
    IEAS public eas;
    address public treasuryAddress;
    address public trustedSigner;
    mapping(address => uint256) public nonces;
    mapping(string => bytes32) public boardAttestations;

    // Single mapping for all board information
    mapping(string => BoardInfo) public boardInfos;

    uint256[49] private __gap;

    function initialize(address _eas, address _treasury, address _trustedSigner, address _owner) external initializer {
        if (_eas == address(0) || _treasury == address(0) || _trustedSigner == address(0) || _owner == address(0)) {
            revert NullAddress();
        }
        __Context_init();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);
        eas = IEAS(_eas);
        treasuryAddress = _treasury;
        trustedSigner = _trustedSigner;
    }

    function _authorizeUpgrade(address newImpl) internal override onlyOwner { }

    function setEAS(address newEAS) external onlyOwner {
        if (newEAS == address(0)) revert NullAddress();
        eas = IEAS(newEAS);
    }

    function setTreasuryAddress(address newT) external onlyOwner {
        if (newT == address(0)) revert NullAddress();
        treasuryAddress = newT;
    }

    function setTrustedSigner(address s) external onlyOwner {
        if (s == address(0)) revert NullAddress();
        trustedSigner = s;
    }

    /**
     * @notice Updates the attestation fee
     * @param newFee The new fee amount in wei
     */
    function setAttestFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = attestFee;
        attestFee = newFee;

        emit AttestFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Internal function to check if a board is locked
     * @param boardId The board ID to check
     */
    function _checkBoardLocked(string calldata boardId) internal view {
        BoardInfo storage existingBoard = boardInfos[boardId];
        // Check if board exists (creator != address(0)) and is locked
        if (existingBoard.creator != address(0) && existingBoard.locked) {
            revert BoardLocked();
        }
    }

    function attestBoard(AttestBoardRequest calldata req, bytes calldata signature) external payable {
        _checkBoardLocked(req.boardId);
        if (msg.value != attestFee) revert InvalidFee();
        if (block.timestamp > req.expiresAt) revert SignatureExpired();

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                req.expiresAt,
                req.nonce,
                req.schemaId,
                req.boardId,
                req.category,
                req.uri,
                req.referrer,
                req.attestationExpirationTime,
                block.chainid
            )
        );

        address signer = _safeRecover(msgHash, signature);
        if (signer != trustedSigner) revert InvalidSigner();

        if (req.nonce != nonces[msg.sender]) revert InvalidNonce();
        nonces[msg.sender]++;

        treasuryAddress.safeTransferETH(msg.value);
        if (req.schemaId == 0) revert SchemaNotProvided();

        bytes memory data = abi.encode(req.boardId, req.category, req.uri, req.referrer);
        IEAS.AttestationRequest memory ar = IEAS.AttestationRequest({
            schema: req.schemaId,
            data: IEAS.AttestationRequestData({
                recipient: msg.sender,
                expirationTime: req.attestationExpirationTime,
                revocable: true,
                refUID: 0,
                data: data,
                value: 0
            })
        });
        bytes32 uid = eas.attest(ar);
        boardAttestations[req.boardId] = uid;
        emit BoardAttested(msg.sender, uid, req.schemaId, req.boardId, req.uri, req.attestationExpirationTime);
    }

    /**
     * @notice Enhanced version of attestBoard with additional fields
     * @param req The extended attestation request with title, imageURI, verified, and locked fields
     * @param signature The trusted signer's signature
     */
    function attestBoardV2(AttestBoardRequestV2 calldata req, bytes calldata signature) external payable {
        _checkBoardLocked(req.boardId);
        _validateAttestBoardV2(req, signature);
        bytes32 uid = _processAttestBoardV2(req);
        _storeBoardInfoV2(req);

        emit BoardAttestedV2(
            msg.sender,
            uid,
            req.schemaId,
            req.boardId,
            req.uri,
            req.attestationExpirationTime,
            req.metadata.verified,
            req.metadata.locked
        );
    }

    /**
     * @notice Internal function to validate attestBoardV2 request
     */
    function _validateAttestBoardV2(AttestBoardRequestV2 calldata req, bytes calldata signature) internal {
        if (msg.value != attestFee) revert InvalidFee();
        if (block.timestamp > req.expiresAt) revert SignatureExpired();

        bytes32 msgHash = _createMessageHashV2(req);
        address signer = _safeRecover(msgHash, signature);

        if (signer != trustedSigner) revert InvalidSigner();

        if (req.nonce != nonces[msg.sender]) revert InvalidNonce();
        nonces[msg.sender]++;

        treasuryAddress.safeTransferETH(msg.value);
        if (req.schemaId == 0) revert SchemaNotProvided();
    }

    /**
     * @notice Internal function to create message hash for V2
     */
    function _createMessageHashV2(AttestBoardRequestV2 calldata req) internal view returns (bytes32) {
        // Create base hash with core request data
        bytes32 baseHash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                req.expiresAt,
                req.nonce,
                req.schemaId,
                req.boardId,
                req.category,
                req.uri,
                req.referrer,
                req.attestationExpirationTime
            )
        );

        // Create metadata hash
        bytes32 metadataHash = keccak256(
            abi.encodePacked(req.metadata.title, req.metadata.imageURI, req.metadata.verified, req.metadata.locked)
        );

        // Combine both hashes with chainid
        return keccak256(abi.encodePacked(baseHash, metadataHash, block.chainid));
    }

    /**
     * @notice Internal function to process attestation for V2
     */
    function _processAttestBoardV2(AttestBoardRequestV2 calldata req) internal returns (bytes32) {
        // Split data encoding to avoid stack too deep
        bytes memory baseData = abi.encode(req.boardId, req.category, req.uri, req.referrer);
        bytes memory metadataData =
            abi.encode(req.metadata.title, req.metadata.imageURI, req.metadata.verified, req.metadata.locked);

        // Combine both data parts
        bytes memory data = abi.encode(baseData, metadataData);

        IEAS.AttestationRequest memory ar = IEAS.AttestationRequest({
            schema: req.schemaId,
            data: IEAS.AttestationRequestData({
                recipient: msg.sender,
                expirationTime: req.attestationExpirationTime,
                revocable: true,
                refUID: 0,
                data: data,
                value: 0
            })
        });

        bytes32 uid = eas.attest(ar);
        boardAttestations[req.boardId] = uid;
        return uid;
    }

    /**
     * @notice Internal function to store board information for V2
     */
    function _storeBoardInfoV2(AttestBoardRequestV2 calldata req) internal {
        boardInfos[req.boardId] = BoardInfo({
            title: req.metadata.title,
            imageURI: req.metadata.imageURI,
            uri: req.uri,
            verified: req.metadata.verified,
            locked: req.metadata.locked,
            creator: msg.sender
        });
    }

    function revokeAttestation(bytes32 schemaId, bytes32 attestationUID) external onlyOwner {
        IEAS.RevocationRequest memory request = IEAS.RevocationRequest({
            schema: schemaId,
            data: IEAS.RevocationRequestData({ uid: attestationUID, value: 0 })
        });

        eas.revoke(request);
        emit AttestationRevoked(attestationUID);
    }

    function getBoardInfo(string calldata boardId)
        external
        view
        returns (
            string memory title,
            string memory imageURI,
            string memory uri,
            bool verified,
            bool locked,
            address creator
        )
    {
        BoardInfo memory info = boardInfos[boardId];

        return (info.title, info.imageURI, info.uri, info.verified, info.locked, info.creator);
    }

    function _safeRecover(bytes32 h, bytes calldata sig) internal view returns (address) {
        bytes32 d = ECDSA.toEthSignedMessageHash(h);
        return ECDSA.recover(d, sig);
    }
}
