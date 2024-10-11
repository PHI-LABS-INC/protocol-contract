// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ICreatorRoyaltiesControl } from "./ICreatorRoyaltiesControl.sol";

interface IPhiFactory {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressNotSigned();
    error InvalidAddressZero();
    error InvalidMintFee();
    error OverMaxAllowedToMint();
    error ArtCreatFeeTooHigh();
    error ProtocolFeeTooHigh();
    error Reentrancy();
    error ClaimFailed();
    error CreateFailed();
    error TxOriginMismatch();
    error SignatureExpired();
    error InvalidMerkleProof();
    error InvalidVerificationType();
    error InvalidArtCreator();
    error EndTimeInPast();
    error EndTimeLessThanOrEqualToStartTime();
    error ArtNotStarted();
    error ArtEnded();
    error ArtAlreadyCreated();
    error ExceedMaxSupply();
    error InvalidQuantity();
    error InvalidEthValue();
    error ArrayLengthMismatch();
    error ArtNotCreated();
    error InvalidChainId();
    error InvalidExecutor();
    error InvalidNonce();
    error InvalidMaxSupply();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct CreateConfig {
        address receiver;
        uint256 endTime;
        uint256 startTime;
        uint256 maxSupply;
        uint256 mintFee;
        bool soulBounded;
    }

    struct UpdateConfig {
        address receiver;
        uint256 endTime;
        uint256 startTime;
        uint256 maxSupply;
        uint256 mintFee;
        uint32 royaltyBPS;
        address royaltyRecipient;
    }

    struct SigClaimData {
        uint256 expiresIn; // Timestamp when the signature expires
        address minter; // Address of the account minting the NFT
        address ref; // Referrer's address for potential referral rewards
        address verifier; // Address of the entity verifying the claim
        uint256 artId; // Unique identifier for the art piece
        uint256 chainId; // ID of the blockchain where the transaction occurs
        bytes32 data; // Additional data (usage depends on specific requirements)
        string snapshotImage; // URI of the snapshot image
    }

    struct MerkleClaimData {
        uint256 expiresIn;
        address minter;
        address ref;
        uint256 artId;
        uint256 chainId;
        string snapshotImage;
    }

    struct ERC1155Data {
        address artist;
        address receiver;
        uint256 artChainId;
        uint256 maxSupply;
        uint256 endTime;
        uint256 startTime;
        bytes credData;
        uint256 artId;
        string uri;
        uint256 mintFee;
        bool soulBounded;
    }

    struct CreateSignatureData {
        uint256 expiresIn;
        uint256 signedChainId;
        uint256 nonce;
        address executor;
        address artist;
        string uri;
        bytes credData;
    }
    //     bytes32 credData;
    //     =>uint256 credId,address credCreator,string memory verificationType,uint256 credChainId,bytes32 merkleRoot

    struct UpdateSignatureData {
        uint256 expiresIn;
        uint256 signedChainId;
        uint256 nonce;
        uint256 artId;
        string url;
    }

    struct PhiArt {
        uint256 credId;
        address credCreator;
        uint256 credChainId;
        string verificationType;
        string uri;
        address artAddress;
        address artist;
        address receiver;
        uint256 maxSupply;
        uint256 mintFee;
        uint256 startTime;
        uint256 endTime;
        uint256 numberMinted;
        bool soulBounded;
    }

    struct ArtData {
        uint256 credId;
        address credCreator;
        uint256 credChainId;
        string verificationType;
        string uri;
        address artAddress;
        uint256 tokenId;
        address artist;
        address receiver;
        ICreatorRoyaltiesControl.RoyaltyConfiguration royalties;
        uint256 maxSupply;
        uint256 mintFee;
        uint256 startTime;
        uint256 endTime;
        uint256 numberMinted;
        bool soulBounded;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ArtClaimedData(
        uint256 indexed artId,
        string verificationType,
        address indexed recipient,
        address ref,
        address verifier,
        address artAddress,
        uint256 quantity,
        string snapshotImage
    );
    event NewArtCreated(
        address indexed artist,
        uint256 indexed credId,
        uint256 indexed credChainId,
        uint256 artId,
        string url,
        address artAddress,
        uint256 tokenId
    );
    event ArtContractCreated(
        address artist, address contractAddress, uint256 indexed credId, uint256 indexed credChainId
    );
    event ProtocolFeeSet(uint256 fee);
    event ArtCreatFeeSet(uint256 fee);
    event ArtUpdated(
        uint256 indexed artId,
        string url,
        address receiver,
        uint256 maxSupply,
        uint256 mintFee,
        uint256 startTime,
        uint256 endTime
    );
    event PhiSignerAddressSet(address phiSignerAddress);
    event PhiRewardsAddressSet(address phiRewardsAddress);
    event ERC1155ArtAddressSet(address erc1155ArtAddress);
    event ProtocolFeeDestinationSet(address protocolFeeDestination);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function mintProtocolFee() external view returns (uint256);
    function protocolFeeDestination() external view returns (address);
    function phiRewardsAddress() external view returns (address);
    function artCreateFee() external view returns (uint256);
    function getNumberMinted(uint256 artId) external view returns (uint256);
    function artData(uint256 artId) external view returns (ArtData memory);
    function getArtMintFee(uint256 artId, uint256 quantity) external view returns (uint256);
    function getTotalMintFee(uint256[] memory artId, uint256[] memory quantity) external view returns (uint256);
    function isCredMinted(uint256 credChainId, uint256 credId, address minter) external view returns (bool);
    function isArtMinted(uint256 artId, address minter) external view returns (bool);
    function contractURI(address nft) external view returns (string memory);
    function getArtAddress(uint256 artId) external view returns (address);
    function getTokenURI(uint256 artId) external view returns (string memory);
    function createdContracts(address art) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                               OPERATIONS
    //////////////////////////////////////////////////////////////*/
    function signatureClaim(bytes calldata signature, bytes calldata encodeData, uint256 quantity_) external payable;

    function merkleClaim(
        bytes32[] calldata proof_,
        bytes calldata encodeData_,
        bytes32 leafPart_,
        bytes calldata signature_,
        uint256 quantity_
    )
        external
        payable;

    function claim(bytes calldata encodeData) external payable;

    function batchClaim(bytes[] calldata encodeData, uint256[] calldata ethValue) external payable;

    function setPhiSignerAddress(address phiSignerAddress) external;

    function setErc1155ArtAddress(address erc1155ArtAddress) external;

    function setProtocolFeeDestination(address protocolFeeDestination) external;

    function setProtocolFee(uint256 protocolFee) external;

    function setArtCreatFee(uint256 artFee) external;
}
