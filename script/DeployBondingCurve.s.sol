// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";

import { BondingCurve } from "../src/curve/BondingCurve.sol";

import { BaseScript } from "./Base.s.sol";

// https://github.com/Cyfrin/foundry-upgrades-f23/blob/main/script/DeployBox.s.sol
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address public deployer;

    BondingCurve public bondingCurve;

    address public oji3 = 0x5cD18dA4C84758319C8E1c228b48725f5e4a3506;

    function setUp() public virtual {
        string memory mnemonic = vm.envString("MNEMONIC");
        (deployer,) = deriveRememberKey(mnemonic, 0);
    }

    function run() public broadcast {
        // address owner_
        bondingCurve = new BondingCurve(oji3);
        console2.log("BondingCurve deployed at address: %s", address(bondingCurve));
    }
}
