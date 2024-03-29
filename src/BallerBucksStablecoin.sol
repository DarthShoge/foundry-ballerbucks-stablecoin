// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import { ERC20, ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BallerBucksStablecoin
 * @author @darthshoge.
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Stability: Pegged to GBP
 *    
 * This is contract is governed by the BBSCEngine. This contract is the ERC20 implementaiton of the BallerBucksStablecoin system.
 */
contract BallerBucksStablecoin is ERC20Burnable, Ownable {

    error BallerBucksStablecoin__MustBeGreaterThanZero();
    error BallerBucksStablecoin__BurnAmountExceedsBalance();
    error BallerBucksStablecoin__NotZeroAdress();

    string public constant NAME = "BallerBucksStablecoin";
    string public constant SYMBOL = "BBSC";
    uint8 public constant DECIMALS = 18;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**uint256(DECIMALS);

    constructor() ERC20(NAME, SYMBOL) Ownable(msg.sender) {
    } 

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if(_amount <= 0){
            revert BallerBucksStablecoin__MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert BallerBucksStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if(_to == address(0)){
            revert BallerBucksStablecoin__NotZeroAdress();
        }
        if(_amount <= 0){
            revert BallerBucksStablecoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}