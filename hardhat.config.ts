import "dotenv/config";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { ProxyAgent, setGlobalDispatcher } from "undici";

if (process.env.http_proxy || process.env.https_proxy) {
	const proxy = (process.env.http_proxy || process.env.https_proxy)!;
	const proxyAgent = new ProxyAgent(proxy);
	setGlobalDispatcher(proxyAgent);
}

const DEPLOYER_PRIVATE_KEY = process.env["DEPLOYER_PRIVATE_KEY"]!;
const POLYGONSCAN_API_KEY = process.env["POLYGONSCAN_API_KEY"] || "";

const config: HardhatUserConfig = {
	solidity: {
		version: "0.8.17",
		settings: {
			optimizer: {
				enabled: true,
				runs: 200,
			},
		},
	},
	networks: {
		polygon: {
			// If not set, you can get your own Alchemy API key at https://dashboard.alchemyapi.io or https://infura.io
			url: process.env["POLYGON_RPC_URL"],
			accounts: [DEPLOYER_PRIVATE_KEY],
		},
		mumbai: {
			// If not set, you can get your own Alchemy API key at https://dashboard.alchemyapi.io or https://infura.io
			url: process.env.MUMBAI_RPC_URL ?? "",
			accounts: [DEPLOYER_PRIVATE_KEY],
		},
	},
	etherscan: {
		apiKey: POLYGONSCAN_API_KEY,
	},
};

export default config;
