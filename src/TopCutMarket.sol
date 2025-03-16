// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

contract TopCutMarket {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
