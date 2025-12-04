import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ZETACHAIN_TESTNET_CONFIG as config } from "../../config/zetachain_testnet";
import { BigNumber } from "@ethersproject/bignumber";
import * as dotenv from 'dotenv';
import { ethers } from "hardhat";
import { Vault } from "../../typechain-types";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const { ethers, upgrades } = require("hardhat");
  
    // await main();
  
    async function main() {
        await deployUnifiedTokens();
        await deployVaults();
        await deployMinters();
        await deployAdapter();
        await setMinters();
        await registerAssets();
        await transferOwner();
        await upgradeProxys();
    }
  
    async function deployContract(name: string, contract: string, args?: any[], verify?: boolean) {
        if (typeof args == 'undefined') {
            args = []
        }
        if (typeof verify == 'undefined') {
            verify = false
        }
        const deployedAddress = config.deployedAddress[name as keyof typeof config.deployedAddress]
        if (!deployedAddress || deployedAddress == "") {
                console.log("Deploying contract:", name);
                const deployResult = await deploy(contract, {
                from: deployer,
                args: args,
                log: true,
            });
            return deployResult.address;
        } else {
            if (verify) {
                await verifyContract(deployedAddress, args);
            }
            console.log("Fetch previous deployed address for", name, deployedAddress );
            return deployedAddress;
        }
    }
  
    async function verifyContract(address: string, args?: any[]) {
        if (typeof args == 'undefined') {
            args = []
        }
        try {
            await hre.run("verify:verify", {
                address: address,
                constructorArguments: args,
            });
        } catch (e) {
            if ((e as Error).message != "Contract source code already verified") {
                throw(e)
            }
            console.log((e as Error).message)
        }
    }

    async function deployUnifiedTokens() {
        const UnifiedToken = await ethers.getContractFactory('UnifiedToken');

        const uUSDC = await upgrades.deployProxy(UnifiedToken, [
            "Unified USDC",
            "uUSDC"
        ]);
        await uUSDC.waitForDeployment();
        console.log("✅ uUSDC proxy deployed at:", uUSDC.target);
        const implAddress1 = await upgrades.erc1967.getImplementationAddress(uUSDC.target);
        console.log("🔧 uUSDC implementation deployed at:", implAddress1);
        await verifyContract(implAddress1, []);

        const uUSDT = await upgrades.deployProxy(UnifiedToken, [
            "Unified USDT",
            "uUSDT"
        ]);
        await uUSDT.waitForDeployment();
        console.log("✅ uUSDT proxy deployed at:", uUSDT.target);
        const implAddress2 = await upgrades.erc1967.getImplementationAddress(uUSDT.target);
        console.log("🔧 uUSDT implementation deployed at:", implAddress2);
        await verifyContract(implAddress2, []);
    }

    async function deployVaults() {
        await deployContract("USDCVault", "contracts/unified/Vault.sol");
        await deployContract("USDTVault", "contracts/unified/Vault.sol");
    }

    async function deployMinters() {
        const d = config.deployedAddress;
        const Minter = await ethers.getContractFactory('Minter');

        const uUSDCMinter = await upgrades.deployProxy(Minter, [
            d.uUSDCProxy,
            d.USDCVault
        ]);
        await uUSDCMinter.waitForDeployment();
        console.log("✅ uUSDCMinter proxy deployed at:", uUSDCMinter.target);
        const implAddress1 = await upgrades.erc1967.getImplementationAddress(uUSDCMinter.target);
        console.log("🔧 uUSDCMinter implementation deployed at:", implAddress1);
        await verifyContract(implAddress1, []);

        const uUSDTMinter = await upgrades.deployProxy(Minter, [
            d.uUSDTProxy,
            d.USDTVault
        ]);
        await uUSDTMinter.waitForDeployment();
        console.log("✅ uUSDTMinter proxy deployed at:", uUSDTMinter.target);
        const implAddress2 = await upgrades.erc1967.getImplementationAddress(uUSDTMinter.target);
        console.log("🔧 uUSDTMinter implementation deployed at:", implAddress2);
        await verifyContract(implAddress2, []);
    }

    async function deployAdapter() {
        await deployContract("MinterAdapter", "MinterAdapter");
    }

    async function setMinters() {
        const d = config.deployedAddress;

        console.log("uUSDC set minter...");
        const uUSDC = await ethers.getContractAt(
        "UnifiedToken",
        d.uUSDCProxy
        );
        await uUSDC.setMinter(d.uUSDCMinterProxy);

        console.log("USDCVault set minter...");
        const USDCVault = await ethers.getContractAt(
        "contracts/unified/Vault.sol:Vault",
        d.USDCVault
        );
        await USDCVault.setMinter(d.uUSDCMinterProxy);

        console.log("uUSDT set minter...");
        const uUSDT = await ethers.getContractAt(
        "UnifiedToken",
        d.uUSDTProxy
        );
        await uUSDT.setMinter(d.uUSDTMinterProxy);

        console.log("USDTVault set minter...");
        const USDTVault = await ethers.getContractAt(
        "contracts/unified/Vault.sol:Vault",
        d.USDTVault
        );
        await USDTVault.setMinter(d.uUSDTMinterProxy);
    }

    async function registerAssets() {
        const def = config.defaultAddress;
        const dep = config.deployedAddress;

        console.log("uUSDCMinter register assets...");
        const uUSDCMinter = await ethers.getContractAt(
        "Minter",
        dep.uUSDCMinterProxy
        );
        await uUSDCMinter.registerAssets(
            [def.USDC_ARBSEP, def.USDC_SEP, dep.uUSDCProxy],
            [true, true, true],
            [0, 0, 0],
            [0, 0, 0],
        );

        // console.log("uUSDTMinter register assets...");
        // const uUSDTMinter = await ethers.getContractAt(
        // "Minter",
        // dep.uUSDTMinterProxy
        // );
        // await uUSDTMinter.registerAssets(
        //     [def.USDT_ARBSEP, def.USDT_SEP, dep.uUSDTProxy],
        //     [true, true, true],
        //     [0, 0, 0],
        //     [0, 0, 0],
        // );
    }

    async function transferOwner() {
        const def = config.defaultAddress;
        const dep = config.deployedAddress;

        console.log("uUSDC transfer owner...");
        const uUSDC = await ethers.getContractAt('UnifiedToken', dep.uUSDCProxy);
        await uUSDC.transferOwnership(def.UnifiedMultiSig);

        console.log("USDCVault transfer owner...");
        const USDCVault = await ethers.getContractAt('contracts/unified/Vault.sol:Vault', dep.USDCVault);
        await USDCVault.transferOwnership(def.UnifiedMultiSig);

        console.log("uUSDCMinter transfer owner...");
        const uUSDCMinter = await ethers.getContractAt('Minter', dep.uUSDCMinterProxy);
        await uUSDCMinter.transferOwnership(def.UnifiedMultiSig);

        console.log("uUSDT transfer owner...");
        const uUSDT = await ethers.getContractAt('UnifiedToken', dep.uUSDTProxy);
        await uUSDT.transferOwnership(def.UnifiedMultiSig);

        console.log("USDTVault transfer owner...");
        const USDTVault = await ethers.getContractAt('contracts/unified/Vault.sol:Vault', dep.USDTVault);
        await USDTVault.transferOwnership(def.UnifiedMultiSig);

        console.log("uUSDTMinter transfer owner...");
        const uUSDTMinter = await ethers.getContractAt('Minter', dep.uUSDTMinterProxy);
        await uUSDTMinter.transferOwnership(def.UnifiedMultiSig);
    }

    async function upgradeProxys() {
        const d = config.deployedAddress;

        const uUSDC = await ethers.getContractFactory('UnifiedToken');
        const upgraded1 = await upgrades.upgradeProxy(d.uUSDCProxy, uUSDC);
        console.log("✅ uUSDC proxy upgraded at:", upgraded1.target);
        const implAddress1 = await upgrades.erc1967.getImplementationAddress(upgraded1.target);
        console.log("🔧 New uUSDC implementation deployed at:", implAddress1);

        const uUSDCMinter = await ethers.getContractFactory('Minter');
        const upgraded2 = await upgrades.upgradeProxy(d.uUSDCMinterProxy, uUSDCMinter);
        console.log("✅ uUSDCMinter proxy upgraded at:", upgraded2.target);
        const implAddress2 = await upgrades.erc1967.getImplementationAddress(upgraded2.target);
        console.log("🔧 New uUSDCMinter implementation deployed at:", implAddress2);

        const uUSDT = await ethers.getContractFactory('UnifiedToken');
        const upgraded3 = await upgrades.upgradeProxy(d.uUSDTProxy, uUSDT);
        console.log("✅ uUSDT proxy upgraded at:", upgraded3.target);
        const implAddress3 = await upgrades.erc1967.getImplementationAddress(upgraded3.target);
        console.log("🔧 New uUSDT implementation deployed at:", implAddress3);

        const uUSDTMinter = await ethers.getContractFactory('Minter');
        const upgraded4 = await upgrades.upgradeProxy(d.uUSDTMinterProxy, uUSDTMinter);
        console.log("✅ uUSDTMinter proxy upgraded at:", upgraded4.target);
        const implAddress4 = await upgrades.erc1967.getImplementationAddress(upgraded4.target);
        console.log("🔧 New uUSDTMinter implementation deployed at:", implAddress4);
    }
};

export default func;