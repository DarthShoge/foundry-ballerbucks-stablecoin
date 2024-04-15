//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

//What are out invariants?

// 1. The total supply of  BBSC should be less than the total value of collateral

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {BBSCEngine} from "src/BBSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployStableCoin} from "script/DeployStableCoin.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    BallerBucksStablecoin public stableCoin;
    BBSCEngine public engine;
    HelperConfig public config;
    Handler public handler;
    address public weth;
    address public wbtc;

    function setUp() public {
        DeployStableCoin deployStableCoin = new DeployStableCoin();
        (stableCoin, engine, config) = deployStableCoin.run();
        handler = new Handler(engine, stableCoin);
        (,,,, weth, wbtc,) = config.activeConfig();
        targetContract(address(handler));
    }


    function invariant_protocolMustHaveMoreDepositsThanValue() public view {
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 totalWethDeposits = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposits = IERC20(wbtc).balanceOf(address(engine));
        
        uint256 wethValue = engine.getCcyValue(weth, totalWethDeposits);
        uint256 wbtcValue = engine.getCcyValue(wbtc, totalWbtcDeposits);

        console.log("Times Mint is called: ", handler.timesMintIsCalled());
        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("Total Supply: ", totalSupply);


        assert(wethValue + wbtcValue >= totalSupply);
    }
}
