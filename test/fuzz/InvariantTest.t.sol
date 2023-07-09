// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DeployTSC} from "../../script/DeployTSC.s.sol";

import {TrieStableCoin} from "../../src/TrieStableCoin.sol";
import {TSCEngine} from "../../src/TSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtTSC} from "../mocks/MockMoreDebtTSC.sol";

import {Handler} from "../fuzz/HandlerTest.t.sol";

// what are invariants?
//1. The total suppy of Tsc should always be less then the collateral
//2. Getter and view function should never revert

contract InvariantsTest is StdInvariant, Test {
    DeployTSC deployer;
    TrieStableCoin tsc;
    TSCEngine tscEngine;
    HelperConfig helperConfig;
    ERC20Mock wethMock;
    ERC20Mock wbtcMock;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    Handler handler;

    function setUp() public {
        deployer = new DeployTSC();
        (tsc, tscEngine, helperConfig) = deployer.run();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) =
            helperConfig.activeNetworkConfig();
        ethUsdPriceFeed = MockV3Aggregator(wethUsdPriceFeed);
        btcUsdPriceFeed = MockV3Aggregator(wbtcUsdPriceFeed);
        wethMock = ERC20Mock(weth);
        wbtcMock = ERC20Mock(wbtc);
        handler = new Handler(tscEngine,tsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThenTotalSupply() public view {
        uint256 totalSupply = tsc.totalSupply();
        uint256 wethAmountInProtocol = wethMock.balanceOf(address(tscEngine));
        uint256 wbtcAmountInProtocol = wbtcMock.balanceOf(address(tscEngine));
        uint256 wethValueInUsd = tscEngine.getUsdValue(address(wethMock), wethAmountInProtocol);
        uint256 wbtcValueInUsd = tscEngine.getUsdValue(address(wbtcMock), wbtcAmountInProtocol);
        // uint256 totalValueInProtocol = wethValueInUsd + wbtcValueInUsd;
        assert(wethAmountInProtocol + wbtcAmountInProtocol >= totalSupply);
    }
}
