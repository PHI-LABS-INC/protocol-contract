// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { Cred } from "../src/Cred.sol";
import { PhiNFT1155 } from "../src/art/PhiNFT1155.sol";
import { BondingCurve } from "../src/curve/BondingCurve.sol";
import { PhiRewards } from "../src/reward/PhiRewards.sol";
import { CuratorRewardsDistributor } from "../src/reward/CuratorRewardsDistributor.sol";
import { PhiFactoryZkSync } from "../src/PhiFactoryZkSync.sol";
import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    using LibClone for address;

    address public deployer;
    Cred public cred;
    PhiFactoryZkSync public phiFactory;
    PhiNFT1155 public phiNFT1155;
    BondingCurve public bondingCurve;
    PhiRewards public phiRewards;
    CuratorRewardsDistributor public curatorRewardsDistributor;

    address public oji3 = 0x5cD18dA4C84758319C8E1c228b48725f5e4a3506;
    address public signer = 0xe35E5f8B912C25cDb6B00B347cb856467e4112A3;
    address public treasury;

    function setUp() public virtual {
        string memory mnemonic = vm.envString("MNEMONIC");
        (deployer,) = deriveRememberKey(mnemonic, 0);
    }

    function run() public {
        console2.log("Chain Info: %s", block.chainid);
        if (block.chainid == 8453) {
            treasury = 0xcDc56A5187AeB05bf713055D46FbA616471b1812;
        } else {
            treasury = deployer;
        }
        console2.log("Treasury address: %s", treasury);

        // Deploy base contracts first
        deployBaseContracts();

        // Then deploy and initialize proxies
        deployAndInitializeProxies();

        // Finally configure contract connections
        configureContracts();
    }

    function deployBaseContracts() internal {
        vm.startBroadcast(deployer);

        // Deploy PhiNFT1155
        phiNFT1155 = new PhiNFT1155();
        require(address(phiNFT1155) != address(0), "PhiNFT1155 deployment failed");
        console2.log("PhiNFT1155 deployed at address: %s", address(phiNFT1155));

        // Deploy PhiRewards
        phiRewards = new PhiRewards(deployer);
        require(address(phiRewards) != address(0), "PhiRewards deployment failed");
        console2.log("PhiRewards deployed at address: %s", address(phiRewards));

        // Deploy BondingCurve
        bondingCurve = new BondingCurve(oji3);
        require(address(bondingCurve) != address(0), "BondingCurve deployment failed");
        console2.log("BondingCurve deployed at address: %s", address(bondingCurve));

        vm.stopBroadcast();
    }

    function deployAndInitializeProxies() internal {
        vm.startBroadcast(deployer);

        // Deploy and initialize PhiFactory
        phiFactory = new PhiFactoryZkSync();
        ERC1967Proxy phiFactoryProxy = new ERC1967Proxy(address(phiFactory), "");
        require(address(phiFactoryProxy) != address(0), "PhiFactory proxy deployment failed");

        PhiFactoryZkSync(payable(address(phiFactoryProxy))).initialize(
            signer, treasury, address(phiNFT1155), address(phiRewards), oji3, 0.00015 ether, 0.00001 ether
        );
        console2.log("PhiFactory deployed and initialized at address: %s", address(phiFactoryProxy));

        // Deploy and initialize Cred
        Cred credImpl = new Cred();
        ERC1967Proxy credProxy = new ERC1967Proxy(address(credImpl), "");
        require(address(credProxy) != address(0), "Cred proxy deployment failed");

        Cred(payable(address(credProxy))).initialize(
            signer, oji3, treasury, 500, address(bondingCurve), address(phiRewards)
        );
        console2.log("Cred deployed and initialized at address: %s", address(credProxy));

        vm.stopBroadcast();
    }

    function configureContracts() internal {
        vm.startBroadcast(deployer);

        // Deploy CuratorRewardsDistributor
        curatorRewardsDistributor = new CuratorRewardsDistributor(address(phiRewards), payable(address(cred)));
        require(address(curatorRewardsDistributor) != address(0), "CuratorRewardsDistributor deployment failed");
        console2.log("CuratorRewardsDistributor deployed at address: %s", address(curatorRewardsDistributor));

        // Configure contract connections
        phiRewards.updateCuratorRewardsDistributor(address(curatorRewardsDistributor));
        phiRewards.setPhiFactory(address(phiFactory));

        vm.stopBroadcast();
    }
}
