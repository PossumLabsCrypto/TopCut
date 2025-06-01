// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IChainlink} from "src/interfaces/IChainlink.sol";
import {ITopCutNFT} from "src/interfaces/ITopCutNFT.sol";
import {ITopCutMarket} from "src/interfaces/ITopCutMarket.sol";
import {TopCutMarket} from "src/TopCutMarket.sol";
import {TopCutNFT} from "src/TopCutNFT.sol";
import {TopCutVault} from "src/TopCutVault.sol";
import {DOScontract} from "test/mocks/DOScontract.sol";
import {BrokenOracle} from "test/mocks/BrokenOracle.sol";
import {FakeOracle} from "test/mocks/FakeOracle.sol";

// ============================================
error cohortActive();
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
error BrokenOraclePrice();
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
    address payable Alice = payable(address(0x117));
    address payable Bob = payable(address(0x118));
    address payable Charlie = payable(address(0x119));
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
    DOScontract dosContract;
    TopCutMarket brokenOracleMarket;
    TopCutMarket fakeOracleMarket;

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;
    uint256 oneWeek = 60 * 60 * 24 * 7;

    // Constants
    struct tradeData {
        address predictionOwner;
        uint256 prediction;
    }

    uint256 constant PSM_TOTAL_SUPPLY_L1 = 1e28; // 10Bn

    uint256 constant FIRST_SETTLEMENT = 1748430000;
    uint256 constant TRADE_DURATION = 86400;
    uint256 constant TRADE_SIZE = 1e16;
    uint256 constant WIN_SIZE = 1e17;
    uint256 constant MAX_COHORT_SIZE = 3300;
    address constant BTC_USD_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9;
    IChainlink constant oracle = IChainlink(BTC_USD_CHAINLINK_ORACLE);
    uint256 constant ORACLE_RESPONSE_AT_FORK_HEIGHT = 11060800999999; // 110608.001 BTC/USD
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

        BrokenOracle brokenOracle = new BrokenOracle();
        brokenOracleMarket = new TopCutMarket(
            address(brokenOracle), address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        FakeOracle fakeOracle = new FakeOracle();
        fakeOracleMarket = new TopCutMarket(
            address(fakeOracle), address(vault), MAX_COHORT_SIZE, TRADE_SIZE, TRADE_DURATION, FIRST_SETTLEMENT
        );

        dosContract = new DOScontract(address(psm), address(vault), address(fakeOracleMarket), address(refNFT));

        vm.deal(Alice, aliceETH);
        vm.deal(Bob, bobETH);
        vm.deal(treasury, treasuryETH);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // Cast a grid of predictions via serial castPrediction()
    function helper_predictionGrid() public {
        uint256 predictionStartBob = 109000e18;
        uint256 predictionStartAlice = 110330e18;

        for (uint256 i = 0; i < 23; i++) {
            vm.prank(Bob);
            fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, predictionStartBob + (i * 100e18));
        }

        // Alice wins both predictions
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(Alice);
            fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, predictionStartAlice + (i * 5e18));
        }
    }

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

        (address user, uint256 prediction) = market.tradesCohort_1(1);
        assertEq(user, address(0));
        assertEq(prediction, 0);

        (user, prediction) = market.tradesCohort_2(1);
        assertEq(user, address(0));
        assertEq(prediction, 0);

        assertEq(market.claimAmounts(treasury), 0);
        assertEq(market.totalPendingClaims(), 0);
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
        uint256 pricePrediction = 107123e18;
        uint256 refID = 22;

        uint256 vaultBalance = address(vault).balance;
        uint256 frontendBalance = treasury.balance;

        uint256 frontendReward = (TRADE_SIZE * SHARE_FRONTEND) / SHARE_PRECISION;
        uint256 vaultReward = (TRADE_SIZE * SHARE_VAULT) / SHARE_PRECISION;

        vm.prank(Alice);
        fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, refID, pricePrediction);

        // Verify ETH flows to frontend, vault, market
        assertEq(treasury.balance, frontendBalance + frontendReward);
        assertEq(address(vault).balance, vaultBalance + vaultReward);
        assertEq(address(fakeOracleMarket).balance, TRADE_SIZE - frontendReward - vaultReward);

        // Verify state updates (cohortSize, predictions, owners)
        (address owner, uint256 prediction) = fakeOracleMarket.tradesCohort_1(0);

        assertEq(prediction, pricePrediction);
        assertEq(owner, Alice);
        assertEq(fakeOracleMarket.cohortSize_1(), 1); // next cohort (accepting trades)
        assertEq(fakeOracleMarket.cohortSize_2(), 0); // active cohort (blocked)

        // Verify that points were updated in the Vault
        assertEq(vault.loyaltyPoints(Alice), vaultReward);
        assertEq(vault.affiliatePoints(refID), vaultReward);
        assertEq(vault.loyaltyPointsLeader(), Alice);
        assertEq(vault.leadingPoints(), vaultReward);

        // pass time, settle and cast prediction to the next cohort
        vm.warp(fakeOracleMarket.nextSettlement());
        vm.prank(Alice);
        fakeOracleMarket.settleCohort();

        vm.startPrank(Bob);
        fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, 110123e18);
        fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, 110123e18);
        vm.stopPrank();

        // Verify state updates of next cohort
        (owner, prediction) = fakeOracleMarket.tradesCohort_2(0);

        assertEq(prediction, 110123e18);
        assertEq(owner, Bob);
        assertEq(fakeOracleMarket.cohortSize_1(), 1); // active cohort (blocked)
        assertEq(fakeOracleMarket.cohortSize_2(), 2); // next cohort (accepting trades)

        // pass time, settle, verify resetting of cohort size
        vm.warp(fakeOracleMarket.nextSettlement());
        vm.prank(Alice);
        fakeOracleMarket.settleCohort();

        assertEq(fakeOracleMarket.cohortSize_1(), 0); // next cohort (just settled)
        assertEq(fakeOracleMarket.cohortSize_2(), 2); // active cohort (blocked)
    }

    // Revert cases
    function testRevert_castPrediction() public {
        uint256 pricePrediction = 107123e18;
        uint256 refID = 22;

        // Scenario 1: zero address as frontend ref
        vm.prank(Alice);
        vm.expectRevert(ZeroAddress.selector);
        market.castPrediction{value: TRADE_SIZE}(address(0), refID, pricePrediction);

        // Scenario 2: predicted price is 0
        vm.prank(Alice);
        vm.expectRevert(InvalidPrice.selector);
        market.castPrediction{value: TRADE_SIZE}(treasury, refID, 0);

        // Scenario 3: wrong trade size / ETH
        vm.prank(Alice);
        vm.expectRevert(InvalidTradeSize.selector);
        market.castPrediction{value: 123}(treasury, refID, pricePrediction);

        // Scnario 4: Set a non-payable frontend address (revert ETH sending)
        vm.prank(Alice);
        vm.expectRevert(FailedToSendFrontendReward.selector);
        market.castPrediction{value: TRADE_SIZE}(address(dosContract), refID, pricePrediction);

        // Scenario 5: too many predictions (cohort is full)
        vm.startPrank(treasury);
        for (uint256 i = 0; i < MAX_COHORT_SIZE; i++) {
            market.castPrediction{value: TRADE_SIZE}(treasury, refID, pricePrediction);
        }
        vm.stopPrank();

        vm.prank(Alice);
        vm.expectRevert(CohortFull.selector);
        market.castPrediction{value: TRADE_SIZE}(treasury, refID, pricePrediction);
    }

    function testRevert_castPrediction_II() public {
        uint256 pricePrediction = 107123e18;
        uint256 refID = 22;

        // Scenario 6: Market must be settled first
        vm.warp(market.nextSettlement() + 1);

        vm.prank(Alice);
        vm.expectRevert(WaitingToSettle.selector);
        market.castPrediction{value: TRADE_SIZE}(treasury, refID, pricePrediction);
    }

    // test the successful settlement
    function testSuccess_settleCohort() public {
        // cast 25 predictions
        helper_predictionGrid();

        // verify cohort size & saved predictions
        assertEq(fakeOracleMarket.cohortSize_1(), 25);
        assertEq(fakeOracleMarket.cohortSize_2(), 0);

        // verify predictions & owners
        address owner;
        uint256 prediction;
        for (uint256 i = 0; i < 23; i++) {
            (owner, prediction) = fakeOracleMarket.tradesCohort_1(i);

            assertEq(owner, Bob);
            assertEq(prediction, 109000e18 + (i * 100e18));
        }

        for (uint256 i = 0; i < 2; i++) {
            (owner, prediction) = fakeOracleMarket.tradesCohort_1(i + 23);

            assertEq(owner, Alice);
            assertEq(prediction, 110330e18 + (i * 5e18));
        }

        // end of the line (outside cohort)
        (owner, prediction) = fakeOracleMarket.tradesCohort_1(25);
        assertEq(owner, address(0));
        assertEq(prediction, 0);

        // settle first cohort (no traders)
        //int256 fakeOraclePrice = 110333e8;
        vm.warp(fakeOracleMarket.nextSettlement());
        vm.prank(Charlie);
        fakeOracleMarket.settleCohort();

        assertEq(fakeOracleMarket.totalPendingClaims(), 0);

        // settle next cohort (25 traders -> 2 winners)
        vm.warp(fakeOracleMarket.nextSettlement());
        vm.prank(Charlie);
        fakeOracleMarket.settleCohort();

        // verify winners in aggregate + individual (Alice wins two times)
        assertEq(fakeOracleMarket.totalPendingClaims(), 2 * WIN_SIZE);
        assertEq(fakeOracleMarket.claimAmounts(Alice), 2 * WIN_SIZE);

        // verify keeper reward
        uint256 expectedReward = (25 * SHARE_KEEPER * TRADE_SIZE) / SHARE_PRECISION;
        assertEq(Charlie.balance, expectedReward);
    }

    // Revert cases
    function testRevert_settleCohort() public {
        uint256 timeStart = block.timestamp;

        // Scenario 1: Cohort is still active
        vm.expectRevert(cohortActive.selector);
        market.settleCohort();

        // Scenario 2: Get a stale oracle price (time)
        vm.warp(market.nextSettlement());
        vm.expectRevert(StaleOraclePrice.selector);
        market.settleCohort();

        // Scenario 3: Get a false oracle price (0)
        vm.expectRevert(BrokenOraclePrice.selector);
        brokenOracleMarket.settleCohort();

        // Scenario 4: keeper cannot receive ETH
        vm.warp(timeStart);
        vm.prank(Alice);
        fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, 111000e18);

        assertTrue(address(fakeOracleMarket).balance > 0);

        vm.warp(fakeOracleMarket.nextSettlement());
        vm.prank(address(dosContract));
        vm.expectRevert(FailedToSendKeeperReward.selector);
        fakeOracleMarket.settleCohort();
    }

    // test the claiming function
    function testSuccess_claim() public {
        // cast 25 predictions
        helper_predictionGrid();

        // Transition to active, then settle
        vm.startPrank(Bob);
        vm.warp(fakeOracleMarket.nextSettlement());
        fakeOracleMarket.settleCohort();
        vm.warp(fakeOracleMarket.nextSettlement());
        fakeOracleMarket.settleCohort();
        vm.stopPrank();

        // verify the updated user claims (Alice won 2 times)
        assertEq(fakeOracleMarket.claimAmounts(Alice), 2 * WIN_SIZE);

        // verify the updated global claim tracker
        assertEq(fakeOracleMarket.totalPendingClaims(), 2 * WIN_SIZE);

        // Claim & verify the user's ETH balance increase
        uint256 balance = Alice.balance;

        vm.prank(Alice);
        fakeOracleMarket.claim();

        assertEq(Alice.balance, balance + (2 * WIN_SIZE));
    }

    // Revert cases
    function testRevert_claim() public {
        // Scenario 1: user has no claims
        vm.startPrank(Alice);

        vm.expectRevert(NoClaims.selector);
        market.claim();

        // Scenario 2: contract has not enough balance to pay out user
        fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, 1234567);

        vm.warp(fakeOracleMarket.nextSettlement());
        fakeOracleMarket.settleCohort();

        dosContract.castVulnerablePrediction{value: TRADE_SIZE}(treasury, 22, 555);

        vm.warp(fakeOracleMarket.nextSettlement());
        fakeOracleMarket.settleCohort();

        vm.expectRevert(InsufficientBalance.selector);
        fakeOracleMarket.claim();

        // Scenario 3: User cannot receive ETH
        vm.warp(fakeOracleMarket.nextSettlement());
        fakeOracleMarket.settleCohort();
        for (uint256 i = 0; i < 12; i++) {
            fakeOracleMarket.castPrediction{value: TRADE_SIZE}(treasury, 22, 1234567);
        }

        vm.stopPrank();

        vm.prank(address(dosContract));
        vm.expectRevert(FailedToSendWinnerReward.selector);
        fakeOracleMarket.claim();
    }
}
