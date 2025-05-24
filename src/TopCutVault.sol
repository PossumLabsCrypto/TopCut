// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TopCutNFT} from "./TopCutNFT.sol";
import {ITopCutNFT} from "./interfaces/ITopCutNFT.sol";

// ============================================
error CeilingBreached();
error DeadlineExpired();
error FailedToSendNativeToken();
error InsufficientPoints();
error InsufficientReceived();
error InvalidAffiliateID();
error InvalidConstructor();
error InvalidPaidETH();
error InvalidToken();
error NotOwnerOfNFT();
error ZeroPointRedeem();
error ZeroAddress();
// ============================================

/// @title TopCut Vault
/// @author Possum Labs
/**
 * @notice This contract receives ETH from TopCut Markets to distributes Loyalty Rewards and Affiliate Rewards
 * Traders receive Loyalty Points when trading on a TopCutMarket
 * Every week, the trader with the most Loyalty Points receives 1% of the Reward Pool's ETH balance
 * The Loyalty Points of the trader receiving the weekly draw are reset to 0
 * The LoyaltyRewardPool has one associated and immutable Affiliate NFT collection to reward growth efforts
 */
contract TopCutVault {
    constructor(bytes32 _salt, uint256 _firstDistributionTime) {
        ///@dev Enforce a minimum of 2 weeks from deployment until distributing the first loyalty reward
        if (_firstDistributionTime < block.timestamp + DISTRIBUTION_INTERVAL) revert InvalidConstructor();
        nextDistributionTime = _firstDistributionTime;

        ///@dev Deploy the affiliate NFT contract
        TopCutNFT nft = new TopCutNFT{salt: _salt}("TopCut Affiliates", "TCA");
        address nft_address = address(nft);
        AFFILIATE_NFT = ITopCutNFT(nft_address);

        totalRedeemedAP = 1e18; // Set starting value to 1 point
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    using SafeERC20 for IERC20;

    uint256 private constant DISTRIBUTION_INTERVAL = 604800; // 7 days between loyalty reward distributions
    uint256 private constant MAX_AP_REDEEMED = 5e22; // 50k points
    uint256 private constant LOYALTY_DISTRIBUTION_PERCENT = 1;

    IERC20 private constant PSM = IERC20(0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5);
    uint256 private constant PSM_REDEEM_DENOMINATOR = 1e26; // 100M PSM for 50% of vault
    uint256 private constant PSM_CEILING = 1e28; // 10Bn = PSM max total supply as defined on L1
    uint256 private totalRedeemedPSM;

    uint256 public constant EXTRACTION_FEE_ETH = 1e19; // 10 ETH to extract any token aside from PSM

    ITopCutNFT public immutable AFFILIATE_NFT;
    uint256 private totalRedeemedAP;
    mapping(uint256 nftID => uint256 points) public affiliatePoints;

    address public loyaltyPointsLeader;
    uint256 public leadingPoints;
    uint256 public nextDistributionTime;

    mapping(address trader => uint256 points) public loyaltyPoints;

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event AffiliatePointsUpdated(uint256 indexed nftID, uint256 affiliatePoints);
    event AffiliateRewardsClaimed(uint256 indexed nftID, uint256 reward);

    event LoyaltyPointsUpdated(address indexed trader, uint256 loyaltyPoints);
    event LoyaltyRewardDistributed(address indexed trader, uint256 reward);

    event RedeemedPSM(address indexed user, uint256 amountPSM, uint256 reward);

    // ============================================
    // ==            LOYALTY REWARDS             ==
    // ============================================
    ///@notice Allow any address that pays ETH to update loyalty points of traders and affiliate points of NFTs
    ///@dev After updating the points, this function attempts to distribute the loyalty rewards of the current epoch
    function updatePoints(address _trader, uint256 _refID) external payable {
        // CHECKS
        ///@dev Avoid points for the zero address
        if (_trader == address(0)) revert ZeroAddress();

        ///@dev Ensure that the affiliate points can be assigned to an existing NFT
        if (_refID >= AFFILIATE_NFT.totalSupply()) revert InvalidAffiliateID();

        // EFFECTS
        ///@dev Calculate the trader's added loyalty points based on received ETH
        uint256 accruedPoints = msg.value;

        ///@dev Update the trader's loyalty points
        uint256 newPoints = loyaltyPoints[_trader] + accruedPoints;
        loyaltyPoints[_trader] = newPoints;

        ///@dev Check if the trader becomes the new active point leader
        if (newPoints > leadingPoints) {
            loyaltyPointsLeader = _trader;
            leadingPoints = newPoints;
        }

        ///@dev Update the points of the affiliate NFT
        ///@dev Handle persistence of ref IDs via the frontend / access point
        uint256 newAffiliatePoints = affiliatePoints[_refID] + accruedPoints;
        affiliatePoints[_refID] = newAffiliatePoints;

        // INTERACTIONS
        ///@dev Emit events for updating the loyalty and affiliate points
        emit LoyaltyPointsUpdated(_trader, newPoints);
        emit AffiliatePointsUpdated(_refID, newAffiliatePoints);

        ///@dev Attempt to distribute the loyalty reward and move to the next epoch
        _distributeLoyaltyReward(loyaltyPointsLeader);
    }

    ///@notice Internal function to distribute the Loyalty Reward to the winner of the epoch
    function _distributeLoyaltyReward(address _recipient) private {
        // CHECKS
        ///@dev Check if the current distribution epoch has ended, otherwise skip to end
        if (block.timestamp >= nextDistributionTime) {
            // EFFECTS
            ///@dev Set distribution time for the next epoch
            nextDistributionTime += DISTRIBUTION_INTERVAL;

            ///@dev Calculate the reward to be distributed (1%)
            uint256 balanceETH = address(this).balance;
            uint256 loyaltyDistribution = (balanceETH * LOYALTY_DISTRIBUTION_PERCENT) / 100;

            ///@dev Reset the trader's loyalty points & global trackers
            loyaltyPoints[_recipient] = 0;
            loyaltyPointsLeader = address(0);
            leadingPoints = 0;

            // INTERACTIONS
            ///@dev Send the ETH reward to the former points leader (recipient)
            ///@dev Keep ETH in the contract if the transfer fails but continue anyways (prevent DOS)
            (bool sent,) = payable(_recipient).call{value: loyaltyDistribution}("");
            if (!sent) loyaltyDistribution = 0;

            emit LoyaltyRewardDistributed(_recipient, loyaltyDistribution);
        }
    }

    // ============================================
    // ==           AFFILIATE REWARDS            ==
    // ============================================
    ///@notice Returns the pending affiliate reward in ETH when redeeming points of the given affiliate NFT ID
    ///@dev Affiliate Points are earned by referring new traders and are recurring based on trading volume of referrees
    function quoteAffiliateReward(uint256 _pointsRedeemed) public view returns (uint256 ethReward) {
        uint256 ethBalance = address(this).balance;
        uint256 newTotalAffiliatePoints = totalRedeemedAP + _pointsRedeemed;

        ///@dev Calculate the ETH rewards received by the affiliate after pool protection (slippage as in AMM)
        ethReward = (ethBalance * _pointsRedeemed) / newTotalAffiliatePoints;
    }

    ///@notice Allow affiliates to claim the ETH rewards for their Affiliate NFT
    ///@dev Redeem Affiliate Points of an NFT and send ETH to the NFT owner
    function claimAffiliateReward(uint256 _refID, uint256 _pointsRedeemed, uint256 _minReceived, uint256 _deadline)
        external
    {
        // CHECKS
        ///@dev Check that the reward request comes from the NFT owner
        if (msg.sender != AFFILIATE_NFT.ownerOf(_refID)) revert NotOwnerOfNFT();

        ///@dev Check if any points are redeemed
        uint256 points = _pointsRedeemed;
        if (points == 0) revert ZeroPointRedeem();

        ///@dev Check for available points, fat finger protection
        if (points > affiliatePoints[_refID]) revert InsufficientPoints();

        ///@dev Ensure that the received amount matches or exceeds the expected minimum
        uint256 rewardsReceived = quoteAffiliateReward(points);
        if (rewardsReceived < _minReceived) revert InsufficientReceived();

        ///@dev Check deadline
        if (_deadline < block.timestamp) revert DeadlineExpired();

        // EFFECTS
        ///@dev Increase the redeemed point tracker ("pool size") until maximum is reached
        if (totalRedeemedAP < MAX_AP_REDEEMED) {
            totalRedeemedAP = (totalRedeemedAP + affiliatePoints[_refID] < MAX_AP_REDEEMED)
                ? totalRedeemedAP + affiliatePoints[_refID]
                : MAX_AP_REDEEMED;
        }

        ///@dev Update the affiliate points of the NFT
        affiliatePoints[_refID] -= points;

        // INTERACTONS
        ///@dev Send the ETH reward to the affiliate
        (bool sent,) = payable(msg.sender).call{value: rewardsReceived}("");
        if (!sent) revert FailedToSendNativeToken();

        emit AffiliateRewardsClaimed(_refID, rewardsReceived);
    }

    // ============================================
    // ==             POSSUM REWARDS             ==
    // ============================================
    ///@notice Returns the amount of ETH received by redeeming a given number of PSM
    ///@dev PSM is exchanged for ETH from the TopCut Vault
    ///@dev Maximum 50% of the Vault can be redeemed in one transaction
    function quoteRedeemPSM(uint256 _amountPSM) public view returns (uint256 ethOut) {
        uint256 ethBalance = address(this).balance;
        uint256 amount = _amountPSM;

        ///@dev Ensure that the PSM amount is within the maximum of a single transaction
        if (amount > PSM_REDEEM_DENOMINATOR) amount = PSM_REDEEM_DENOMINATOR;

        ///@dev Calculate the ETH received in exchange of PSM (100M for 50% of Vault)
        ethOut = (ethBalance * amount) / (2 * PSM_REDEEM_DENOMINATOR);
    }

    ///@notice Allow PSM holders to redeem their PSM for ETH from the TopCut Vault
    ///@dev Exchange PSM for ETH from the TopCut Vault where the PSM is stuck ("burned")
    function redeemPSM(uint256 _amountPSM, uint256 _minReceived, uint256 _deadline) external {
        uint256 amount = _amountPSM;
        // CHECKS
        ///@dev Ensure that the PSM amount is within the maximum for a single transaction
        if (amount > PSM_REDEEM_DENOMINATOR) amount = PSM_REDEEM_DENOMINATOR;

        ///@dev Ensure that the received amount matches the expected minimum
        uint256 received = quoteRedeemPSM(amount);
        if (received < _minReceived) revert InsufficientReceived();

        ///@dev Check deadline
        if (_deadline < block.timestamp) revert DeadlineExpired();

        ///@dev Ensure that the total redeemed PSM stays within its L1 supply constraints
        if (totalRedeemedPSM + amount > PSM_CEILING) revert CeilingBreached();

        // EFFECTS
        ///@dev Increase the redeemed PSM tracker
        totalRedeemedPSM = totalRedeemedPSM + amount;

        // INTERACTONS
        ///@dev Take PSM from the user
        PSM.safeTransferFrom(msg.sender, address(this), amount);

        ///@dev Send ETH to the user
        (bool sent,) = payable(msg.sender).call{value: received}("");
        if (!sent) revert FailedToSendNativeToken();

        emit RedeemedPSM(msg.sender, amount, received);
    }

    // ============================================
    // ==       ENABLE ETH & RANDOM ERC20        ==
    // ============================================
    ///@notice Allow anyone to withdraw the balance of an ERC20 token for a fee in ETH
    ///@dev PSM is excluded
    ///@dev This function exchanges donated tokens to increase rewards for regular users
    function extractTokenBalance(address _token, uint256 _minReceived, uint256 _deadline) external payable {
        // CHECKS
        ///@dev Enforce payment of the extraction fee in ETH
        if (msg.value != EXTRACTION_FEE_ETH) revert InvalidPaidETH();

        ///@dev Prevent Zero address and the extraction of PSM
        if (_token == address(0) || _token == address(PSM)) revert InvalidToken();

        ///@dev Enforce the deadline
        if (block.timestamp > _deadline) revert DeadlineExpired();

        ///@dev Prevent frontrunning
        uint256 balanceToken = IERC20(_token).balanceOf(address(this));
        if (balanceToken < _minReceived) revert InsufficientReceived();

        // EFFECTS - none

        // INTERACTIONS
        ///@dev Transfer the token balance to the caller
        ///@dev Caller is expected to be MEV professional and perform additional checks in case of exotic token
        IERC20(_token).transfer(msg.sender, balanceToken);
    }

    receive() external payable {}

    fallback() external payable {}
}
