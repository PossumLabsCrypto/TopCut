// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface ITopCutVault {
    function getAffiliateReward(uint256 _refID) external view returns (uint256 ethReward);
    function claimAffiliateReward(uint256 _refID, uint256 _minReceived) external;

    function updatePoints(address _trader, uint256 _refID) external payable;

    function getRedeemRewardPSM(uint256 _amountPSM) external view returns (uint256 ethReward);
    function redeemPSM(uint256 _amountPSM, uint256 _minReceived, uint256 _deadline) external;
}
