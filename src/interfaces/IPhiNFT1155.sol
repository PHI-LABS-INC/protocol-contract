// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ICreatorRoyaltiesControl } from "./ICreatorRoyaltiesControl.sol";

interface IPhiNFT1155 is ICreatorRoyaltiesControl {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TokenNotTransferable();
    error InsufficientTokenBalance();
    error NotStarted();
    error NotEnded();
    error NotPhiFactory();
    error AddressNotSigned();
    error NotArtCreator();
    error InValdidTokenId();
    error NotEnoughFee();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ArtClaimedData(
        address indexed recipient,
        address indexed artistRewardReceiver,
        address indexed referrer,
        address verifier,
        uint256 artId,
        uint256 tokenId,
        uint256 quantity,
        bytes32 data,
        string snapshotImage
    );
    event InitializePhiNFT1155(uint256 credChainId, uint256 credId, string verificationType);
    event MintComment(address indexed to, address from, uint256 tokenId, string snapshotImage);
    event ArtCreated(uint256 artId, uint256 tokenId);
    event ContractURIUpdated();

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // Initializer/Constructor Function
    function initialize(uint256 credChainId, uint256 credId, string memory verificationType) external;

    // Read Functions
    function tokenIdCounter() external view returns (uint256);
    function credId() external view returns (uint256);
    function getTokenIdFromFactoryArtId(uint256 artId) external view returns (uint256);
    function getFactoryArtId(uint256 tokenId) external view returns (uint256);
    function verificationType() external view returns (string memory);

    // Update Functions
    function pause() external;
    function unPause() external;
    function updateRoyalties(uint256 tokenId, RoyaltyConfiguration memory configuration) external;
    function createArtFromFactory(address sender, uint256 artId) external payable returns (uint256);
}
