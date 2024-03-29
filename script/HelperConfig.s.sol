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

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        string ccy;
        address ccyUsdPriceFeed;
        address wethUsdPriceFeed;
        address btcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeConfig;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    int256 public constant DECIMALS = 8;
    int256 public constant GBP_PRICE = 127000000;
    int256 public constant WETH_PRICE = 400000000000;
    int256 public constant WBTC_PRICE = 70000000000000;
    constructor() {
        if (block.chainid == 11155111){
            activeConfig = getSepoliaEthConfig();
        } else {
            activeConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() internal view returns(NetworkConfig memory) {
        return NetworkConfig({
            ccy: "GBP",
            ccyUsdPriceFeed: 0x91FAB41F5f3bE955963a986366edAcff1aaeaa83,
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa,
            wbtc: 0xc778417E063141139Fce010982780140Aa0cD5Ab,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory) {
        if(activeConfig.wethUsdPriceFeed != address(0)){
            return activeConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator gbpUsdPriceFeed = new MockV3Aggregator(8, GBP_PRICE);
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(8, WETH_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(8, WBTC_PRICE);
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            ccy: "GBP",
            ccyUsdPriceFeed: address(gbpUsdPriceFeed),
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            btcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }


}