// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ITopCutVault} from "src/interfaces/ITopCutVault.sol";

contract GasWasteContract {
    constructor(address _vault) {
        vault = ITopCutVault(_vault);
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    ITopCutVault vault;
    uint256 private counter;

    // ============================================
    // ==               FUNCTIONS                ==
    // ============================================
    function updatePointsInVault() external payable {
        uint256 buyPoints = msg.value;
        address recipient = address(this);
        vault.updatePoints{value: buyPoints}(recipient, 0);
    }

    // malicious receive function that wastes infinite gas
    receive() external payable {
        while (true) {
            counter++;
        }
    }
}
