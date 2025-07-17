// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface ITopCutMarket {
    // storage
    function ORACLE() external view returns (uint256);
    function SHARE_PRECISION() external view returns (uint256);
    function SHARE_VAULT() external view returns (uint256);
    function SHARE_FRONTEND() external view returns (uint256);

    function TOP_CUT_VAULT() external view returns (address);
    function TRADE_DURATION() external view returns (uint256);
    function TRADE_SIZE() external view returns (uint256);
    function WIN_SIZE() external view returns (uint256);
    function PREDICTION_DECIMALS() external view returns (uint256);

    function activeCohortID() external view returns (uint256);
    function cohortSize_1() external view returns (uint256);
    function cohortSize_2() external view returns (uint256);
    function nextSettlement() external view returns (uint256);

    struct tradeData {
        address predictionOwner;
        uint256 prediction;
    }

    function tradesCohort_1(uint256 tradeID) external view returns (tradeData memory);
    function tradesCohort_2(uint256 tradeID) external view returns (tradeData memory);

    function claimAmounts(address trader) external view returns (uint256);
    function totalPendingClaims() external view returns (uint256);

    // functions
    function castPrediction(address _frontend, uint256 _refID, uint256 _price, uint256 _cohortID) external payable;
    function settleCohort() external;
    function claim() external;

    function getSettlementReward() external view returns (uint256 keeperReward);
    function claimKeeperReward(address _recipient, uint256 _amountETH) external;
}
