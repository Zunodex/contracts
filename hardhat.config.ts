import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
require('@openzeppelin/hardhat-upgrades');
import dotenv from "dotenv"; 
dotenv.config();

// For WSL2 users, you may need to set a proxy agent to connect to the internet
// import { ProxyAgent, setGlobalDispatcher } from 'undici';
// const proxyAgent = new ProxyAgent("http://172.29.32.1:55315"); // replace ip with cat /etc/resolv.conf | grep nameserver
// setGlobalDispatcher(proxyAgent);

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
    eth: {
      chainId: 1,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://1rpc.io/eth",
      deploy: ["./deploy/eth/"],
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
    avax: {
      chainId: 43114,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://api.avax.network/ext/bc/C/rpc",
      deploy: ["./deploy/avax/"],
    },
    arb: {
      chainId: 42161,
      accounts: [process.env.PRIVATE_KEY ?? ""],
      url: "https://arb-mainnet.g.alchemy.com/v2/i7AGD7NB2oucWbfTCszVNn1KE9WltlBw",
      deploy: ["./deploy/arb/"],
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
      eth: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      polygon: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      bnb: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      base: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      avax: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      arb: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      sepolia: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      arb_sepolia: "JP1EHB7VINQ6YP3UYBNCY8YFW6CXDEYTRE",
      zetachain_testnet: "6542100",
      zetachain_mainnet: "6542100",
    },
    customChains: [
      {
        network: "eth",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=1",
          browserURL: "https://etherscan.io/",
        },
      },
      {
        network: "polygon",
        chainId: 137,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=137",
          browserURL: "https://polygonscan.com/",
        },
      },
      {
        network: "bnb",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://bscscan.com/",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
          browserURL: "https://basescan.org/",
        },
      },
      {
        network: "avax",
        chainId: 43114,
          urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=43114",
          browserURL: "https://snowscan.xyz/",
        },
      },
      {
        network: "arb",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io/",
        },
      },
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=11155111",
          browserURL: "https://sepolia.etherscan.io/",
        },
      },
      {
        network: "arb_sepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=421614",
          browserURL: "https://sepolia.arbiscan.io/",
        },
      },
      {
        network: "zetachain_testnet",
        chainId: 7001,
        urls: {
          apiURL: "https://testnet.zetascan.com/api",
          browserURL: "https://testnet.zetascan.com/",
        },
      },
      {
        network: "zetachain_mainnet",
        chainId: 7000,
        urls: {
          apiURL: "https://zetascan.com/api",
          browserURL: "https://zetascan.com/",
        },
      },
    ]
  },
};

export default config;
