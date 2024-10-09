// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ICred } from "../src/interfaces/ICred.sol";
import { Settings } from "./helpers/Settings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IPhiFactory } from "../src/interfaces/IPhiFactory.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { LibZip } from "solady/utils/LibZip.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { IPhiFactory } from "../src/interfaces/IPhiFactory.sol";
import { IPhiNFT1155Ownable } from "../src/interfaces/IPhiNFT1155Ownable.sol";
import { ICreatorRoyaltiesControl } from "../src/interfaces/ICreatorRoyaltiesControl.sol";

contract TestPhiFactory is Settings {
    string ART_ID_URL_STRING;
    string ART_ID2_URL_STRING;
    string IMAGE_URL;
    string IMAGE_URL2;
    uint256 expiresIn;
    bytes32[] leaves;
    bytes[] datasCompressed = new bytes[](2);
    address[] accounts;
    bytes32[] datas;

    function setUp() public override {
        super.setUp();

        ART_ID_URL_STRING = "333L2H5BLDwyojZtOi-7TSCqFM7ISlsDOIlAfTUs5es";
        ART_ID2_URL_STRING = "432CqFM7ISlsDOIlA-7TSCqFM7ISlsDOIlAfTUs5es";
        IMAGE_URL = "https://example.com/image.png";
        IMAGE_URL2 = "https://example.com/image2.png";

        expiresIn = START_TIME + 100;

        _createCred("BASIC", "SIGNATURE", 0x0);
        vm.warp(START_TIME + 1);
    }

    function _createCred(string memory credType, string memory verificationType, bytes32 merkleRoot) internal {
        vm.startPrank(participant);
        uint256 credId = 1;
        uint256 supply = 0;
        uint256 amount = 1;

        uint256 buyPrice = bondingCurve.getBuyPriceAfterFee(credId, supply, amount);
        string memory credURL = "test";

        // Get the current nonce for the participant
        uint256 nonce = cred.nonces(participant);

        ICred.CreateCredData memory createCredData = ICred.CreateCredData({
            expiresIn: block.timestamp + 1 hours,
            nonce: nonce,
            executor: participant,
            chainId: block.chainid,
            bondingCurve: address(bondingCurve),
            credURL: credURL,
            credType: credType,
            verificationType: verificationType,
            merkleRoot: merkleRoot
        });

        bytes memory signCreateData = abi.encode(createCredData);
        bytes32 createMsgHash = keccak256(signCreateData);
        bytes32 createDigest = ECDSA.toEthSignedMessageHash(createMsgHash);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(claimSignerPrivateKey, createDigest);
        bytes memory signature =
            cv == 27 ? abi.encodePacked(cr, cs) : abi.encodePacked(cr, cs | bytes32(uint256(1) << 255));

        cred.createCred{ value: buyPrice }(participant, signCreateData, signature, 100, 100, 1);

        vm.stopPrank();
    }

    function _createSigArt() internal {
        bytes memory credData = abi.encode(1, owner, "SIGNATURE", 31_337, bytes32(0));

        uint256 currentNonce = phiFactory.nonces(artCreator);

        IPhiFactory.CreateSignatureData memory createSigData = IPhiFactory.CreateSignatureData({
            expiresIn: expiresIn,
            signedChainId: block.chainid,
            nonce: currentNonce,
            executor: artCreator,
            uri: ART_ID_URL_STRING,
            credData: credData
        });

        bytes memory signCreateData = abi.encode(createSigData);
        bytes32 createMsgHash = keccak256(signCreateData);
        bytes32 createDigest = ECDSA.toEthSignedMessageHash(createMsgHash);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(claimSignerPrivateKey, createDigest);
        if (cv != 27) cs = cs | bytes32(uint256(1) << 255);
        bytes memory signature = abi.encodePacked(cr, cs);

        IPhiFactory.CreateConfig memory config = IPhiFactory.CreateConfig({
            artist: artCreator,
            receiver: receiver,
            endTime: END_TIME,
            startTime: START_TIME,
            maxSupply: MAX_SUPPLY,
            mintFee: MINT_FEE,
            soulBounded: false
        });

        uint256 beforeBalance = protocolFeeDestination.balance;
        vm.startPrank(artCreator);
        phiFactory.createArt{ value: NFT_ART_CREATE_FEE }(signCreateData, signature, config);
        vm.stopPrank();
        assertEq(protocolFeeDestination.balance - beforeBalance, NFT_ART_CREATE_FEE, "protocolFeeDestination fee");
    }

    function _createMerArt() public {
        for (uint256 i = 0; i < accounts.length; ++i) {
            leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(accounts[i], datas[i]))));
        }

        bytes32 expectedRoot = 0xe70e719557c28ce2f2f3545d64c633728d70fbcfe6ae3db5fa01420573e0f34b;
        bytes memory credData = abi.encode(1, owner, "MERKLE", 31_337, expectedRoot);

        uint256 currentNonce = phiFactory.nonces(artCreator);

        IPhiFactory.CreateSignatureData memory createSigData = IPhiFactory.CreateSignatureData({
            expiresIn: expiresIn,
            signedChainId: block.chainid,
            nonce: currentNonce,
            executor: artCreator,
            uri: ART_ID2_URL_STRING,
            credData: credData
        });

        bytes memory signCreateData = abi.encode(createSigData);
        bytes32 createMsgHash = keccak256(signCreateData);
        bytes32 createDigest = ECDSA.toEthSignedMessageHash(createMsgHash);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(claimSignerPrivateKey, createDigest);
        if (cv != 27) cs = cs | bytes32(uint256(1) << 255);
        bytes memory signature = abi.encodePacked(cr, cs);

        IPhiFactory.CreateConfig memory config = IPhiFactory.CreateConfig({
            artist: artCreator,
            receiver: receiver,
            endTime: END_TIME,
            startTime: START_TIME,
            maxSupply: MAX_SUPPLY,
            mintFee: MINT_FEE,
            soulBounded: false
        });

        vm.startPrank(artCreator);
        phiFactory.createArt{ value: NFT_ART_CREATE_FEE }(signCreateData, signature, config);
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(phiFactory.owner(), owner, "owner is correct");
        assertEq(phiFactory.protocolFeeDestination(), protocolFeeDestination, "protocolFeeDestination is correct");
    }

    function test_contractURI() public {
        // Create an art
        _createSigArt();

        // Get the art address
        address artAddress = phiFactory.getArtAddress(1);

        // Call the contractURI function
        string memory uri = phiFactory.contractURI(artAddress);
        console2.log("contractURI: %s", uri);
        // Check if the returned URI starts with the expected prefix
        assertTrue(bytes(uri).length > 0, "contractURI should return a non-empty string");
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/
    function test_claimMerkle() public {
        _createMerArt();

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x0927f012522ebd33191e00fe62c11db25288016345e12e6b63709bb618d777d4;
        proof[1] = 0xdd05ddd79adc5569806124d3c5d8151b75bc81032a0ea21d4cd74fd964947bf5;
        address to = 0x1111111111111111111111111111111111111111;
        bytes32 value = 0x0000000000000000000000000000000003c2f7086aed236c807a1b5000000000;

        uint256 artId = 1;
        IPhiFactory.MerkleClaimData memory merkleClaimData =
            IPhiFactory.MerkleClaimData(expiresIn, to, referrer, uint256(1), block.chainid, IMAGE_URL2);
        bytes memory signData = abi.encode(merkleClaimData);
        bytes32 msgHash = keccak256(signData);
        bytes32 digest = ECDSA.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
        if (v != 27) s = s | bytes32(uint256(1) << 255);
        bytes memory signature = abi.encodePacked(r, s);
        bytes memory data = abi.encode(
            artId,
            to,
            proof,
            referrer,
            expiresIn,
            uint256(3),
            bytes32(0x0000000000000000000000000000000003c2f7086aed236c807a1b5000000000),
            IMAGE_URL2,
            signature
        );

        vm.startPrank(participant, participant);

        assertEq(
            phiFactory.checkProof(
                proof,
                keccak256(
                    bytes.concat(keccak256(abi.encode(address(0x1111111111111111111111111111111111111111), value)))
                ),
                0xe70e719557c28ce2f2f3545d64c633728d70fbcfe6ae3db5fa01420573e0f34b //expectedRoot
            ),
            true,
            "merkle proof is correct"
        );
        bytes memory dataCompressed = LibZip.cdCompress(data);
        uint256 totalMintFee = phiFactory.getArtMintFee(artId, 3);

        phiFactory.claim{ value: totalMintFee }(dataCompressed);
    }

    function test_claim_1155_with_ref() public {
        _createSigArt();
        uint256 artId = 1;
        bytes32 advanced_data = bytes32("1");
        IPhiFactory.SigClaimData memory sigClaimData = IPhiFactory.SigClaimData(
            expiresIn, participant, referrer, verifier, artId, block.chainid, advanced_data, IMAGE_URL
        );
        bytes memory signData = abi.encode(sigClaimData);

        bytes32 msgHash = keccak256(signData);
        bytes32 digest = ECDSA.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
        if (v != 27) s = s | bytes32(uint256(1) << 255);
        bytes memory signature = abi.encodePacked(r, s);
        bytes memory data =
            abi.encode(1, participant, referrer, verifier, expiresIn, uint256(1), advanced_data, IMAGE_URL, signature);
        bytes memory dataCompressed = LibZip.cdCompress(data);
        uint256 totalMintFee = phiFactory.getArtMintFee(1, 1);

        vm.startPrank(participant, participant);
        phiFactory.claim{ value: totalMintFee }(dataCompressed);

        // referrer payout
        address artAddress = phiFactory.getArtAddress(1);
        assertEq(IERC1155(artAddress).balanceOf(participant, 1), 1, "particpiant erc1155 balance");

        assertEq(curatorRewardsDistributor.balanceOf(1), CURATE_REWARD, "epoch fee");
    }

    function test_batchClaim_1155_with_ref() public {
        _createCred("BASIC", "SIGNATURE", 0x0);
        expiresIn = START_TIME + 100;
        vm.startPrank(artCreator);
        _createSigArt();
        _createMerArt();

        uint256 artId = 1;
        IPhiFactory.SigClaimData memory sigClaimData = IPhiFactory.SigClaimData(
            expiresIn, participant, referrer, verifier, artId, block.chainid, bytes32("1"), IMAGE_URL
        );
        bytes memory signData = abi.encode(sigClaimData);
        bytes32 digest = ECDSA.toEthSignedMessageHash(keccak256(signData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
        if (v != 27) s = s | bytes32(uint256(1) << 255);
        bytes memory signature = abi.encodePacked(r, s);
        bytes memory data = abi.encode(
            artId, participant, referrer, verifier, expiresIn, uint256(1), bytes32("1"), IMAGE_URL, signature
        );
        datasCompressed[0] = LibZip.cdCompress(data);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x0927f012522ebd33191e00fe62c11db25288016345e12e6b63709bb618d777d4;
        proof[1] = 0xdd05ddd79adc5569806124d3c5d8151b75bc81032a0ea21d4cd74fd964947bf5;
        address to = 0x1111111111111111111111111111111111111111;
        bytes32 value = 0x0000000000000000000000000000000003c2f7086aed236c807a1b5000000000;

        IPhiFactory.MerkleClaimData memory merkleClaimData =
            IPhiFactory.MerkleClaimData(expiresIn, to, referrer, uint256(2), block.chainid, IMAGE_URL2);
        bytes memory signData2 = abi.encode(merkleClaimData);
        digest = ECDSA.toEthSignedMessageHash(keccak256(signData2));
        (v, r, s) = vm.sign(claimSignerPrivateKey, digest);
        if (v != 27) s = s | bytes32(uint256(1) << 255);
        bytes memory signature2 = abi.encodePacked(r, s);
        bytes memory data2 = abi.encode(2, to, proof, referrer, expiresIn, uint256(2), value, IMAGE_URL2, signature2);

        datasCompressed[1] = LibZip.cdCompress(data2);

        uint256[] memory artIds = new uint256[](2);
        artIds[0] = 1;
        artIds[1] = 2;
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 1;
        quantities[1] = 2;
        uint256 totalMintFee = phiFactory.getTotalMintFee(artIds, quantities);

        uint256[] memory mintFee = new uint256[](2);
        mintFee[0] = phiFactory.getArtMintFee(1, 1);
        mintFee[1] = phiFactory.getArtMintFee(2, 2);

        vm.warp(START_TIME + 2);
        vm.startPrank(participant, participant);
        phiFactory.batchClaim{ value: totalMintFee }(datasCompressed, mintFee);

        // referrer payout
        address artAddress = phiFactory.getArtAddress(artIds[0]);
        assertEq(IERC1155(artAddress).balanceOf(participant, 1), 1, "particpiant erc1155 balance");

        address artAddress2 = phiFactory.getArtAddress(artIds[1]);
        assertEq(IERC1155(artAddress2).balanceOf(participant, 2), 0, "particpiant erc1155 artid2 balance");
        assertEq(IERC1155(artAddress2).balanceOf(to, 2), 2, "to erc1155 artid2 balance");

        assertEq(curatorRewardsDistributor.balanceOf(1), CURATE_REWARD * 3, "epoch fee");

        vm.startPrank(verifier);
        phiRewards.withdraw(verifier, 0);
        assertEq(verifier.balance, 1 ether + VERIFY_REWARD * 1, "verify fee");
        vm.stopPrank();
        vm.startPrank(referrer);
        phiRewards.withdraw(referrer, 0);
        assertEq(referrer.balance, 1 ether + REFERRAL_REWARD * 3, "referrer fee");
        vm.stopPrank();
        vm.startPrank(artCreator);
        phiRewards.withdraw(artCreator, 0);
        assertEq(artCreator.balance, 1 ether - NFT_ART_CREATE_FEE * 2, "artist fee");
        vm.stopPrank();
        vm.startPrank(receiver);
        phiRewards.withdraw(receiver, 0);
        assertEq(receiver.balance, MINT_FEE * 3 + ARTIST_REWARD * 3, "receiver fee");
    }

    function test_createTokenId2() public {
        vm.startPrank(participant);
        string memory artId1 = "rL5L2H5BLDwyojZtOi-7TSCqFM7ISlsDOIlAfTUs5et";
        string memory artId2 = "7TSCqFM7ISlsDOIlAf-7TSCqFM7ISlsDOIlAfTUs5ts";
        _createSigArt();
        _createSigArt();

        address artAddress = phiFactory.getArtAddress(1);
        address artAddress2 = phiFactory.getArtAddress(2);

        assertEq(artAddress, artAddress2, "artAddress is correct");
    }

    function test_updateArt() public {
        // Create an art for testing
        _createSigArt();

        // Prepare new settings
        uint256 newStartTime = 1_000_100;
        uint256 newEndTime = 2_000_100;
        address newReceiver = address(0x456);
        address newRoyaltyRecipient = address(0x789);
        uint32 newRoyaltyBPS = 500;

        // Get the current nonce for the artCreator
        uint256 currentNonce = phiFactory.nonces(artCreator);

        // Prepare UpdateSignatureData
        IPhiFactory.UpdateSignatureData memory updateSigData = IPhiFactory.UpdateSignatureData({
            expiresIn: block.timestamp + 1 hours,
            signedChainId: block.chainid,
            nonce: currentNonce,
            artId: 1,
            url: "new-url"
        });

        // Prepare UpdateConfig
        IPhiFactory.UpdateConfig memory updateConfig = IPhiFactory.UpdateConfig({
            receiver: newReceiver,
            endTime: newEndTime,
            startTime: newStartTime,
            maxSupply: 10_000,
            mintFee: 1 ether,
            royaltyBPS: newRoyaltyBPS,
            royaltyRecipient: newRoyaltyRecipient
        });

        // Encode the UpdateSignatureData
        bytes memory signedData = abi.encode(updateSigData);

        // Sign the data
        bytes32 messageHash = keccak256(signedData);
        bytes32 digest = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Call the function
        vm.prank(artCreator);
        phiFactory.updateArt(signedData, signature, updateConfig);

        // Get the updated art settings
        IPhiFactory.ArtData memory updatedArt = phiFactory.artData(1);

        // Assert the changes
        assertEq(updatedArt.uri, "new-url", "uri should be updated");
        assertEq(updatedArt.receiver, newReceiver, "receiver should be updated");
        assertEq(updatedArt.maxSupply, 10_000, "maxSupply should be updated");
        assertEq(updatedArt.mintFee, 1 ether, "mintFee should be updated");
        assertEq(updatedArt.startTime, 1_000_100, "startTime should be updated");
        assertEq(updatedArt.endTime, 2_000_100, "endTime should be updated");

        // Assert the royalty configuration
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory checkRoyaltyConfig =
            ICreatorRoyaltiesControl(updatedArt.artAddress).getRoyalties(updatedArt.tokenId);
        assertEq(newRoyaltyRecipient, checkRoyaltyConfig.royaltyRecipient, "royalty recipient should be updated");
        assertEq(newRoyaltyBPS, checkRoyaltyConfig.royaltyBPS, "royalty BPS should be updated");

        // Assert that the nonce has been incremented
        assertEq(phiFactory.nonces(artCreator), currentNonce + 1, "nonce should be incremented");
    }
}
