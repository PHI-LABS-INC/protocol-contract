// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ICred } from "../src/interfaces/ICred.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IPhiFactory } from "../src/interfaces/IPhiFactory.sol";

import { PhiFactory } from "../src/PhiFactory.sol";
import { PhiRewards } from "../src/reward/PhiRewards.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { JSONParserLib } from "solady/utils/JSONParserLib.sol";

import { Settings } from "./helpers/Settings.sol";

contract TestClaimable is Settings {
    string ART_ID_URL_STRING;
    string ART_ID2_URL_STRING;

    using LibString for *;
    using JSONParserLib for string;

    uint256 expiresIn;
    bytes32[] leaves;
    address[] accounts;
    bytes32[] datas;

    function setUp() public override {
        super.setUp();

        ART_ID_URL_STRING = "333L2H5BLDwyojZtOi-7TSCqFM7ISlsDOIlAfTUs5es";
        ART_ID2_URL_STRING = "432CqFM7ISlsDOIlA-7TSCqFM7ISlsDOIlAfTUs5es";
        expiresIn = START_TIME + 1 days;
        assertEq(protocolFeeDestination.balance, 0, "protocolFeeDestination before balance");

        vm.warp(START_TIME + 1);

        _createCred("BASIC", "SIGNATURE", 0x0);
        vm.startPrank(artCreator);
        _createSigArt();
        _createMerArt();
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
            executor: participant,
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
            artist: participant,
            receiver: receiver,
            endTime: END_TIME,
            startTime: START_TIME,
            maxSupply: MAX_SUPPLY,
            mintFee: MINT_FEE,
            soulBounded: false
        });

        uint256 beforeBalance = protocolFeeDestination.balance;
        vm.startPrank(participant);
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

        uint256 currentNonce = phiFactory.nonces(participant);

        IPhiFactory.CreateSignatureData memory createSigData = IPhiFactory.CreateSignatureData({
            expiresIn: expiresIn,
            signedChainId: block.chainid,
            nonce: currentNonce,
            executor: participant,
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
            artist: participant,
            receiver: receiver,
            endTime: END_TIME,
            startTime: START_TIME,
            maxSupply: MAX_SUPPLY,
            mintFee: MINT_FEE,
            soulBounded: false
        });

        vm.startPrank(participant);
        phiFactory.createArt{ value: NFT_ART_CREATE_FEE }(signCreateData, signature, config);
        vm.stopPrank();
    }

    function _createSigSignData(bool ref) internal view returns (bytes memory) {
        uint256 artId = 1;
        uint256 tokenId = 1;
        uint256 quantity = 1;
        bytes32 claimData = bytes32("1");
        if (ref) {
            IPhiFactory.SigClaimData memory sigClaimData = IPhiFactory.SigClaimData(
                expiresIn, participant, referrer, verifier, artId, block.chainid, claimData, "ART_ID_URL_STRING"
            );
            bytes memory signData = abi.encode(sigClaimData);
            bytes32 msgHash = keccak256(signData);
            bytes32 digest = ECDSA.toEthSignedMessageHash(msgHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
            if (v != 27) s = s | bytes32(uint256(1) << 255);
            bytes memory data = abi.encode(
                r, s, referrer, verifier, participant, tokenId, quantity, expiresIn, "ART_ID_URL_STRING", bytes32("1")
            );
            return data;
        } else {
            IPhiFactory.SigClaimData memory sigClaimData = IPhiFactory.SigClaimData(
                expiresIn, participant, participant, verifier, artId, block.chainid, claimData, "ART_ID_URL_STRING"
            );
            bytes memory signData = abi.encode(sigClaimData);
            bytes32 msgHash = keccak256(signData);
            bytes32 digest = ECDSA.toEthSignedMessageHash(msgHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
            if (v != 27) s = s | bytes32(uint256(1) << 255);
            bytes memory data = abi.encode(
                r,
                s,
                participant,
                verifier,
                participant,
                tokenId,
                quantity,
                expiresIn,
                "ART_ID_URL_STRING",
                bytes32("1")
            );
            return data;
        }
    }

    function _createMerSignData() internal view returns (bytes memory) {
        uint256 artId = 2;
        // uint256 tokenId = 2;
        // uint256 quantity = 1;
        address to = 0x1111111111111111111111111111111111111111;
        bytes32 leafPart = 0x0000000000000000000000000000000003c2f7086aed236c807a1b5000000000;
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x0927f012522ebd33191e00fe62c11db25288016345e12e6b63709bb618d777d4;
        proof[1] = 0xdd05ddd79adc5569806124d3c5d8151b75bc81032a0ea21d4cd74fd964947bf5;
        IPhiFactory.MerkleClaimData memory merkleClaimData =
            IPhiFactory.MerkleClaimData(expiresIn, to, referrer, artId, block.chainid, "ART_ID2_URL_STRING");
        bytes memory signData = abi.encode(merkleClaimData);

        bytes32 msgHash = keccak256(signData);
        bytes32 digest = ECDSA.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);
        if (v != 27) s = s | bytes32(uint256(1) << 255);
        bytes memory data = abi.encode(
            r,
            s,
            to,
            proof,
            referrer,
            2,
            1,
            bytes32(0x0000000000000000000000000000000003c2f7086aed236c807a1b5000000000),
            expiresIn,
            "ART_ID2_URL_STRING"
        );
        return data;
    }

    /*//////////////////////////////////////////////////////////////
                             CLAIM ERC1155
    //////////////////////////////////////////////////////////////*/
    function test_claim_1155_with_ref() public {
        vm.warp(START_TIME + 1);
        uint256 artId = 1;
        address artAddress = phiFactory.getArtAddress(artId);
        vm.warp(START_TIME + 2);
        bytes memory data = _createSigSignData(true);
        bytes memory payload = abi.encodePacked(abi.encodeWithSignature("signatureClaim()"), data);

        vm.recordLogs();

        vm.startPrank(participant, participant);
        (bool success,) = artAddress.call{ value: phiFactory.getArtMintFee(artId, 1) }(payload);
        require(success, "1155 artAddress.call failed");

        // 1155 reward
        assertEq(IERC1155(artAddress).balanceOf(participant, 1), 1, "particpiant erc1155 balance");

        assertEq(curatorRewardsDistributor.balanceOf(1), CURATE_REWARD, "epoch fee");
        assertEq(verifier.balance, 1 ether, "verify fee");

        vm.startPrank(verifier);
        phiRewards.withdraw(verifier, VERIFY_REWARD);
        assertEq(verifier.balance, 1 ether + VERIFY_REWARD, "verify fee");
    }

    function test_claim_1155_with_ref_merkle() public {
        vm.warp(START_TIME + 1);
        uint256 artId = 2;
        address artAddress = phiFactory.getArtAddress(artId);
        vm.warp(START_TIME + 2);
        bytes memory data = _createMerSignData();
        bytes memory payload = abi.encodePacked(abi.encodeWithSignature("merkleClaim()"), data);

        vm.recordLogs();

        vm.startPrank(participant, participant);
        (bool success,) = artAddress.call{ value: phiFactory.getArtMintFee(artId, 1) }(payload);
        require(success, "1155 artAddress.call failed");

        // 1155 reward
        address to = 0x1111111111111111111111111111111111111111;
        assertEq(IERC1155(artAddress).balanceOf(to, 2), 1, "particpiant erc1155 balance");

        assertEq(curatorRewardsDistributor.balanceOf(1), CURATE_REWARD, "epoch fee");
        assertEq(verifier.balance, 1 ether, "verify fee");
    }

    function test_claimFor_1155_without_ref() public {
        uint256 artId = 1;
        address artAddress = phiFactory.getArtAddress(artId);

        vm.warp(START_TIME + 2);
        bytes memory data = _createSigSignData(false);
        bytes memory payload = abi.encodePacked(abi.encodeWithSignature("signatureClaim()"), data);

        vm.recordLogs();
        uint256 totalMintFee = phiFactory.getArtMintFee(artId, 1);
        vm.startPrank(anyone, anyone);
        (bool success,) = artAddress.call{ value: totalMintFee }(payload);
        require(success, "1155 artAddress.call failed");

        // 1155 reward
        assertEq(IERC1155(artAddress).balanceOf(participant, 1), 1, "particpiant erc1155 balance");

        assertEq(curatorRewardsDistributor.balanceOf(1), CURATE_REWARD, "epoch fee");
        assertEq(verifier.balance, 1 ether, "verify fee");

        vm.startPrank(verifier);
        phiRewards.withdraw(verifier, VERIFY_REWARD);
        assertEq(verifier.balance, 1 ether + VERIFY_REWARD, "verify fee");
    }
}
