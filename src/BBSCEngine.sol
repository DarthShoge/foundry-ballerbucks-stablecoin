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

import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/**
 * @title BBSCEngine
 * @author @darthshoge.
 * 
 * The system s designed to be as minimal as possible, and have the tokens maintain a peg to the GBP or another chainlink currency feed.
 * this stablecoin has the properties:
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Stability: Pegged to GBP
 * 
 * This system should always be overcollateralized, and the collateral vs debt ratio should never at any point be less than 1.
 * 
 * It is similar to DAI if DAI had no governance, no fees, was pegged to GBP, and was backed by BTC and ETH.
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming BBSCTokens.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract BBSCEngine is ReentrancyGuard {
    //Errors
    error BBSCEngine__MustBeGreaterThanZero();
    error BBSCEngine__TokenPriceFeedsMustBeEqualLength();
    error BBSCEngine__NotAllowedToken(address tokenAddress);
    error BBSCEngine__DepositFailed(); 
    error BBSCEngine__TransferFailed(); 
    error BBSCEngine__MintFailed();
    error BBSCEngine__HealthFactorBroken(uint256 healthFactor); 
    error BBSCEngine__HealthFactorOk(); 
    error BBSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    // Types
    using OracleLib for AggregatorV3Interface;

    //State Variables
    uint256 private constant FEED_PRECISION = 1e8;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    string private s_crossCcy;
    mapping(address token => address priceFeed) private s_tokenPriceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_userCollateral;
    mapping(address user => uint256 amountBBSCMinted) private s_BBSCMinted; 
    address private immutable i_crossCcyFeed;
    BallerBucksStablecoin private immutable i_bbsc;
    address[] private s_collateralTokens;

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    //Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert BBSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_tokenPriceFeeds[_tokenAddress] == address(0)) {
            revert BBSCEngine__NotAllowedToken(_tokenAddress);
        }
        _;
    }

    //Functions

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address bbscAddress,
        address ccyCrossFeed,
        string memory ccy
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert BBSCEngine__TokenPriceFeedsMustBeEqualLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_tokenPriceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        s_crossCcy = ccy;
        i_crossCcyFeed = ccyCrossFeed;
        i_bbsc = BallerBucksStablecoin(bbscAddress);
    }


    /**
     * @notice This function allows the user to deposit collateral into the system.
     * @param tokenCollateralAddress The address of the token to be deposited as collateral.
     * @param collateralAmount The amount of collateral to be deposited.
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount) public  
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant{
        s_userCollateral[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert BBSCEngine__DepositFailed();
        }

    }


    /**
     * @notice This function allows the user to deposit collateral and mint BBSCTokens.
     * @param tokenCollateralAddress The address of the token to be deposited as collateral.
     * @param amountCollateral The amount of collateral to be deposited.
     * @param amountStableToMint The amount of BBSCTokens to mint.
     * @notice they must have more collateral value than the minimum threshold.
     */ 
    function depositCollateralAndMint(address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountStableToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintBBSC(amountStableToMint);
        }

    /*
    * @notice This function allows the user to redeem collateral and burn BBSCTokens.
    * @param tokenCollateralAddress The address of the token to be redeemed as collateral.
    * @param amount The amount of collateral to be redeemed.
    * @param bbscToBurn The amount of BBSCTokens to burn.
    * @notice they must have more collateral value than the minimum threshold.
    */
    function redeemCollateralForBBSCTokens(address tokenCollateralAddress, uint256 amount, uint256 bbscToBurn) 
        public {
        burnBBSC(bbscToBurn);
        redeemCollateral(tokenCollateralAddress, amount);
    }

    // in order to redeem collateral, the user must have more collateral value than the minimum threshold.	
    //1. health factor must be greater than 1 after redeeming collateral
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public
        moreThanZero(amountCollateral)  
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
        {
            _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        }

    /**
     * @notice This function allows the user to mint BBSCTokens by depositing collateral.
     * @param amountToMint The amount of BBSCTokens to mint.
     * @notice they must have more collateral value than the minimum threshold.
     */
    function mintBBSC(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_BBSCMinted[msg.sender] += amountToMint;   

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_bbsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert BBSCEngine__MintFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    function burnBBSC(uint256 amount) public {
        _burnBBSC(amount, msg.sender, msg.sender);
    }


    /*
     * @notice This function allows anyone to liquidate a user aka call redeemCollateralForBBSC on the users behalf 
        * @param collateral The address of the token to be redeemed as collateral.
        * @param user The address of the user to be liquidated.
        * @param debtToCover The amount of BBSCTokens to burn.
        * @notice you can partially liquidate a user
        * @notice you will get a liquidation bonus for helping the system purge
        * Follows CEI
     */
    function liquidate(address collateral, address user, uint256 debtToCover) 
        public  
        moreThanZero(debtToCover) 
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert BBSCEngine__HealthFactorOk();
        }
        // We want tot burn their BBSC debt and take their collateral
        // Unhealthy user: £140 ETH, £100 BBSC -> debt to cover £100
        // liquidator get 10% bonus thus: we give them £110 worth of collateral for BBSC
        // which we then burn. The remaining £30 worth of collateral is moved to the treasury
        uint256 collateralToLiquidate = getTokenAmountFromCcy(collateral, debtToCover);
        uint256 bonusCollateral = (collateralToLiquidate * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = collateralToLiquidate + bonusCollateral;
        console.log("Collateral to liquidate: ", collateralToLiquidate);
        console.log("Bonus collateral: ", bonusCollateral);
        console.log("Total collateral to redeem: ", totalCollateralToRedeem);
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnBBSC(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert BBSCEngine__HealthFactorNotImproved(endingHealthFactor);
        }
    }

    //*****************************//
    // private/internal functions  //
    //*****************************//

    function _burnBBSC(uint256 amount, address onBehalfOf, address from) 
        moreThanZero(amount) 
        private {
        s_BBSCMinted[onBehalfOf] -= amount;
        
        bool success = i_bbsc.transferFrom(from, address(this), amount);
        if (!success) {

            revert BBSCEngine__TransferFailed();
        }
        i_bbsc.burn(amount);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_userCollateral[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success= IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success) {
            revert BBSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns(uint256 totalMinted, uint256 collateralGBPValue) {
        totalMinted = s_BBSCMinted[user];
        collateralGBPValue = getCollateralValue(user);
    }

    function _healthFactor(address user) private view returns(uint256) {
        (uint256 totalMinted, uint256 collateralCcyValue) = _getAccountInformation(user);

        if(totalMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold = (collateralCcyValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalMinted;
        // return collateralGBPValue / totalMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert BBSCEngine__HealthFactorBroken(healthFactor);
        }
    }

    //*****************************//
    // public and external views   //
    //*****************************//
    function getCollateralValue(address user) public view returns(uint256 totalCollateralValue) {
        for( uint256 i= 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_userCollateral[user][token];
            if(collateralAmount > 0){
                totalCollateralValue += getCcyValue(token, collateralAmount);
            }
        }
    }

    function getCollateralUsdValue(address user) public view returns(uint256 totalCollateralValue) {
        for( uint256 i= 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_userCollateral[user][token];
            totalCollateralValue += getUsdValue(token, collateralAmount);
        }
    }


    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenPriceFeeds[token]);
        (, int price, , , ) = priceFeed.stalePriceCheck();
        return ((uint256(price) *  ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }

    function getTokenAmountFromCcy(address token, uint256 ccyAmountInWei) public view returns(uint256) {
        AggregatorV3Interface tokenPriceFeed = AggregatorV3Interface(s_tokenPriceFeeds[token]);
        (, int tokenPrice, , , ) = tokenPriceFeed.stalePriceCheck();
        AggregatorV3Interface crossPriceFeed = AggregatorV3Interface(i_crossCcyFeed);
        (, int crossPrice, , , ) = crossPriceFeed.stalePriceCheck();
        uint256 price = (uint256(tokenPrice) / uint256(crossPrice)) * FEED_PRECISION;
        return ((ccyAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getCcyValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface tokenPriceFeed = AggregatorV3Interface(s_tokenPriceFeeds[token]);
        (, int tokenPrice, , , ) = tokenPriceFeed.stalePriceCheck();
        AggregatorV3Interface crossPriceFeed = AggregatorV3Interface(i_crossCcyFeed);
        (, int crossPrice, , , ) = crossPriceFeed.stalePriceCheck();
        uint256 price = (uint256(tokenPrice) / uint256(crossPrice)) * FEED_PRECISION;
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }

    function getUserAccountInfo(address user) external view returns(uint256 totalMinted, uint256 collateralGBPValue) {
        return _getAccountInformation(user);
    }

    //*****************************//
    // getters                     //
    //*****************************//

    function getAccountInfo() external view returns(uint256 totalMinted, uint256 collateralGBPValue) {
        return _getAccountInformation(msg.sender);
    }

    function getCcy() public view returns(string memory) {
        return s_crossCcy;
    }

    function getBBSCMinted() public view returns(uint256) {
        return s_BBSCMinted[msg.sender];
    }

    function getHealthFactor(address user) public view returns(uint256) {
        return _healthFactor(user);
    }

    function getLiquidationBonus() public pure returns(uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokens() public view returns(address[] memory) {
        return s_collateralTokens;
    }

    function getUserCollateralBalance(address collateral) public view returns(uint256) {
        return s_userCollateral[msg.sender][collateral];
    }

    function getCollateralFeed(address token) public view returns(address) {
        return s_tokenPriceFeeds[token];
    }

    function getCcyFeed() public view returns(address) {
        return i_crossCcyFeed;
    }

}