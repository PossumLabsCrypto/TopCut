// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutNFT} from "src/TopCutNFT.sol";
import {RewardVault} from "src/RewardVault.sol";

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
    RewardVault vault;
    TopCutMarket fakeMarket;

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;
    uint256 oneWeek = 60 * 60 * 24 * 7;
    uint256 deployment;

    // Constants
    bytes32 constant SALT = "1245678";
    uint256 constant FIRST_SETTLEMENT = 1748430000;
    uint256 constant TRADE_DURATION = 86400;
    uint256 constant TRADE_SIZE = 1e16;
    uint256 constant MAX_COHORT_SIZE = 3300;
    address constant BTC_USD_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9;
    uint256 private constant MAX_AP_REDEEMED = 1e24; // Reached after 1M ETH trade volume

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 280000000});

        // Calculate first loyalty reward distribution time
        uint256 firstDistribution = 3 * oneWeek + block.timestamp;

        // Create contract instances
        vault = new RewardVault(SALT, firstDistribution);
        market = new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        fakeMarket = new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, MAX_AP_REDEEMED, TRADE_DURATION, FIRST_SETTLEMENT
        );

        deployment = block.timestamp;

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(treasury, 1000000000 ether);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // Cast a grid of predictions via serial castPrediction()
    function helper_predictionGrid_one() public {}

    // Cast maximum number of predictions in a cohort
    function helper_fullCohortPredictions() public {}

    // Use fake market to pump maximum total points in the Vault
    function helper_loopPointsMaximum() public {}

    //////////////////////////////////////
    /////// TESTS - Deployment
    //////////////////////////////////////
    // Check that all starting parameters are correct and the NFT contract was deployed via Vault contructor
    function testSuccess_verifyDeployments() public {}

    //////////////////////////////////////
    /////// TESTS - Vault
    //////////////////////////////////////
    ///////////// LOYALTY POINTS /////////////
    // test update points from any address without distributing the loyalty reward
    function testSuccess_updatePoints_noDistribution() public {
        // verify that Loyalty points updated
        // verify that Affiliate points updated
        // verify that ETH balance increased
    }

    // test the distribution of the weekly loyalty reward
    function testSuccess_updatePoints_triggerLoyaltyReward() public {
        // Scenario 1: Recipient can accept ETH (balance change)
        // Scenario 2: Recipient cannot accept ETH (no balance change)
    }

    // Revert cases
    function testRevert_updatePoints() public {
        // Scenario 1: Invalid NFT ID
    }

    ///////////// AFFILIATE POINTS /////////////
    // test claiming affiliate points & quote
    function testSuccess_claimAffiliateReward() public {
        // Scenario 1: higher input than points owned -> verify adjustment
        // verify increase in total points redeemed
        // verify points reduction of the affiliate
        // verify ETH balance increase of the affiliate

        // helper: max out redeemed points via fake market

        // Scenario 3: Points redeemed beyond maximum
        // verify stagnation of total points redeemed
        // verify points reduction of the affiliate
        // verify ETH balance increase of the affiliate
    }

    // Revert cases
    function testRevert_claimAffiliateReward() public {
        // Scenario 1: caller doesn't own the NFT
        // Scenario 2: affiliate doesn't have any points
        // Scenario 3: Receives less than expected
        // Scenario 4: NFT held by a contract that doesn't accept ETH
    }

    ///////////// REDEEMING PSM /////////////
    // test the correct redemption of PSM for ETH & quote
    function testSuccess_redeemPSM() public {}

    // Revert cases
    function testRevert_redeemPSM() public {
        // Scenario 1: Deadline expired
        // Scenario 2: Received less than expected
        // Scenario 3: Redeem more tokens than total supply on L1
        // Scenario 4: Called from a contract that can't receive ETH
    }

    //////////////////////////////////////
    /////// TESTS - NFT
    //////////////////////////////////////
    // test minting of NFTs
    function testSuccess_mint() public {
        // ID increase
        // Price increase
        // ETH increase of Vault
    }

    function testRevert_mint() public {
        // Scenario 1: not enough ETH paid

        // Scenario 2: Called by contract without onERC721-received
    }

    //////////////////////////////////////
    /////// TESTS - Markets
    //////////////////////////////////////
    // test the successful execution of predictions
    function testSuccess_castPrediction_default() public {
        // Verify state updates (predictions, owners)
        // Verify that points were updated in the Vault
        // Verify that the connected affiliate is 0
        // Verify that frontend received 3% fee
        // Verify that Vault received 5% fee
    }

    // Revert cases
    function testRevert_castPrediction_default() public {
        // Scenario 1: zero address as frontend ref
        // Scenario 2: predicted price is 0
        // Scenario 3: wrong trade size / ETH
        // Scenario 4: too many predictions (cohort is full)
        // Scenario 5: trade duration is active / too late for predictions
        // Scnario 6: Set a non-payable frontend address (revert ETH sending)
    }

    // test the successful settlement
    function testSuccess_settleCohort() public {
        // verify oracle price
        // verify expected number of winners
        // verify expected sequence of winners
        // verify the increase in claims of winners
        // verify the global tracker of claims
        // verify new cohort ID
        // verify new settlement time
        // verify keeper reward

        // confirm that this is working with 0 traders in the cohort
    }

    // Revert cases
    function testRevert_settleCohort() public {
        // Scenario 1: Cohort is still active
        // Scenario 2: Get a stale oracle price (time)
        // Scenario 3: Get a false oracle price (0)
        // Scenario 4: keeper cannot receive ETH
    }

    // test the claiming function
    function testSuccess_claim() public {
        // verify the updated user claims
        // verify the updated global claim tracker
        // verify the user's ETH balance increase
    }

    // Revert cases
    function testRevert_claim() public {
        // Scenario 1: user has no claims
        // Scenario 2: contract has not enough balance to pay out user
        // Scenario 3: user is a contract that cannot receive ETH
    }
}
