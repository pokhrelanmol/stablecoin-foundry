// SPDX-License-Identifier: MIT
// handler is going to narrow down the function call
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {TSCEngine} from "../../src/TSCEngine.sol";
import {TrieStableCoin} from "../../src/TrieStableCoin.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    // don't call redeem collateral unless there is collateral
    TSCEngine tscEngine;
    TrieStableCoin tsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint96 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(TSCEngine _tscEngine, TrieStableCoin _tsc) public {
        tscEngine = _tscEngine;
        tsc = _tsc;
        address[] memory collateralTokens = tscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(tscEngine), amountCollateral);
        tscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintTsc(uint256 amount) public {
        (uint256 totalTscMinted, uint256 collateralValueInUsd) = tscEngine.getAccountInformation(msg.sender);
        int256 maxTscToMint = (int256(collateralValueInUsd) / 2) - int256(totalTscMinted);
        if (maxTscToMint < 0) {
            return;
        }
        amount = bound(amount, 1, uint256(maxTscToMint));
        tscEngine.mintTsc(amount);
    }

    // function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateral = tscEngine.getCollateralBalOfUser(msg.sender, address(collateral));

    //     amountCollateral = bound(amountCollateral, 0, maxCollateral);
    //     if (amountCollateral == 0) {
    //         return;
    //     }
    //     tscEngine.redeemCollateral(address(collateral), amountCollateral);
    // }

    //     helper functions

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
