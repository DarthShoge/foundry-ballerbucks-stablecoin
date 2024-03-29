// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {BBSCEngine} from "src/BBSCEngine.sol";
import {DeployStableCoin} from "script/DeployStableCoin.s.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract BBSCEngineTests is Test {
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
 
    
    BBSCEngine public engine;
    BallerBucksStablecoin public stablecoin;
    HelperConfig public config;


    address weth;   
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public immutable OWNER = makeAddr("owner");
    address public immutable USER = makeAddr("user");

    function setUp() public  {
        vm.deal(USER, 1 ether);
        DeployStableCoin deployStableCoin = new DeployStableCoin();
        (stablecoin, engine, config) = deployStableCoin.run();
        (, ,ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeConfig();
        ERC20Mock(weth).mint(USER, COLLATERAL_AMOUNT);
    }

    function testBBSCEngineInitialisesProperly() public {
        assertEq(engine.getCcy(), "GBP");
    }

    //**************//
    // Price Tests //
    //************//
    function testGetUsdEthValue() public {
        uint256 ethAmount = 1e18;
        // 15e18 * 4000Eth/USD = 60,000
        uint256 expectedUsdValue = 4000e18;
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetCcyValue() public {
        uint256 ethAmount = 1e18;
        // 1e18 * 4000/1.27 Eth/GBP = 60,000
        uint256 expectedCcyValue = 3149e18;
        uint256 actualCcyValue = engine.getCcyValue(weth, ethAmount);
        assertEq(actualCcyValue, expectedCcyValue);
    }

    //*********************//
    // Deposit test        //
    //*********************//
    function testDepositRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);  
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);       

        vm.expectRevert(BBSCEngine.BBSCEngine__MustBeGreaterThanZero.selector);
        engine.depositCollateral(weth, 0);
    }


    function testDepositRevertsIfUnapprovedTokenUsed() public {
        vm.startPrank(USER);  
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__NotAllowedToken.selector, address(0)));
        engine.depositCollateral(address(0), COLLATERAL_AMOUNT);
    }
}