// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {TrieStableCoin} from "../src/TrieStableCoin.sol";
import {TSCEngine} from "../src/TSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployTSC is Script {
    address[] priceFeedAddresses;
    address[] collateralAddresses;

    function run() external returns (TrieStableCoin, TSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, ) =
            helperConfig.activeNetworkConfig();
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        collateralAddresses = [weth, wbtc];

        vm.startBroadcast();
        TrieStableCoin tsc = new TrieStableCoin();
        TSCEngine tscEngine = new TSCEngine(collateralAddresses,priceFeedAddresses,address(tsc));
        tsc.transferOwnership(address(tscEngine));
        vm.stopBroadcast();
        return (tsc, tscEngine, helperConfig);

        // in order to mint we need to figure out the deposited collateral and its USD value and on the basis of that we gotta mint the token lets say 70% of collateral
    }
}
