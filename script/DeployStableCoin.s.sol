// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {BBSCEngine} from "src/BBSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployStableCoin is Script {
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function run() external returns( BallerBucksStablecoin, BBSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (string memory ccy, address ccyFeed, address wethFeed, address btcFeed , address weth, address btc,) = helperConfig.activeConfig();
        vm.startBroadcast();
        BallerBucksStablecoin stablecoin = new BallerBucksStablecoin();
        
        feedAddresses = [wethFeed, btcFeed];
        tokenAddresses = [weth, btc];
        
        BBSCEngine engine = new BBSCEngine(tokenAddresses, feedAddresses, address(stablecoin), ccyFeed, ccy);
        stablecoin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (stablecoin, engine, helperConfig);
    }
}
