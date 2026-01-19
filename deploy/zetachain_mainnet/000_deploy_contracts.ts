import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ZETACHAIN_MAINNET_CONFIG as config } from "../../config/zetachain_mainnet";
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
        // await deployRefundVault();
        // await setProxys();
        // await setRefundVault();
        // await transferOwnership();
        // await upgradeProxys();
        // await upgradeRefundVault();
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
        const feePercent = 10; // 0.01%
        const slippage = 10;
        const gasLimit = 700000;
        
        const GatewayCrossChain = await ethers.getContractFactory('GatewayCrossChain');
        const gatewayCrossChain = await upgrades.deployProxy(
            GatewayCrossChain,
            [
                d.Gateway,
                d.MultiSig,
                d.DODORouteProxy,
                d.DODOApprove,
                feePercent,
                slippage,
                gasLimit
            ],
            {
                redeployImplementation: "always",
            }
        );
        await gatewayCrossChain.waitForDeployment();
        console.log("✅ GatewayCrossChain proxy deployed at:", gatewayCrossChain.target);
        const implAddress1 = await upgrades.erc1967.getImplementationAddress(gatewayCrossChain.target);
        console.log("🔧 GatewayCrossChain implementation deployed at:", implAddress1);

        const GatewayTransferNative = await ethers.getContractFactory('GatewayTransferNative');
        const gatewayTransferNative = await upgrades.deployProxy(
            GatewayTransferNative,
            [
                d.Gateway,
                d.MultiSig,
                d.DODORouteProxy,
                d.DODOApprove,
                feePercent,
                slippage,
                gasLimit
            ],
            {
                redeployImplementation: "always",
            }
        );
        await gatewayTransferNative.waitForDeployment();
        console.log("✅ GatewayTransferNative proxy deployed at:", gatewayTransferNative.target);
        const implAddress2 = await upgrades.erc1967.getImplementationAddress(gatewayTransferNative.target);
        console.log("🔧 GatewayTransferNative implementation deployed at:", implAddress2);
    }

    async function deployRefundVault() {
        const d = config.defaultAddress;
        const gasLimit = 1000000;

        const RefundVault = await ethers.getContractFactory('RefundVault');
        const refundVault = await upgrades.deployProxy(RefundVault, [
            d.Gateway,
            gasLimit
        ]);
        await refundVault.waitForDeployment();
        console.log("✅ RefundVault proxy deployed at:", refundVault.target);
        const implAddress = await upgrades.erc1967.getImplementationAddress(refundVault.target);
        console.log("🔧 RefundVault implementation deployed at:", implAddress);
        await verifyContract(implAddress, []);
    }

    async function setProxys() {
        const d = config.deployedAddress;

        console.log("GatewayCrossChain set refund vault...");
        const gatewayCrossChain = await ethers.getContractAt('GatewayCrossChain', d.GatewayCrossChainProxy);
        await gatewayCrossChain.setVault(d.RefundVaultProxy);

        console.log("GatewayTransferNative set refund vault...");
        const gatewayTransferNative = await ethers.getContractAt('GatewayTransferNative', d.GatewayTransferNativeProxy);
        await gatewayTransferNative.setVault(d.RefundVaultProxy);
    }

    async function setRefundVault() {
        const d = config.deployedAddress;

        console.log("RefundVault set whiteList contracts...");
        const refundVault = await ethers.getContractAt('RefundVault', d.RefundVaultProxy);
        await refundVault.setWhiteList(d.GatewayCrossChainProxy, true);
        await refundVault.setWhiteList(d.GatewayTransferNativeProxy, true);

        console.log("RefundVault set bot...");
        await refundVault.setBot(config.defaultAddress.RefundBot, true);
    }

    async function transferOwner() {
        const d = config.deployedAddress;

        console.log("RefundVault transfer owner...");
        const refundVault = await ethers.getContractAt('RefundVault', d.RefundVaultProxy);
        await refundVault.transferOwnership(config.defaultAddress.MultiSig);

        console.log("GatewayCrossChain transfer owner...");
        const gatewayCrossChain = await ethers.getContractAt('GatewayCrossChain', d.GatewayCrossChainProxy);
        await gatewayCrossChain.transferOwnership(config.defaultAddress.MultiSig);

        console.log("GatewayTransferNative transfer owner...");
        const gatewayTransferNative = await ethers.getContractAt('GatewayTransferNative', d.GatewayTransferNativeProxy);
        await gatewayTransferNative.transferOwnership(config.defaultAddress.MultiSig);
    }

    async function upgradeProxys() {
        const d = config.deployedAddress;

        // const GatewayCrossChain = await ethers.getContractFactory('GatewayCrossChain');
        // const upgraded1 = await upgrades.upgradeProxy(d.GatewayCrossChainProxy, GatewayCrossChain);
        // console.log("✅ GatewayCrossChain proxy upgraded at:", upgraded1.target);
        // const implAddress1 = await upgrades.erc1967.getImplementationAddress(upgraded1.target);
        // console.log("🔧 New GatewayCrossChain implementation deployed at:", implAddress1);

        // const GatewayTransferNative = await ethers.getContractFactory('GatewayTransferNative');
        // const upgraded2 = await upgrades.upgradeProxy(d.GatewayTransferNativeProxy, GatewayTransferNative);
        // console.log("✅ GatewayTransferNative proxy upgraded at:", upgraded2.target);
        // const implAddress2 = await upgrades.erc1967.getImplementationAddress(upgraded2.target);
        // console.log("🔧 New GatewayTransferNative implementation deployed at:", implAddress2);

        const GatewayCrossChain = await ethers.getContractFactory('GatewayCrossChain');
        const implementation1 = await GatewayCrossChain.deploy();
        await implementation1.waitForDeployment();
        console.log("🔧 New GatewayCrossChain implementation deployed at:", implementation1.target);

        const GatewayTransferNative = await ethers.getContractFactory('GatewayTransferNative');
        const implementation2 = await GatewayTransferNative.deploy();
        await implementation2.waitForDeployment();
        console.log("🔧 New GatewayTransferNative implementation deployed at:", implementation2.target);
    }

    async function upgradeRefundVault() {
        const d = config.deployedAddress;

        const RefundVault = await ethers.getContractFactory('RefundVault');
        const upgraded = await upgrades.upgradeProxy(d.RefundVaultProxy, RefundVault);
        console.log("✅ RefundVault proxy upgraded at:", upgraded.target);
        const implAddress = await upgrades.erc1967.getImplementationAddress(upgraded.target);
        console.log("🔧 New RefundVault implementation deployed at:", implAddress);
    }
};

export default func;