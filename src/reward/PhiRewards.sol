// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Logo } from "../lib/Logo.sol";
import { IPhiRewards } from "../interfaces/IPhiRewards.sol";
import { IPhiFactory } from "../interfaces/IPhiFactory.sol";
import { RewardControl } from "../abstract/RewardControl.sol";
import { ICuratorRewardsDistributor } from "../interfaces/ICuratorRewardsDistributor.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PhiRewards
/// @notice Manager of deposits & withdrawals for art rewards
contract PhiRewards is Logo, RewardControl, Ownable2Step, IPhiRewards {
    /*//////////////////////////////////////////////////////////////
                                 USING
    //////////////////////////////////////////////////////////////*/
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    ICuratorRewardsDistributor public curatorRewardsDistributor;
    IPhiFactory public phiFactory;

    uint256 public artistReward = 0.0001 ether;
    uint256 public referralReward = 0.00005 ether;
    uint256 public verifierReward = 0.0001 ether;
    uint256 public curatorReward = 0.00005 ether;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address ownerAddress_) payable Ownable(ownerAddress_) { }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyFactoryCreateArt(address address_) {
        if (address(phiFactory) == address(0)) revert PhiFactoryNotSet();
        if (!phiFactory.createdContracts(address_)) {
            revert ContractNotCreatedByFactory();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Update the PhiFactory address
    /// @param newPhiFactory_ The address of the new PhiFactory contract
    function setPhiFactory(address newPhiFactory_) external onlyOwner {
        if (newPhiFactory_ == address(0)) revert InvalidAddressZero();
        phiFactory = IPhiFactory(newPhiFactory_);
        emit PhiFactoryUpdated(newPhiFactory_);
    }

    /// @notice Update artist reward amount
    /// @param newArtistReward_ New artist reward amount
    function updateArtistReward(uint256 newArtistReward_) external onlyOwner {
        artistReward = newArtistReward_;
        emit ArtistRewardUpdated(newArtistReward_);
    }

    /// @notice Update referral reward amount
    /// @param newReferralReward_ New referral reward amount
    function updateReferralReward(uint256 newReferralReward_) external onlyOwner {
        referralReward = newReferralReward_;
        emit ReferralRewardUpdated(newReferralReward_);
    }

    /// @notice Update verify reward amount
    /// @param newVerifyReward_ New verify reward amount
    function updateVerifierReward(uint256 newVerifyReward_) external onlyOwner {
        verifierReward = newVerifyReward_;
        emit VerifierRewardUpdated(newVerifyReward_);
    }

    /// @notice Update curate reward amount
    /// @param newCurateReward_ New curate reward amount
    function updateCurateReward(uint256 newCurateReward_) external onlyOwner {
        curatorReward = newCurateReward_;
        emit CuratorRewardUpdated(newCurateReward_);
    }

    /// @notice Update curator rewards distributor
    /// @dev This method is only used credential contract is deployed on a same network,
    /// if not, it should be set to address(0)
    function updateCuratorRewardsDistributor(address curatorRewardsDistributor_) external onlyOwner {
        curatorRewardsDistributor = ICuratorRewardsDistributor(curatorRewardsDistributor_);
        emit CuratorRewardsDistributorUpdated(curatorRewardsDistributor_);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL UPDATE
    //////////////////////////////////////////////////////////////*/
    /// @notice deposit protocol rewards
    /// @param credId_ Cred ID
    function depositRewards(
        uint256 artId_,
        uint256 credId_,
        bytes calldata addressesData_,
        uint256 artistTotalReward_,
        uint256 referralTotalReward_,
        uint256 verifierTotalReward_,
        uint256 curateTotalReward_,
        bool chainSync_
    )
        internal
    {
        (address minter_, address receiver_, address referral_, address verifier_) =
            abi.decode(addressesData_, (address, address, address, address));

        if (receiver_ == address(0) || minter_ == address(0) || verifier_ == address(0)) {
            revert InvalidAddressZero();
        }

        if (referral_ == minter_ || referral_ == address(0)) {
            artistTotalReward_ += referralTotalReward_;
            referralTotalReward_ = 0;
        } else if (referral_ != address(0)) {
            balanceOf[referral_] += referralTotalReward_;
        }

        balanceOf[verifier_] += verifierTotalReward_;
        balanceOf[receiver_] += artistTotalReward_;

        bytes memory rewardsData;
        if (chainSync_ && address(curatorRewardsDistributor) != address(0)) {
            //slither-disable-next-line arbitrary-send-eth
            curatorRewardsDistributor.deposit{ value: curateTotalReward_ }(credId_, curateTotalReward_);
            rewardsData =
                abi.encode(artId_, artistTotalReward_, referralTotalReward_, verifierTotalReward_, curateTotalReward_);
        } else {
            balanceOf[verifier_] += curateTotalReward_;
            rewardsData = abi.encode(
                artId_, artistTotalReward_, referralTotalReward_, verifierTotalReward_ + curateTotalReward_, 0
            );
            emit NotChainSyncDeposit(artId_, verifier_, curateTotalReward_);
        }
        emit RewardsDeposit(minter_, receiver_, referral_, verifier_, rewardsData);
    }

    function handleRewardsAndGetValueSent(
        uint256 artId_,
        uint256 credId_,
        uint256 quantity_,
        uint256 mintFee_,
        bytes calldata addressesData_,
        bool chainSync_
    )
        external
        payable
        onlyFactoryCreateArt(_msgSender())
    {
        if (computeMintReward(quantity_, mintFee_) != msg.value) {
            revert InvalidDeposit();
        }

        depositRewards(
            artId_,
            credId_,
            addressesData_,
            quantity_ * (mintFee_ + artistReward),
            quantity_ * referralReward,
            quantity_ * verifierReward,
            quantity_ * curatorReward,
            chainSync_
        );
    }

    /*//////////////////////////////////////////////////////////////
                             EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    function computeMintReward(uint256 quantity_, uint256 mintFee_) public view returns (uint256) {
        return quantity_ * (artistReward + mintFee_ + referralReward + verifierReward + curatorReward);
    }
}
