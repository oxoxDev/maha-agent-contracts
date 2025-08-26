import { HardhatRuntimeEnvironment } from "hardhat/types";
import { RamsesAdapter } from "../types";
import { deployAdapter, deployTokenSimple, templateLaunchpad } from "./mainnet-template";
import { deployContract, waitForTx } from "../scripts/utils";

async function main(hre: HardhatRuntimeEnvironment) {
  const deployer = "0xeD3Af36D7b9C5Bbd7ECFa7fb794eDa6E242016f5";
  const proxyAdmin = "0x106aDFea82fA618aa49C85b5A92F99AC65ea38F6";
  const wethAddressOnLinea = "0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f";
  const odosAddressOnLinea = "0x2d8879046f1559E53eb052E949e9544bCB72f414";
  const nftPositionManager = "0xAAA78E8C4241990B4ce159E105dA08129345946A";
  const e18 = 10n ** 18n;

  const {launchpad, swapper } = await templateLaunchpad(
    hre,
    deployer,
    proxyAdmin,
    "TokenLaunchpadLinea",
    wethAddressOnLinea,
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

  // CONTRACTS ARE DEPLOYED; NOW WE CAN LAUNCH A NEW TOKEN

  // setup parameters
  const name = "Test Token";
  const symbol = "TEST";
  const metadata = JSON.stringify({ image: "https://i.imgur.com/56aQaCV.png" });

  if ((await launchpad.creationFee()) == 0n) {
    // 5$ in eth
    const efrogsTreasury = "0xeD3Af36D7b9C5Bbd7ECFa7fb794eDa6E242016f5";
    await waitForTx(
      await launchpad.setFeeSettings(
        efrogsTreasury,
        2000000000000000n,
        1000n * e18
      )
    );
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
