import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { BASE_CONFIG as config } from "../../config/base";
import { BigNumber } from "@ethersproject/bignumber";
import * as dotenv from 'dotenv';
import { ethers } from "hardhat";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const { ethers, upgrades } = require("hardhat");
  
    await main();
  
    async function main() {
        // await deployProxys();
        // await deployVault();
        // await setVault();
        // await transferOwner();
        // await upgradeProxys();
        // await upgradeVault();
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

    async function deployProxys() {
        const d = config.defaultAddress;
        const gasLimit = 1000000;
        const GatewaySend = await ethers.getContractFactory('GatewaySend');
        const gatewaySend = await upgrades.deployProxy(GatewaySend, [
            d.Gateway,
            d.DODORouteProxy,
            d.DODOApprove,
            gasLimit
        ]);
        await gatewaySend.waitForDeployment();
        console.log("✅ GatewaySend proxy deployed at:", gatewaySend.target);

        const implAddress = await upgrades.erc1967.getImplementationAddress(gatewaySend.target);
        console.log("🔧 GatewaySend implementation deployed at:", implAddress);
    }

    async function deployVault() {
        const Vault = await ethers.getContractFactory('Vault');
        const vault = await upgrades.deployProxy(Vault, []);
        await vault.waitForDeployment();
        console.log("✅ Vault proxy deployed at:", vault.target);
        const implAddress = await upgrades.erc1967.getImplementationAddress(vault.target);
        console.log("🔧 Vault implementation deployed at:", implAddress);
        await verifyContract(implAddress, []);
    }

    async function setVault() {
        const d = config.deployedAddress;

        console.log("Vault set bot...");
        const vault = await ethers.getContractAt('Vault', d.VaultProxy);
        await vault.setBot(config.defaultAddress.RefundBot, true);
    }

    async function transferOwner() {
        const d = config.deployedAddress;
        const gatewaySend = await ethers.getContractAt("GatewaySend", d.GatewaySendProxy);
        
        console.log("Transferring GatewaySend ownership...")
        const tx = await gatewaySend.transferOwnership(config.defaultAddress.MultiSig);
        await tx.wait();
        console.log("✅ Ownership transfer transaction confirmed");
    }

    async function upgradeProxys() {
        const d = config.deployedAddress;
        const GatewaySend = await ethers.getContractFactory('GatewaySend');
        const upgraded = await upgrades.upgradeProxy(d.GatewaySendProxy, GatewaySend);
        console.log("✅ GatewaySend proxy upgraded at:", upgraded.target);

        const implAddress = await upgrades.erc1967.getImplementationAddress(upgraded.target);
        console.log("🔧 New GatewaySend implementation deployed at:", implAddress);
    }

    async function upgradeVault() {
        const d = config.deployedAddress;

        const Vault = await ethers.getContractFactory('RefundVault');
        const upgraded = await upgrades.upgradeProxy(d.VaultProxy, Vault);
        console.log("✅ Vault proxy upgraded at:", upgraded.target);
        const implAddress = await upgrades.erc1967.getImplementationAddress(upgraded.target);
        console.log("🔧 New Vault implementation deployed at:", implAddress);
    }
};

export default func;