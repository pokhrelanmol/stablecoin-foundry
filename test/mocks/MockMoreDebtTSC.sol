// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {MockV3Aggregator} from ".//MockV3Aggregator.sol";

/**
 * @title MockMoreDebtTSC
 * @author Anmol Pokhrel
 * collateral:Exegeneous(ETH & BTC)
 * Minting: Algorithmic
 * Relative: Pegged(USD)
 * This contract is meant to be governed by TSCEngine.
 */
contract MockMoreDebtTSC is ERC20Burnable, Ownable {
    error TrieStableCoin__BurnAmountExceedsBalance();
    error TrieStableCoin__AmountMustBeMoreThanZero();
    error TrieStableCoin__NotZeroAddress();

    address mockAggregator;

    constructor(address _mockAggregator) ERC20("TrieStableCoin", "TSC") Ownable(msg.sender) {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 _amount) public override onlyOwner {
        // crash the price
        MockV3Aggregator(mockAggregator).updateAnswer(0);
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert TrieStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert TrieStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert TrieStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert TrieStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
