// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITopCutNFT} from "src/interfaces/ITopCutNFT.sol";
import {ITopCutMarket} from "src/interfaces/ITopCutMarket.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";

contract DOScontract {
    constructor(address _psm, address _vault, address _market, address _nft) {
        psm = IERC20(_psm);
        market = ITopCutMarket(_market);
        vault = IRewardVault(_vault);
        nft = ITopCutNFT(_nft);
    }

    // ============================================
    // ==                STORAGE                 ==
    // ============================================
    IERC20 psm;
    ITopCutMarket market;
    IRewardVault vault;
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
}
