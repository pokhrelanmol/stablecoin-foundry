// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployTSC} from "../script/DeployTSC.s.sol";
import {TrieStableCoin} from "../src/TrieStableCoin.sol";
import {TSCEngine} from "../src/TSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";

contract TSCEngineTest is Test {
    DeployTSC deployer;
    TrieStableCoin tsc;
    TSCEngine tscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 1000 ether;

    function setUp() public {
        deployer = new DeployTSC();
        (tsc, tscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testGetUsdvalue() public {
        uint256 ethAmount = 15e18;
        //    15e18 * 2000 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = tscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
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
}
