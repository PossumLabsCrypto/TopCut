// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";
import {FakeOracle} from "test/mocks/FakeOracle.sol";
import {MockSequencerFeed} from "test/mocks/MockSequencerFeed.sol";

contract DeployTestnet is Script {
    function setUp() public {}

    uint256 tradeSize = 1e16; //  0.01 ETH
    uint256 tradeDuration = 86400; // 24 hours
    uint256 firstSettlement = 1749826800; // Jun 13, 3pm UTC
    uint256 firstSettlement_weekly = 1751295600; // Jun 30, 3pm UTC

    bytes32 salt = "Testnet";
    uint256 firstDistribution = 1751295600; // Jun 30, 3pm UTC

    function run()
        public
        returns (
            address oracleAd,
            address vaultAd,
            address market1Ad,
            address market2Ad,
            address market3Ad,
            address market4Ad
        )
    {
        vm.startBroadcast();

        // Create contract instances
        MockSequencerFeed sequencer = new MockSequencerFeed();
        address uptimeFeed = address(sequencer);

        FakeOracle oracle = new FakeOracle();
        oracleAd = address(oracle);

        TopCutVault vault = new TopCutVault(salt, firstDistribution);
        vaultAd = address(vault);

        // BTC 1
        TopCutMarket market1 =
            new TopCutMarket(oracleAd, uptimeFeed, vaultAd, tradeSize, tradeDuration, firstSettlement);
        market1Ad = address(market1);

        // BTC 2
        TopCutMarket market2 =
            new TopCutMarket(oracleAd, uptimeFeed, vaultAd, tradeSize * 10, tradeDuration, firstSettlement);
        market2Ad = address(market2);

        // BTC
        TopCutMarket market3 =
            new TopCutMarket(oracleAd, uptimeFeed, vaultAd, tradeSize, tradeDuration * 7, firstSettlement_weekly);
        market3Ad = address(market3);

        // ETH
        TopCutMarket market4 =
            new TopCutMarket(oracleAd, uptimeFeed, vaultAd, tradeSize, tradeDuration, firstSettlement);
        market4Ad = address(market4);

        vm.stopBroadcast();
    }
}

// forge script script/DeployTestnet.s.sol --rpc-url $ARB_SEPOLIA_URL --private-key $PRIVATE_KEY --broadcast --optimize --optimizer-runs 9999 --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
