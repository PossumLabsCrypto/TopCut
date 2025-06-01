// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutVault} from "src/TopCutVault.sol";

contract DeployVault is Script {
    function setUp() public {}

    bytes32 salt = "DeFiPrecisionMarkets";
    uint256 firstDistribution = 1749391200;

    function run() public returns (address vaultAddress) {
        vm.startBroadcast();

        // Configure optimizer settings
        vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(9999)));

        // Create contract instances
        TopCutVault vault = new TopCutVault(salt, firstDistribution);

        vaultAddress = address(vault);

        vm.stopBroadcast();
    }
}

// forge script script/DeployVault.s.sol --rpc-url $ARB_SEPOLIA_URL --private-key $PRIVATE_KEY --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --optimize --optimizer-runs 9999
