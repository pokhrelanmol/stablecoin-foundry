// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployTSC} from "../script/DeployTSC.s.sol";
import {TrieStableCoin} from "../src/TrieStableCoin.sol";
import {TSCEngine} from "../src/TSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract TSCEngineTest is Test {
    DeployTSC deployer;
    TrieStableCoin tsc;
    TSCEngine tscEngine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 1000 ether;

    function setUp() public {
        deployer = new DeployTSC();
        (tsc, tscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    /* ---------------------------- CONSTRUCTOR TESTS ---------------------------- */

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthNotEqualPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(TSCEngine.TSCEngine__TokenAddressAndPriceFeedAddressMustBeEqual.selector);
        new TSCEngine(tokenAddresses, priceFeedAddresses,address(tsc));
    }

    /* ------------------------------- PRICE TESTS ------------------------------ */

    function testGetUsdvalue() public {
        uint256 ethAmount = 15e18;
        //    15e18 * 2000 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = tscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; // using ether for decimals => 100 * 1e18
        // $2000 /ETH => 100/2000 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = tscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
    /**
     *
     * DEPOSIT COLLATERAL TEST *
     *
     */

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(tscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(TSCEngine.TSCEngine__MoreThanZero.selector);
        tscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnaprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(TSCEngine.TSCEngine__NotAllowedToken.selector);
        tscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(tscEngine), AMOUNT_COLLATERAL);
        tscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalTscMinted, uint256 collateralValueInUsd) = tscEngine.getAccountInformation(USER);
        uint256 expectedTotalTscMinted = 0;
        uint256 expectedCollateralValueInUsd = tscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(totalTscMinted, expectedTotalTscMinted);
    }

    function testTransferCollateralFromUserToContractUponDeposit() public depositedCollateral {
        uint256 updatedContractCollateralTokenBalance = ERC20Mock(weth).balanceOf(address(tscEngine));
        assertEq(updatedContractCollateralTokenBalance, AMOUNT_COLLATERAL);
    }

    /* ----------------------------- MINT_TSC TESTS ----------------------------- */

    function testRevertIfAmountTscToMintIsZero() public depositedCollateral {
        vm.expectRevert(TSCEngine.TSCEngine__MoreThanZero.selector);
        tscEngine.mintTsc(0);
    }

    function testRevertIfHealthFactorIsLowerThanOne() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(tscEngine), AMOUNT_COLLATERAL);
        // we know that in MockAggregatorV3 1 weth = $2000
        // so now we need to calculate the $ amount of TSC to mint
        // in our s_depositedCollateral = 10 * 2000 = 20000 USD
        // ETH/USD have 8 decimals so = 20000e8 * 1e10 = 20000e18
        uint256 amountTscToMint = 20000e18;
        tscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(TSCEngine.TSCEngine__BreaksHealthFactor.selector, 5e17)); //0.5 health factor
        tscEngine.mintTsc(amountTscToMint);
    }

    function testCanMintTsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(tscEngine), AMOUNT_COLLATERAL);
        uint256 amountTscToMint = 10000e18;
        tscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        tscEngine.mintTsc(amountTscToMint);
        uint256 expectedTscBalance = amountTscToMint;
        uint256 actualUserBalance = tsc.balanceOf(USER);
        assertEq(expectedTscBalance, actualUserBalance);
        vm.stopPrank();
    }
    /* --------------------------- CHECK HEALTH FACTOR -------------------------- */

    modifier depositedCollateralAndMintedTsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(tscEngine), AMOUNT_COLLATERAL);
        uint256 AMOUNT_TSC_TO_MINT = 100 ether;
        tscEngine.depositCollateralAndMintTSC(weth, AMOUNT_COLLATERAL, AMOUNT_TSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testGetCorrectHealthFactor() public depositedCollateralAndMintedTsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 actualHealthFactor = tscEngine.getUserHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedTsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $150 at all times if we have $100 of debt

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = tscEngine.getUserHealthFactor(USER);
        // $180 collateral / 200 debt = 0.9
        assert(userHealthFactor == 0.9 ether);
    }
}
