// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPhiFactory } from "./interfaces/IPhiFactory.sol";
import { IPhiRewards } from "./interfaces/IPhiRewards.sol";
import { IPhiNFT1155Ownable } from "./interfaces/IPhiNFT1155Ownable.sol";
import { ICreatorRoyaltiesControl } from "./interfaces/ICreatorRoyaltiesControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ECDSA } from "solady/utils/ECDSA.sol";

import { LibClone } from "solady/utils/LibClone.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibZip } from "solady/utils/LibZip.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";

/// @title PhiFactory
contract PhiFactory is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, IPhiFactory {
    /*//////////////////////////////////////////////////////////////
                                 USING
    //////////////////////////////////////////////////////////////*/
    using SafeTransferLib for address;
    using LibClone for address;
    using LibString for string;
    using LibString for uint256;
    using LibString for address;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    address public phiSignerAddress;
    address public protocolFeeDestination;
    address public erc1155ArtAddress;
    address public phiRewardsAddress;

    uint256 public constant MAX_PROTOCOL_FEE = 0.01 ether;
    uint256 public constant MAX_ART_CREATE_FEE = 0.01 ether;

    uint256 private locked;
    uint256 private artIdCounter;
    uint256 public artCreateFee;
    uint256 public mintProtocolFee;

    mapping(address user => uint256 count) public nonces;
    mapping(uint256 artId => PhiArt art) private arts;
    mapping(uint256 artId => mapping(address minter => bool)) public isArtMinted;

    mapping(uint256 credChainId => mapping(uint256 credId => bytes32 root)) public credMerkleRoot;
    mapping(uint256 credChainId => mapping(uint256 credId => address art)) private credNFTContracts;
    mapping(uint256 credChainId => mapping(uint256 credId => mapping(address minter => bool))) public isCredMinted;

    mapping(address artContract => bool result) public createdContracts;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initializeV2() external reinitializer(2) {
        // V2 specific initializations
    }

    function version() public pure returns (uint256) {
        return 2;
    }

    function contractURI(address nftAddress) public view returns (string memory) {
        uint256 artId = IPhiNFT1155Ownable(nftAddress).getFactoryArtId(1); // use 1 as the token id
        PhiArt memory art = arts[artId];
        address ownerAddress = this.owner();
        string memory json = string(
            abi.encodePacked(
                "{",
                '"name":"',
                "Phi",
                '",',
                '"description":"',
                _buildDescription(art),
                '",',
                '"image":"',
                "https://arweave.net/_oxKSZMtvAuGrRiNxVRYzpkzUSPsGQ7RJilQ7MYnZ70",
                '",',
                '"banner_image":"',
                "https://arweave.net/qHojDzf6FvtjI7OV8eyjm1oXzm17klsrSJpUzbV5pNA",
                '",',
                '"featured_image":"',
                "https://arweave.net/O1rPnGN7U3MDjYUHjzthEIyp0INLNYuY5RQRCZpELtc",
                '",',
                '"external_link":"https://phi.box/",',
                '"collaborators":["',
                ownerAddress.toHexString(),
                '"]',
                "}"
            )
        );

        return string.concat("data:application/json;utf8,", json);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev ReentrancyGuard modifier from solmate
    modifier nonReentrant() virtual {
        if (locked != 1) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }

    modifier nonZeroAddress(address address_) {
        if (address_ == address(0)) revert InvalidAddressZero();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the contract.
    /// @param phiSignerAddress_ The address of the claim signer.
    /// @param protocolFeeDestination_ The address to receive protocol fees.
    /// @param erc1155ArtAddress_ The address of the ERC1155Art contract.
    /// @param phiRewardsAddress_ The address of the PhiRewards contract.
    /// @param ownerAddress_ The address of the contract owner.
    /// @param protocolFee_ The protocol fee
    /// @param artCreateFee_ The art creation fee
    function initialize(
        address phiSignerAddress_,
        address protocolFeeDestination_,
        address erc1155ArtAddress_,
        address phiRewardsAddress_,
        address ownerAddress_,
        uint256 protocolFee_,
        uint256 artCreateFee_
    )
        external
        initializer
    {
        __Ownable_init(ownerAddress_);
        __Pausable_init();
        __UUPSUpgradeable_init();

        locked = 1;
        artIdCounter = 1;

        // Set the contract variables
        artCreateFee = artCreateFee_;
        mintProtocolFee = protocolFee_;
        phiSignerAddress = phiSignerAddress_;
        protocolFeeDestination = protocolFeeDestination_;
        erc1155ArtAddress = erc1155ArtAddress_;
        phiRewardsAddress = phiRewardsAddress_;
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE
    //////////////////////////////////////////////////////////////*/
    /// @notice Pauses the contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    function unPause() external onlyOwner {
        _unpause();
    }

    /// @notice Pause a art contract.
    /// @dev effect to all tokens in a art contract
    function pauseArtContract(uint256 artId_) external onlyOwner {
        IPhiNFT1155Ownable(arts[artId_].artAddress).pause();
    }

    /// @notice unPause a art contract.
    /// @dev effect to all tokens in a art contract
    function unPauseArtContract(uint256 artId_) external onlyOwner {
        IPhiNFT1155Ownable(arts[artId_].artAddress).unPause();
    }

    /*//////////////////////////////////////////////////////////////
                                 CREATE
    //////////////////////////////////////////////////////////////*/
    /// @notice Creates a art.
    /// @param signedData_ The signed art data.
    /// @param signature_ The signature of the signed art data.
    /// @param createConfig_ The art creation configuration.
    /// @return The address of the created art contract.
    function createArt(
        bytes calldata signedData_,
        bytes calldata signature_,
        CreateConfig memory createConfig_
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (address)
    {
        if (_recoverSigner(keccak256(signedData_), signature_) != phiSignerAddress) revert AddressNotSigned();

        CreateSignatureData memory createSigData = abi.decode(signedData_, (CreateSignatureData));
        // uint256 expiresIn;
        // uint256 signedChainId;
        // uint256 nonce;
        // address executor;
        // address artist;
        // string uri;
        // bytes credData;

        if (createSigData.expiresIn < block.timestamp) revert SignatureExpired();
        if (createSigData.signedChainId != block.chainid) revert InvalidChainId();
        if (createSigData.executor != _msgSender()) revert InvalidExecutor();
        if (createSigData.nonce != nonces[_msgSender()]) revert InvalidNonce();

        ERC1155Data memory erc1155Data = _createERC1155Data(
            artIdCounter, createConfig_, createSigData.artist, createSigData.uri, createSigData.credData
        );
        _validateArtCreation(erc1155Data);

        address artAddress = createERC1155Internal(artIdCounter, erc1155Data);
        nonces[_msgSender()]++;
        artIdCounter++;
        return artAddress;
    }

    function updateArt(
        bytes calldata signedData_,
        bytes calldata signature_,
        UpdateConfig memory updateConfig_
    )
        external
        nonReentrant
        whenNotPaused
    {
        if (_recoverSigner(keccak256(signedData_), signature_) != phiSignerAddress) revert AddressNotSigned();

        UpdateSignatureData memory updateSigData = abi.decode(signedData_, (UpdateSignatureData));
        // uint256 expiresIn;
        // uint256 signedChainId;
        // uint256 nonce;
        // uint256 artId;
        // string url;

        if (updateSigData.expiresIn < block.timestamp) revert SignatureExpired();
        if (updateSigData.signedChainId != block.chainid) revert InvalidChainId();
        if (updateSigData.nonce != nonces[_msgSender()]) revert InvalidNonce();

        PhiArt storage art = arts[updateSigData.artId];

        if (art.artist != _msgSender() && _msgSender() != owner()) revert InvalidArtCreator();
        if (updateConfig_.receiver == address(0)) revert InvalidAddressZero();
        if (updateConfig_.endTime <= updateConfig_.startTime) revert EndTimeLessThanOrEqualToStartTime();
        if (art.numberMinted > updateConfig_.maxSupply) revert ExceedMaxSupply();

        art.receiver = updateConfig_.receiver;
        art.maxSupply = updateConfig_.maxSupply;
        art.mintFee = updateConfig_.mintFee;
        art.startTime = updateConfig_.startTime;
        art.endTime = updateConfig_.endTime;
        art.uri = updateSigData.url;

        uint256 tokenId = IPhiNFT1155Ownable(art.artAddress).getTokenIdFromFactoryArtId(updateSigData.artId);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory configuration = ICreatorRoyaltiesControl
            .RoyaltyConfiguration({ royaltyBPS: updateConfig_.royaltyBPS, royaltyRecipient: updateConfig_.royaltyRecipient });
        IPhiNFT1155Ownable(art.artAddress).updateRoyalties(tokenId, configuration);
        nonces[_msgSender()]++;
        emit ArtUpdated(
            updateSigData.artId,
            updateSigData.url,
            updateConfig_.receiver,
            updateConfig_.maxSupply,
            updateConfig_.mintFee,
            updateConfig_.startTime,
            updateConfig_.endTime
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/
    /// @notice Claims a art reward.
    /// @param encodeData_ The encoded claim data.
    function claim(bytes calldata encodeData_) external payable {
        bytes memory encodedata_ = LibZip.cdDecompress(encodeData_);
        (uint256 artId) = abi.decode(encodedata_, (uint256));
        PhiArt storage art = arts[artId];
        if (art.verificationType.eq("MERKLE")) {
            (
                ,
                address minter_,
                bytes32[] memory proof,
                address ref_,
                uint256 expiresIn_,
                uint256 quantity_,
                bytes32 leafPart_,
                string memory snapshotImage_,
                bytes memory signature_
            ) = abi.decode(
                encodedata_, (uint256, address, bytes32[], address, uint256, uint256, bytes32, string, bytes)
            );

            MerkleClaimData memory merkleClaimData = MerkleClaimData({
                expiresIn: expiresIn_,
                minter: minter_,
                ref: ref_,
                artId: artId,
                chainId: block.chainid,
                snapshotImage: snapshotImage_
            });
            bytes memory claimEncodeData = abi.encode(merkleClaimData);

            this.merkleClaim{ value: msg.value }(proof, claimEncodeData, leafPart_, signature_, quantity_);
        } else if (art.verificationType.eq("SIGNATURE")) {
            (
                ,
                address minter_,
                address ref_,
                address verifier_,
                uint256 expiresIn_,
                uint256 quantity_,
                bytes32 data_,
                string memory snapshotImage_,
                bytes memory signature_
            ) = abi.decode(encodedata_, (uint256, address, address, address, uint256, uint256, bytes32, string, bytes));

            SigClaimData memory sigClaimData = SigClaimData({
                expiresIn: expiresIn_,
                minter: minter_,
                ref: ref_,
                verifier: verifier_,
                artId: artId,
                chainId: block.chainid,
                data: data_,
                snapshotImage: snapshotImage_
            });
            bytes memory claimEncodeData = abi.encode(sigClaimData);

            this.signatureClaim{ value: msg.value }(signature_, claimEncodeData, quantity_);
        } else {
            revert InvalidVerificationType();
        }
    }

    /// @notice Claims multiple art rewards in a batch.
    /// @param encodeDatas_ The array of encoded claim data.
    function batchClaim(bytes[] calldata encodeDatas_, uint256[] calldata ethValue_) external payable {
        if (encodeDatas_.length != ethValue_.length) revert ArrayLengthMismatch();

        // calc claim fee
        uint256 totalEthValue;
        for (uint256 i = 0; i < encodeDatas_.length; i++) {
            totalEthValue = totalEthValue + ethValue_[i];
        }
        if (msg.value != totalEthValue) revert InvalidEthValue();

        for (uint256 i = 0; i < encodeDatas_.length; i++) {
            this.claim{ value: ethValue_[i] }(encodeDatas_[i]);
        }
    }

    /// @notice Claims a art reward using a signature.
    /// @param signature_ The signature of the claim data.
    /// @param encodeData_ The encoded claim data.
    /// @param quantity_ The mint quantity.
    function signatureClaim(
        bytes calldata signature_,
        bytes calldata encodeData_,
        uint256 quantity_
    )
        external
        payable
    {
        if (_recoverSigner(keccak256(encodeData_), signature_) != phiSignerAddress) revert AddressNotSigned();
        // Decode the encoded data into the SigClaimData struct
        // uint256 expiresIn; // Timestamp when the signature expires
        // address minter; // Address of the account minting the NFT
        // address ref; // Referrer's address for potential referral rewards
        // address verifier; // Address of the entity verifying the claim
        // uint256 artId; // Unique identifier for the art piece
        // uint256 chainId; // ID of the blockchain where the transaction occurs
        // bytes32 data; // Additional data (usage depends on specific requirements)
        // string snapshotImage; // URI of the snapshot image
        SigClaimData memory claimData = abi.decode(encodeData_, (SigClaimData));

        if (claimData.expiresIn < block.timestamp) revert SignatureExpired();
        if (claimData.chainId != block.chainid) revert InvalidChainId();

        PhiArt storage art = arts[claimData.artId];
        if (!art.verificationType.eq("SIGNATURE")) revert InvalidVerificationType();

        _validateAndUpdateClaimState(claimData.artId, claimData.minter, quantity_);
        _processClaim(
            claimData.artId,
            claimData.minter,
            claimData.ref,
            claimData.verifier,
            quantity_,
            claimData.data,
            claimData.snapshotImage,
            msg.value
        );

        emit ArtClaimedData(
            claimData.artId,
            "SIGNATURE",
            claimData.minter,
            claimData.ref,
            claimData.verifier,
            arts[claimData.artId].artAddress,
            quantity_,
            claimData.snapshotImage
        );
    }

    /// @notice Claims a art reward using a Merkle proof.
    /// @param proof_ The Merkle proof.
    /// @param encodeData_ The encoded claim data.
    /// @param quantity_ The mint quantity.
    function merkleClaim(
        bytes32[] calldata proof_,
        bytes calldata encodeData_,
        bytes32 leafPart_,
        bytes calldata signature_,
        uint256 quantity_
    )
        external
        payable
    {
        if (_recoverSigner(keccak256(encodeData_), signature_) != phiSignerAddress) revert AddressNotSigned();
        // Decode the encoded data into the MerkleClaimData struct
        // uint256 expiresIn;
        // address minter;
        // address ref;
        // uint256 artId;
        // uint256 chainId;
        // string snapshotImage;
        MerkleClaimData memory claimData = abi.decode(encodeData_, (MerkleClaimData));

        if (claimData.expiresIn < block.timestamp) revert SignatureExpired();
        if (claimData.chainId != block.chainid) revert InvalidChainId();

        PhiArt storage art = arts[claimData.artId];

        if (!art.verificationType.eq("MERKLE") || credMerkleRoot[art.credChainId][art.credId] == bytes32(0)) {
            revert InvalidMerkleProof();
        }
        if (
            !MerkleProofLib.verifyCalldata(
                proof_,
                credMerkleRoot[art.credChainId][art.credId],
                keccak256(bytes.concat(keccak256(abi.encode(claimData.minter, leafPart_))))
            )
        ) {
            revert InvalidMerkleProof();
        }

        _validateAndUpdateClaimState(claimData.artId, claimData.minter, quantity_);
        _processClaim(
            claimData.artId,
            claimData.minter,
            claimData.ref,
            art.credCreator,
            quantity_,
            leafPart_,
            claimData.snapshotImage,
            msg.value
        );

        emit ArtClaimedData(
            claimData.artId,
            "MERKLE",
            claimData.minter,
            claimData.ref,
            art.credCreator,
            art.artAddress,
            quantity_,
            claimData.snapshotImage
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  SET
    //////////////////////////////////////////////////////////////*/
    /// @notice Sets the claim signer address.
    /// @param phiSignerAddress_ The new claim signer address.
    function setPhiSignerAddress(address phiSignerAddress_) external nonZeroAddress(phiSignerAddress_) onlyOwner {
        phiSignerAddress = phiSignerAddress_;
        emit PhiSignerAddressSet(phiSignerAddress_);
    }

    /// @notice Sets the PhiRewards contract address.
    /// @param phiRewardsAddress_ The new PhiRewards contract address.
    function setPhiRewardsAddress(address phiRewardsAddress_) external nonZeroAddress(phiRewardsAddress_) onlyOwner {
        phiRewardsAddress = phiRewardsAddress_;
        emit PhiRewardsAddressSet(phiRewardsAddress_);
    }

    /// @notice Sets the ERC1155Art contract address.
    /// @param erc1155ArtAddress_ The new ERC1155Art contract address.
    function setErc1155ArtAddress(address erc1155ArtAddress_) external nonZeroAddress(erc1155ArtAddress_) onlyOwner {
        erc1155ArtAddress = erc1155ArtAddress_;
        emit ERC1155ArtAddressSet(erc1155ArtAddress_);
    }

    /// @notice Sets the protocol fee destination address.
    /// @param protocolFeeDestination_ The new protocol fee destination address.
    function setProtocolFeeDestination(address protocolFeeDestination_)
        external
        nonZeroAddress(protocolFeeDestination_)
        onlyOwner
    {
        protocolFeeDestination = protocolFeeDestination_;
        emit ProtocolFeeDestinationSet(protocolFeeDestination_);
    }

    /// @notice Sets the protocol fee percentage.
    /// @param protocolFee_ The new protocol fee.
    function setProtocolFee(uint256 protocolFee_) external onlyOwner {
        if (protocolFee_ > MAX_PROTOCOL_FEE) revert ProtocolFeeTooHigh();
        mintProtocolFee = protocolFee_;
        emit ProtocolFeeSet(protocolFee_);
    }

    /// @notice Sets the art creation fee percentage.
    /// @param artCreateFee_ The new art creation fee percentage (in basis points).
    function setArtCreatFee(uint256 artCreateFee_) external onlyOwner {
        if (artCreateFee_ > MAX_ART_CREATE_FEE) revert ArtCreatFeeTooHigh();
        artCreateFee = artCreateFee_;
        emit ArtCreatFeeSet(artCreateFee_);
    }

    /*//////////////////////////////////////////////////////////////
                             EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the address of a art contract for a given art ID.
    /// @param artId_ The ID of the art.
    /// @return The address of the art contract.
    function getArtAddress(uint256 artId_) external view returns (address) {
        return arts[artId_].artAddress;
    }

    /// @notice Returns the number of minted tokens for a art.
    /// @param artId_ The ID of the art.
    /// @return The number of minted tokens.
    function getNumberMinted(uint256 artId_) external view returns (uint256) {
        return arts[artId_].numberMinted;
    }

    function getTokenURI(uint256 artId_) external view returns (string memory) {
        return arts[artId_].uri;
    }

    /// @notice Returns the art data for a given art ID.
    /// @param artId_ The ID of the art.
    /// @return The art data.
    function artData(uint256 artId_) external view returns (ArtData memory) {
        PhiArt storage thisArt = arts[artId_];
        if (thisArt.artAddress == address(0)) revert ArtNotCreated();

        IPhiNFT1155Ownable artContract = IPhiNFT1155Ownable(thisArt.artAddress);
        uint256 tokenId = artContract.getTokenIdFromFactoryArtId(artId_);
        IPhiNFT1155Ownable.RoyaltyConfiguration memory royaltyConfig = artContract.getRoyalties(tokenId);
        ArtData memory data = ArtData({
            credId: thisArt.credId,
            credCreator: thisArt.credCreator,
            credChainId: thisArt.credChainId,
            verificationType: thisArt.verificationType,
            uri: thisArt.uri,
            artAddress: thisArt.artAddress,
            tokenId: tokenId,
            artist: thisArt.artist,
            receiver: thisArt.receiver,
            royalties: royaltyConfig,
            maxSupply: thisArt.maxSupply,
            mintFee: thisArt.mintFee,
            startTime: thisArt.startTime,
            endTime: thisArt.endTime,
            numberMinted: thisArt.numberMinted,
            soulBounded: thisArt.soulBounded
        });

        return data;
    }

    /*//////////////////////////////////////////////////////////////
                             MINT FEE CALCULATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the mint fee for a art.
    /// @param artId_ The ID of the art.
    /// @return The mint fee for the art.
    function getArtMintFee(uint256 artId_, uint256 quantity_) public view returns (uint256) {
        return IPhiRewards(phiRewardsAddress).computeMintReward(quantity_, arts[artId_].mintFee)
            + quantity_ * mintProtocolFee;
    }

    /// @notice Returns the total mint fee for multiple arts.
    /// @param artId_ The array of art IDs.
    /// @return The total mint fee.
    function getTotalMintFee(
        uint256[] calldata artId_,
        uint256[] calldata quantitys_
    )
        external
        view
        returns (uint256)
    {
        if (artId_.length != quantitys_.length) revert ArrayLengthMismatch();
        uint256 totalMintFee;
        for (uint256 i = 0; i < artId_.length; i++) {
            uint256 artId = artId_[i];
            totalMintFee = totalMintFee + getArtMintFee(artId, quantitys_[i]);
        }
        return totalMintFee;
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM PROCESS
    //////////////////////////////////////////////////////////////*/
    /// @notice Checks a Merkle proof.
    /// @param proof The Merkle proof.
    /// @param leaf The leaf node.
    /// @param root The root hash.
    /// @return Whether the proof is valid.
    function checkProof(bytes32[] calldata proof, bytes32 leaf, bytes32 root) public pure returns (bool) {
        return MerkleProofLib.verifyCalldata(proof, root, leaf);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL UPDATE
    //////////////////////////////////////////////////////////////*/
    /// @dev Internal function to create an ERC1155 art.
    /// @param createData_ The ERC1155 art data.
    /// @return The address of the created art contract.
    function createERC1155Internal(uint256 newArtId, ERC1155Data memory createData_) internal returns (address) {
        PhiArt storage currentArt = arts[newArtId];
        _initializePhiArt(currentArt, createData_);

        // Decode the credData into the credId, credCreator, verificationType, credChainId, and merkleRootHash
        (uint256 credId,, string memory verificationType, uint256 credChainId,) =
            abi.decode(createData_.credData, (uint256, address, string, uint256, bytes32));

        address artAddress;
        if (credNFTContracts[credChainId][credId] == address(0)) {
            artAddress = _createNewNFTContract(currentArt, newArtId, createData_, credId, credChainId, verificationType);
            createdContracts[artAddress] = true;
        } else {
            artAddress = _useExistingNFTContract(currentArt, newArtId, createData_, credId, credChainId);
        }

        return artAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    /// @notice Recovers the signer of a hash and signature.
    /// @param hash_ The signed hash.
    /// @param signature_ The signature.
    /// @return The address of the signer.
    function _recoverSigner(bytes32 hash_, bytes memory signature_) private view returns (address) {
        return ECDSA.recover(ECDSA.toEthSignedMessageHash(hash_), signature_);
    }

    function _validateArtCreation(ERC1155Data memory createData_) private view {
        if (arts[createData_.artId].artAddress != address(0)) revert ArtAlreadyCreated();
        if (createData_.artist == address(0)) revert InvalidAddressZero();
        if (createData_.receiver == address(0)) revert InvalidAddressZero();
        if (createData_.endTime <= block.timestamp) revert EndTimeInPast();
        if (createData_.endTime <= createData_.startTime) revert EndTimeLessThanOrEqualToStartTime();
        if (createData_.maxSupply == 0) revert InvalidMaxSupply();
    }

    function _initializePhiArt(PhiArt storage art, ERC1155Data memory createData_) private {
        (
            uint256 credId,
            address credCreator,
            string memory verificationType,
            uint256 credChainId,
            bytes32 merkleRootHash
        ) = abi.decode(createData_.credData, (uint256, address, string, uint256, bytes32));

        art.credId = credId;
        art.credCreator = credCreator;
        art.credChainId = credChainId;
        art.verificationType = verificationType;
        art.uri = createData_.uri;
        art.artist = createData_.artist;
        art.receiver = createData_.receiver;
        art.maxSupply = createData_.maxSupply;
        art.mintFee = createData_.mintFee;
        art.startTime = createData_.startTime;
        art.endTime = createData_.endTime;
        art.soulBounded = createData_.soulBounded;

        credMerkleRoot[credChainId][credId] = merkleRootHash;
    }

    function _createNewNFTContract(
        PhiArt storage art,
        uint256 newArtId,
        ERC1155Data memory createData_,
        uint256 credId,
        uint256 credChainId,
        string memory verificationType
    )
        private
        returns (address)
    {
        address payable newArt =
            payable(erc1155ArtAddress.cloneDeterministic(keccak256(abi.encodePacked(block.chainid, newArtId, credId))));

        art.artAddress = newArt;

        IPhiNFT1155Ownable(newArt).initialize(credChainId, credId, verificationType);

        credNFTContracts[credChainId][credId] = address(newArt);

        (bool success_, bytes memory response) = newArt.call{ value: msg.value }(
            abi.encodeWithSignature("createArtFromFactory(address,uint256)", _msgSender(), newArtId)
        );

        if (!success_) revert CreateFailed();
        uint256 tokenId = abi.decode(response, (uint256));
        emit ArtContractCreated(createData_.artist, address(newArt), credId, credChainId);
        emit NewArtCreated(createData_.artist, credId, credChainId, newArtId, createData_.uri, address(newArt), tokenId);

        return address(newArt);
    }

    function _useExistingNFTContract(
        PhiArt storage art,
        uint256 newArtId,
        ERC1155Data memory createData_,
        uint256 credId,
        uint256 credChainId
    )
        private
        returns (address)
    {
        address existingArt = credNFTContracts[credChainId][credId];
        art.artAddress = existingArt;
        (bool success_, bytes memory response) = existingArt.call{ value: msg.value }(
            abi.encodeWithSignature("createArtFromFactory(address,uint256)", _msgSender(), newArtId)
        );

        if (!success_) revert CreateFailed();
        uint256 tokenId = abi.decode(response, (uint256));
        emit NewArtCreated(createData_.artist, credId, credChainId, newArtId, createData_.uri, existingArt, tokenId);

        return existingArt;
    }

    // Function to create ERC1155Data struct
    function _createERC1155Data(
        uint256 newArtId_,
        CreateConfig memory createConfig_,
        address artist_,
        string memory uri_,
        bytes memory credData
    )
        private
        view
        returns (ERC1155Data memory)
    {
        return ERC1155Data({
            artist: artist_,
            receiver: createConfig_.receiver,
            artChainId: block.chainid,
            maxSupply: createConfig_.maxSupply,
            endTime: createConfig_.endTime,
            startTime: createConfig_.startTime,
            credData: credData,
            artId: newArtId_,
            uri: uri_,
            mintFee: createConfig_.mintFee,
            soulBounded: createConfig_.soulBounded
        });
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM  INTERNAL PROCESS
    //////////////////////////////////////////////////////////////*/
    function _validateAndUpdateClaimState(uint256 artId_, address minter_, uint256 quantity_) private {
        PhiArt storage art = arts[artId_];

        // Common validations
        if (_msgSender() != art.artAddress && _msgSender() != address(this)) {
            revert TxOriginMismatch();
        }
        if (msg.value < getArtMintFee(artId_, quantity_)) revert InvalidMintFee();
        if (block.timestamp < art.startTime) revert ArtNotStarted();
        if (block.timestamp > art.endTime) revert ArtEnded();
        if (quantity_ == 0) revert InvalidQuantity();
        if (art.numberMinted + quantity_ > art.maxSupply) revert OverMaxAllowedToMint();

        // Common state updates
        if (!isCredMinted[art.credChainId][art.credId][minter_]) {
            isCredMinted[art.credChainId][art.credId][minter_] = true;
        }
        isArtMinted[artId_][minter_] = true;
        art.numberMinted += quantity_;
    }

    function _processClaim(
        uint256 artId_,
        address minter_,
        address ref_,
        address verifier_,
        uint256 quantity_,
        bytes32 data_,
        string memory snapshotImage_,
        uint256 etherValue_
    )
        private
        whenNotPaused
    {
        PhiArt storage art = arts[artId_];

        // Handle refund
        uint256 mintFee = getArtMintFee(artId_, quantity_);
        if (etherValue_ != mintFee) revert InvalidMintFee();

        protocolFeeDestination.safeTransferETH(mintProtocolFee * quantity_);

        (bool success_,) = art.artAddress.call{ value: mintFee - mintProtocolFee * quantity_ }(
            abi.encodeWithSignature(
                "claimFromFactory(uint256,address,address,address,uint256,bytes32,string)",
                artId_,
                minter_,
                ref_,
                verifier_,
                quantity_,
                data_,
                snapshotImage_
            )
        );

        if (!success_) revert ClaimFailed();
    }

    /*//////////////////////////////////////////////////////////////
                                OTHER
    //////////////////////////////////////////////////////////////*/
    function _buildDescription(PhiArt memory art) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Phi Protocol is an open credential layer for onchain identity. ",
                "Phi NFT collections represent your onchain achievement. ",
                "Details about this collection: cred-id: ",
                uint256(art.credId).toString(),
                ", chain-id: ",
                uint256(art.credChainId).toString(),
                ", created by: ",
                art.credCreator.toHexString(),
                ". ",
                "Explore https://phi.box/ to learn more."
            )
        );
    }
}
