// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ERC20RevertableMock is ERC20Mock {
    bool private shouldRevert;

    constructor(string memory name, string memory symbol) ERC20Mock() {}

    function setRevert(bool _shouldRevert) public {
        shouldRevert = _shouldRevert;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (shouldRevert) {
            revert("Mock transfer failure");
        }
        return super.transfer(recipient, amount);
    }
}
