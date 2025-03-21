// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

// ============================================
error FailedToSendNativeToken();
error InsufficientPayment();
// ============================================

/// @title TopCut Affiliate NFTs
/// @author Possum Labs
/**
 * @notice Holders of any TopCut NFT can earn affiliate rewards by referring traders
 * Affiliate rewards accrue in Affiliate Points (AP) in the LoyaltyRewardPool
 * AP can be burned for ETH from the LoyaltyRewardPool
 * Traders are incentivized to set an affiliateID via increased loyalty points when trading
 * Affiliate NFTs can be minted by paying the increasing minting price in ETH
 * The ETH is sent to the LoyaltyRewardPool
 */
contract TopCutNFT is ERC721URIStorage {
    constructor(string memory _name, string memory _symbol, string memory _metadataURI) ERC721(_name, _symbol) {
        LOYALTY_POOL = msg.sender;
        mintPriceETH = START_MINT_COST;
        metadataURI = _metadataURI;
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    uint256 private constant START_MINT_COST = 1e16; // 0.01 ETH
    uint256 private constant MINT_COST_INCREASE = 1e15; // +0.001 ETH per mint
    address private immutable LOYALTY_POOL;
    string metadataURI;

    uint256 public mintPriceETH;
    uint256 public totalSupply;

    // ============================================
    // ==               FUNCTIONS                ==
    // ============================================
    ///@notice Enable users to mint a new NFT when paying the ETH price
    function mint() external payable returns (uint256 nftID) {
        ///@dev Check for sufficient ETH payment
        if (msg.value != mintPriceETH) revert InsufficientPayment();

        ///@dev mint the NFT to the caller
        _safeMint(msg.sender, totalSupply);
        _setTokenURI(totalSupply, metadataURI);

        ///@dev Update supply and price trackers
        nftID = totalSupply;
        totalSupply++;
        mintPriceETH += MINT_COST_INCREASE;

        ///@dev Send the received ETH to the LoyaltyRewardPool
        uint256 contractBalance = address(this).balance;
        (bool sent,) = payable(LOYALTY_POOL).call{value: contractBalance}("");
        if (!sent) revert FailedToSendNativeToken();
    }
}
