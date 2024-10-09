// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ICreatorRoyaltiesControl } from "../interfaces/ICreatorRoyaltiesControl.sol";
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title CreatorRoyaltiesControl
/// @notice Contract for managing the royalties of an ERC1155 contract
abstract contract CreatorRoyaltiesControl is ICreatorRoyaltiesControl {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(uint256 _tokenId => RoyaltyConfiguration _configuration) public royalties;

    uint256 private constant ROYALTY_BPS_TO_PERCENT = 10_000;
    uint256 private constant MAX_ROYALTY_BPS = 2000;

    address private royaltyRecipient;

    bool private initilized;

    /*//////////////////////////////////////////////////////////////
                            VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getProtocolFeeDestination() public view virtual returns (address);

    /// @notice Checks if the contract supports a given interface
    /// @param interfaceId The interface identifier
    /// @return true if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC2981).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function __initializeRoyalties() internal {
        address protocolFeeDestination = getProtocolFeeDestination();
        if (protocolFeeDestination == address(0)) revert InvalidRoyaltyRecipient();
        if (initilized) revert AlreadyInitialized();
        royaltyRecipient = protocolFeeDestination;
        initilized = true;
    }

    /// @notice Updates the royalties for a given token
    /// @param tokenId The token ID to update royalties for
    /// @param configuration The new royalty configuration
    function _updateRoyalties(uint256 tokenId, RoyaltyConfiguration memory configuration) internal {
        if (configuration.royaltyRecipient == address(0) && configuration.royaltyBPS > 0) {
            revert InvalidRoyaltyRecipient();
        }
        if (configuration.royaltyBPS > MAX_ROYALTY_BPS) {
            revert RoyaltyTooHigh();
        }

        royalties[tokenId] = configuration;

        emit UpdatedRoyalties(tokenId, msg.sender, configuration);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice The royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    /// @return The royalty configuration for the token.
    function getRoyalties(uint256 tokenId) public view returns (RoyaltyConfiguration memory) {
        if (!initilized) revert NotInitialized();
        RoyaltyConfiguration memory config = royalties[tokenId];
        if (config.royaltyRecipient != address(0)) {
            return config;
        }
        // Return default configuration
        return RoyaltyConfiguration({ royaltyBPS: 500, royaltyRecipient: royaltyRecipient });
    }

    /// @notice Returns the royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    /// @param salePrice The sale price of the NFT asset specified by tokenId
    /// @return receiver The address of the royalty recipient
    /// @return royaltyAmount The royalty amount to be paid
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    )
        public
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyConfiguration memory config = getRoyalties(tokenId);
        royaltyAmount = (config.royaltyBPS * salePrice) / ROYALTY_BPS_TO_PERCENT;
        receiver = config.royaltyRecipient;
    }
}
