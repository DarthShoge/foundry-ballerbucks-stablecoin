// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {BallerBucksStablecoin} from "src/BallerBucksStablecoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BallerBucksStableCoinTests is Test {
    BallerBucksStablecoin public stablecoin;
    address public immutable OWNER = makeAddr("owner");
    address public immutable USER = makeAddr("user");
    uint256 public constant AMOUNT = 100;

    modifier mintsBalance(uint256 amount, address account) {
        vm.prank(OWNER);
        stablecoin.mint(account, amount);
        _;
        
    }

    function setUp() public {
        // DeployStableCoin deployStableCoin = new DeployStableCoin();
        
        vm.deal(OWNER, 1 ether);
        vm.prank(OWNER);
        stablecoin= new BallerBucksStablecoin();    
        }

    function testOwnerCanMint() public mintsBalance(100, USER){
        assertEq(stablecoin.balanceOf(USER), 100);
        assertEq(stablecoin.totalSupply(), 100);
    }

    function testUserCannotMint() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER)
            );
        stablecoin.mint(USER, 100);
        assertEq(stablecoin.balanceOf(USER), 0);
    }

    function testCannotMintZeroAmount() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BallerBucksStablecoin.BallerBucksStablecoin__MustBeGreaterThanZero.selector)
            );
        stablecoin.mint(USER, 0);
        assertEq(stablecoin.balanceOf(USER), 0);
    }

    function testCannotMintToZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BallerBucksStablecoin.BallerBucksStablecoin__NotZeroAdress.selector)
            );
        stablecoin.mint(address(0), 100);
        assertEq(stablecoin.balanceOf(address(0)), 0);
    }

    function testCannotBurnWithNoBalance() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BallerBucksStablecoin.BallerBucksStablecoin__BurnAmountExceedsBalance.selector)
            );
        stablecoin.burn(100);
    }

    function testCanBurnHeldBalance() public mintsBalance(100, OWNER) {
        uint256 amount = 100;
        vm.prank(OWNER);
        stablecoin.burn(amount);
        assertEq(stablecoin.balanceOf(OWNER), 0);
        assertEq(stablecoin.totalSupply(), 0);
    }

    function testCannotBurnZeroAmount() public mintsBalance(100, OWNER) {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BallerBucksStablecoin.BallerBucksStablecoin__MustBeGreaterThanZero.selector)
            );
        stablecoin.burn(0);
    }

    function testCannotBurnMoreThanBalance() public mintsBalance(100, OWNER) {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BallerBucksStablecoin.BallerBucksStablecoin__BurnAmountExceedsBalance.selector)
            );
        stablecoin.burn(101);
    }

}