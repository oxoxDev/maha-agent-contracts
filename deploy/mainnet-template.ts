import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, deployProxy, waitForTx } from "../scripts/utils";
import { roundTickToNearestTick } from "./utils";
import { computeTickPrice } from "./utils";
import { guessTokenAddress } from "../scripts/create2/guess-token-addr";
import { ICLMMAdapter, ITokenLaunchpad, TokenLaunchpad } from "../types";

export async function templateLaunchpad(
  hre: HardhatRuntimeEnvironment,
  deployer: string,
  proxyAdmin: string,
  launchpadContract: string,
  wethAddress: string,
  odosAddress: string
) {
  const launchpadD = await deployProxy(
    hre,
    launchpadContract,
    [deployer, wethAddress],
    proxyAdmin,
    launchpadContract,
    deployer
  );

  const launchpad = await hre.ethers.getContractAt(
    "TokenLaunchpad",
    launchpadD.address
  );

  const swappeD = await deployContract(
    hre,
    "Swapper",
    [wethAddress, odosAddress, launchpadD.address],
    "Swapper"
  );
  const swapper = await hre.ethers.getContractAt("Swapper", swappeD.address);

  return {
    launchpad,
    swapper,
  };
}

export async function deployAdapter(
  hre: HardhatRuntimeEnvironment,
  adapterContract: string,
  args: {
    launchpad: TokenLaunchpad;
    wethAddress: string;
    swapRouter: string;
    locker: string;
    nftPositionManager: string;
    clPoolFactory: string;
  }
) {
  const adapterD = await deployContract(
    hre,
    adapterContract,
    [
      args.launchpad.target,
      args.clPoolFactory,
      args.swapRouter,
      args.wethAddress,
      args.locker,
      args.nftPositionManager,
    ],
    adapterContract
  );

  const adapter = await hre.ethers.getContractAt(
    "ICLMMAdapter",
    adapterD.address
  );

  // if (!(await args.launchpad.adapters(adapter))) {
  //   console.log("whitelisting adapter");
  //   await waitForTx(await args.launchpad.toggleAdapter(adapter));
  // }

  return adapter;
}

/**
 * Deploy a simple token on the launchpad
 * @param hre - HardhatRuntimeEnvironment
 * @param adapter - ICLMMAdapter - The adapter to use for the token
 * @param deployer - string - The deployer of the token
 * @param name - string - The name of the token
 * @param symbol - string - The symbol of the token
 * @param metadata - string - The metadata of the token
 * @param fundingToken - string - The funding token of the token
 * @param launchpad - TokenLaunchpad - The launchpad to use for the token
 * @param amountToBuy - bigint - The amount of tokens to buy
 * @returns - WAGMIEToken - The deployed token
 */
export const deployTokenSimple = async (
  hre: HardhatRuntimeEnvironment,
  adapter: ICLMMAdapter,
  deployer: string,
  name: string,
  symbol: string,
  metadata: string,
  fundingToken: string,
  launchpad: TokenLaunchpad,
  amountToBuy: bigint
) => {
  // get the bytecode for the WAGMIEToken
  const wagmie = await hre.ethers.getContractFactory("WAGMIEToken");

  // guess the salt and computed address for the given token
  const { salt, computedAddress } = await guessTokenAddress(
    launchpad.target,
    wagmie.bytecode, // tokenImpl.target,
    fundingToken,
    deployer,
    name,
    symbol
  );

  const data: ITokenLaunchpad.CreateParamsStruct = {
    adapter: adapter.target,
    creatorAllocation: 0,
    fundingToken,
    launchPoolAmounts: [],
    metadata,
    name,
    salt,
    symbol,
    valueParams: {
      fee: 0,
      graduationLiquidity: 0,
      graduationTick: 0,
      launchTick: 0,
      tickSpacing: 0,
      upperMaxTick: 0,
    },
  };

  const creationFee = await launchpad.creationFee();
  const dust = 10000000000000n;

  // create a launchpad token
  await waitForTx(
    await launchpad.createAndBuy(data, computedAddress, amountToBuy, hre.ethers.ZeroHash, false, {
      value: creationFee + dust,
    })
  );

  console.log("Simple Token deployed at", computedAddress);

  return hre.ethers.getContractAt("WAGMIEToken", computedAddress);
};

/**
 * Deploy a premium token on the launchpad
 * @param hre - HardhatRuntimeEnvironment
 * @param adapter - ICLMMAdapter - The adapter to use for the token
 * @param deployer - string - The deployer of the token
 * @param name - string - The name of the token
 * @param symbol - string - The symbol of the token
 * @param priceOfETHinUSD - number - The price of ETH in USD
 * @param tickSpacing - number - The tick spacing of the token
 * @param fee - bigint - The fee of the token
 * @param metadata - string - The metadata of the token
 * @param startingMarketCapInUSD - number - The starting market cap of the token
 * @param endingMarketCapInUSD - number - The ending market cap of the token
 * @param fundingToken - string - The funding token of the token
 * @param launchpad - TokenLaunchpad - The launchpad to use for the token
 * @param amountToBuy - bigint - The amount of tokens to buy
 * @returns - WAGMIEToken - The deployed token
 */
export const deployTokenPremium = async (
  hre: HardhatRuntimeEnvironment,
  adapter: ICLMMAdapter,
  deployer: string,
  name: string,
  symbol: string,
  priceOfETHinUSD: number,
  tickSpacing: number,
  fee: bigint,
  metadata: string,
  startingMarketCapInUSD: number,
  endingMarketCapInUSD: number,
  fundingToken: string,
  launchpad: TokenLaunchpad,
  amountToBuy: bigint
) => {
  // calculate ticks
  const launchTick = computeTickPrice(
    startingMarketCapInUSD,
    priceOfETHinUSD,
    18,
    tickSpacing
  );
  const _graduationTick = computeTickPrice(
    endingMarketCapInUSD,
    priceOfETHinUSD,
    18,
    tickSpacing
  );
  const graduationTick =
    _graduationTick == launchTick ? launchTick + tickSpacing : _graduationTick;
  const upperMaxTick = roundTickToNearestTick(887220, tickSpacing); // Maximum possible tick value

  // get the bytecode for the WAGMIEToken
  const wagmie = await hre.ethers.getContractFactory("WAGMIEToken");

  // guess the salt and computed address for the given token
  const { salt, computedAddress } = await guessTokenAddress(
    launchpad.target,
    wagmie.bytecode, // tokenImpl.target,
    fundingToken,
    deployer,
    name,
    symbol
  );

  const data: ITokenLaunchpad.CreateParamsStruct = {
    adapter: adapter.target,
    creatorAllocation: 0,
    fundingToken,
    launchPoolAmounts: [],
    metadata,
    name,
    salt,
    symbol,
    valueParams: {
      fee,
      graduationLiquidity: 800000000n,
      graduationTick,
      launchTick,
      tickSpacing,
      upperMaxTick,
    },
  };

  const creationFee = await launchpad.creationFee();
  const dust = 10000000000000n;

  // create a launchpad token
  console.log("creating a launchpad token", data);
  console.log(
    "data",
    await launchpad.createAndBuy.populateTransaction(
      data,
      computedAddress,
      amountToBuy,
      "",
      false,
      {
        value: creationFee + dust,
      }
    )
  );
  await waitForTx(
    await launchpad.createAndBuy(data, computedAddress, amountToBuy, "", false, {
      value: creationFee + dust,
    })
  );

  return hre.ethers.getContractAt("WAGMIEToken", computedAddress);
};
