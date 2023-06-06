// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
      * @title TrieStableCoin     
      * @author Anmol Pokhrel
      * collateral:Exegeneous(ETH & BTC)
      * Minting: Algorithmic
      * Relative: Pegged(USD)
      * This contract is meant to be governed by TSCEngine.
    
 */
contract TrieStableCoin is ERC20Burnable, Ownable {
    error TrieStableCoin__MustBeMoreThanZero();
    error TrieStableCoin__BurnAmountExceedsBalance();
    error TrieStableCoin__NotZeroAddress();

    constructor() public ERC20("TrieStabeCoin", "TSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert TrieStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert TrieStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert TrieStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert TrieStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
