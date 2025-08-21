// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BondingCurve} from "contracts/BondingCurve.sol";
import {TokenLaunchpadBSC} from "contracts/launchpad/TokenLaunchpadBSC.sol";
import {PancakeAdapter} from "contracts/launchpad/clmm/adapters/PancakeAdapter.sol";
import {AirdropRewarder} from "contracts/airdrop/AirdropReward.sol";
import {WAGMIEToken} from "contracts/WAGMIEToken.sol";
import {MockERC20} from "contracts/mocks/MockERC20.sol";

import {ITokenLaunchpad, ILaunchpool} from "contracts/interfaces/ITokenLaunchpad.sol";
import {IBondingCurve} from "contracts/interfaces/IBondingCurve.sol";

contract BondingCurveForkTest is Test {
    // BSC addresses
    address constant PANCAKE_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
    address constant NFT_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant LOCKER = 0x25c9C4B56E820e0DEA438b145284F02D9Ca9Bd52;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant BNB_USD_ORACLE = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; //chaink link price feed

    // Accounts
    address owner = makeAddr("owner");
    address creator = makeAddr("creator");
    address feeDestination = makeAddr("feeDestination");
    address trader = makeAddr("trader");

    // Contracts
    TokenLaunchpadBSC launchpad;
    BondingCurve bondingCurve;
    PancakeAdapter adapter;
    AirdropRewarder airdropRewarder;
    MockERC20 maha;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");

    function setUp() public {
        // Fork BSC
        uint256 bscFork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(bscFork);

        // Setup accounts
        vm.deal(owner, 1000 ether);
        vm.deal(creator, 1000 ether);
        vm.deal(trader, 1000 ether);
        // Deploy
        maha = new MockERC20("MAHA", "MAHA", 18);
        launchpad = new TokenLaunchpadBSC();
        adapter = new PancakeAdapter(
            address(launchpad),
            PANCAKE_FACTORY,
            PANCAKE_ROUTER,
            WBNB,
            LOCKER,
            NFT_MANAGER
        );
        bondingCurve = new BondingCurve();
        airdropRewarder = new AirdropRewarder();

        // Initialize
        vm.startPrank(owner);
        launchpad.initialize(owner, WBNB, address(maha));
        bondingCurve.initialize(
            owner,
            address(launchpad),
            100,
            feeDestination,
            10_000e18
        ); // $10,000 launch threshold
        airdropRewarder.initialize(address(launchpad));

        // Configure
        launchpad.setFeeSettings(feeDestination, 0.01 ether, 1000e18);
        launchpad.toggleAdapter(adapter);
        launchpad.setBondingCurve(address(bondingCurve));
        launchpad.setAirdropRewarder(address(airdropRewarder));

        launchpad.setDefaultValueParams(
            IERC20(WBNB),
            adapter,
            ITokenLaunchpad.ValueParams(
                -171_000,
                -170_800,
                887_200,
                10_000,
                200,
                800_000_000 ether
            )
        );

        // Set up price oracle for BNB/USD (BSC Chainlink feed)
        bondingCurve.setPriceOracle(IERC20(WBNB), BNB_USD_ORACLE);

        bondingCurve.setLaunchMarketCapUSD(10000e18); // $10 launch threshold

        vm.stopPrank();
    }

    function test_buy_tokens() public {
        // Create token
        bytes32 salt = findValidTokenHash(
            "Test Token",
            "TEST",
            creator,
            IERC20(WBNB)
        );

        vm.prank(creator);
        (address tokenAddr, , ) = launchpad.createAndBuy{value: 100 ether}(
            _createParams(salt),
            0x44Cc9d46cb36A1678B793a3d56d90791e073Ae31,
            1 ether,
            bytes32("0x1"),
            false
        );

        assertTrue(tokenAddr != address(0), "Token address should not be zero");

        IERC20 token = IERC20(tokenAddr);

        deal(WBNB, trader, 100 ether);

        vm.startPrank(trader);
        IERC20(WBNB).approve(address(bondingCurve), 100 ether);
        uint256 tokensReceived = bondingCurve.buyTokens{value: 100 ether}(
            token,
            100 ether,
            0
        );
        vm.stopPrank();

        assertEq(token.balanceOf(trader), tokensReceived);
        assertTrue(tokensReceived > 0, "Trader should receive tokens");

        console.log("Token balance of trader:", token.balanceOf(trader));
        console.log(
            "Token balance of bonding curve:",
            token.balanceOf(address(bondingCurve))
        );
        console.log("Tokens received:", tokensReceived);
    }

    function test_launchToDex() public {
        // Create token
        bytes32 salt = findValidTokenHash(
            "Test Token",
            "TEST",
            creator,
            IERC20(WBNB)
        );

        vm.prank(creator);
        (address tokenAddr, , ) = launchpad.createAndBuy{value: 100 ether}(
            _createParams(salt),
            0x44Cc9d46cb36A1678B793a3d56d90791e073Ae31,
            1 ether,
            bytes32("0x1"),
            false
        );

        assertTrue(tokenAddr != address(0), "Token address should not be zero");
        IERC20 token = IERC20(tokenAddr);

        // Set launch threshold to $10,000
        vm.prank(owner);
        bondingCurve.setLaunchMarketCapUSD(10e18);

        // Buy tokens in increments until we reach the $10,000 threshold
        uint256 buyAmount = 10 ether; // Buy 10 BNB worth at a time
        uint256 totalSpent = 0;
        uint256 trades = 0;

        while (!bondingCurve.shouldLaunchToDEX(token) && trades < 20) {
            address currentTrader = address(uint160(0x1000 + trades));
            vm.deal(currentTrader, buyAmount + 1 ether);

            console.log("\n=== Trade", trades + 1, "===");
            console.log("Trader:", currentTrader);
            console.log("Buying:", buyAmount / 1e18, "BNB worth of tokens");

            vm.startPrank(currentTrader);
            IERC20(WBNB).approve(address(bondingCurve), buyAmount);

            uint256 tokensReceived = bondingCurve.buyTokens{value: buyAmount}(
                token,
                buyAmount,
                0
            );
            vm.stopPrank();

            totalSpent += buyAmount;
            trades++;

            console.log("Tokens received:", tokensReceived / 1e18);
            console.log("Total BNB spent:", totalSpent / 1e18);
            console.log(
                "Current market cap USD:",
                bondingCurve.getMarketCapUSD(token)
            );
            console.log(
                "Should launch to DEX:",
                bondingCurve.shouldLaunchToDEX(token)
            );

            // Safety check to prevent infinite loop
            if (trades >= 20) {
                console.log("Reached max trades, stopping");
                break;
            }
        }

        // Get bonding curve config before launch
        IBondingCurve.BondingCurveConfig memory configBefore = bondingCurve
            .getBondingCurveConfig(token);
        console.log(
            "Tokens in bonding curve before launch:",
            configBefore.reserveBalance / 1e18
        );
        console.log(
            "Circulating supply before launch:",
            (bondingCurve.TOTAL_SUPPLY() - configBefore.reserveBalance) / 1e18
        );

        // Launch to DEX
        vm.prank(owner);
        address pool = bondingCurve.launchToDEX(token);

        assertTrue(pool != address(0), "Pool should be created");
        console.log("DEX pool created:", pool);

        // Verify post-launch state
        IBondingCurve.BondingCurveConfig memory configAfter = bondingCurve
            .getBondingCurveConfig(token);
        assertTrue(
            configAfter.isLaunched,
            "Token should be marked as launched"
        );

    }

    function _createParams(
        bytes32 salt
    ) internal view returns (ITokenLaunchpad.CreateParams memory) {
        return
            ITokenLaunchpad.CreateParams({
                name: "Test Token",
                symbol: "TEST",
                metadata: "Test metadata",
                fundingToken: IERC20(WBNB),
                salt: salt,
                valueParams: ITokenLaunchpad.ValueParams({
                    launchTick: -171_000,
                    graduationTick: -170_800,
                    upperMaxTick: 887_200,
                    fee: 10_000,
                    tickSpacing: 200,
                    graduationLiquidity: 800_000_000 ether
                }),
                isPremium: false,
                launchPools: new ILaunchpool[](0),
                launchPoolAmounts: new uint256[](0),
                creatorAllocation: 0,
                adapter: adapter
            });
    }

    function _executeTradesToThreshold(IERC20 token) internal {
        uint256 tradeAmount = 40 ether;
        uint256 trades = 0;

        while (!bondingCurve.shouldLaunchToDEX(token) && trades < 12) {
            address currentTrader = address(uint160(0x4000 + trades));
            vm.deal(currentTrader, tradeAmount + 1 ether);

            vm.prank(currentTrader);
            bondingCurve.buyTokens{value: tradeAmount}(token, tradeAmount, 0);

            trades++;
        }

        console.log("Executed trades:", trades);
    }

    function findValidTokenHash(
        string memory _name,
        string memory _symbol,
        address _creator,
        IERC20 _quoteToken
    ) internal view returns (bytes32) {
        // Get the runtime bytecode of WAGMIEToken
        bytes memory bytecode = type(WAGMIEToken).creationCode;

        // Maximum number of attempts to find a valid address
        uint256 maxAttempts = 100;

        for (uint256 i = 0; i < maxAttempts; i++) {
            bytes32 salt = keccak256(abi.encode(i));
            bytes32 saltUser = keccak256(
                abi.encode(salt, _creator, _name, _symbol)
            );

            // Calculate CREATE2 address
            bytes memory creationCode = abi.encodePacked(
                bytecode,
                abi.encode(_name, _symbol)
            );
            bytes32 hash = keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(launchpad),
                    saltUser,
                    keccak256(creationCode)
                )
            );
            address target = address(uint160(uint256(hash)));

            if (target < address(_quoteToken)) {
                console.log("Found valid salt after %d attempts", i + 1);
                return salt;
            }
        }

        revert(
            "No valid token address found after 100 attempts. Try increasing maxAttempts or using a different quote token."
        );
    }
}
