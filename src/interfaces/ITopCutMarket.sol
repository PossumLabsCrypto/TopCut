// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface ITopCutMarket {
    function SHARE_PRECISION() external view returns (uint256);
    function SHARE_VAULT() external view returns (uint256);
    function SHARE_FRONTEND() external view returns (uint256);
    function SHARE_KEEPER() external view returns (uint256);

    function TOP_CUT_VAULT() external view returns (address);
    function TRADE_DURATION() external view returns (uint256);
    function TRADE_SIZE() external view returns (uint256);
    function WIN_SIZE() external view returns (uint256);
    function PREDICTION_DECIMALS() external view returns (uint256);

    function nextSettlement() external view returns (uint256);

    function predictions(uint256 tradeID) external view returns (uint256);
    function predictionOwners(uint256 tradeID) external view returns (address);
    function claimAmounts(address trader) external view returns (uint256);

    function totalPendingClaims() external view returns (uint256);
    function winnersList() external view returns (uint256[] memory);
}
