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
                req.category,
                req.uri,
                req.attestationExpirationTime
            )
        );

        address signer = _safeRecover(msgHash, signature);
        if (signer != trustedSigner) revert InvalidSigner();

        if (req.nonce != nonces[msg.sender]) revert InvalidNonce();
        nonces[msg.sender]++;

        treasuryAddress.safeTransferETH(msg.value);
        if (req.schemaId == 0) revert SchemaNotProvided();

        bytes memory data = abi.encode(req.category, req.uri);
        IEAS.AttestationRequest memory ar = IEAS.AttestationRequest({
            schema: req.schemaId,
            data: IEAS.AttestationRequestData({
                recipient: msg.sender,
                expirationTime: req.attestationExpirationTime,
                revocable: true,
                refUID: 0,
                data: data
            })
        });
        bytes32 uid = eas.attest(ar);
        emit BoardAttested(msg.sender, uid, req.schemaId, req.category, req.uri, req.attestationExpirationTime);
    }

    function _safeRecover(bytes32 h, bytes calldata sig) internal view returns (address) {
        (bool ok, bytes memory res) =
            address(this).staticcall(abi.encodeWithSelector(this._recoverPublic.selector, h, sig));
        if (!ok) revert InvalidSigner();
        return abi.decode(res, (address));
    }

    function _recoverPublic(bytes32 h, bytes calldata sig) public view returns (address) {
        bytes32 d = ECDSA.toEthSignedMessageHash(h);
        return ECDSA.recover(d, sig);
    }
}
