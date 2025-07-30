// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IChainlink} from "./interfaces/IChainlink.sol";
import {ITopCutVault} from "./interfaces/ITopCutVault.sol";

// ============================================
error BrokenOraclePrice();
error CohortActive();
error CohortFull();
error FailedToSendWinnerReward();
error FailedToSendFrontendReward();
error FailedToSendKeeperReward();
error GracePeriodNotOver();
error InsufficientBalance();
error InvalidAmount();
error InvalidCohortID();
error InvalidConstructor();
error InvalidPrice();
error InvalidTradeSize();
error NoClaims();
error SequencerDown();
error StalePrice();
error WaitingToSettle();
error ZeroAddress();
// ============================================

/// @title TopCut Precision Market
/// @author Possum Labs
/**
 * @notice This contract accepts and settles predicitions by traders of a cohort
 * Traders receive Loyalty Points when trading via a registered TopCutMarket
 */
contract TopCutMarket {
    constructor(
        address _oracleContract,
        address _sequencerUptimeFeed,
        address _topCutVault,
        uint256 _tradeSize,
        uint256 _tradeDuration,
        uint256 _firstSettlementTime
    ) {
        if (_oracleContract == address(0)) revert InvalidConstructor();
        if (_sequencerUptimeFeed == address(0)) revert InvalidConstructor();
        ORACLE = IChainlink(_oracleContract);
        ORACLE_DECIMALS = ORACLE.decimals();
        SEQUENCER_UPTIME_FEED = IChainlink(_sequencerUptimeFeed);

        if (_topCutVault == address(0)) revert InvalidConstructor();
        TOP_CUT_VAULT = ITopCutVault(_topCutVault);

        ///@dev Given 1 in 11 (9%) fee potential, calculate how much reward can be allocated to keepers per unit (prediction)
        uint256 feeShareSum = SHARE_VAULT + SHARE_FRONTEND; // e.g. 80
        uint256 maxFeeRemainder = 90 - feeShareSum; // e.g. 10 (1%)
        uint256 maxKeeperRewardUnit = (maxFeeRemainder * _tradeSize) / SHARE_PRECISION;

        if (KEEPER_REWARD_UNIT > maxKeeperRewardUnit) revert InvalidConstructor(); // keeper reward + fees cannot exceed 9% of tradeSize
        TRADE_SIZE = _tradeSize;
        WIN_SIZE = _tradeSize * 10;

        if (_tradeDuration < 86400) revert InvalidConstructor(); // min 24h
        TRADE_DURATION = _tradeDuration;

        if (_firstSettlementTime < block.timestamp + _tradeDuration) revert InvalidConstructor();
        nextSettlement = _firstSettlementTime;

        activeCohortID = 2;

        VAULT_REWARD = (TRADE_SIZE * SHARE_VAULT) / SHARE_PRECISION;
        FRONTEND_REWARD = (TRADE_SIZE * SHARE_FRONTEND) / SHARE_PRECISION;
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    IChainlink public immutable ORACLE;
    IChainlink private immutable SEQUENCER_UPTIME_FEED; // = IChainlink(0xFdB631F5EE196F0ed6FAa767959853A9F217697D); // liveness feed for Chainlink on Arbitrum
    uint256 private constant ORACLE_THRESHOLD_TIME = 3600; // 1h threshold for price freshness & grace period after sequencer reboot
    uint256 private immutable ORACLE_DECIMALS; // Decimals of the oracle price feed

    uint256 private constant MAX_COHORT_SIZE = 2200;

    uint256 public constant SHARE_PRECISION = 1000;
    uint256 public constant SHARE_VAULT = 50; // 5% of trade volume
    uint256 public constant SHARE_FRONTEND = 30; // 3% of trade volume

    uint256 private constant KEEPER_REWARD_UNIT = 1e14; // Multiplied by the cohortSize to get the reward for settlement
    uint256 private constant MIN_KEEPER_REWARD = 1e15; // min 0.001 ETH reward for settling a cohort
    uint256 private immutable VAULT_REWARD;
    uint256 private immutable FRONTEND_REWARD;

    ITopCutVault public immutable TOP_CUT_VAULT;
    uint256 public immutable TRADE_DURATION; // The duration when no new trades are accepted before a cohort is settled
    uint256 public immutable TRADE_SIZE; // The amount of ETH that traders pay for each prediction
    uint256 public immutable WIN_SIZE; // Winning trades get back 10x of the TradeSize
    uint256 public constant PREDICTION_DECIMALS = 18; // Decimals of the price input by traders - oracle price is normalized to match

    uint256 public activeCohortID;
    uint256 public cohortSize_1; // Tracks trades in the cohort 1
    uint256 public cohortSize_2; // Tracks trades in the cohort 2

    uint256 public nextSettlement; // Time when the active Cohort can be settled

    struct tradeData {
        address predictionOwner;
        uint256 prediction;
    }

    mapping(uint256 tradeID => tradeData) public tradesCohort_1;
    mapping(uint256 tradeID => tradeData) public tradesCohort_2;

    mapping(address trader => uint256 claim) public claimAmounts; // Amount of ETH payouts a winner can claim
    uint256 public totalPendingClaims; // Sum of all claim amounts

    mapping(address keeper => uint256 claim) public keeperRewards; // Amount of ETH a keeper can claim

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event PredictionPosted(address indexed user, uint256 indexed settlementTime, uint256 price);
    event CohortSettled(uint256 cohortSize, uint256 winners, uint256 settlementPrice, uint256 settlementTime);
    event PrizesClaimed(address indexed user, uint256 claimedAmount);

    // ============================================
    // ==           EXTERNAL FUNCTIONS           ==
    // ============================================
    ///@notice Traders enter their price predictions and pay ETH according to TradeSize
    ///@dev Frontends add their wallet address to receive a volume share as compensation for providing access
    ///@dev A referral ID must be assigned with each trade and it must be an existing TopCut NFT ID
    ///@dev Predictions are not accepted within TRADE_DURATION before settlement
    function castPrediction(address _frontend, uint256 _refID, uint256 _price, uint256 _cohortID) external payable {
        address user = msg.sender;

        // CHECKS
        ///@dev Validate frontend beneficiary and price prediction
        if (_frontend == address(0)) revert ZeroAddress();
        if (_price == 0) revert InvalidPrice();

        ///@dev Enforce uniform trade size of each prediction
        if (msg.value != TRADE_SIZE) revert InvalidTradeSize();

        ///@dev Ensure that the prediction is entered in the valid cohort (next cohort)
        if (_cohortID == activeCohortID) revert InvalidCohortID();

        ///@dev Only allow predictions if the settlement of the active cohort is not overdue
        uint256 settlementTime = nextSettlement;
        if (block.timestamp >= settlementTime) revert WaitingToSettle();

        ///@dev Get the number of predictions from the next cohort because the active cohort is blocked and waiting for settlement
        uint256 tradeCounter = (activeCohortID == 2) ? cohortSize_1 : cohortSize_2;

        ///@dev Enforce the ceiling of cohort size
        if (tradeCounter == MAX_COHORT_SIZE) revert CohortFull();

        // EFFECTS
        ///@dev Save the prediction and trader address in storage
        ///@dev Increase the trade counter of the respective cohort
        tradeData memory data;
        data.predictionOwner = user;
        data.prediction = _price;

        ///@dev Add prediction to the next cohort, because the active cohort is blocked and waits for settlement
        if (activeCohortID == 2) {
            tradesCohort_1[tradeCounter] = data;
            cohortSize_1 = tradeCounter + 1;
        } else {
            tradesCohort_2[tradeCounter] = data;
            cohortSize_2 = tradeCounter + 1;
        }

        ///@dev Add the trade duration to the current settlement time to attribute this prediction to the next cohort via event
        settlementTime += TRADE_DURATION;

        // INTERACTIONS
        ///@dev Update Loyalty Points and Affiliate Points in the TopCut Vault
        ///@dev Send the Vault rev share with the function call
        TOP_CUT_VAULT.updatePoints{value: VAULT_REWARD}(user, _refID);

        ///@dev Send frontend reward
        (bool sent,) = payable(_frontend).call{value: FRONTEND_REWARD}("");
        if (!sent) revert FailedToSendFrontendReward();

        ///@dev Emit event that informs about this prediction
        emit PredictionPosted(user, settlementTime, _price);
    }

    ///@notice Find the winning predictions of the active Cohort and save in storage
    ///@dev Update the winnersList[] array with owners of the smallest differences (most precise)
    ///@dev Compensate a permissionless keeper for running this function
    function settleCohort() external {
        // CHECKS
        ///@dev Ensure that the L2 sequencer is live and was not restarted just recently
        _checkSequencerStatus();

        ///@dev Get the settlement price and timestamps from the oracle
        (uint80 roundId, int256 price, /*uint256 startedAt*/, uint256 updatedAt, uint80 answeredInRound) =
            ORACLE.latestRoundData();

        ///@dev Perform validation checks on the oracle feed
        _validatePriceData(roundId, price, updatedAt, answeredInRound);

        ///@dev Ensure that the settlement time is reached
        uint256 settlementTime = nextSettlement;
        if (block.timestamp < settlementTime) revert CohortActive();

        ///@dev Typecast oracle price to uint256 and normalize to prediction input precision
        uint256 settlementPrice = (uint256(price) * (10 ** PREDICTION_DECIMALS)) / (10 ** ORACLE_DECIMALS);

        ///@dev Get the cohort size of the active cohort
        uint256 activeID = activeCohortID;
        uint256 _cohortSize = (activeID == 2) ? cohortSize_2 : cohortSize_1; // Cache for gas savings

        ///@dev Evaluate only if there was at least 1 trade, otherwise skip to end
        uint256 cohortWinners;
        if (_cohortSize > 0) {
            // EFFECTS
            ///@dev Calculate number of winners and update the global tracker of pending claims
            cohortWinners = (_cohortSize > 11) ? _cohortSize / 11 : 1; // Minimum 1 winner
            totalPendingClaims = totalPendingClaims + (cohortWinners * WIN_SIZE);

            ///@dev Find the winners by looping through all predictions & save the most precise 1 out of 11
            uint256[] memory winnerDiffs = new uint256[](cohortWinners); // absolute differences to oracle price of winning predictions
            address[] memory owners = new address[](cohortWinners); // owner addresses of the winning predictions

            uint256 currentMaxIndex = 0;
            uint256 currentMaxValue = 0; // maximum deviation among winning predictions

            tradeData memory data;
            uint256 prediction;
            uint256 diff;
            address owner;

            ///@dev Loop through all predictions of the active cohort & calculate differences to settlement price
            for (uint256 i = 0; i < _cohortSize; i++) {
                data = (activeID == 2) ? tradesCohort_2[i] : tradesCohort_1[i];

                prediction = data.prediction;
                diff = (prediction > settlementPrice) ? prediction - settlementPrice : settlementPrice - prediction; // Absolute difference to settlement price
                owner = data.predictionOwner;

                ///@dev Populate the winner list and track largest difference
                if (i < cohortWinners) {
                    winnerDiffs[i] = diff;
                    owners[i] = owner;

                    if (diff >= currentMaxValue) {
                        currentMaxValue = diff;
                        currentMaxIndex = i;
                    }

                    ///@dev After winner list is populated, only replace winners if evaluated prediction is more precise than current largest difference
                } else if (diff < currentMaxValue) {
                    winnerDiffs[currentMaxIndex] = diff;
                    owners[currentMaxIndex] = owner;

                    ///@dev Find the new maximum value in the array (worst prediction among the winners)
                    currentMaxIndex = _findMaxIndex(winnerDiffs);
                    currentMaxValue = winnerDiffs[currentMaxIndex];
                }
            }

            ///@dev Update the pending claim amount for each winning address
            for (uint256 i = 0; i < cohortWinners; i++) {
                claimAmounts[owners[i]] = claimAmounts[owners[i]] + WIN_SIZE;
            }
        }

        ///@dev Update the settlement time for the next round
        nextSettlement = settlementTime + TRADE_DURATION;

        ///@dev Increase keeper rewards based on the number of traders in the Cohort & ensure a minimum compensation
        uint256 keeperReward = getSettlementReward();
        keeperRewards[msg.sender] += keeperReward;

        ///@dev Transition the active cohort 1 -> 2 or 2 -> 1 and reset the settled cohort size
        if (activeID == 2) {
            activeCohortID = 1;
            cohortSize_2 = 0;
        } else {
            activeCohortID = 2;
            cohortSize_1 = 0;
        }

        // INTERACTIONS
        ///@dev Emit event that the cohort was settled
        emit CohortSettled(_cohortSize, cohortWinners, settlementPrice, settlementTime);
    }

    ///@notice Calculate the reward for permissionless settlement
    function getSettlementReward() public view returns (uint256 keeperReward) {
        ///@dev Get the cohort size of the active cohort
        uint256 _cohortSize = (activeCohortID == 2) ? cohortSize_2 : cohortSize_1;

        ///@dev Calculate and return the reward for settlement
        keeperReward = (_cohortSize * KEEPER_REWARD_UNIT < MIN_KEEPER_REWARD)
            ? MIN_KEEPER_REWARD
            : _cohortSize * KEEPER_REWARD_UNIT;
    }

    ///@notice Enable users to claim their pending prizes
    function claim() external {
        // CHECKS
        ///@dev Ensure that the user has pending claims
        address user = msg.sender;
        uint256 amount = claimAmounts[user];
        if (amount == 0) revert NoClaims();

        ///@dev Ensure that the contract has enough ETH
        if (amount > address(this).balance) revert InsufficientBalance();

        // EFFECTS
        ///@dev Update the pending amount
        claimAmounts[user] = 0;

        ///@dev Update the global tracker of pending claims
        totalPendingClaims -= amount;

        // INTERACTIONS
        ///@dev Distribute ETH to the user
        (bool sent,) = payable(user).call{value: amount}("");
        if (!sent) revert FailedToSendWinnerReward();

        ///@dev Emit the event that the user claimed ETH
        emit PrizesClaimed(user, amount);
    }

    ///@notice Enable keepers who settle markets to claim their ETH rewards
    ///@dev Make sure the recipient can receive ETH
    ///@dev No event because this function is only relevant for experts and does not need to be tracked
    function claimKeeperReward(address _recipient, uint256 _amountETH) external {
        // CHECKS
        ///@dev Standard checks
        if (_recipient == address(0)) revert ZeroAddress();
        if (_amountETH == 0) revert InvalidAmount();

        ///@dev Check for sufficient ETH in the contract when considering pending claims
        uint256 withdrawable =
            (totalPendingClaims < address(this).balance) ? address(this).balance - totalPendingClaims : 0;
        if (_amountETH > withdrawable) revert InsufficientBalance();

        ///@dev Validate the amount to be claimed by the keeper
        uint256 rewards = keeperRewards[msg.sender];
        if (_amountETH > rewards) revert InvalidAmount();

        // EFFECTS
        ///@dev Deduct the claimed amount from rewards
        keeperRewards[msg.sender] = rewards - _amountETH;

        // INTERACTIONS
        ///@dev Distribute ETH to the recipient as specified by the keeper
        (bool sent,) = payable(_recipient).call{value: _amountETH}("");
        if (!sent) revert FailedToSendKeeperReward();
    }

    // ============================================
    // ==          INTERNAL FUNCTIONS            ==
    // ============================================
    /// @notice Find the index of the largest number in a memory array
    function _findMaxIndex(uint256[] memory array) private pure returns (uint256 maxIndex) {
        ///@dev Presume that the largest number is at index 0, then search rest of the array
        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] > array[maxIndex]) {
                maxIndex = i;
            }
        }
    }

    ///@notice Ensures that the L2 sequencer is live and that a grace period has passed since restart
    function _checkSequencerStatus() internal view {
        (
            /*uint80 roundID*/
            ,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = SEQUENCER_UPTIME_FEED.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown();
        }

        // Make sure grace period has passed after sequencer comes back up
        uint256 timeSinceUp = (block.timestamp < startedAt) ? 0 : block.timestamp - startedAt;
        if (timeSinceUp <= ORACLE_THRESHOLD_TIME) {
            revert GracePeriodNotOver();
        }
    }

    ///@notice Validates the data provided by Chainlink
    function _validatePriceData(uint80 roundId, int256 price, uint256 updatedAt, uint80 answeredInRound)
        internal
        view
    {
        // Check for stale data & round completion (round incomplete when updatedAt == 0)
        // Incomplete rounds will always revert because block.timestamp > (0 + ORACLE_THRESHOLD_TIME)
        uint256 timeDiff = (block.timestamp < updatedAt) ? 0 : block.timestamp - updatedAt;
        if (timeDiff > ORACLE_THRESHOLD_TIME) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        // Check for valid price
        if (price <= 0) revert InvalidPrice();
    }
}
