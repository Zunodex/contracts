import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ZETACHAIN_TESTNET_CONFIG as config } from "../../config/zetachain_testnet";
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
        await deployProxys();
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
        const feePercent = 10; // 1%
        const slippage = 10;
        const gasLimit = 1000000;
        const GatewayCrossChain = await ethers.getContractFactory('GatewayCrossChain');
        const gatewayCrossChain = await upgrades.deployProxy(GatewayCrossChain, [
            d.Gateway,
            d.MultiSig,
            d.DODORouteProxy,
            feePercent,
            slippage,
            gasLimit
        ])
        await gatewayCrossChain.waitForDeployment();
        console.log("GatewayCrossChain deployed to:", await gatewayCrossChain.getAddress());
        const GatewayTransferNative = await ethers.getContractFactory('GatewayTransferNative');
        const gatewayTransferNative = await upgrades.deployProxy(GatewayTransferNative, [
            d.Gateway,
            d.MultiSig,
            d.DODORouteProxy,
            feePercent,
            slippage,
            gasLimit
        ])
        await gatewayTransferNative.waitForDeployment();
        console.log("GatewayTransferNative deployed to:", await gatewayTransferNative.getAddress());
    }
};

export default func;