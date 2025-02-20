// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPhiAttester } from "./interfaces/IPhiAttester.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IEAS } from "./interfaces/IEAS.sol";

contract PhiAttester is IPhiAttester, Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
  using SafeTransferLib for address;

  uint256 public constant ATTEST_FEE = 0.0001 ether;
  IEAS public eas;
  address public treasuryAddress;
  address public trustedSigner;
  mapping(address => uint256) public nonces;
  mapping(string => bytes32) public boardAttestations;

  uint256[50] private __gap;

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

  function _authorizeUpgrade(address newImpl) internal override onlyOwner {}

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

  function attestBoard(AttestBoardRequest calldata req, bytes calldata signature) external payable {
    if (msg.value != ATTEST_FEE) revert InvalidFee();
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

    bytes memory data = abi.encode(req.boardId, req.category, req.uri);
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

  function revokeAttestation(bytes32 schemaId, bytes32 attestationUID) external onlyOwner {
    IEAS.RevocationRequest memory request = IEAS.RevocationRequest({
      schema: schemaId,
      data: IEAS.RevocationRequestData({ uid: attestationUID, value: 0 })
    });

    eas.revoke(request);
    emit AttestationRevoked(attestationUID);
  }

  function _safeRecover(bytes32 h, bytes calldata sig) internal view returns (address) {
    bytes32 d = ECDSA.toEthSignedMessageHash(h);
    return ECDSA.recover(d, sig);
  }
}
