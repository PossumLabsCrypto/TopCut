// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ITopCutNFT} from "src/interfaces/ITopCutNFT.sol";
import {ITopCutMarket} from "src/interfaces/ITopCutMarket.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutNFT} from "src/TopCutNFT.sol";
import {TopCutVault} from "src/TopCutVault.sol";
import {DOScontract} from "test/mocks/DOScontract.sol";

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
error DeadlineExpired();
error InsufficientPoints();
error InsufficientReceived();
error InvalidAffiliateID();
error InvalidPaidETH();
error InvalidToken();
error NotOwnerOfNFT();
error ZeroPointRedeem();
// ============================================

contract TopCutTest is Test {
    // addresses
    address payable Alice = payable(address(0x7));
    address payable Bob = payable(address(0x8));
    address payable treasury = payable(0xa0BFD02a7a47CBCA7230E03fbf04A196C3E771E3);
    IERC20 psm = IERC20(0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5);
    IERC20 usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    // ETH amounts
    uint256 aliceETH = 100e18;
    uint256 bobETH = 100e18;
    uint256 treasuryETH = 1000000000e18;

    // Contract instances
    TopCutMarket market;
    ITopCutNFT refNFT;
    TopCutVault vault;
    TopCutMarket fakeMarket;
    DOScontract dosContract;

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;
    uint256 oneWeek = 60 * 60 * 24 * 7;

    // Constants
    uint256 constant PSM_TOTAL_SUPPLY_L1 = 1e28; // 10Bn

    uint256 constant FIRST_SETTLEMENT = 1748430000;
    uint256 constant TRADE_DURATION = 86400;
    uint256 constant TRADE_SIZE = 1e16;
    uint256 constant WIN_SIZE = 1e17;
    uint256 constant MAX_COHORT_SIZE = 3300;
    address constant BTC_USD_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9;
    uint256 constant ORACLE_RESPONSE_AT_FORK_HEIGHT = 11060800999999;
    uint256 constant MAX_AP_REDEEMED = 5e22; // 50k points

    bytes32 constant SALT = "1245678";
    uint256 constant DISTRIBUTION_INTERVAL = 604800;
    uint256 constant SHARE_PRECISION = 1000;
    uint256 constant SHARE_VAULT = 50;
    uint256 constant SHARE_FRONTEND = 30;
    uint256 constant SHARE_KEEPER = 10;
    uint256 constant PREDICTION_DECIMALS = 18;
    uint256 constant INITIAL_REDEEMED_POINTS = 1e18;
    uint256 constant EXTRACTION_FEE_ETH = 1e19;

    string metadataURI = "420g02n230f203f";
    uint256 constant START_MINT_PRICE = 1e17;
    uint256 constant MINT_PRICE_INCREASE = 1e16;

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 339289690});

        // Calculate first loyalty reward distribution time
        uint256 firstDistribution = 3 * oneWeek + block.timestamp;

        // Create contract instances
        vault = new TopCutVault(SALT, firstDistribution);
        refNFT = ITopCutNFT(vault.AFFILIATE_NFT());
        market = new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        fakeMarket = new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, MAX_AP_REDEEMED, TRADE_DURATION, FIRST_SETTLEMENT
        );

        dosContract = new DOScontract(address(psm), address(vault), address(market), address(refNFT));

        vm.deal(Alice, aliceETH);
        vm.deal(Bob, bobETH);
        vm.deal(treasury, treasuryETH);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // Cast a grid of predictions via serial castPrediction()
    function helper_predictionGrid_one() public {}

    // Cast maximum number of predictions in a cohort
    function helper_fullCohortPredictions() public {}

    //////////////////////////////////////
    /////// TESTS - Deployment
    //////////////////////////////////////
    // Check that all starting parameters are correct and the NFT contract was deployed via Vault contructor
    function testSuccess_verifyDeployments() public view {
        ITopCutNFT nft = vault.AFFILIATE_NFT();

        // Vault
        assertTrue(address(nft) != address(0));
        assertEq(vault.loyaltyPointsLeader(), address(0));
        assertEq(vault.leadingPoints(), 0);
        assertEq(vault.nextDistributionTime(), 3 * oneWeek + block.timestamp);

        // NFT
        assertEq(nft.TOPCUT_VAULT(), address(vault));
        assertEq(nft.metadataURI(), metadataURI);
        assertEq(nft.mintPriceETH(), START_MINT_PRICE);
        assertEq(nft.ownerOf(22), treasury);
        assertEq(nft.totalSupply(), 40);

        // Market
        assertEq(market.SHARE_PRECISION(), SHARE_PRECISION);
        assertEq(market.SHARE_VAULT(), SHARE_VAULT);
        assertEq(market.SHARE_FRONTEND(), SHARE_FRONTEND);
        assertEq(market.SHARE_KEEPER(), SHARE_KEEPER);

        assertEq(address(market.TOP_CUT_VAULT()), address(vault));
        assertEq(market.TRADE_DURATION(), TRADE_DURATION);
        assertEq(market.TRADE_SIZE(), TRADE_SIZE);
        assertEq(market.WIN_SIZE(), WIN_SIZE);
        assertEq(market.PREDICTION_DECIMALS(), PREDICTION_DECIMALS);

        assertEq(market.nextSettlement(), FIRST_SETTLEMENT);

        assertEq(market.predictions(1), 0);
        assertEq(market.predictionOwners(1), address(0));
        assertEq(market.claimAmounts(treasury), 0);

        assertEq(market.totalPendingClaims(), 0);

        uint256 max_winners = MAX_COHORT_SIZE / 11;
        for (uint256 i = 0; i < max_winners; i++) {
            assertEq(market.winnersList(i), address(vault));
        }
    }

    // Revert of vault deployment
    function testRevert_vaultConstructor() public {
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutVault(SALT, 12345);
    }

    // Revert of market deployment
    function testRevert_marketConstructor() public {
        // Invalid oracle
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(address(0), address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT);

        // Invalid vault
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(0), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        // Too small cohort
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(BTC_USD_CHAINLINK_ORACLE, address(vault), 11, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT);

        // Too large cohort
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(BTC_USD_CHAINLINK_ORACLE, address(vault), 1e5, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT);

        // Invalid trade size
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, 1e5, TRADE_DURATION, FIRST_SETTLEMENT
        );

        // Too short trade duration
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(BTC_USD_CHAINLINK_ORACLE, address(vault), MAX_COHORT_SIZE, TRADE_SIZE, 1111, FIRST_SETTLEMENT);

        // Invalid first settlement date
        vm.expectRevert(InvalidConstructor.selector);
        new TopCutMarket(
            BTC_USD_CHAINLINK_ORACLE,
            address(vault),
            MAX_COHORT_SIZE,
            TRADE_SIZE,
            TRADE_DURATION,
            block.timestamp + TRADE_DURATION
        );
    }

    //////////////////////////////////////
    /////// TESTS - Vault
    //////////////////////////////////////
    ///////////// LOYALTY POINTS /////////////
    // test update points from any address without distributing the loyalty reward
    function testSuccess_updatePoints_noDistribution() public {
        vm.prank(Alice);
        vault.updatePoints{value: 1e18}(Bob, 3);

        assertEq(vault.loyaltyPoints(Bob), 1e18);
        assertEq(vault.affiliatePoints(3), 1e18);
        assertEq(vault.leadingPoints(), 1e18);
        assertEq(vault.loyaltyPointsLeader(), Bob);
        assertEq(address(vault).balance, 1e18);
    }

    // test the distribution of the weekly loyalty reward
    function testSuccess_updatePoints_triggerLoyaltyReward() public {
        uint256 pointsToBob = 1e18;
        uint256 pointsToAlice = 2e18;
        uint256 pointsToContract = 5e18;

        // Increase points of Bob, Bob becomes leader
        vm.prank(Alice);
        vault.updatePoints{value: pointsToBob}(Bob, 3);

        assertEq(vault.leadingPoints(), pointsToBob);
        assertEq(vault.loyaltyPointsLeader(), Bob);

        // Increase points of Alice even more, Alice becomes leader
        vm.prank(Alice);
        vault.updatePoints{value: pointsToAlice}(Alice, 3);

        assertEq(vault.leadingPoints(), pointsToAlice);
        assertEq(vault.loyaltyPointsLeader(), Alice);

        uint256 epochEnd = vault.nextDistributionTime();

        // Jump to a time after the nextDistributionTime
        vm.warp(vault.nextDistributionTime() + 1);

        // Scenario 1: Winner (Alice) can accept ETH (balance changes)
        vm.prank(Alice);
        vault.updatePoints{value: pointsToAlice}(Alice, 3);

        uint256 vaultBalancePreDistro = pointsToBob + pointsToAlice + pointsToAlice;

        assertEq(Bob.balance, bobETH);
        assertEq(Alice.balance, aliceETH - vaultBalancePreDistro + (vaultBalancePreDistro / 100));
        assertEq(address(vault).balance, (vaultBalancePreDistro * 99) / 100);

        assertEq(vault.loyaltyPointsLeader(), address(0));
        assertEq(vault.leadingPoints(), 0);
        assertEq(vault.loyaltyPoints(Alice), 0);
        assertEq(vault.nextDistributionTime(), epochEnd + DISTRIBUTION_INTERVAL);

        // Scenario 2: Winner (dosContract) cannot accept ETH (no balance change)
        vm.prank(Alice);
        vault.updatePoints{value: pointsToContract}(address(dosContract), 3);

        assertEq(vault.loyaltyPointsLeader(), address(dosContract));

        // Jump to a time after the nextDistributionTime
        vm.warp(vault.nextDistributionTime() + 1);

        vm.prank(Alice);
        vault.updatePoints{value: pointsToContract}(address(dosContract), 3);

        assertEq(
            Alice.balance, aliceETH - vaultBalancePreDistro + (vaultBalancePreDistro / 100) - (2 * pointsToContract)
        );
        assertEq(address(dosContract).balance, 0);
        assertEq(address(vault).balance, (vaultBalancePreDistro * 99) / 100 + (2 * pointsToContract));
    }

    // Revert cases
    function testRevert_updatePoints() public {
        // Scenario 1: Zero address
        vm.startPrank(Alice);
        vm.expectRevert(ZeroAddress.selector);
        vault.updatePoints{value: 1e18}(address(0), 3);

        // Scenario 2: Invalid NFT ID
        vm.expectRevert(InvalidAffiliateID.selector);
        vault.updatePoints{value: 1e18}(Bob, 156);

        vm.stopPrank();
    }

    ///////////// AFFILIATE POINTS /////////////
    // test claiming affiliate points & quote
    function testSuccess_claimAffiliateReward() public {
        // prepare NFT & points
        uint256 mintCost = refNFT.mintPriceETH();
        uint256 pointLoad = 1e18;

        vm.startPrank(Alice);
        refNFT.mint{value: mintCost}(); // mint ID 40 to Alice
        vault.updatePoints{value: pointLoad}(Bob, 40); // attribute points to ID 40

        // Scenario 1: Regular claim
        uint256 points = vault.affiliatePoints(40);
        uint256 balanceVault = address(vault).balance;
        uint256 expectedETH = vault.quoteAffiliateReward(points);
        uint256 expectedManualCalc = (balanceVault * pointLoad) / (pointLoad + INITIAL_REDEEMED_POINTS); // 50% of 1.1 ETH

        assertEq(expectedETH, expectedManualCalc);

        vault.claimAffiliateReward(40, points, expectedETH, block.timestamp);

        assertEq(address(vault).balance, balanceVault - expectedETH);
        assertEq(Alice.balance, aliceETH - mintCost - pointLoad + expectedETH);
        assertEq(vault.affiliatePoints(40), 0);

        vm.stopPrank();

        // Redeem points until upper threshold (50k eth)
        vm.prank(treasury);
        vault.updatePoints{value: MAX_AP_REDEEMED}(Bob, 40); // attribute 50k points to ID 40

        assertEq(address(vault).balance, MAX_AP_REDEEMED + balanceVault - expectedETH);

        vm.startPrank(Alice);
        vault.claimAffiliateReward(40, MAX_AP_REDEEMED, 0, block.timestamp);
        vault.updatePoints{value: pointLoad}(Bob, 40);

        uint256 balanceAlice = Alice.balance;
        balanceVault = address(vault).balance;

        // Scenario 2: Points redeemed after maximum is reached (MAX_AP_REDEEMED)
        points = vault.affiliatePoints(40);
        expectedETH = vault.quoteAffiliateReward(points);
        expectedManualCalc = (balanceVault * pointLoad) / (pointLoad + MAX_AP_REDEEMED);

        assertEq(expectedETH, expectedManualCalc);

        vault.claimAffiliateReward(40, points, 1, block.timestamp);

        assertEq(Alice.balance, balanceAlice + expectedETH);

        vm.stopPrank();
    }

    // Revert cases
    function testRevert_claimAffiliateReward() public {
        // Scenario 1: caller doesn't own the NFT
        vm.startPrank(Alice);
        vm.expectRevert(NotOwnerOfNFT.selector);
        vault.claimAffiliateReward(3, 100, 1, block.timestamp);

        // Scenario 2: affiliate doesn't have any points
        refNFT.mint{value: 1e17}(); // mint ID 40 to Alice
        vm.expectRevert(ZeroPointRedeem.selector);
        vault.claimAffiliateReward(40, 0, 1, block.timestamp);

        // Scenario 3: affiliate doesn't have enough points
        vault.updatePoints{value: 1e18}(Bob, 40); // attribute points to ID 40

        vm.expectRevert(InsufficientPoints.selector);
        vault.claimAffiliateReward(40, 2e18, 1, block.timestamp);

        // Scenario 4: Receives less than expected
        vm.expectRevert(InsufficientReceived.selector);
        vault.claimAffiliateReward(40, 1e18, 1e22, block.timestamp);

        // Scenario 5: Deadline expired
        vm.expectRevert(DeadlineExpired.selector);
        vault.claimAffiliateReward(40, 1e18, 1, block.timestamp - 100);

        // Scenario 6: NFT held by a contract that doesn't accept ETH
        uint256 price = refNFT.mintPriceETH();
        dosContract.buyNFT{value: price}(); // mint NFT by (to) the dosContract

        assertEq(refNFT.totalSupply(), 42);
        assertEq(refNFT.ownerOf(41), address(dosContract));

        vault.updatePoints{value: 1e18}(Bob, 41); // attribute points to ID 41

        vm.expectRevert(FailedToSendNativeToken.selector);
        dosContract.claimAP(41, 1e18, 1, block.timestamp);

        vm.stopPrank();
    }

    ///////////// REDEEMING PSM /////////////
    // test the  redemption of PSM for ETH & quote
    function testSuccess_redeemPSM() public {
        // Parameters
        uint256 amountRedeem = 5e25; // 50M
        uint256 vaultBalanceStart = 1e18;
        uint256 psmStartBalance = psm.balanceOf(treasury);

        // Send some ETH to increase Vault balance
        vm.startPrank(treasury);
        (bool sent,) = address(vault).call{value: vaultBalanceStart}("");
        sent = true;
        assertEq(address(vault).balance, vaultBalanceStart);

        // Quote for 50M PSM redemption
        uint256 ethOut_first = vault.quoteRedeemPSM(amountRedeem);
        assertEq(ethOut_first, vaultBalanceStart / 4); // 50M redeems 25% of vault

        // Redeem 50M PSM
        psm.approve(address(vault), 1e55);
        vault.redeemPSM(amountRedeem, 1, block.timestamp);

        // Quote for 150M PSM redemption --> adjusted to 100M
        uint256 ethOut_second = vault.quoteRedeemPSM(amountRedeem * 3);
        assertEq(ethOut_second, (vaultBalanceStart * 3) / 8); // 100M redeem 50% of remaining balance (3/8 of initial)

        // Redeem 150M PSM (100m effective)
        vault.redeemPSM(amountRedeem * 3, 1, block.timestamp);
        vm.stopPrank();

        assertEq(psm.balanceOf(treasury), psmStartBalance - (3 * amountRedeem)); // 150M got redeemed in total
        assertEq(address(vault).balance, vaultBalanceStart - ethOut_first - ethOut_second);
        assertEq(address(vault).balance, (vaultBalanceStart * 3) / 8); // total of 5/8 of initial ETH balance was extracted
    }

    // Revert cases
    function testRevert_redeemPSM() public {
        // Parameters
        uint256 amountRedeem = 5e25; // 50M
        uint256 vaultBalanceStart = 1e18;

        // Send some ETH to increase Vault balance
        vm.startPrank(treasury);
        (bool sent,) = address(vault).call{value: vaultBalanceStart}("");
        sent = true;
        assertEq(address(vault).balance, vaultBalanceStart);

        // Scenario 1: Received less than expected
        psm.approve(address(vault), 1e55);
        vm.expectRevert(InsufficientReceived.selector);
        vault.redeemPSM(amountRedeem, vaultBalanceStart, block.timestamp);

        // Scenario 2: Deadline expired
        uint256 timePrev = block.timestamp;
        vm.warp(timePrev + 1000);
        vm.expectRevert(DeadlineExpired.selector);
        vault.redeemPSM(amountRedeem, 1, timePrev);

        // Scenario 3: Redeem from contract that cannot receive ETH
        // Send 50M PSM to DOS contract
        psm.transfer(address(dosContract), amountRedeem);

        vm.expectRevert(FailedToSendNativeToken.selector);
        dosContract.tryRedeemPSM();

        vm.stopPrank();
        assertEq(address(dosContract).balance, 0); // 0 ETH in the dosContract
        assertEq(psm.balanceOf(address(dosContract)), amountRedeem); // 50M PSM in the dosContract

        // Scenario 4: Redeem more tokens than total supply on L1
        // loop of redeeming PSM in Vault and sending it back to caller so that storage variable goes up
        for (uint256 i = 0; i < 200; i++) {
            vm.prank(treasury);
            vault.redeemPSM(amountRedeem, 0, block.timestamp);

            uint256 balancePSM = psm.balanceOf(address(vault));
            vm.prank(address(vault));
            psm.transfer(treasury, balancePSM);
        }

        vm.startPrank(treasury);
        // refill vault with ETH
        (sent,) = address(vault).call{value: vaultBalanceStart}("");

        vm.expectRevert(CeilingBreached.selector);
        vault.redeemPSM(amountRedeem, 1, block.timestamp);

        vm.stopPrank();
    }

    ///////////// BALANCE EXTRACTION FOR ETH /////////////
    // test the withdrawal of an ERC20 token when paying the ETH fee
    function testSuccess_extractTokenBalance() public {
        // Send USDC to the vault
        uint256 amount = 1e6; // 1 USDC
        vm.prank(treasury);
        usdc.transfer(address(vault), amount);

        assertEq(usdc.balanceOf(address(vault)), amount);

        // Alice extracts the usdc balance
        vm.prank(Alice);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(usdc), 1, block.timestamp);

        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(Alice), amount);
        assertEq(address(vault).balance, EXTRACTION_FEE_ETH);
    }

    // Revert cases
    function testRevert_extractTokenBalance() public {
        // Send USDC to the vault
        uint256 amount = 1e6; // 1 USDC
        vm.prank(treasury);
        usdc.transfer(address(vault), amount);

        // Scenario 1: ETH not paid
        vm.startPrank(Alice);
        vm.expectRevert(InvalidPaidETH.selector);
        vault.extractTokenBalance{value: 11}(address(usdc), 1, block.timestamp);

        // Scenario 2: zero address
        vm.expectRevert(InvalidToken.selector);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(0), 1, block.timestamp);

        // Scenario 3: PSM address
        vm.expectRevert(InvalidToken.selector);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(psm), 1, block.timestamp);

        // Scenario 4: deadline expired
        vm.expectRevert(DeadlineExpired.selector);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(usdc), 1, block.timestamp - 10);
        vm.stopPrank();

        // Scenario 5: Frontrunned by Bob (less than expected)
        vm.prank(Bob);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(usdc), amount, block.timestamp);

        vm.prank(Alice);
        vm.expectRevert(InsufficientReceived.selector);
        vault.extractTokenBalance{value: EXTRACTION_FEE_ETH}(address(usdc), amount, block.timestamp);
    }

    //////////////////////////////////////
    /////// TESTS - NFT
    //////////////////////////////////////
    // test minting of NFTs
    function testSuccess_mint() public {
        // Vault balance before mint
        uint256 vaultBalanceETH = address(vault).balance;

        vm.prank(treasury);
        uint256 newID = refNFT.mint{value: START_MINT_PRICE}();

        assertEq(newID, 40);
        assertEq(refNFT.totalSupply(), 41);
        assertEq(refNFT.mintPriceETH(), START_MINT_PRICE + MINT_PRICE_INCREASE);
        assertEq(address(vault).balance, vaultBalanceETH + START_MINT_PRICE);
    }

    function testRevert_mint() public {
        // Scenario 1: not enough ETH paid
        vm.startPrank(treasury);
        vm.expectRevert(InsufficientPayment.selector);
        refNFT.mint{value: START_MINT_PRICE - 1}();
        vm.stopPrank();
    }

    //////////////////////////////////////
    /////// TESTS - Markets
    //////////////////////////////////////
    // test the successful execution of predictions
    function testSuccess_castPrediction() public {
        // Verify state updates (predictions, owners)
        // Verify that points were updated in the Vault
        // Verify that the connected affiliate is 0
        // Verify that frontend received 3% fee
        // Verify that Vault received 5% fee
    }

    // Revert cases
    function testRevert_castPrediction() public {
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
