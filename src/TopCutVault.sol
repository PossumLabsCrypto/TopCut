// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TopCutNFT} from "./TopCutNFT.sol";
import {ITopCutNFT} from "./interfaces/ITopCutNFT.sol";

// ============================================
error Deadline();
error FailedToSendNativeToken();
error InsufficientReceived();
error InvalidAffiliateID();
error InvalidAmount();
error InvalidMarket();
error NotAuthorized();
error Timelock();
error CeilingReached();
// ============================================

/// @title TopCut Vault
/// @author Possum Labs
/**
 * @notice This contract receives ETH from TopCut Markets to distributes Loyalty Rewards and Affiliate Rewards
 * Traders receive Loyalty Points when trading via a registered TopCutMarket
 * The owner can add and remove TopCutMarkets from the LoyaltyRewardPool
 * Every week, the trader with the most Loyalty Points receives 1% of the Reward Pool's ETH balance
 * The Loyalty Points of the trader receiving the weekly draw are reset to 0
 * The LoyaltyRewardPool has one associated and immutable Affiliate NFT collection to reward growth efforts
 */
contract TopCutVault {
    constructor(bytes32 _salt) {
        nextDistributionTime = block.timestamp + (4 * TIMELOCK);

        ///@dev Deploy the affiliate NFT contract
        TopCutNFT nft = new TopCutNFT{salt: _salt}("TopCut Affiliates", "TCA");
        address nft_address = address(nft);
        AFFILIATE_NFT = ITopCutNFT(nft_address);

        totalRedeemedAP = 1e19; // Set starting value eq 10 ETH
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    using SafeERC20 for IERC20;

    uint256 private constant TIMELOCK = 604800; // 7 days
    uint256 private constant MAX_AP_REDEEMED = 1e24; // Reached after 1M ETH trade volume
    uint256 private constant LOYALTY_DISTRIBUTION_PERCENT = 1;

    IERC20 private constant PSM = IERC20(0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5);
    uint256 private constant PSM_REDEEM_DENOMINATOR = 1e26; // 100M PSM for 100% of vault
    uint256 private constant PSM_CEILING = 1e28; // 10Bn = PSM max total supply as defined on L1
    uint256 private totalPsmRedeemed;

    address public owner;
    address public pendingOwner;
    uint256 public timelockEnd;

    mapping(address topCutMarket => bool isRegistered) public registeredMarkets;
    mapping(address topCutMarket => uint256 timestamp) public lastChanged;

    ITopCutNFT public immutable AFFILIATE_NFT;
    uint256 private totalRedeemedAP;
    mapping(uint256 nftID => uint256 points) public affiliatePoints;

    address public loyaltyPointsLeader;
    uint256 public leadingPoints;
    uint256 public nextDistributionTime;

    mapping(address trader => uint256 points) public loyaltyPoints;
    mapping(address trader => uint256 refID) public refRecords;

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event OwnerTransferStarted(address newOwner, uint256 acceptanceTime);
    event OwnerTransferCompleted(address newOwner);

    event MarketStatusUpdated(address indexed market, bool registered, uint256 lastUpdateTime);

    event AffiliatePointsUpdated(uint256 indexed nftID, uint256 affiliatePoints);
    event AffiliateRewardsClaimed(uint256 indexed nftID, uint256 reward);

    event LoyaltyPointsUpdated(address indexed trader, uint256 loyaltyPoints);
    event LoyaltyRewardDistributed(address indexed trader, uint256 reward);

    event RedeemedPSM(address indexed user, uint256 amountPSM, uint256 reward);

    // ============================================
    // ==           OWNER FUNCTIONS              ==
    // ============================================
    ///@notice Initiate an ownership transfer with a timelock
    function transferOwnership(address _newOwner) external {
        if (msg.sender != owner) revert NotAuthorized();
        pendingOwner = _newOwner;
        timelockEnd = block.timestamp + TIMELOCK;

        emit OwnerTransferStarted(_newOwner, timelockEnd);
    }

    ///@notice The new owner must accept ownership after the timelock ended
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotAuthorized();
        if (block.timestamp < timelockEnd) revert Timelock();
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnerTransferCompleted(owner);
    }

    ///@notice Allow the owner to connect or disconnect markets from the Vault
    ///@dev Ownership protected to prevent malicious markets to connect
    ///@dev Enforce a timelock between changing market status to prevent systematic interference by malicious owner
    function updateMarketRegistry(address _market, bool _registryStatus) external {
        if (msg.sender != owner) revert NotAuthorized();
        if (block.timestamp < lastChanged[_market] + TIMELOCK) revert Timelock();
        registeredMarkets[_market] = _registryStatus;
        lastChanged[_market] = block.timestamp;

        emit MarketStatusUpdated(_market, _registryStatus, block.timestamp);
    }

    // ============================================
    // ==           AFFILIATE REWARDS            ==
    // ============================================
    ///@notice Returns the pending affiliate reward in ETH when redeeming all points of the given affiliate NFT ID
    ///@dev Affiliate Points are earned by referring new traders and are recurring based on trading volume of referrees
    function getAffiliateReward(uint256 _refID) public view returns (uint256 ethReward) {
        uint256 points = affiliatePoints[_refID];
        uint256 ethBalance = address(this).balance;
        uint256 newTotalAffiliatePoints = totalRedeemedAP + points;

        ///@dev Calculate the ETH rewards received by the affiliate after pool protection (slippage as in AMM)
        ethReward = (ethBalance * points) / newTotalAffiliatePoints;
    }

    ///@notice Allow affiliates to claim the ETH rewards for their Affiliate NFT
    ///@dev Redeem Affiliate Points of an NFT and send ETH to the NFT owner
    function claimAffiliateReward(uint256 _refID, uint256 _minReceived) external {
        // CHECKS
        ///@dev Check that the reward request comes from the NFT owner
        if (msg.sender != AFFILIATE_NFT.ownerOf(_refID)) revert NotAuthorized();

        ///@dev Ensure that the received amount matches the expected minimum
        uint256 rewardsReceived = getAffiliateReward(_refID);
        if (rewardsReceived < _minReceived) revert InsufficientReceived();

        // EFFECTS
        ///@dev Increase the redeemed point tracker until maximum is reached
        if (totalRedeemedAP < MAX_AP_REDEEMED) {
            totalRedeemedAP = (totalRedeemedAP + affiliatePoints[_refID] < MAX_AP_REDEEMED)
                ? totalRedeemedAP + affiliatePoints[_refID]
                : MAX_AP_REDEEMED;
        }

        ///@dev Update the affiliate points of the NFT
        affiliatePoints[_refID] = 0;

        // INTERACTONS
        ///@dev Send the ETH reward to the affiliate
        (bool sent,) = payable(msg.sender).call{value: rewardsReceived}("");
        if (!sent) revert FailedToSendNativeToken();

        emit AffiliateRewardsClaimed(_refID, rewardsReceived);
    }

    // ============================================
    // ==            LOYALTY REWARDS             ==
    // ============================================
    ///@notice Allow registered markets to update loyalty points of traders and affiliate points of NFTs
    ///@dev After updating the points, this function attempts to distribute the loyalty rewards of the current epoch
    function updatePoints(address _trader, uint256 _refID) external payable {
        // CHECKS
        ///@dev Ensure only a registered market can call this function
        if (!registeredMarkets[msg.sender]) revert InvalidMarket();

        ///@dev Ensure that the affiliate points can be assigned to an existing NFT
        if (_refID >= AFFILIATE_NFT.totalSupply()) revert InvalidAffiliateID();

        // EFFECTS
        ///@dev Calculate the trader's added loyalty points based on received ETH
        uint256 accruedPoints = msg.value * 20;

        ///@dev Update the trader's loyalty points
        uint256 newPoints = loyaltyPoints[_trader] + accruedPoints;
        loyaltyPoints[_trader] = newPoints;

        ///@dev Check if the trader becomes the new active point leader
        if (newPoints > leadingPoints) {
            loyaltyPointsLeader = _trader;
            leadingPoints = newPoints;
        }

        ///@dev Permanently connect the trader to the affiliate
        uint256 refID = refRecords[_trader];
        refID = (refID == 0) ? _refID : refID;

        ///@dev Update the referrer if it changes from 0 to a different ID
        ///@dev Only ref ID 0 can be overwritten (default) all other connections are permanent
        if (refRecords[_trader] == 0 && refID != 0) refRecords[_trader] = refID;

        ///@dev Update the points of the affiliate NFT
        uint256 newAffiliatePoints = affiliatePoints[refID] + accruedPoints;
        affiliatePoints[refID] = newAffiliatePoints;

        // INTERACTIONS
        ///@dev Emit events for updating the loyalty and affiliate points
        emit LoyaltyPointsUpdated(_trader, newPoints);
        emit AffiliatePointsUpdated(refID, newAffiliatePoints);

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
            ///@dev Keep ETH in the contract if the transfer fails but continue anyways (prevent DOS)
            (bool sent,) = payable(_recipient).call{value: loyaltyDistribution}("");
            if (!sent) loyaltyDistribution = 0;

            emit LoyaltyRewardDistributed(_recipient, loyaltyDistribution);
        }
    }

    // ============================================
    // ==             POSSUM REWARDS             ==
    // ============================================
    ///@notice Returns the amount of ETH received by redeeming a given number of PSM
    ///@dev PSM is exchanged for ETH from the TopCut Vault
    function getRedeemRewardPSM(uint256 _amountPSM) public view returns (uint256 ethReward) {
        uint256 ethBalance = address(this).balance;
        uint256 amount = _amountPSM;

        ///@dev Ensure that the PSM amount is within the logical maximum for a single transaction (100% of Vault)
        if (amount > PSM_REDEEM_DENOMINATOR) amount = PSM_REDEEM_DENOMINATOR;

        ///@dev Calculate the ETH received in exchange of PSM
        ethReward = (ethBalance * amount) / PSM_REDEEM_DENOMINATOR;
    }

    ///@notice Allow PSM holders to redeem their PSM for ETH from the TopCut Vault
    ///@dev Exchange PSM for ETH from the TopCut Vault where the PSM is stuck ("burned")
    function redeemPSM(uint256 _amountPSM, uint256 _minReceived, uint256 _deadline) external {
        uint256 amount = _amountPSM;
        // CHECKS
        ///@dev Ensure that the total redeemed PSM stays within its L1 supply constraints & check deadline
        if (totalPsmRedeemed >= PSM_CEILING) revert CeilingReached();
        if (_deadline < block.timestamp) revert Deadline();

        ///@dev Ensure that the PSM amount is within the logical maximum for a single transaction (100% of Vault)
        if (amount > PSM_REDEEM_DENOMINATOR) amount = PSM_REDEEM_DENOMINATOR;

        ///@dev Ensure that the received amount matches the expected minimum
        uint256 rewardsReceived = getRedeemRewardPSM(amount);
        if (rewardsReceived < _minReceived) revert InsufficientReceived();

        // EFFECTS
        ///@dev Increase the redeemed PSM tracker
        totalPsmRedeemed = totalPsmRedeemed + amount;

        // INTERACTONS
        ///@dev Take PSM from the user
        PSM.safeTransferFrom(msg.sender, address(this), amount);

        ///@dev Send ETH to the user
        (bool sent,) = payable(msg.sender).call{value: rewardsReceived}("");
        if (!sent) revert FailedToSendNativeToken();

        emit RedeemedPSM(msg.sender, amount, rewardsReceived);
    }

    // ============================================
    // ==              ENABLE ETH                ==
    // ============================================
    receive() external payable {}

    fallback() external payable {}
}
