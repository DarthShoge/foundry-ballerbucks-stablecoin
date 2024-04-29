// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title OracleLib
 * @notice This library is used to interact with to check chainlink for stale data
 * 
 * We want the engine to freeze if the data is stale
 */
library OracleLib {
    error OracleLib__StaleData();
    uint256 constant TIME_OUT = 3 hours;

    function stalePriceCheck( AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
        {
            (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

            uint256 secondsSinceUpdate = block.timestamp - updatedAt;
            if (secondsSinceUpdate > TIME_OUT) revert OracleLib__StaleData();
            return (roundId, price, startedAt, updatedAt, answeredInRound);
        }

}