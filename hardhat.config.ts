import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
require('@openzeppelin/hardhat-upgrades');
import dotenv from "dotenv"; 
dotenv.config();

// For WSL2 users, you may need to set a proxy agent to connect to the internet
import { ProxyAgent, setGlobalDispatcher } from 'undici';
const proxyAgent = new ProxyAgent("http://172.29.32.1:55315"); // replace ip with cat /etc/resolv.conf | grep nameserver
setGlobalDispatcher(proxyAgent);

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    ethereum: {
      chainId: 1,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://1rpc.io/eth",
      deploy: ["./deploy/ethereum/"],
    },
    polygon: {
      chainId: 137,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://polygon-mainnet.g.alchemy.com/v2/i7AGD7NB2oucWbfTCszVNn1KE9WltlBw",
      deploy: ["./deploy/polygon/"],
    },
    bnb: {
      chainId: 56,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://bsc.drpc.org",
      deploy: ["./deploy/bnb/"],
    },
    base: {
      chainId: 8453,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://base-mainnet.g.alchemy.com/v2/i7AGD7NB2oucWbfTCszVNn1KE9WltlBw",
      deploy: ["./deploy/base/"],
    },
    zetachain_mainnet: {
      chainId: 7000,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://zetachain-evm.blockpi.network/v1/rpc/public",
      deploy: ["./deploy/zetachain_mainnet/"],
    },
    zetachain_testnet: {
      chainId: 7001,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://zetachain-athens-evm.blockpi.network/v1/rpc/public",
      deploy: ["./deploy/zetachain_testnet/"],
    },
    sepolia: {
      chainId: 11155111,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://sepolia.drpc.org",
      deploy: ["./deploy/sepolia/"],
    },
    arb_sepolia: {
      chainId: 421614,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://arbitrum-sepolia.drpc.org",
      deploy: ["./deploy/arb_sepolia/"],
    },
  },
  etherscan: {
    apiKey: {
      ethereum: "VV6FB3HDE9FSVBBVMVXGPQX4KSJUJIY3E6",
      polygon: "2JZHRC8JP35PTPY64QPBDTCT2QE1ARI5ZP",
      bnb: "FDRR41V15H8WDGEGRU2KEPXWBYSS5IFDIY",
      base: "ABVYVFMXQCR35J2Y58RH52KW4AY66EQXUZ",
      sepolia: "VV6FB3HDE9FSVBBVMVXGPQX4KSJUJIY3E6",
      arb_sepolia: "8TDWU29I4QA8AW713FK2Y29QABP5AF9FXX",
      zetachain_testnet: "6542100",
      zetachain_mainnet: "6542100",
    },
    customChains: [
      {
        network: "ethereum",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/api",
          browserURL: "https://etherscan.io/",
        },
      },
      {
        network: "polygon",
        chainId: 137,
        urls: {
          apiURL: "https://api.polygonscan.com/api",
          browserURL: "https://polygonscan.com/",
        },
      },
      {
        network: "bnb",
        chainId: 56,
        urls: {
          apiURL: "https://api.bscscan.com/api",
          browserURL: "https://bscscan.com/",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io/",
        },
      },
      {
        network: "arb_sepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io/",
        },
      },
      {
        network: "zetachain_testnet",
        chainId: 7001,
        urls: {
          apiURL: "https://zetachain-testnet.blockscout.com/api",
          browserURL: "https://zetachain-testnet.blockscout.com",
        },
      },
      {
        network: "zetachain_mainnet",
        chainId: 7000,
        urls: {
          apiURL: "https://zetachain.blockscout.com/api",
          browserURL: "https://zetachain.blockscout.com/",
        },
      },
    ]
  },
};

export default config;
