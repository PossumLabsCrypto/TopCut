// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";
import {FakeOracle} from "test/mocks/FakeOracle.sol";

contract DeployTestnet is Script {
    function setUp() public {}

    uint256 maxChohortSize = 3300;
    uint256 tradeSize = 1e16; //  0.01 ETH
    uint256 tradeDuration = 86400; // 24 hours
    uint256 firstSettlement = 1749135600; // Jun 05, 3pm UTC
    uint256 firstSettlement_weekly = 1750258800; // Jun 18, 3pm UTC

    bytes32 salt = "Testnet";
    uint256 firstDistribution = 1749564000; // Jun 10

    function run() public {
        vm.startBroadcast();

        // Configure optimizer settings
        // vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        // vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(9999)));

        // Create contract instances
        FakeOracle oracle = new FakeOracle();

        TopCutVault vault = new TopCutVault(salt, firstDistribution);

        // BTC 1
        new TopCutMarket(address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration, firstSettlement);

        // BTC 2
        new TopCutMarket(
            address(oracle), address(vault), maxChohortSize, tradeSize * 10, tradeDuration, firstSettlement
        );

        // BTC
        new TopCutMarket(
            address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration * 7, firstSettlement_weekly
        );

        // ETH
        new TopCutMarket(address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration, firstSettlement);

        vm.stopBroadcast();
    }
}
