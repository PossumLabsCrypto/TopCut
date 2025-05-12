// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IChainlink} from "./interfaces/IChainlink.sol";
import {ITopCutVault} from "./interfaces/ITopCutVault.sol";

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
        address _topCutVault,
        uint256 _maxCohortSize,
        uint256 _tradeSize,
        uint256 _tradeDuration,
        uint256 _firstSettlementTime
    ) {
        if (_oracleContract == address(0)) revert InvalidConstructor();
        ORACLE = IChainlink(_oracleContract);
        ORACLE_DECIMALS = ORACLE.decimals();

        if (_topCutVault == address(0)) revert InvalidConstructor();
        TOP_CUT_VAULT = ITopCutVault(_topCutVault);

        if (_maxCohortSize < 330 || _maxCohortSize > 3300) revert InvalidConstructor();
        MAX_COHORT_SIZE = _maxCohortSize;
        uint256 max_winners = _maxCohortSize / (11);

        if (_tradeDuration < 86400) revert InvalidConstructor(); // min 24h
        TRADE_DURATION = _tradeDuration;

        if (_tradeSize == 0) revert InvalidConstructor();
        TRADE_SIZE = _tradeSize;
        WIN_SIZE = _tradeSize * 10;

        if (_firstSettlementTime < block.timestamp + _tradeDuration * 3) revert InvalidConstructor();
        FIRST_SETTLEMENT = _firstSettlementTime;

        // Allocate storage space for up to max winners with non-zero values (use vault as dummy address)
        for (uint256 i = 0; i < max_winners; i++) {
            winnersList.push(_topCutVault);
        }
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    IChainlink private immutable ORACLE;
    uint256 private immutable ORACLE_DECIMALS; // Decimals of the oracle price feed

    uint256 private immutable MAX_COHORT_SIZE;
    uint256 private immutable FIRST_SETTLEMENT;

    uint256 private cohortSize; // Tracks trades in a cohort
    uint256 private activeCohortID; // ID of the current cohort that accepts predictions

    uint256 public constant SHARE_PRECISION = 1000;
    uint256 public constant SHARE_VAULT = 50; // 5% of trade volume
    uint256 public constant SHARE_FRONTEND = 30; // 3% of trade volume
    uint256 public constant SHARE_KEEPER = 10; // 1% of trade volume

    ITopCutVault public immutable TOP_CUT_VAULT;
    uint256 public immutable TRADE_DURATION; // The duration when no new trades are accepted before a cohort is settled
    uint256 public immutable TRADE_SIZE; // The amount of ETH that traders pay for each prediction
    uint256 public immutable WIN_SIZE; // Winning trades get back 10x of the TradeSize
    uint256 public constant PREDICTION_DECIMALS = 18; // Decimals of the price input by traders - oracle price is normalized to match

    uint256 public nextSettlement; // Time when the current Cohort can be settled
    mapping(uint256 tradeID => uint256 prediction) public predictions; // Predictions to evaluate
    mapping(uint256 tradeID => address user) public predictionOwners; // Who submitted each prediction
    mapping(address winner => uint256 profit) public claimAmounts; // Amount of ETH payouts a winner can receive
    uint256 public totalPendingClaims; // Sum of all users claim amounts
    address[] public winnersList; // Top-N best accuracy prediction owners

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event PredictionPosted(address indexed user, uint256 indexed price);
    event CohortSettled(uint256 indexed cohortID, uint256 cohortSize, uint256 winners, uint256 keeperShare);
    event PendingClaims(address indexed user, uint256 pendingClaimAmount);

    // ============================================
    // ==            WRITE FUNCTIONS             ==
    // ============================================
    ///@notice Traders enter their price predictions and pay ETH according to TradeSize
    ///@dev Frontends add their wallet address to receive a volume share as compensation for providing access
    ///@dev A referral ID must be assigned with each trade and it must be an existing TopCut NFT ID
    ///@dev Predictions are not accepted within TRADE_DURATION before settlement
    function castPrediction(address _frontend, uint256 _refID, uint256 _price) external payable {
        address user = msg.sender;
        uint256 tradeSize = msg.value;

        // CHECKS
        ///@dev Input validation. refID is validated in the Vault.
        if (_frontend == address(0)) revert ZeroAddress();
        if (_price == 0) revert InvalidPrice();

        ///@dev Ensure ceiling of the cohort size is maintained
        if (cohortSize == MAX_COHORT_SIZE) revert CohortFull();

        ///@dev Ensure that predictions can only be cast if there is at least TRADE_DURATION seconds until settlement
        if (block.timestamp + TRADE_DURATION > nextSettlement) revert WaitingToSettle();

        ///@dev Enforce uniform trade size of each prediction
        if (tradeSize != TRADE_SIZE) revert InvalidTradeSize();

        // EFFECTS
        ///@dev Save the prediction and trader in storage
        predictions[cohortSize] = _price;
        predictionOwners[cohortSize] = user;

        ///@dev Increase the counter of this cohort
        cohortSize += 1;

        // INTERACTIONS
        ///@dev Update the user's Loyalty Points and referrers Affiliate Points in the TopCut Vault
        ///@dev Send the Vault share with the function call
        uint256 vaultReward = (tradeSize * SHARE_VAULT) / SHARE_PRECISION;
        TOP_CUT_VAULT.updatePoints{value: vaultReward}(user, _refID);

        ///@dev Send frontend reward
        uint256 frontendReward = (tradeSize * SHARE_FRONTEND) / SHARE_PRECISION;
        (bool sent,) = payable(msg.sender).call{value: frontendReward}("");
        if (!sent) revert FailedToSendFrontendReward();

        ///@dev Emit event that informs about this prediction
        emit PredictionPosted(user, _price);
    }

    ///@notice Find the winning predictions of the active Cohort and save in storage
    ///@dev Update the winnersList[] array with owners of the smallest differences (most precise)
    ///@dev Compensate a permissionless keeper for running this function
    function settleCohort() external {
        // CHECKS
        ///@dev Ensure that the settlement time is reached
        if (block.timestamp < nextSettlement) revert activeCohort();

        ///@dev Get the settlement price and timestamp from the oracle
        (, int256 price,, uint256 updatedAt,) = ORACLE.latestRoundData();

        ///@dev Ensure that the oracle price was updated after the settlement time
        if (updatedAt < nextSettlement) revert StaleOraclePrice();

        ///@dev Typecast oracle price to uint256 and normalize to price prediction input precision
        uint256 settlementPrice = (uint256(price) * (10 ** PREDICTION_DECIMALS)) / (10 ** ORACLE_DECIMALS);

        ///@dev Evaluate only if there was at least 1 trade, otherwise skip to end
        uint256 cohortWinners;
        uint256 _cohortSize = cohortSize; // Cache for gas savings
        if (_cohortSize > 0) {
            // EFFECTS
            cohortWinners = (_cohortSize > 11) ? _cohortSize / 11 : 1; // Minimum 1 winner

            ///@dev Find the winners by looping through all predictions & save the most precise 9%
            uint256[] memory winnerDiffs = new uint256[](cohortWinners); // absolute differences to oracle price of winning predictions
            address[] memory owners = new address[](cohortWinners); // owner addresses of the winning predictions

            uint256 currentMaxIndex = 0;
            uint256 currentMaxValue = 0;

            ///@dev Loop over all predictions of this cohort in the mapping & calculate differences to settlement price
            for (uint256 i = 0; i < _cohortSize; i++) {
                uint256 prediction = predictions[i]; // Cache from storage
                uint256 diff =
                    (prediction > settlementPrice) ? prediction - settlementPrice : settlementPrice - prediction; // Absolute difference to settlement price
                address owner = predictionOwners[i];

                ///@dev Populate the winner list and track largest difference
                if (i < cohortWinners) {
                    winnerDiffs[i] = diff;
                    owners[i] = owner;

                    if (diff > currentMaxValue) {
                        currentMaxValue = diff;
                        currentMaxIndex = i;
                    }

                    ///@dev After winner list is populated, only replace winners if prediction is more precise than current worst winner
                } else if (diff < currentMaxValue) {
                    winnerDiffs[currentMaxIndex] = diff;
                    owners[currentMaxIndex] = owner;

                    ///@dev Get the new maximum value in the array (worst prediction among the winners)
                    currentMaxIndex = findMaxIndex(winnerDiffs);
                    currentMaxValue = winnerDiffs[currentMaxIndex];
                }
            }

            ///@dev Store winners in storage: winnersList[0 to cohortWinners-1]
            for (uint256 i = 0; i < cohortWinners; i++) {
                winnersList[i] = owners[i];

                ///@dev Update the pending claim amount for each winning address
                uint256 _claimAmount = claimAmounts[owners[i]] + WIN_SIZE;
                claimAmounts[owners[i]] = _claimAmount;

                ///@dev Emit event to notify keepers of the new pending claims
                emit PendingClaims(owners[i], _claimAmount);
            }

            ///@dev Update the global tracker of pending claims
            uint256 addedClaims = cohortWinners * WIN_SIZE;
            totalPendingClaims += addedClaims;
        }

        ///@dev Advance the Cohort so that new predictions are possible
        uint256 cohort = activeCohortID;
        activeCohortID = cohort + 1;

        ///@dev Update the settlement time for the next round
        ///@dev Trade duration is added twice to give time for traders to enter predictions
        ///@dev To get 1 settlement every Trade duration (e.g. 24h), deploy two contracts with an offset
        nextSettlement = FIRST_SETTLEMENT + (activeCohortID * TRADE_DURATION * 2);

        ///@dev Reset the Cohort Size for the next round
        cohortSize = 0;

        // INTERACTIONS
        ///@dev Compensate the keeper based on the volume of the Cohort
        uint256 keeperReward = (_cohortSize * TRADE_SIZE * SHARE_KEEPER) / SHARE_PRECISION;
        (bool sent,) = payable(msg.sender).call{value: keeperReward}("");
        if (!sent) revert FailedToSendKeeperReward();

        ///@dev Emit event that the cohort was settled
        emit CohortSettled(cohort, _cohortSize, cohortWinners, keeperReward);
    }

    ///@notice Enable users to claim their profits
    function claim() external {
        // CHECKS
        ///@dev Ensure that the user has pending claims
        address user = msg.sender;
        uint256 amount = claimAmounts[user];
        if (amount == 0) revert NoClaims();

        ///@dev Ensure that the contract has enough ETH
        uint256 balance = address(this).balance;
        if (amount > balance) revert InsufficientBalance();

        // EFFECTS
        ///@dev Update the pending claims
        claimAmounts[user] = 0;

        ///@dev Update the global tracker of pending claims
        totalPendingClaims -= amount;

        // INTERACTIONS
        ///@dev Distribute ETH to the user
        (bool sent,) = payable(user).call{value: amount}("");
        if (!sent) revert FailedToSendWinnerReward();

        ///@dev Update the pending distributions
        emit PendingClaims(user, 0);
    }

    ///@notice Send surplus ETH balance to the Vault
    ///@dev Make use of ETH in the contract that is not required to cover pending claims
    ///@dev A small surplus occurs frequently when rounding down winners per Cohort (cohortSize / 11)
    ///@dev A deficit occurs if cohortSize < 11 which is offset by more participants later
    function skimSurplus() external {
        uint256 balance = address(this).balance;

        ///@dev Calculate balance associated with active trades + buffer
        uint256 reservedTradeVolume = (
            cohortSize * TRADE_SIZE * (SHARE_PRECISION - (SHARE_VAULT + SHARE_FRONTEND + SHARE_KEEPER))
        ) / SHARE_PRECISION;
        uint256 buffer = WIN_SIZE;

        ///@dev Check for surplus ETH balance
        uint256 surplusBalance = ((totalPendingClaims + reservedTradeVolume + buffer) < balance)
            ? balance - (totalPendingClaims + reservedTradeVolume + buffer)
            : 0;

        if (surplusBalance > 0) {
            uint256 keeperReward = surplusBalance / 20; // 5% of surplus
            uint256 sendAmount = surplusBalance - keeperReward;

            ///@dev Send net surplus ETH to the Vault
            (bool sent,) = payable(address(TOP_CUT_VAULT)).call{value: sendAmount}("");
            if (!sent) revert FailedToSkimSurplus();

            ///@dev Send keeper incentive (larger share than for settlement because low value transactions)
            (sent,) = payable(msg.sender).call{value: keeperReward}("");
            if (!sent) revert FailedToSkimSurplus();
        }
    }

    // ============================================
    // ==             READ FUNCTIONS             ==
    // ============================================
    /// @notice Find the index of the largest number in a memory array
    function findMaxIndex(uint256[] memory array) private pure returns (uint256 maxIndex) {
        ///@dev Presume that the largest number is at index 0, then search rest of the array
        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] > array[maxIndex]) {
                maxIndex = i;
            }
        }
    }
}
