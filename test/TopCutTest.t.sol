// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutNFT} from "src/TopCutNFT.sol";
import {TopCutVault} from "src/TopCutVault.sol";

// ============================================
error activeCohort();
error CohortFull();
error FailedToSendWinnerReward();
error FailedToSendFrontendReward();
error FailedToSendKeeperReward();
error FailedToSkimSurplus();
error InsufficientBalance();
error InvalidConstructor();
error InvalidPrice();
error InvalidTradeSize();
error NoClaims();
error StaleOraclePrice();
error WaitingToSettle();
error ZeroAddress();

error FailedToSendNativeToken();
error InsufficientPayment();

error CeilingBreached();
error Deadline();
error InsufficientReceived();
error InsufficientPoints();
error InvalidAffiliateID();
error NotAuthorized();
error Timelock();
// ============================================

contract TopCutTest is Test {
    // addresses
    address payable Alice = payable(0x46340b20830761efd32832A74d7169B29FEB9758);
    address payable Bob = payable(0x490b1E689Ca23be864e55B46bf038e007b528208);
    address payable treasury = payable(0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33);
    address psm = 0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;

    // TopCut instances
    TopCutMarket market;
    TopCutNFT refNFT;
    TopCutVault vault;

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;
    uint256 deployment;

    // Constants
    bytes32 constant SALT = "1245678";
    uint256 constant FIRST_SETTLEMENT = 1748430000;
    uint256 constant TRADE_DURATION = 86400;
    uint256 constant TRADE_SIZE = 1e16;
    uint256 constant MAX_COHORT_SIZE = 3300;
    address constant BTC_USD_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9;

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 280000000});

        // Create contract instances
        vault = new TopCutVault(SALT);
        market = new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        deployment = block.timestamp;

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(treasury, 100 ether);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // Add liquidity to the LP
    function helper_one() public {}

    //////////////////////////////////////
    /////// TESTS - Deployment
    //////////////////////////////////////

    //////////////////////////////////////
    /////// TESTS - Markets
    //////////////////////////////////////

    //////////////////////////////////////
    /////// TESTS - Vault
    //////////////////////////////////////

    //////////////////////////////////////
    /////// TESTS - NFT
    //////////////////////////////////////
}
