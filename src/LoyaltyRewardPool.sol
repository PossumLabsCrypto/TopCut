// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.19;

import {IPasselNFT} from "./interfaces/IPasselNFT.sol";

// ============================================
error FailedToSendNativeToken();
error InsufficientReceived();
error InvalidAffiliateID();
error InvalidMarket();
error NotAuthorized();
error Timelock();
error TokenExists();
// ============================================

/// @title Loyalty Reward Pool
/// @author Possum Labs
/**
 * @notice This contract receives ETH from TopCutMarket contracts
 * Traders receive Loyalty Points when trading via a registered TopCutMarket
 * The owner can add and remove TopCutMarkets from the LoyaltyRewardPool
 * Every week, the trader with the most Loyalty Points receives 1% of the Reward Pool's ETH balance
 * The Loyalty Points of the trader receiving the weekly draw are reset to 0
 * The LoyaltyRewardPool has one associated and immutable Affiliate NFT collection to reward growth efforts
 */
contract LoyaltyRewardPool {
    constructor() {
        nextDistributionTime = block.timestamp + (4 * TIMELOCK);
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    uint256 private constant TIMELOCK = 604800;
    uint256 private constant MAX_AP_REDEEMED = 1e22; // 10k
    uint256 private constant LOYALTY_DISTRIBUTION_PERCENT = 1;

    address public owner;
    address public pendingOwner;
    uint256 public timelockEnd;

    mapping(address topCutMarket => bool isRegistered) public registeredMarkets;

    IPasselNFT public constant AFFILIATE_NFT = IPasselNFT(0xa9c2833Bb3658Db2b0d7b3CC41D851b75E3508Cf);
    uint256 private totalRedeemedAP;
    mapping(uint256 nftID => uint256 points) public affiliatePoints;

    address public loyaltyPointsLeader;
    uint256 public leadingPoints;
    mapping(address trader => uint256 points) public loyaltyPoints;

    uint256 nextDistributionTime;

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event AffiliatePointsUpdated(uint256 indexed nftID, uint256 affiliatePoints);
    event AffiliateRewardsClaimed(uint256 indexed nftID, uint256 reward);

    event LoyaltyPointsUpdated(address indexed trader, uint256 loyaltyPoints);
    event LoyaltyRewardDistributed(address indexed trader, uint256 reward);

    // ============================================
    // ==           OWNER FUNCTIONS              ==
    // ============================================
    function transferOwnership(address _newOwner) external {
        if (msg.sender != owner) revert NotAuthorized();
        pendingOwner = _newOwner;
        timelockEnd = block.timestamp + TIMELOCK;
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotAuthorized();
        if (timelockEnd > block.timestamp) revert Timelock();
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    ///@notice Allow the owner to connect or disconnect markets from the LoyaltyRewardPool
    ///@dev Ownership protected to prevent malicious markets to connect
    function updateMarketRegistry(address _market, bool _registryStatus) external {
        if (msg.sender != owner) revert NotAuthorized();
        registeredMarkets[_market] = _registryStatus;
    }

    // ============================================
    // ==          AFFILIATE FUNCTIONS           ==
    // ============================================
    ///@notice Returns the pending affiliate reward in ETH when redeeming all points of the given affiliate NFT ID
    ///@dev Affiliate Points are earned by referring new traders and are recurring based on trading volume of referrees
    function getAffiliateReward(uint256 _nftID) public view returns (uint256 ethReward) {
        uint256 points = affiliatePoints[_nftID];
        uint256 ethBalance = address(this).balance;
        uint256 newTotalAffiliatePoints = totalRedeemedAP + points;

        ///@dev Calculate the ETH rewards received by the affiliate after pool protection (slippage as in AMM)
        ethReward = (ethBalance * points) / newTotalAffiliatePoints;
    }

    ///@notice Allow affiliates to claim the ETH rewards for their Affiliate NFT
    ///@dev Redeem Affiliate Points of an NFT and send ETH to the NFT owner
    function claimAffiliateReward(uint256 _nftID, uint256 _minReceived) external {
        // CHECKS
        ///@dev Check that the reward request comes from the NFT owner
        if (msg.sender != AFFILIATE_NFT.ownerOf(_nftID)) revert NotAuthorized();

        ///@dev Ensure that the received amount matches the expected minimum
        uint256 rewardsReceived = getAffiliateReward(_nftID);
        if (rewardsReceived < _minReceived) revert InsufficientReceived();

        // EFFECTS
        ///@dev Increase the redeemed point tracker until maximum
        if (totalRedeemedAP < MAX_AP_REDEEMED) {
            totalRedeemedAP = (totalRedeemedAP + affiliatePoints[_nftID] < MAX_AP_REDEEMED)
                ? totalRedeemedAP + affiliatePoints[_nftID]
                : MAX_AP_REDEEMED;
        }

        ///@dev Update the affiliate points of the NFT
        affiliatePoints[_nftID] = 0;

        // INTERACTONS
        ///@dev Send the ETH reward to the affiliate
        (bool sent,) = payable(msg.sender).call{value: rewardsReceived}("");
        if (!sent) revert FailedToSendNativeToken();

        emit AffiliateRewardsClaimed(_nftID, rewardsReceived);
    }

    // ============================================
    // ==            LOYALTY REWARDS             ==
    // ============================================
    ///@notice Enable registered markets to update loyalty points of traders and affiliate points of NFTs
    ///@dev After updating the points, this function attempts to distribute the loyalty rewards of the current epoch
    function updateLoyaltyPoints(address _trader, uint256 _points, uint256 _nftID) external {
        // CHECKS
        ///@dev Ensure only a registered market can call this function
        if (!registeredMarkets[msg.sender]) revert InvalidMarket();

        ///@dev Ensure that the affiliate points can be assigned to an existing NFT
        if (_nftID >= AFFILIATE_NFT.totalSupply()) revert InvalidAffiliateID();

        // EFFECTS
        ///@dev Update the trader's loyalty points
        uint256 newPoints = loyaltyPoints[_trader] + _points;
        loyaltyPoints[_trader] = newPoints;

        ///@dev Check if the trader becomes the new active point leader
        if (newPoints > leadingPoints) {
            loyaltyPointsLeader = _trader;
            leadingPoints = newPoints;
        }

        ///@dev Update the points of the affiliate NFT
        uint256 newAffiliatePoints = affiliatePoints[_nftID] + _points;
        affiliatePoints[_nftID] = newAffiliatePoints;

        // INTERACTIONS
        ///@dev Emit events for updating the loyalty and affiliate points
        emit LoyaltyPointsUpdated(_trader, newPoints);
        emit AffiliatePointsUpdated(_nftID, newAffiliatePoints);

        ///@dev Attempt to distribute the loyalty reward and move to the next epoch
        distributeLoyaltyReward(loyaltyPointsLeader);
    }

    function distributeLoyaltyReward(address _recipient) private {
        // CHECKS
        ///@dev Ensure that the current distribution epoch has ended
        if (block.timestamp >= nextDistributionTime) {
            // EFFECTS
            ///@dev Set distribution time for the next epoch
            nextDistributionTime + TIMELOCK;

            ///@dev Calculate the reward to be distributed
            uint256 balanceETH = address(this).balance;
            uint256 loyaltyDistribution = (balanceETH * LOYALTY_DISTRIBUTION_PERCENT) / 100;

            ///@dev Reset the trader's loyalty points & global trackers
            loyaltyPoints[_recipient] = 0;
            loyaltyPointsLeader = address(0);
            leadingPoints = 0;

            // INTERACTIONS
            ///@dev Send the ETH reward to the former points leader (recipient)
            ///@dev Keep ETH in the contract if the transfer fails but execute the function anyways
            (bool sent,) = payable(_recipient).call{value: loyaltyDistribution}("");
            if (!sent) loyaltyDistribution = 0;

            emit LoyaltyRewardDistributed(_recipient, loyaltyDistribution);
        }
    }

    // ============================================
    // ==              ENABLE ETH                ==
    // ============================================
    receive() external payable {}

    fallback() external payable {}
}
