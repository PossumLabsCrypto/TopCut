// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITopCutNFT} from "src/interfaces/ITopCutNFT.sol";
import {ITopCutMarket} from "src/interfaces/ITopCutMarket.sol";
import {ITopCutVault} from "src/interfaces/ITopCutVault.sol";

contract DOScontract is ERC721Holder {
    constructor(address _psm, address _vault, address _market, address _nft) {
        psm = IERC20(_psm);
        market = ITopCutMarket(_market);
        vault = ITopCutVault(_vault);
        nft = ITopCutNFT(_nft);
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    IERC20 psm;
    ITopCutMarket market;
    ITopCutVault vault;
    ITopCutNFT nft;

    // ============================================
    // ==               FUNCTIONS                ==
    // ============================================
    // Try to disrupt the PSM redeeming in the Vault
    function tryRedeemPSM() external {
        uint256 balance = psm.balanceOf(address(this));
        psm.approve(address(vault), 1e55);
        vault.redeemPSM(balance, 1, block.timestamp);
    }

    function buyNFT() external payable {
        uint256 price = nft.MINT_FEE_ETH();
        nft.mint{value: price}();
    }

    function claimAP(uint256 _refID, uint256 _pointsRedeemed, uint256 _minReceived, uint256 _deadline) external {
        vault.claimAffiliateReward(_refID, _pointsRedeemed, _minReceived, _deadline);
    }

    function castVulnerablePrediction(address _frontend, uint256 _refID, uint256 _price, uint256 _cohortID)
        external
        payable
    {
        uint256 tradeSize = msg.value;
        market.castPrediction{value: tradeSize}(_frontend, _refID, _price, _cohortID);
    }
}
