// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";

contract AddNewMarket is Script {
    function setUp() public {}

    uint256 tradeSize = 5e16; //  0.05 ETH
    uint256 firstSettlement = 1753196400; // July 22, 3pm UTC

    address vault = 0x3cfc3CBA1B4aAF969057F590D23efe46848F4270; // Arbitrum
    uint256 tradeDuration_daily = 86400; // 24 hours
    uint256 tradeDuration_weekly = 604800; // 7 days

    // L2 sequencer uptime feed of Chainlink on Arbitrum
    address uptimeFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    // Chainlink oracle feeds on Arbitrum
    address btcFeed = 0x6ce185860a4963106506C203335A2910413708e9;
    //address ethFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    //address dogeFeed = 0x9A7FB1b3950837a8D9b40517626E11D4127C098C;
    //address pepeFeed = 0x02DEd5a7EDDA750E3Eb240b54437a54d57b74dBE;
    //address linkFeed = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
    //address arbFeed = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;

    function run() public returns (address market) {
        vm.startBroadcast();

        TopCutMarket market_ =
            new TopCutMarket(btcFeed, uptimeFeed, vault, tradeSize, tradeDuration_daily, firstSettlement);
        market = address(market_);

        vm.stopBroadcast();
    }
}

// forge script script/AddNewMarket.s.sol --rpc-url $ARB_MAINNET_URL --private-key $PRIVATE_KEY --broadcast --optimize --optimizer-runs 9999 --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
