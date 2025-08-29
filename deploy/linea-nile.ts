import { HardhatRuntimeEnvironment } from "hardhat/types";
import { RamsesAdapter } from "../types";
import { deployAdapter, deployTokenSimple, templateLaunchpad } from "./mainnet-template";
import { deployContract, waitForTx } from "../scripts/utils";

async function main(hre: HardhatRuntimeEnvironment) {
  const deployer = "0xeD3Af36D7b9C5Bbd7ECFa7fb794eDa6E242016f5";
  const proxyAdmin = "0x5135f3A6aC33C8616b5ee59b89afc1021D1a8086";
  const wethAddressOnLinea = "0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f";
  const odosAddressOnLinea = "0x2d8879046f1559E53eb052E949e9544bCB72f414";
  const nftPositionManager = "0xAAA78E8C4241990B4ce159E105dA08129345946A";
  const e18 = 10n ** 18n;

  // Deploy SOMETHING contract
  const something = await deployContract(
    hre,
    "SOMETHING",
    ["SOMETHING Token", "SOMETHING"],
    "SOMETHING",
    deployer
  );

  console.log("SOMETHING contract deployed at:", something.address);

  const {launchpad, swapper } = await templateLaunchpad(
    hre,
    deployer,
    proxyAdmin,
    "TokenLaunchpadLinea",
    something.address,
    odosAddressOnLinea
  );

  const adapterNile = await deployAdapter(
    hre,
    "RamsesAdapter",
    {
      launchpad,
      wethAddress: wethAddressOnLinea,
      nftPositionManager,
      swapRouter: "0xAAAE99091Fbb28D400029052821653C1C752483B",
      locker: "0x0000BF531058EE5eC27417F96eBb1D7Bb8ccF4db",
      clPoolFactory: "0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42"
    }
  );

  // Set default value parameters
  await waitForTx(
    await launchpad.setDefaultValueParams(
      something.address, // _token - using SOMETHING contract
      adapterNile.target, // _adapter - using the deployed RamsesAdapter
      {
        fee: 3000,
        graduationLiquidity: 800000000000000000000000000n,
        graduationTick: -160500,
        launchTick: -186600,
        tickSpacing: 60,
        upperMaxTick: 885000
      }
    )
  );
  console.log("Default value parameters set successfully!");

  // Set fee settings
  await waitForTx(
    await launchpad.setFeeSettings(
      "0x5135f3A6aC33C8616b5ee59b89afc1021D1a8086",
      2000000000000000n,
      1000n * e18
    )
  );
  console.log("Fee settings set");

  // CONTRACTS ARE DEPLOYED; NOW WE CAN LAUNCH A NEW TOKEN

  // setup parameters
  const name = "Test Token";
  const symbol = "TEST";
  const metadata = JSON.stringify({ image: "https://i.imgur.com/56aQaCV.png" });

  if ((await launchpad.creationFee()) == 0n) {
    // 5$ in eth
    const efrogsTreasury = "0x5135f3A6aC33C8616b5ee59b89afc1021D1a8086";
    await waitForTx(
      await launchpad.setFeeSettings(
        efrogsTreasury,
        2000000000000000n,
        1000n * e18
      )
    );
    console.log("Fee settings set");
  }

  const shouldMock = false;
  if (shouldMock) {
    // const mahaD = await deployContract(
    //   hre,
    //   "MockERC20",
    //   ["TEST MAHA", "TMAHA", 18],
    //   "MAHA"
    // );

    // const maha = await hre.ethers.getContractAt("MockERC20", mahaD.address);

    // await waitForTx(await maha.mint(deployer, 1000000000000000000000000n));
    // await waitForTx(
    //   await maha.approve(launchpad.target, 1000000000000000000000000n)
    // );

    const token2 = await deployTokenSimple(
      hre,
      adapterNile,
      deployer,
      name,
      symbol,
      metadata,
      wethAddressOnLinea,
      launchpad,
      0n
    );

    console.log("Token deployed at", token2.target);
  }
}

main.tags = ["DeploymentNile"];
export default main;
