require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Local development network (run: npx hardhat node)
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    // Sepolia testnet — configure .env with your credentials Gavin -- switched to polygon to match currency that we have
    polygon: {
  url: "https://sepolia.infura.io/v3/b72550e08d5b4eeca40abc078903bc6d",
  accounts: [process.env.PRIVATE_KEY],
  chainId: 11155111,
}
,
  },
  // Etherscan verification (optional)
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};
