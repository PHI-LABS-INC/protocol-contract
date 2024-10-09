// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { PhiFactory } from "../src/PhiFactory.sol";
// import { DevOpsTools } from "foundry-devops/DevOpsTools.sol";
import { BaseScript } from "./Base.s.sol";
import { console2 } from "forge-std/console2.sol";

contract UpgradeFactory is BaseScript {
    address public deployer;

    function setUp() public virtual {
        string memory mnemonic = vm.envString("MNEMONIC");
        (deployer,) = deriveRememberKey(mnemonic, 0);
    }

    function run() external returns (address) {
        // address mostRecentlyDeployedProxy = DevOpsTools.get_most_recent_deployment("PhiFactory", block.chainid);
        vm.startBroadcast();
        PhiFactory newFactory = new PhiFactory();
        address currentPhiFactoryProxy = address(0xbD5Eb068D5D0f932Bee250Fa0b895b44091a4E52);
        address proxy = upgradeFactory(currentPhiFactoryProxy, address(newFactory));
        console2.log("Upgraded PhiFactory to address: %s", proxy);
        vm.stopBroadcast();
        return proxy;
    }

    function upgradeFactory(address oldfactoryProxyAddress, address newFactory) public returns (address) {
        PhiFactory factoryProxy = PhiFactory(payable(oldfactoryProxyAddress));
        factoryProxy.upgradeToAndCall(address(newFactory), abi.encodeWithSelector(PhiFactory.initialize.selector));
        return address(factoryProxy);
    }
}
