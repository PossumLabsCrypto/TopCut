// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";
import {FakeOracle} from "test/mocks/FakeOracle.sol";

contract DeployMarkets is Script {
    function setUp() public {}

    uint256 maxChohortSize = 3300;
    uint256 tradeSize = 1e16; //  0.01 ETH
    uint256 tradeDuration = 86400; // 24 hours
    uint256 firstSettlement = 1749135600; // Jun 05, 3pm UTC

    bytes32 salt = "Testnet";
    uint256 firstDistribution = 1749391200; // Jun 8

    function run() public returns (address vaultAddress, address[] memory marketAddresses) {
        vm.startBroadcast();

        // Configure optimizer settings
        vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(9999)));

        // Create contract instances
        FakeOracle oracle = new FakeOracle();

        TopCutVault vault = new TopCutVault(salt, firstDistribution);

        TopCutMarket marketBTC_1 =
            new TopCutMarket(address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration, firstSettlement);
        marketAddresses[0] = address(marketBTC_1);

        TopCutMarket marketBTC_2 = new TopCutMarket(
            address(oracle), address(vault), maxChohortSize, tradeSize * 10, tradeDuration, firstSettlement
        );
        marketAddresses[1] = address(marketBTC_2);

        TopCutMarket marketBTC_3 = new TopCutMarket(
            address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration * 7, firstSettlement
        );
        marketAddresses[2] = address(marketBTC_3);

        TopCutMarket marketETH =
            new TopCutMarket(address(oracle), address(vault), maxChohortSize, tradeSize, tradeDuration, firstSettlement);
        marketAddresses[3] = address(marketETH);

        vaultAddress = address(vault);

        vm.stopBroadcast();
    }
}

// forge script script/DeployTestnet.s.sol --rpc-url $ETH_SEPOLIA_URL --private-key $PRIVATE_KEY --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --optimize --optimizer-runs 9999
