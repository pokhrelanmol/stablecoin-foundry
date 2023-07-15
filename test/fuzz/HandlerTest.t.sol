// SPDX-License-Identifier: MIT
// handler is going to narrow down the function call
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {TSCEngine} from "../../src/TSCEngine.sol";
import {TrieStableCoin} from "../../src/TrieStableCoin.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    // don't call redeem collateral unless there is collateral
    TSCEngine tscEngine;
    TrieStableCoin tsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint96 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] usersWithCollateralDeposited;
    uint256 public timeMintIsCalled;
    MockV3Aggregator ethUsdPriceFeed;

    constructor(TSCEngine _tscEngine, TrieStableCoin _tsc) {
        tscEngine = _tscEngine;
        tsc = _tsc;
        address[] memory collateralTokens = tscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(tscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    // function mintTsc(uint256 amount, uint256 addressSeed) public {
    //     if (usersWithCollateralDeposited.length == 0) {
    //         return;
    //     }
    //     address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
    //     (uint256 totalTscMinted, uint256 collateralValueInUsd) = tscEngine.getAccountInformation(sender);

    //     int256 maxTscToMint = (int256(collateralValueInUsd) / 2) - int256(totalTscMinted);
    //     if (maxTscToMint < 0) {
    //         return;
    //     }
    //     amount = bound(amount, 0, uint256(maxTscToMint));
    //     if (amount == 0) {
    //         return;
    //     }
    //     vm.startPrank(sender);
    //     tscEngine.mintTsc(amount);
    //     vm.stopPrank();
    //     timeMintIsCalled++;
    // }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(tscEngine), amountCollateral);
        tscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = tscEngine.getCollateralBalOfUser(msg.sender, address(collateral));

        // amountCollateral = bound(amountCollateral, 1, maxCollateral); // we could have added this line bcoz we don't want user to redeem zero but maxCollateral can me zero sometimes so the bound function through error. just to satisfy the bound function we have added the below line
        vm.prank(msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) {
            return;
        }
        tscEngine.redeemCollateral(address(collateral), amountCollateral);
    }
    // this breaks if price falls so quickl
    //  function updateCollateralPrice(uint96 newPrice) public{
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);

    //  }
    //     helper functions

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
