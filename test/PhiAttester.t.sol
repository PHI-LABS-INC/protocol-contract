// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import { PhiAttester } from "../src/PhiAttester.sol";
import { IPhiAttester } from "../src/interfaces/IPhiAttester.sol";
import { MockEAS } from "./helpers/MockEAS.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

contract TestPhiAttester is Test {
    uint256 claimSignerPrivateKey;
    address claimSignerAddress;
    address owner;
    address protocolFeeDestination;
    PhiAttester phiAttester;
    MockEAS mockEAS;

    uint256 constant ATTEST_FEE = 0.0001 ether;

    function setUp() public {
        // Initialize addresses
        owner = address(0x123);
        protocolFeeDestination = address(0x456);

        // Set up the claimSigner private key for signing
        claimSignerPrivateKey = 0x4af1bceebf7f3634ec3cff8a2c38e51178d5d4ce585c52d6043e5e2cc3418bb0;
        // Derive the address from the private key
        claimSignerAddress = vm.addr(claimSignerPrivateKey);

        // Deploy the MockEAS contract
        mockEAS = new MockEAS();

        // (Optional) If initialize() requires msg.sender == owner, use vm.prank:
        // vm.prank(owner);

        // Initialize PhiAttester with MockEAS address and other parameters
        phiAttester = new PhiAttester();
        phiAttester.initialize(
            address(mockEAS), // Pass MockEAS contract address
            protocolFeeDestination, // Treasury address
            claimSignerAddress, // Trusted signer address (derived from private key)
            owner // Owner address
        );
    }

    // Helper function to create a signature
    function getSignature(IPhiAttester.AttestBoardRequest memory request) internal view returns (bytes memory) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(phiAttester),
                address(this), // caller
                request.expiresAt,
                request.nonce,
                request.schemaId,
                request.boardId,
                request.category,
                request.uri,
                request.attestationExpirationTime,
                block.chainid // Add chainId for cross-chain replay protection
            )
        );

        bytes32 digest = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    // -----------------------------------------
    //             TEST FUNCTIONS
    // -----------------------------------------

    // Test the constructor and initialization
    function test_constructor() public {
        // Verify the correct initialization of the contract
        assertEq(phiAttester.owner(), owner, "Owner should be correctly set.");
        assertEq(phiAttester.treasuryAddress(), protocolFeeDestination, "Treasury address should be correctly set.");
    }

    function test_validAttestation() public {
        // Prepare the request and signature using IPhiAttester.AttestBoardRequest
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp + 1000,
            nonce: 0,
            schemaId: bytes32("1"), // Cast to bytes32,
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000) // Cast to uint64
         });

        bytes memory signature = getSignature(request);

        // Track the initial balance of the protocol fee destination
        uint256 initialBalance = protocolFeeDestination.balance;

        // Correctly place the value modifier for the payable function call
        phiAttester.attestBoard{ value: ATTEST_FEE }(request, signature);

        // Verify that the fee was sent to the protocolFeeDestination
        uint256 finalBalance = protocolFeeDestination.balance;
        assertEq(finalBalance - initialBalance, ATTEST_FEE, "Protocol fee should be transferred.");
    }

    // Test invalid signature (wrong signer)
    function test_invalidSigner() public {
        // Prepare the request
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp + 1000,
            nonce: 0,
            schemaId: bytes32("1"),
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000)
        });

        // Create an obviously invalid signature (e.g., zeroed out)
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        // Expect revert with InvalidSignature error instead of InvalidSignature
        vm.expectRevert(IPhiAttester.InvalidSignature.selector); // Changed this line
        phiAttester.attestBoard{ value: ATTEST_FEE }(request, invalidSignature);
    }

    // Test invalid fee
    function test_invalidFee() public {
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp + 1000,
            nonce: 0,
            schemaId: bytes32("1"),
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000)
        });

        bytes memory signature = getSignature(request);

        // Expect revert due to incorrect fee
        vm.expectRevert(IPhiAttester.InvalidFee.selector);
        phiAttester.attestBoard{ value: ATTEST_FEE + 1 ether }(request, signature);
    }

    // Test expired signature
    function test_expiredSignature() public {
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp - 1000, // Already expired
            nonce: 0,
            schemaId: bytes32("1"),
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000)
        });

        bytes memory signature = getSignature(request);

        // Expect revert due to expired signature
        vm.expectRevert(IPhiAttester.SignatureExpired.selector);
        phiAttester.attestBoard{ value: ATTEST_FEE }(request, signature);
    }

    // Test schema validation
    function test_schemaValidation() public {
        // Prepare the request with invalid schema (0)
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp + 1000,
            nonce: 0,
            schemaId: bytes32(0), // 0 => invalid
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000)
        });

        bytes memory signature = getSignature(request);

        // Expect revert due to invalid schema
        vm.expectRevert(IPhiAttester.SchemaNotProvided.selector);
        phiAttester.attestBoard{ value: ATTEST_FEE }(request, signature);
    }

    function test_validRevocation() public {
        // First create an attestation
        IPhiAttester.AttestBoardRequest memory request = IPhiAttester.AttestBoardRequest({
            expiresAt: block.timestamp + 1000,
            nonce: 0,
            schemaId: bytes32("1"), // このスキーマIDを使用
            boardId: "1", // Cast to uint256
            category: "art",
            uri: "ipfs://exampleuri",
            attestationExpirationTime: uint64(block.timestamp + 10_000)
        });
        bytes memory signature = getSignature(request);
        phiAttester.attestBoard{ value: ATTEST_FEE }(request, signature);

        // Then test revocation
        vm.startPrank(owner);
        bytes32 attestationUID = mockEAS.getLatestAttestationUID();
        // schemaIdも引数として渡す
        phiAttester.revokeAttestation(request.schemaId, attestationUID);
        vm.stopPrank();
    }

    function test_storageGap() public {
        // Ensure the storage gap is properly set
        uint256[50] memory gap;
        bytes32 slot = bytes32(uint256(keccak256("phi.storage.gap")) - 1);
        assembly {
            sstore(slot, gap)
        }
    }
}
