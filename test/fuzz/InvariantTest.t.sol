// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DeployTSC} from "../../script/DeployTSC.s.sol";

import {TrieStableCoin} from "../../src/TrieStableCoin.sol";
import {TSCEngine} from "../../src/TSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtTSC} from "../mocks/MockMoreDebtTSC.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {Handler} from "../fuzz/HandlerTest.t.sol";

// what are invariants?
//1. The total suppy of Tsc should always be less then the collateral
//2. Getter and view function should never revert

contract InvariantsTest is StdInvariant, Test {
    DeployTSC deployer;
    TrieStableCoin tsc;
    TSCEngine tscEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        deployer = new DeployTSC();
        (tsc, tscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        weth = weth;
        wbtc = wbtc;
        handler = new Handler(tscEngine,tsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThenTotalSupply() public view {
        uint256 totalSupply = tsc.totalSupply();
        uint256 wethAmountInProtocol = IERC20(weth).balanceOf(address(tscEngine));
        uint256 wbtcAmountInProtocol = IERC20(wbtc).balanceOf(address(tscEngine));
        uint256 wethValueInUsd = tscEngine.getUsdValue(weth, wethAmountInProtocol);
        uint256 wbtcValueInUsd = tscEngine.getUsdValue(wbtc, wbtcAmountInProtocol);
        console.log("wethValueInUsd", wethValueInUsd);
        console.log("wbtcValueInUsd", wbtcValueInUsd);
        console.log("totalSupply", totalSupply);
        console.log("timeMintIsCalled", handler.timeMintIsCalled());
        assert(wethAmountInProtocol + wbtcAmountInProtocol >= totalSupply);
    }
}
