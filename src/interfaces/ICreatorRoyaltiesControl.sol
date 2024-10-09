// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";

interface ICreatorRoyaltiesControl is IERC2981 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AlreadyInitialized();
    error NotInitialized();
    error RoyaltyTooHigh();
    error InvalidRoyaltyRecipient();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Event emitted when royalties are updated
    event UpdatedRoyalties(uint256 indexed tokenId, address indexed user, RoyaltyConfiguration configuration);

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/
    /// @notice The RoyaltyConfiguration struct is used to store the royalty configuration for a given token.
    /// @param royaltyMintSchedule Every nth token will go to the royalty recipient.
    /// @param royaltyBPS The royalty amount in basis points for secondary sales.
    /// @param royaltyRecipient The address that will receive the royalty payments.
    struct RoyaltyConfiguration {
        uint32 royaltyBPS;
        address royaltyRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice External data getter to get royalties for a token
    /// @param tokenId tokenId to get royalties configuration for
    function getRoyalties(uint256 tokenId) external view returns (RoyaltyConfiguration memory);
}
