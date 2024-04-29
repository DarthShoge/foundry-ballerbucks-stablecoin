// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {BBSCEngine} from "src/BBSCEngine.sol";
import {DeployStableCoin} from "script/DeployStableCoin.s.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20RevertableMock} from "test/mocks/ERC20Mock.sol";
import {Vm} from "forge-std/Vm.sol";

contract BBSCEngineTests is Test {
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant ONE_ETH_IN_GBP = 3149;
    uint256 public constant ONE_ETH_IN_GBP_E18 = 3149e18;
    uint256 public constant ONE_ETH_IN_USD_E18 = 4000e18;
 
    
    BBSCEngine public engine;
    BallerBucksStablecoin public stablecoin;
    HelperConfig public config;
    string public ccy;

    address weth;   
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address ccyUsdPriceFeed;

    address public immutable OWNER = makeAddr("owner");
    address public immutable USER = makeAddr("user");
    address public immutable LIQUIDATOR = makeAddr("liquidator");

    modifier depositedCollateral(uint256 amount) {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
        _;
    }

    modifier mintedBBSC(uint256 amount) {
        vm.startPrank(USER);
        engine.mintBBSC(amount);
        vm.stopPrank();
        _;
    }

    modifier transitionFeedPrice(address priceFeed, int256  newPrice) {
        vm.warp(block.timestamp + 1 hours);
        MockV3Aggregator(priceFeed).updateAnswer(newPrice);
        _;
    }

    function setUp() public  {
        vm.deal(USER, 10 ether);
        DeployStableCoin deployStableCoin = new DeployStableCoin();
        (stablecoin, engine, config) = deployStableCoin.run();
        (ccy, ccyUsdPriceFeed, ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeConfig();
        ERC20Mock(weth).mint(USER, COLLATERAL_AMOUNT);
        ERC20Mock(wbtc).mint(USER, COLLATERAL_AMOUNT);

    }

    //********************//
    // Constructor Tests  //
    //********************//
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testInitialiseEngineFeedsWithInconsistentLengths() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUsdPriceFeed);
        feedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(BBSCEngine.BBSCEngine__TokenPriceFeedsMustBeEqualLength.selector);
        new BBSCEngine(tokenAddresses, feedAddresses, address(stablecoin), ccyUsdPriceFeed, ccy);
    }

    function testBBSCEngineInitialisesProperly() public {
        assertEq(engine.getCcy(), "GBP");
    }

    //**************//
    // Price Tests  //
    //**************//
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
        uint256 expectedCcyValue = ONE_ETH_IN_GBP_E18;
        uint256 actualCcyValue = engine.getCcyValue(weth, ethAmount);
        assertEq(actualCcyValue, expectedCcyValue);
    }

    function testGetCollateralValue() depositedCollateral(1 ether) public {
        // 1e18 * 4000/1.27 Eth/GBP = 60,000
        uint256 expectedCcyValue = ONE_ETH_IN_GBP_E18;
        uint256 actualCcyValue = engine.getCollateralValue(USER);
        assertEq(actualCcyValue, expectedCcyValue);
    }

    function testGetCollateralUsdValue() depositedCollateral(1 ether) public {
        // 1e18 * 4000 Eth/USD = 4000
        uint256 expectedUsdValue = ONE_ETH_IN_USD_E18;
        uint256 actualUsdValue = engine.getCollateralUsdValue(USER);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromCcy() public {
        // 1e18 * 4000/1.27 Eth/GBP = 60,000
        uint256 ccyAmount = ONE_ETH_IN_GBP_E18;
        // 60,000 / 4000 = 15e18
        uint256 expectedTokenAmount = 1e18;
        uint256 actualTokenAmount = engine.getTokenAmountFromCcy(weth, ccyAmount);
        assertEq(actualTokenAmount, expectedTokenAmount);
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
        ERC20Mock fakeToken = new ERC20Mock();
        fakeToken.mint(USER, COLLATERAL_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__NotAllowedToken.selector, address(fakeToken)));
        vm.prank(USER);
        engine.depositCollateral(address(fakeToken), COLLATERAL_AMOUNT);
    }

    function testCanDepositAndGetAccountInfo() public depositedCollateral(COLLATERAL_AMOUNT) {
        vm.prank(USER);
        (uint256 debt, uint256 collateral) = engine.getAccountInfo();
        assertEq(debt, 0);
        // 10 eth collateral = 10 * 1e18 = 10e18
        // 1 eth in gbp = 3149
        // 10 eth * 3149 = 31490e18 gbp
        assertEq(collateral, ONE_ETH_IN_GBP * COLLATERAL_AMOUNT);
    }

    //**********************//
    // Redeem tests         //
    //**********************//

    function testRedeemRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__MustBeGreaterThanZero.selector));
        engine.redeemCollateral(weth,0);
    }

    function testRedeemRevertsIfUnapprovedTokenUsed() public {
        ERC20Mock fakeToken = new ERC20Mock();
        fakeToken.mint(USER, COLLATERAL_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__NotAllowedToken.selector, address(fakeToken)));
        vm.prank(USER);
        engine.redeemCollateral(address(fakeToken), COLLATERAL_AMOUNT);
    }

    function testCanRedeemAndGetAccountInfo() public depositedCollateral(COLLATERAL_AMOUNT) {
        vm.prank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        (uint256 debt, uint256 collateral) = engine.getAccountInfo();
        assertEq(debt, 0);
        assertEq(collateral, 0);
    }

    function testShouldEmitOnRedeem() public depositedCollateral(COLLATERAL_AMOUNT) {
        vm.recordLogs();
        vm.prank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // assertEq(logs.length, 1);
        bytes32 expectedEventSignature = keccak256("CollateralRedeemed(address,address,address,uint256)");
        bytes32 expectedAddressInTopic = bytes32(uint256(uint160(USER)));
        assertEq(logs[0].topics[0], expectedEventSignature);
        assertEq(logs[0].topics[1], expectedAddressInTopic);
        assertEq(logs[0].topics[2], expectedAddressInTopic);
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(weth))));
        (uint256 eventAmount) = abi.decode(logs[0].data, (uint256));
        assertEq(eventAmount, COLLATERAL_AMOUNT);
    }

    // function testShouldRevertIfTransferFailed() public depositedCollateral(COLLATERAL_AMOUNT) {
    //     ERC20RevertableMock(weth).setRevert(true);
    //     vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__TransferFailed.selector));
    //     vm.prank(USER);
    //     engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
    // }

    //*********************//
    // Mint tests          //
    //*********************//

    function testMintRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__HealthFactorBroken.selector, 0));
        engine.mintBBSC(100);
    }


    function testCanDepositAndMintBBSCAndGetAccountInfo()  
        public 
        depositedCollateral(COLLATERAL_AMOUNT)
        mintedBBSC(ONE_ETH_IN_GBP_E18)
        {
        vm.prank(USER);
        (uint256 debt, uint256 collateral) = engine.getAccountInfo();
        assertEq(debt, ONE_ETH_IN_GBP_E18);
        assertEq(collateral, ONE_ETH_IN_GBP * COLLATERAL_AMOUNT);
    }

    function testCanDepositAndMintSingularBBSCAndGetAccountInfo() 
        public 
        {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMint(weth, COLLATERAL_AMOUNT, ONE_ETH_IN_GBP);
        (uint256 debt, uint256 collateral) = engine.getAccountInfo();
        vm.stopPrank();
        assertEq(debt, ONE_ETH_IN_GBP);
        assertEq(collateral, ONE_ETH_IN_GBP * COLLATERAL_AMOUNT);
    }
    
    //*********************//
    // Burn tests          //
    //*********************//

    function testBurnRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__MustBeGreaterThanZero.selector));
        engine.burnBBSC(0);
    }

    function testBBSCMintedisZeroAfterBurn() 
        depositedCollateral(COLLATERAL_AMOUNT)
        mintedBBSC(ONE_ETH_IN_GBP)
        public {
        vm.startPrank(USER);
        BallerBucksStablecoin(stablecoin).approve(address(engine), ONE_ETH_IN_GBP);
        engine.burnBBSC(ONE_ETH_IN_GBP);
        (uint256 debt, uint256 collateral) = engine.getAccountInfo();
        vm.stopPrank();
        
        assertEq(debt, 0);
        assertEq(collateral, ONE_ETH_IN_GBP * COLLATERAL_AMOUNT);
    }

    //*********************//
    // Health Factor Tests //
    //*********************//

    function testHealthFactorIsCorrectWhenAtLiquidationBoundry() 
        depositedCollateral(2 ether) 
        mintedBBSC(ONE_ETH_IN_GBP_E18)
        public {
        uint256 expectedHealthFactor = 1e18;
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testHealthFactorIsCorrectWhenFarFromLiquidationBoundry() 
        depositedCollateral(10 ether) 
        mintedBBSC(ONE_ETH_IN_GBP_E18)
        public {
        uint256 expectedHealthFactor = 5e18;
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    //*********************//
    // Liquidation Tests   //
    //*********************//

    function testCallingLiquidateWithNoDebtsReverts() 
        depositedCollateral(2 ether) 
        mintedBBSC(ONE_ETH_IN_GBP)
        transitionFeedPrice(ethUsdPriceFeed, 200000000000)
        public {
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__MustBeGreaterThanZero.selector));
        vm.prank(USER);
        engine.liquidate(weth,USER, 0);
    }


    function testLiquidationRevertsIfHealthFactorIsAboveBoundry() 
        depositedCollateral(10 ether) 
        mintedBBSC(ONE_ETH_IN_GBP)
        transitionFeedPrice(ethUsdPriceFeed, 200000000000)
        public {
        vm.expectRevert(abi.encodeWithSelector( BBSCEngine.BBSCEngine__HealthFactorOk.selector));
        vm.prank(LIQUIDATOR);
        engine.liquidate(weth,USER, 1);
    }

    // function testLiquidationExecutesIfHealthFactorIsBelowBoundry() 
    //     depositedCollateral(2 ether) 
    //     mintedBBSC(ONE_ETH_IN_GBP_E18)
    //     transitionFeedPrice(ethUsdPriceFeed, 200000000000)
    //     public {
    //     console.log("Health Factor: ", engine.getHealthFactor(USER));
    //     uint256 collateralToCover = 2 ether;

    //     vm.startPrank(LIQUIDATOR);
    //     ERC20Mock(weth).approve(address(engine), collateralToCover);
    //     BallerBucksStablecoin(stablecoin).approve(address(engine), ONE_ETH_IN_GBP_E18);
    //     stablecoin.approve(address(engine), ONE_ETH_IN_GBP_E18);

    //     engine.liquidate(weth,USER, (ONE_ETH_IN_GBP_E18/2));
    //     vm.stopPrank();

    //     vm.prank(USER);
    //     (uint256 debt, uint256 collateral) = engine.getAccountInfo();
    //     assertEq(debt, 0);
    //     assertEq(collateral, 0);
    // }

    
  function testCantLiquidateGoodHealthFactor() public
        depositedCollateral(10 ether) 
        mintedBBSC(ONE_ETH_IN_GBP) {
        uint256 collateralToCover = 20 ether;
        uint256 amountToMint = 100 ether;
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMint(weth, collateralToCover, amountToMint);
        stablecoin.approve(address(engine), amountToMint);

        vm.expectRevert(BBSCEngine.BBSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated(uint256 amountCollateral ,uint256 amountToMint,uint256 collateralToCover,int256 ethUsdUpdatedPrice) {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMint(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMint(weth, collateralToCover, amountToMint);
        stablecoin.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    //USER -> 10 ETH collateral and 3149 GBP Debt @ 4000 USDETH / 3149 GBPETH
    //ETH price plummets to 500 USDETH thus USER collateral is worth (500/1.27) * 10 = 3937 GBP vs 3149 GBP debt
    //USER Health Factor = (3937 * 0.5) / 3149 = 0.62 😡 (Hombre finna get likkidated)
    //LIQUIDATOR : 20 ETH (~7874 GBP) collateral to cover against USER debt of 3149 GBP 
    //LIQUIDATOR Health Factor = (7874 * 0.5) / 3149 = 1.25 😎 (Hombre finna get paid)
    //LIQUIDATOR gets collateral of (debt: 3149 GBP / gbp-per-eth: (500/1.27)) = ~ 8 ETH
    //LIQUIDATOR gets 10% bonus on liquidation = 8 * 1.1 = 8.8 ETH
    function testLiquidationPayoutIsCorrect() 
        public 
        liquidated(COLLATERAL_AMOUNT, ONE_ETH_IN_GBP_E18, COLLATERAL_AMOUNT*2, 500e8) {
        // liquidated(10 ether, amountToMint, 20 ether, 18e8) {
            uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
            uint256 expectedWeth = engine.getTokenAmountFromCcy(weth, ONE_ETH_IN_GBP_E18)
                + (engine.getTokenAmountFromCcy(weth, ONE_ETH_IN_GBP_E18) / engine.getLiquidationBonus());
            uint256 hardCodedExpected = 8813994910941475825;
            assertEq(liquidatorWethBalance, hardCodedExpected);
            assertEq(liquidatorWethBalance, expectedWeth);
    }

}