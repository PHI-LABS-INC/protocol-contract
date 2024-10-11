// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console2 } from "forge-std/console2.sol";

import { Settings } from "./helpers/Settings.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { ICred } from "../src/interfaces/ICred.sol";
import { ICuratorRewardsDistributor } from "../src/interfaces/ICuratorRewardsDistributor.sol";
import { IPhiRewards } from "../src/interfaces/IPhiRewards.sol";

contract CuratorRewardsDistributorTest is Settings {
    string constant credUUID = "18cd3748-9a76-4a05-8c69-ba0b8c1a9d17";

    function setUp() public override {
        super.setUp();
        vm.warp(START_TIME + 10_000);

        _createCred("BASIC", "SIGNATURE", 0x0);
    }

    function _createCred(string memory credType, string memory verificationType, bytes32 merkleRoot) internal {
        vm.startPrank(owner);
        uint256 credId = 1;
        uint256 supply = 0;
        uint256 amount = 1;

        uint256 buyPrice = bondingCurve.getBuyPriceAfterFee(credId, supply, amount);
        string memory credURL = "test";

        // Get the current nonce for the participant
        uint256 nonce = cred.nonces(owner);

        ICred.CreateCredData memory createCredData = ICred.CreateCredData({
            expiresIn: block.timestamp + 1 hours,
            nonce: nonce,
            executor: owner,
            credCreator: owner,
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

        cred.createCred{ value: buyPrice }(signCreateData, signature, 100, 100, 1);

        vm.stopPrank();
    }

    function testDistribute() public {
        uint256 credId = 1;
        uint256 depositAmount = 1 ether;

        // Deposit some ETH to the curatorRewardsDistributor
        curatorRewardsDistributor.deposit{ value: depositAmount }(credId, depositAmount);

        // Signal creds for different users
        vm.startPrank(user1);
        vm.deal(user1, bondingCurve.getBuyPriceAfterFee(credId, 1, 1));
        cred.buyShareCred{ value: bondingCurve.getBuyPriceAfterFee(credId, 1, 1) }(credId, 1, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.deal(user2, bondingCurve.getBuyPriceAfterFee(credId, 2, 2));
        cred.buyShareCred{ value: bondingCurve.getBuyPriceAfterFee(credId, 2, 2) }(credId, 2, 0);
        vm.stopPrank();

        assertEq(cred.getShareNumber(credId, user1), 1, "Signal count should be 1");
        assertEq(cred.getShareNumber(credId, user2), 2, "Signal count should be 2");
        assertEq(cred.getCurrentSupply(credId), 4, "Signal count should be 3");
        assertEq(cred.getCuratorAddressLength(credId), 3, "Signal count should be 3");

        // Record initial balances
        uint256 initialUser1Balance = phiRewards.balanceOf(user1);
        uint256 initialUser2Balance = phiRewards.balanceOf(user2);
        uint256 ownerBalance = owner.balance;

        // Distribute rewards
        vm.prank(owner);
        curatorRewardsDistributor.distribute(credId);

        // Check final balances
        uint256 finalUser1Balance = phiRewards.balanceOf(user1);
        uint256 finalUser2Balance = phiRewards.balanceOf(user2);
        uint256 finalOwnerBalance = owner.balance;

        // Assert the distribution
        assertEq(
            finalUser1Balance - initialUser1Balance,
            (depositAmount - depositAmount / 100) / 4,
            "User1 should receive 1/4 of the rewards"
        );
        assertEq(
            finalUser2Balance - initialUser2Balance,
            ((depositAmount - depositAmount / 100) * 2) / 4,
            "User2 should receive 2/4 of the rewards"
        );
        assertEq(
            finalOwnerBalance - ownerBalance, (depositAmount / 100), "Distributer should receive 1/100 of the rewards"
        );

        // Check that the balance in curatorRewardsDistributor is now 0
        assertEq(
            curatorRewardsDistributor.balanceOf(credId),
            0,
            "CuratorRewardsDistributor balance should be 0 after distribution"
        );
    }

    function testDistributeNoBalance() public {
        uint256 credId = 1;

        vm.expectRevert(ICuratorRewardsDistributor.NoBalanceToDistribute.selector);
        curatorRewardsDistributor.distribute(credId);
    }

    function testUpdateRoyaltyToMax() public {
        uint256 credId = 1;
        uint256 depositAmount = 1 ether;
        uint256 newRoyalty = 1000; // 10% in basis points
        uint256 expectedExecuteRoyalty = depositAmount / 10;

        // Deposit some ETH to the curatorRewardsDistributor
        curatorRewardsDistributor.deposit{ value: depositAmount }(credId, depositAmount);

        // Signal creds for different users
        vm.startPrank(user1);
        vm.deal(user1, bondingCurve.getBuyPriceAfterFee(credId, 1, 1));
        cred.buyShareCred{ value: bondingCurve.getBuyPriceAfterFee(credId, 1, 1) }(credId, 1, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.deal(user2, bondingCurve.getBuyPriceAfterFee(credId, 2, 2));
        cred.buyShareCred{ value: bondingCurve.getBuyPriceAfterFee(credId, 2, 2) }(credId, 2, 0);
        vm.stopPrank();

        // Update royalty to max (1000  = 10%)
        vm.prank(owner);
        curatorRewardsDistributor.updateExecuteRoyalty(newRoyalty);

        // Record initial balances
        uint256 initialBalance = anyone.balance;

        // Distribute rewards
        vm.prank(anyone);
        curatorRewardsDistributor.distribute(credId);
        // Check final balances
        uint256 finalBalance = anyone.balance;

        // Assert the distribution
        assertEq(
            finalBalance - initialBalance, expectedExecuteRoyalty, "Executor should receive expectedExecuteRoyalty"
        );

        // Check that the balance in curatorRewardsDistributor is now 0
        assertEq(
            curatorRewardsDistributor.balanceOf(credId),
            0,
            "CuratorRewardsDistributor balance should be 0 after distribution"
        );
    }

    /// forge test --match-test testBloatingBalances -vv --gas-limit 2000000000 --block-gas-limit 2000000000 --isolate
    function testBloatingBalances() public {
        uint256 credId = 1;
        uint256 depositAmount = 1 ether;
        console2.log("bloating test");
        // A similar piece of code may be executed by a griefer to block rewards distribution.
        // However, instead of `vm.startPrank` he'll have to resort to lightweight proxy contracts or EIP-7702.
        // `SHARE_LOCK_PERIOD` won't be a problem since several accounts can trade shares in parallel.
        // If the cred is not far into the bonding curve, the griefing can be done cheaply.
        for (uint256 i = 0; i < 100; i++) {
            address trader = address(uint160(i + 100));
            vm.deal(trader, 0.1 ether);
            vm.startPrank(trader);
            cred.buyShareCred{ value: 0.1 ether }(credId, 1, 0);
            vm.warp(block.timestamp + 1000 minutes + 1 seconds);
            cred.sellShareCred(credId, 1, 0);
            vm.stopPrank();
        }
        for (uint256 i = 0; i < 99; i++) {
            address trader = address(uint160(i + 100));
            vm.deal(trader, 0.1 ether);
            vm.startPrank(trader);
            cred.buyShareCred{ value: 0.1 ether }(credId, 1, 0);
            vm.warp(block.timestamp + 1000 minutes + 1 seconds);
            vm.stopPrank();
        }
        curatorRewardsDistributor.deposit{ value: depositAmount }(credId, depositAmount);

        uint256 gas = gasleft();
        vm.prank(user2);
        curatorRewardsDistributor.distribute(credId);
        uint256 gasSpend = gas - gasleft();

        console2.log("distribute() gas: ", gasSpend);
    }

    function testBigDistribute() public {
        uint256 credId = 1;
        uint256 depositAmount = 1 ether;
        // uint256 backers = 825;
        uint256 backers = 99;

        uint256 totalCap = bondingCurve.getBuyPriceAfterFee(credId, 1, backers);
        console2.log("Total shares price: ", totalCap / 1 ether, "Ether");
        uint256 maxSharePrice = bondingCurve.getBuyPriceAfterFee(credId, backers, 1);
        console2.log("Max share price: ", maxSharePrice * 1000 / 1 ether, "milli Ether");

        // Deposit some ETH to the curatorRewardsDistributor
        curatorRewardsDistributor.deposit{ value: depositAmount }(credId, depositAmount);

        vm.deal(user1, totalCap);

        for (uint256 i = 0; i < backers; i++) {
            vm.startPrank(address(uint160(i + 1000)));
            vm.deal(address(uint160(i + 1000)), maxSharePrice);
            cred.buyShareCred{ value: maxSharePrice }(credId, 1, 0);
            vm.stopPrank();
        }

        uint256 gas = gasleft();
        vm.prank(user2);
        curatorRewardsDistributor.distribute(credId);
        uint256 gasSpend = gas - gasleft();

        console2.log("distribute() gas: ", gasSpend);
    }
}
