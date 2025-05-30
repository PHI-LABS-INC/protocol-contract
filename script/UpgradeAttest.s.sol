// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { PhiAttester } from "../src/PhiAttester.sol";
import { PhiAttesterV2 } from "../src/PhiAttesterv2.sol";
import { DevOpsTools } from "foundry-devops/DevOpsTools.sol";
import { BaseScript } from "./Base.s.sol";

contract UpgradeAttest is BaseScript {
    function run() external returns (address) {
        vm.startBroadcast();
        PhiAttesterV2 newAttest = new PhiAttesterV2();
        address currentAttestProxy = address(0x028052F458142d1689F4f851e78947C7075f2D20);
        address proxy = upgradePhiAttest(currentAttestProxy, address(newAttest));
        vm.stopBroadcast();
        return proxy;
    }

    function upgradePhiAttest(address proxyAddress, address newAttest) public returns (address) {
        PhiAttesterV2 attestProxy = PhiAttesterV2(payable(proxyAddress));
        bytes memory data = "";
        attestProxy.upgradeToAndCall(newAttest, data);
        return address(attestProxy);
    }
}
