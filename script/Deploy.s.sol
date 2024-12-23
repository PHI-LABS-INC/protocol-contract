// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { Cred } from "../src/Cred.sol";
import { PhiNFT1155 } from "../src/art/PhiNFT1155.sol";
import { BondingCurve } from "../src/curve/BondingCurve.sol";
import { FixedPriceBondingCurve } from "../src/lib/FixedPriceBondingCurve.sol";
import { PhiRewards } from "../src/reward/PhiRewards.sol";
import { CuratorRewardsDistributor } from "../src/reward/CuratorRewardsDistributor.sol";
import { PhiFactory } from "../src/PhiFactory.sol";
import { BaseScript } from "./Base.s.sol";

// https://github.com/Cyfrin/foundry-upgrades-f23/blob/main/script/DeployBox.s.sol
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    using LibClone for address;

    address public deployer;
    Cred public cred;
    PhiFactory public phiFactory;
    PhiNFT1155 public phiNFT1155;
    BondingCurve public bondingCurve;
    FixedPriceBondingCurve public fixedPriceBondingCurve;
    PhiRewards public phiRewards;
    CuratorRewardsDistributor public curatorRewardsDistributor;

    address public oji3 = 0x5cD18dA4C84758319C8E1c228b48725f5e4a3506;
    // address public signer = 0x29C76e6aD8f28BB1004902578Fb108c507Be341b;
    address public signer = 0xe35E5f8B912C25cDb6B00B347cb856467e4112A3;
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

        phiNFT1155 = new PhiNFT1155();
        console2.log("PhiNFT1155 deployed at address: %s", address(phiNFT1155));
        // address ownerAddress_
        phiRewards = new PhiRewards(deployer);
        console2.log("PhiRewards deployed at address: %s", address(phiRewards));

        phiFactory = new PhiFactory();
        ERC1967Proxy phiFactoryProxy = new ERC1967Proxy(address(phiFactory), "");

        // address phiSignerAddress_,
        // address protocolFeeDestination_,
        // address erc1155ArtAddress_,
        // address phiRewardsAddress_,
        // address ownerAddress_,
        // uint256 protocolFee_,
        // uint256 artCreateFee_
        PhiFactory(payable(address(phiFactoryProxy))).initialize(
            signer, treasury, address(phiNFT1155), address(phiRewards), oji3, 0.00015 ether, 0.00001 ether
        );
        console2.log("PhiFactory deployed at address: %s", address(phiFactoryProxy));

        // address owner_
        bondingCurve = new BondingCurve(oji3);
        console2.log("BondingCurve deployed at address: %s", address(bondingCurve));

        // fixedPriceBondingCurve = new FixedPriceBondingCurve(oji3);
        // console2.log("FixedPriceBondingCurve deployed at address: %s", address(fixedPriceBondingCurve));

        ERC1967Proxy credProxy = new ERC1967Proxy(address(new Cred()), "");
        console2.log("Cred deployed at address: %s", address(credProxy));

        // address phiSignerAddress_,
        // address ownerAddress_,
        // address protocolFeeDestination_,
        // uint256 protocolFeePercent_,
        // address bondingCurveAddress_,
        // address phiRewardsAddress_
        Cred(payable(address(credProxy))).initialize(
            signer, oji3, treasury, 500, address(bondingCurve), address(phiRewards)
        );

        // address phiRewardsContract_, address credContract_
        curatorRewardsDistributor = new CuratorRewardsDistributor(address(phiRewards), payable(address(credProxy)));
        console2.log("CuratorRewardsDistributor deployed at address: %s", address(curatorRewardsDistributor));

        phiRewards.updateCuratorRewardsDistributor(address(curatorRewardsDistributor));
        phiRewards.setPhiFactory(address(phiFactoryProxy));
        // bondingCurve.setCredContract(address(credProxy));
    }
}
