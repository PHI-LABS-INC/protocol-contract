// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPhiFactory } from "../interfaces/IPhiFactory.sol";

abstract contract Claimable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    // Define constant state variables
    uint256 private constant DECODE_OFFSET = 4;

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getPhiFactoryContract() public view virtual returns (IPhiFactory);
    function getFactoryArtId(uint256 tokenId) public view virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Processes a Signature claim.
    function signatureClaim() external payable {
        (
            bytes32 r_,
            bytes32 vs_,
            address ref_,
            address verifier_,
            address minter_,
            uint256 tokenId_,
            uint256 quantity_,
            uint256 expiresIn_,
            string memory snapshotImage_,
            bytes32 data_
        ) = abi.decode(
            msg.data[DECODE_OFFSET:],
            (bytes32, bytes32, address, address, address, uint256, uint256, uint256, string, bytes32)
        );
        uint256 artId = getFactoryArtId(tokenId_);
        IPhiFactory.SigClaimData memory sigClaimData = IPhiFactory.SigClaimData({
            expiresIn: expiresIn_,
            minter: minter_,
            ref: ref_,
            verifier: verifier_,
            artId: artId,
            chainId: block.chainid,
            data: data_,
            snapshotImage: snapshotImage_
        });
        bytes memory encodeData_ = abi.encode(sigClaimData);
        bytes memory signature = abi.encodePacked(r_, vs_);

        IPhiFactory phiFactoryContract = getPhiFactoryContract();
        phiFactoryContract.signatureClaim{ value: msg.value }(signature, encodeData_, quantity_);
    }

    /// @notice Processes a merkle claim.
    function merkleClaim() external payable {
        (
            bytes32 r_,
            bytes32 vs_,
            address minter_,
            bytes32[] memory proof_,
            address ref_,
            uint256 tokenId_,
            uint256 quantity_,
            bytes32 leafPart_,
            uint256 expiresIn_,
            string memory snapshotImage_
        ) = abi.decode(
            msg.data[DECODE_OFFSET:],
            (bytes32, bytes32, address, bytes32[], address, uint256, uint256, bytes32, uint256, string)
        );
        uint256 artId = getFactoryArtId(tokenId_);
        IPhiFactory.MerkleClaimData memory merkleClaimData = IPhiFactory.MerkleClaimData({
            expiresIn: expiresIn_,
            minter: minter_,
            ref: ref_,
            artId: artId,
            chainId: block.chainid,
            snapshotImage: snapshotImage_
        });
        bytes memory encodeData_ = abi.encode(merkleClaimData);
        bytes memory signature = abi.encodePacked(r_, vs_);

        IPhiFactory phiFactory = getPhiFactoryContract();
        phiFactory.merkleClaim{ value: msg.value }(proof_, encodeData_, leafPart_, signature, quantity_);
    }
}
