// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { PhiAttester } from "../src/PhiAttester.sol";
import { BaseScript } from "./Base.s.sol";

// https://github.com/Cyfrin/foundry-upgrades-f23/blob/main/script/DeployBox.s.sol
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    using LibClone for address;

    PhiAttester public phiAttester;

    address public deployer;
    address public oji3 = 0x5cD18dA4C84758319C8E1c228b48725f5e4a3506;
    address public signer = 0xe35E5f8B912C25cDb6B00B347cb856467e4112A3;
    address public eas = 0x4200000000000000000000000000000000000021;
    address public treasury;

    function setUp() public virtual {
        string memory mnemonic = vm.envString("MNEMONIC");
        (deployer,) = deriveRememberKey(mnemonic, 0);
    }

    function run() public broadcast {
        console2.log("Chain Info: %s", block.chainid);
        if (block.chainid == 8453) {
            treasury = 0xcDc56A5187AeB05bf713055D46FbA616471b1812;
        } else {
            treasury = deployer;
        }
        console2.log("Treasury address: %s", treasury);

        phiAttester = new PhiAttester();
        ERC1967Proxy phiAttesterProxy = new ERC1967Proxy(address(phiAttester), "");
        PhiAttester(payable(address(phiAttesterProxy))).initialize(eas, treasury, signer, oji3);
        console2.log("PhiAttester deployed at address: %s", address(phiAttester));
    }
}
