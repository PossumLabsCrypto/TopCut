// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";

contract DeployDailyMarkets is Script {
    function setUp() public {}

    address vault = address(0);
    uint256 tradeSize = 1e16; //  0.01 ETH
    uint256 tradeDuration = 86400; // 24 hours
    uint256 firstSettlement = 1749135600; // Jun 05, 3pm UTC

    // Chainlink oracle feeds on Arbitrum
    address btcFeed = 0x6ce185860a4963106506C203335A2910413708e9;
    address ethFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address dogeFeed = 0x9A7FB1b3950837a8D9b40517626E11D4127C098C;
    // address pepeFeed = 0x02DEd5a7EDDA750E3Eb240b54437a54d57b74dBE;
    // address linkFeed = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
    // address arbFeed = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;

    // Sequencer uptime feed of Chainlink on Arbitrum
    address uptimeFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    function run() public returns (address[] memory marketAddresses) {
        vm.startBroadcast();

        // Configure optimizer settings
        vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(9999)));

        // Create contract instances
        TopCutMarket marketBTC = new TopCutMarket(btcFeed, uptimeFeed, vault, tradeSize, tradeDuration, firstSettlement);
        marketAddresses[0] = address(marketBTC);

        TopCutMarket marketETH = new TopCutMarket(ethFeed, uptimeFeed, vault, tradeSize, tradeDuration, firstSettlement);
        marketAddresses[1] = address(marketETH);

        TopCutMarket marketDOGE =
            new TopCutMarket(dogeFeed, uptimeFeed, vault, tradeSize, tradeDuration, firstSettlement);
        marketAddresses[2] = address(marketDOGE);

        vm.stopBroadcast();
    }
}

// forge script script/DeployDailyMarkets.s.sol --rpc-url $ARB_MAINNET_URL --private-key $PRIVATE_KEY --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --optimize --optimizer-runs 9999
