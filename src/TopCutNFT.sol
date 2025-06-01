// SPDX-License-Identifier: MIT
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
 * Affiliate rewards accrue in Affiliate Points (AP) in the TopCut Vault
 * AP can be burned for ETH from the TopCut Vault
 * Affiliate NFTs can be minted by paying the increasing minting price in ETH
 */
contract TopCutNFT is ERC721URIStorage {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        TOPCUT_VAULT = msg.sender;
        mintPriceETH = START_MINT_PRICE;

        // Mint initial NFT budget to the treasury
        for (uint256 i = 0; i < 40; i++) {
            _mintInitial();
        }
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    uint256 private constant START_MINT_PRICE = 1e17; // 0.1 ETH
    uint256 private constant MINT_PRICE_INCREASE = 1e16; // +0.01 ETH per mint
    address private constant TREASURY = 0xa0BFD02a7a47CBCA7230E03fbf04A196C3E771E3;

    address public immutable TOPCUT_VAULT;
    string public metadataURI = "420g02n230f203f"; ////////// -------------------->>> UPDATE IPFS METADATA

    uint256 public mintPriceETH;
    uint256 public totalSupply;

    // ============================================
    // ==               FUNCTIONS                ==
    // ============================================
    ///@notice Enable anyone to mint a new NFT when paying the ETH price
    function mint() external payable returns (uint256 nftID) {
        ///@dev Check for sufficient ETH payment
        if (msg.value != mintPriceETH) revert InsufficientPayment();

        ///@dev mint the NFT to the caller
        _safeMint(msg.sender, totalSupply);
        _setTokenURI(totalSupply, metadataURI);

        ///@dev Update supply and price trackers
        nftID = totalSupply;
        totalSupply++;
        mintPriceETH += MINT_PRICE_INCREASE;

        ///@dev Send the received ETH to the TopCut Vault
        ///@dev Sending ETH cannot fail because Vault always have a receive() function
        uint256 contractBalance = address(this).balance;
        (bool sent,) = payable(TOPCUT_VAULT).call{value: contractBalance}("");
        sent = true; // avoid unused variable warning
    }

    ///@notice Internal function to mint the starting supply to the treasury
    function _mintInitial() private {
        _safeMint(TREASURY, totalSupply);
        _setTokenURI(totalSupply, metadataURI);

        ///@dev Update supply
        totalSupply++;
    }
}
