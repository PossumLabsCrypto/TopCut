// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";

contract DeployMainnet is Script {
    function setUp() public {}

    uint256 tradeSize_1 = 1e16; //  0.01 ETH
    uint256 tradeSize_2 = 1e17; //  0.1 ETH

    uint256 tradeDuration_daily = 86400; // 24 hours
    uint256 tradeDuration_weekly = 604800; // 7 days

    uint256 firstSettlement_daily = 1752678000; // July 16, 3pm UTC
    uint256 firstSettlement_weekly_Monday = 1753110000; // July 21, 3pm UTC
    // uint256 firstSettlement_weekly_Tuesday = 1753196400; // July 22, 3pm UTC
    uint256 firstSettlement_weekly_Wednesday = 1752678000; // July 16, 3pm UTC
    // uint256 firstSettlement_weekly_Thursday = 1752764400; // July 17, 3pm UTC
    uint256 firstSettlement_weekly_Friday = 1752850800; // July 18, 3pm UTC
    // uint256 firstSettlement_weekly_Saturday = 1752937200; // July 19, 3pm UTC
    // uint256 firstSettlement_weekly_Sunday = 1753023600; // July 20, 3pm UTC

    bytes32 salt = "DeFiPrecisionMarkets";
    uint256 firstLoyaltyDistribution = 1756612800; // Aug 31, 4am UTC

    // L2 sequencer uptime feed of Chainlink on Arbitrum
    address uptimeFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    // Chainlink oracle feeds on Arbitrum
    address btcFeed = 0x6ce185860a4963106506C203335A2910413708e9;
    //address ethFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    //address dogeFeed = 0x9A7FB1b3950837a8D9b40517626E11D4127C098C;
    //address pepeFeed = 0x02DEd5a7EDDA750E3Eb240b54437a54d57b74dBE;
    //address linkFeed = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
    //address arbFeed = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;

    function run()
        public
        returns (address vault, address market1, address market2, address market3, address market4, address market5)
    {
        vm.startBroadcast();

        // Create contract instances
        TopCutVault vaultContract = new TopCutVault(salt, firstLoyaltyDistribution);
        vault = address(vaultContract);

        // BTC daily
        // 0.01 ETH
        TopCutMarket market_1 =
            new TopCutMarket(btcFeed, uptimeFeed, vault, tradeSize_1, tradeDuration_daily, firstSettlement_daily);
        market1 = address(market_1);

        // BTC daily
        // 0.1 ETH
        TopCutMarket market_2 =
            new TopCutMarket(btcFeed, uptimeFeed, vault, tradeSize_2, tradeDuration_daily, firstSettlement_daily);
        market2 = address(market_2);

        // BTC weekly - Monday
        // 0.01 ETH
        TopCutMarket market_3 = new TopCutMarket(
            btcFeed, uptimeFeed, vault, tradeSize_1, tradeDuration_weekly, firstSettlement_weekly_Monday
        );
        market3 = address(market_3);

        // BTC weekly - Wednesday
        // 0.01 ETH
        TopCutMarket market_4 = new TopCutMarket(
            btcFeed, uptimeFeed, vault, tradeSize_1, tradeDuration_weekly, firstSettlement_weekly_Wednesday
        );
        market4 = address(market_4);

        // BTC weekly - Friday
        // 0.01 ETH
        TopCutMarket market_5 = new TopCutMarket(
            btcFeed, uptimeFeed, vault, tradeSize_1, tradeDuration_weekly, firstSettlement_weekly_Friday
        );
        market5 = address(market_5);

        vm.stopBroadcast();
    }
}

// forge script script/DeployMainnet.s.sol --rpc-url $ARB_MAINNET_URL --private-key $PRIVATE_KEY --broadcast --optimize --optimizer-runs 9999 --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
