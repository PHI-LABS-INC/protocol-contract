// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPhiNFT1155 } from "../interfaces/IPhiNFT1155.sol";
import { IPhiFactory } from "../interfaces/IPhiFactory.sol";
import { IPhiRewards } from "../interfaces/IPhiRewards.sol";
import { Claimable } from "../abstract/Claimable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { ERC1155SupplyUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import { ERC1155PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { CreatorRoyaltiesControl } from "../abstract/CreatorRoyaltiesControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract PhiNFT1155 is
    Initializable,
    UUPSUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155PausableUpgradeable,
    Ownable2StepUpgradeable,
    IPhiNFT1155,
    Claimable,
    CreatorRoyaltiesControl
{
    // The following functions are overrides required by Solidity.
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    )
        internal
        override(ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }

    /*//////////////////////////////////////////////////////////////
                                 USING
    //////////////////////////////////////////////////////////////*/
    using SafeTransferLib for address;
    using LibString for uint256;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    IPhiFactory public phiFactoryContract;

    uint256 public credChainId;
    uint256 public credId;
    uint256 public tokenIdCounter;

    string public name;
    string public symbol;

    string public verificationType;

    mapping(uint256 artId => uint256 tokenId) private _artIdToTokenId;
    mapping(uint256 tokenId => uint256 artId) private _tokenIdToArtId;
    mapping(address minter => bool minted) public minted;

    mapping(address minter => mapping(uint256 tokenId => bytes32[])) public minterDataHistory;
    mapping(address minter => mapping(uint256 tokenId => string[])) public snapshotImageHistory;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public pure returns (uint256) {
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Checks if the sender is the art creator or the contract owner.
    /// @param tokenId_ The token ID of the art.
    modifier onlyArtCreator(uint256 tokenId_) {
        uint256 artId = _tokenIdToArtId[tokenId_];
        address artist = phiFactoryContract.artData(artId).artist;
        if (_msgSender() != artist && _msgSender() != owner()) revert NotArtCreator();
        _;
    }

    /// @notice Checks if the sender is the Phi Factory contract.
    modifier onlyPhiFactory() {
        if (_msgSender() != address(phiFactoryContract)) revert NotPhiFactory();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the contract.
    /// @param credId_ The cred ID.
    /// @param verificationType_ The verification type.
    function initialize(uint256 credChainId_, uint256 credId_, string memory verificationType_) external initializer {
        __Ownable_init(_msgSender());
        __Pausable_init();

        phiFactoryContract = IPhiFactory(payable(_msgSender()));
        __initializeRoyalties();

        tokenIdCounter = 1;
        credChainId = credChainId_;
        credId = credId_;
        name = string(
            abi.encodePacked("Phi Cred-", uint256(credId_).toString(), " on Chain-", uint256(credChainId_).toString())
        );
        symbol = string(abi.encodePacked("PHI-", uint256(credId_).toString(), "-", uint256(credChainId_).toString()));

        verificationType = verificationType_;
        emit InitializePhiNFT1155(credChainId_, credId_, verificationType_);
    }

    /// @notice Pauses the contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    function unPause() external onlyOwner {
        _unpause();
    }

    /// @notice Creates a new art from the Phi Factory contract.
    function createArtFromFactory(
        address sender,
        uint256 artId_
    )
        external
        payable
        onlyPhiFactory
        whenNotPaused
        returns (uint256)
    {
        _artIdToTokenId[artId_] = tokenIdCounter;
        _tokenIdToArtId[tokenIdCounter] = artId_;

        uint256 artFee = phiFactoryContract.artCreateFee();
        address protocolFeeDestination = phiFactoryContract.protocolFeeDestination();
        protocolFeeDestination.safeTransferETH(artFee);
        emit ArtCreated(artId_, tokenIdCounter);
        uint256 createdTokenId = tokenIdCounter;

        unchecked {
            tokenIdCounter += 1;
        }
        // check NOT ENOUGH FEE
        if (msg.value < artFee) {
            revert NotEnoughFee();
        }
        if ((msg.value - artFee) > 0) {
            sender.safeTransferETH(msg.value - artFee);
        }

        return createdTokenId;
    }

    /// @notice Claims a art token from the Phi Factory contract.
    /// @param minter_ The address claiming the art token.
    /// @param ref_ The referrer address.
    /// @param verifier_ The verifier address.
    /// @param data_ The value associated with the claim.
    /// @param snapshotImage_ The imageURI associated with the claim.
    function claimFromFactory(
        uint256 artId_,
        address minter_,
        address ref_,
        address verifier_,
        uint256 quantity_,
        bytes32 data_,
        string memory snapshotImage_
    )
        external
        payable
        whenNotPaused
        onlyPhiFactory
    {
        uint256 tokenId_ = _artIdToTokenId[artId_];
        if (tokenId_ == 0) {
            revert InValdidTokenId();
        }
        mint(minter_, tokenId_, quantity_, snapshotImage_, data_);
        address aristRewardReceiver = phiFactoryContract.artData(artId_).receiver;
        bytes memory addressesData_ = abi.encode(minter_, aristRewardReceiver, ref_, verifier_);

        IPhiRewards(payable(phiFactoryContract.phiRewardsAddress())).handleRewardsAndGetValueSent{ value: msg.value }(
            artId_, credId, quantity_, mintFee(tokenId_), addressesData_, credChainId == block.chainid
        );
        emit ArtClaimedData(
            minter_, aristRewardReceiver, ref_, verifier_, artId_, tokenId_, quantity_, data_, snapshotImage_
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  SET
    //////////////////////////////////////////////////////////////*/
    function updateRoyalties(
        uint256 tokenId_,
        RoyaltyConfiguration memory configuration
    )
        external
        onlyArtCreator(tokenId_)
        whenNotPaused
    {
        _updateRoyalties(tokenId_, configuration);
    }

    /// @dev just notice to update
    function setContractURI() external {
        emit ContractURIUpdated();
    }

    /*//////////////////////////////////////////////////////////////
                             EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    // @notice Returns true if the contract implements the interface defined by interfaceId
    /// @param interfaceId The interface to check for
    /// @return if the interfaceId is marked as supported
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(CreatorRoyaltiesControl, ERC1155Upgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == type(IPhiNFT1155).interfaceId
            || ERC1155Upgradeable.supportsInterface(interfaceId);
    }

    function contractURI() public view returns (string memory) {
        return phiFactoryContract.contractURI(address(this));
    }

    /// @notice Returns the URI of a art token.
    /// @param tokenId_ The token ID.
    /// @return The token URI.
    function uri(uint256 tokenId_) public view override returns (string memory) {
        return phiFactoryContract.getTokenURI(_tokenIdToArtId[tokenId_]);
    }

    /// @notice Returns the URI of a art token.
    /// @param tokenId_ The token ID.
    /// @return The token URI.
    function uri(uint256 tokenId_, address minter_, uint256 index_) public view returns (string memory) {
        uint256 historyLength = snapshotImageHistory[minter_][tokenId_].length;

        if (historyLength == 0) {
            return phiFactoryContract.getTokenURI(_tokenIdToArtId[tokenId_]);
        }

        if (index_ == 0 || index_ > historyLength) {
            // Return the latest URI (last element in the array) if index is 0 or out of bounds
            return snapshotImageHistory[minter_][tokenId_][historyLength - 1];
        } else {
            // Return the URI at the specified index (1-based index)
            return snapshotImageHistory[minter_][tokenId_][index_ - 1];
        }
    }

    /// @notice Returns the Phi Factory contract address.
    /// @return The Phi Factory contract address.
    function getPhiFactoryContract() public view override returns (IPhiFactory) {
        return phiFactoryContract;
    }

    function getTokenIdFromFactoryArtId(uint256 artId_) public view returns (uint256 tokenId) {
        return _artIdToTokenId[artId_];
    }

    function getFactoryArtId(uint256 tokenId_) public view override(Claimable, IPhiNFT1155) returns (uint256) {
        return _tokenIdToArtId[tokenId_];
    }

    function getProtocolFeeDestination() public view override returns (address) {
        return phiFactoryContract.protocolFeeDestination();
    }

    function getArtDataFromFactory(uint256 artId_) public view returns (IPhiFactory.ArtData memory) {
        return phiFactoryContract.artData(artId_);
    }

    function mintFee(uint256 tokenId_) public view returns (uint256) {
        return phiFactoryContract.artData(_tokenIdToArtId[tokenId_]).mintFee;
    }

    function soulBounded(uint256 tokenId_) public view returns (bool) {
        return phiFactoryContract.artData(_tokenIdToArtId[tokenId_]).soulBounded;
    }

    function getURIHistory(uint256 tokenId_, address minter_) public view returns (string[] memory) {
        return snapshotImageHistory[minter_][tokenId_];
    }

    function getMinterDataHistory(uint256 tokenId_, address minter_) public view returns (bytes32[] memory) {
        return minterDataHistory[minter_][tokenId_];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Mints a art token to a recipient.
    /// @param to_ The recipient address.
    /// @param tokenId_ The token ID of the art.
    /// @param snapshotImage_ The snapshotImage associated with the mint.
    /// @param data_ The value associated with the mint.
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 quantity_,
        string memory snapshotImage_,
        bytes32 data_
    )
        internal
    {
        // Add new data and URI to the respective arrays
        minterDataHistory[to_][tokenId_].push(data_);
        snapshotImageHistory[to_][tokenId_].push(snapshotImage_);
        if (!minted[to_]) {
            minted[to_] = true;
        }

        _mint(to_, tokenId_, quantity_, "0x00");
    }

    /// @notice Safely transfers a art token from one address to another.
    /// @param from_ The sender address.
    /// @param to_ The recipient address.
    /// @param id_ The token ID.
    /// @param value_ The amount to transfer.
    /// @param data_ Additional data.
    function safeTransferFrom(
        address from_,
        address to_,
        uint256 id_,
        uint256 value_,
        bytes memory data_
    )
        public
        override
        whenNotPaused
    {
        if (from_ != address(0) && soulBounded(id_)) revert TokenNotTransferable();
        address sender = _msgSender();
        if (from_ != sender && !isApprovedForAll(from_, sender)) {
            revert ERC1155MissingApprovalForAll(sender, from_);
        }

        _safeTransferFrom(from_, to_, id_, value_, data_);
    }

    /// @notice Safely transfers multiple art tokens from one address to another.
    /// @param from_ The sender address.
    /// @param to_ The recipient address.
    /// @param ids_ The token IDs.
    /// @param values_ The amounts to transfer.
    /// @param data_ Additional data.
    function safeBatchTransferFrom(
        address from_,
        address to_,
        uint256[] memory ids_,
        uint256[] memory values_,
        bytes memory data_
    )
        public
        override
        whenNotPaused
    {
        for (uint256 i; i < ids_.length; i++) {
            if (from_ != address(0) && soulBounded(ids_[i])) revert TokenNotTransferable();
        }
        address sender = _msgSender();
        if (from_ != sender && !isApprovedForAll(from_, sender)) {
            revert ERC1155MissingApprovalForAll(sender, from_);
        }
        _safeBatchTransferFrom(from_, to_, ids_, values_, data_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // This function is intentionally left empty to allow for upgrades
    }
}
