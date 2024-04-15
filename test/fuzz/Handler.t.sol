// SPDX-License_Identifier: MIT 


pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {BBSCEngine} from "src/BBSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";



contract Handler is Test {
    BBSCEngine public engine;
    BallerBucksStablecoin public bbsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    uint256 public timesMintIsCalled = 0;
    mapping(address => bool) public usersWithCollateral;

    uint256 constant MAX_DEPOSIT = type(uint96).max;


    constructor(BBSCEngine _engine, BallerBucksStablecoin _bbsc) {
        engine = _engine;
        bbsc = _bbsc;
        address[] memory addresses = engine.getCollateralTokens();

        weth = ERC20Mock(addresses[0]);
        wbtc = ERC20Mock(addresses[1]);
    }

    function depositCollateral(uint256 collateralSeed ,uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed); 
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        usersWithCollateral[msg.sender] = true;
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);  
        uint256 maxAmount = engine.getUserCollateralBalance(address(collateral));
        maxAmount = bound(amount, 0, maxAmount);
        if(maxAmount == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), maxAmount);
    }

    function mintBbsc(uint256 amount) public {
        if(!usersWithCollateral[msg.sender]) {
            return;
        }

        (uint256 totalMinted, uint256 collateralGBPValue) = engine.getUserAccountInfo(msg.sender);
        int256 maxMintable =  (int256(collateralGBPValue) / 2) - int256(totalMinted);
        amount = bound(amount, 0, uint256(maxMintable));
        if(amount <= 0) {
            return;
        }
        timesMintIsCalled++;
        vm.startPrank(msg.sender);
        engine.mintBBSC(amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;    
        }
    }
}