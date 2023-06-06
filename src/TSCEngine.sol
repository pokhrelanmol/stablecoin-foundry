// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 *@title TSCEngine
 *@author Anmol Pokhrel
 * The System is designed to maintain the price of TrieStableCoin at $1.It is backed by WBTC and WETH.
 * This is the core contract of the system.
 */

contract TSCEngine {
    function depositCollateralAndMintTSC() external payable returns (bool) {}

    function depositCollaterals() external payable returns (bool) {}

    function redeemCollateralForTsc() external returns (bool) {}

    function redeemCollateral() external returns (bool) {}

    function mintTsc() external returns (bool) {}

    function burnTsc() external returns (bool) {}

    function liquidate() external returns (bool) {}

    function getHealthFactor() external view returns (bool) {}
}
