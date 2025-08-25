import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy";
import "@typechain/hardhat";
import "hardhat-abi-exporter";

import dotenv from "dotenv";
dotenv.config();

const defaultAccount = {
  mnemonic:
    process.env.SEED_PHRASE ||
    "test test test test test test test test test test test junk",
  path: "m/44'/60'/0'/0",
  initialIndex: 0,
  count: 20,
  passphrase: "",
};

const _network = (url: string, gasPrice: number | "auto" = "auto") => ({
  url,
  accounts: [process.env.PRIVATE_KEY || ""],
  saveDeployments: true,
  gasPrice,
});

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    spacing: 2,
    // format: "minimal",
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
  networks: {
    hardhat: {
      // allowUnlimitedContractSize: true,
      forking: {
        url: `https://linea-rpc.publicnode.com`,
        // blockNumber: 17380608,
      },
      accounts: [
        {
          privateKey: process.env.PRIVATE_KEY || "",
          balance: "1000000000000000000000000",
        },
      ],
    },
    base: _network("https://mainnet.base.org"),
    linea: _network("https://rpc.linea.build", 100000000), // 0.1 gwei
    bsc: _network("https://bsc-dataseed1.bnbchain.org", 1000000000), // 1 gwei
  },
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY || "",
      sepolia: process.env.ETHERSCAN_KEY || "",
      base: process.env.BASESCAN_KEY || "",
      blast: process.env.BLASTSCAN_KEY || "",
      bsc: process.env.BSCSCAN_KEY || "",
      linea: process.env.LINEASCAN_KEY || "",
      optimisticEthereum: process.env.OP_ETHERSCAN_KEY || "",
      scroll: process.env.SCROLLSCAN_KEY || "",
      sonic: process.env.SONICSCAN_KEY || "",
      arbitrumOne: process.env.ARBISCAN_KEY || "",
      xlayer: "test",
    },
    customChains: [
      {
        network: "xlayer",
        chainId: 196,
        urls: {
          apiURL:
            "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/XLAYER",
          browserURL: "https://www.oklink.com/xlayer",
        },
      },
      {
        network: "sonic",
        chainId: 146,
        urls: {
          apiURL: "https://api.sonicscan.org/api",
          browserURL: "https://sonicscan.org",
        },
      },
      {
        network: "linea",
        chainId: 59144,
        urls: {
          apiURL: "https://api.lineascan.build/api",
          browserURL: "https://lineascan.build",
        },
      },
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.blastscan.io/api",
          browserURL: "https://blastscan.io",
        },
      },
      {
        network: "scroll",
        chainId: 534352,
        urls: {
          apiURL: "https://api.scrollscan.com/api",
          browserURL: "https://scrollscan.com",
        },
      },
    ],
  },
};

export default config;
