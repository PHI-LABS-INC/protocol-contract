// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Cred } from "../src/Cred.sol";
import { CredV2 } from "../test/helpers/CredV2.sol";
import { DevOpsTools } from "foundry-devops/DevOpsTools.sol";
import { BaseScript } from "./Base.s.sol";

contract UpgradeCred is BaseScript {
    function run() external returns (address) {
        // address mostRecentlyDeployedProxy = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);

        vm.startBroadcast();
        Cred newCred = new Cred();
        address currentCredProxy = address(0xAb40d935CA0fA8a0943Bfdc1137F8712e57fD8f4);
        address proxy = upgradeCred(currentCredProxy, address(newCred));
        vm.stopBroadcast();
        return proxy;
    }

    function upgradeCred(address proxyAddress, address newCred) public returns (address) {
        Cred credProxy = Cred(payable(proxyAddress));
        // credProxy.upgradeToAndCall(address(newCred), abi.encodeWithSelector(Cred.initializeV2.selector));
        return address(credProxy);
    }
}
