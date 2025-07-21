# TopCut Keeper Bot Setup

Full Credits for providing this awesome work to MahdiRostami!
[MahdiRostami on Github](https://github.com/0xmahdirostami)
[MahdiRostami on X](https://x.com/0xmahdirostami)

## Overview

This repository contains automated scripts for managing TopCut protocol settlements and rewards. The scripts support both single-contract and multi-contract operations, making them suitable for different deployment scenarios.

## Required Files

### 1. Create `.env` file:
```
infura_api_key=your_infura_api_key_here
PRIVATEKEY=your_private_key_here_without_0x
ACCOUNT=your_account_address_here
CONTRACT_ADDRESS=your_topcut_contract_address  # For single contract mode
```

### 2. Create `abi.json` file:
Copy the complete ABI for the TopCut contract. The ABI must include these essential functions:
- `settleCohort()` - Main settlement function
- `nextSettlement()` - Get next settlement time
- `activeCohortID()` - Get active cohort ID
- `cohortSize_1()` / `cohortSize_2()` - Get cohort sizes
- `keeperRewards()` - Get keeper rewards
- `claimKeeperReward()` - Claim keeper rewards
- `TRADE_SIZE()`, `SHARE_KEEPER()`, `SHARE_PRECISION()` - Contract constants

## Installation

1. Install required packages:
```bash
pip install web3 eth-account python-dotenv
```

2. Make scripts executable:
```bash
chmod +x keeper_bot_iter.py
chmod +x keeper_bot.py
chmod +x reward_claimer_iter.py
chmod +x reward_claimer.py
```

## Contract Configuration

The multi-contract scripts include predefined contract addresses:
```python
CONTRACTS = {
    "Market: BTC/USD, 24h, 0.01 ETH": "0x9A5f16c1f2d6b8c9530144aD23Cfa9B3c4717eF1",  
    "Market: BTC/USD, 24h, 0.1 ETH": "0x135a74aaac0E9F4622B94800d069d531d31c4f46",  
    "Market: BTC/USD, 7days (Monday), 0.01 ETH": "0x10EF281AAc569Cb011BfcB4e1C6cA490011486a5",  
    "Market: BTC/USD, 7days (Wednesday), 0.01 ETH": "0xB8eC8622D8B7924337CA7B143683459fE5a13f79",  
    "Market: BTC/USD, 7days (Friday), 0.01 ETH": "0xE8B9a818D57E2413E05144311E2d4d190c3f711c", 
}
```

## Setup Instructions

1. **Get Infura API Key:**
   - Go to https://infura.io
   - Create account and project
   - Get your Project ID (API key)

2. **Add to .env file:**
   - Your Infura API key
   - Your wallet private key (without 0x prefix)
   - Your account address
   - TopCut contract address (for single-contract mode)

3. **Save the ABI:**
   - Copy the complete contract ABI to a file named `abi.json`

4. **Add TopCutMarket contract addresses:**

Find the latest list of active markets in the [TopCut documentation](https://www.topcut.finance/docs/resources/smart-contracts)
Copy addresses of target markets to the CONTRACTS dictionary in keeper_bot_iter.py and reward_claimer_iter.py


## Available Scripts

This repository includes two categories of scripts for interacting with TopCut contracts:

### Multi-Contract Scripts (Recommended for production)

* **keeper\_bot\_iter.py**
  Automates settlement across multiple contracts with flexible execution modes.

* **reward\_claimer\_iter.py**
  Handles reward claiming for multiple contracts with detailed control.

### Single-Contract Scripts (Legacy, simpler)

* **keeper\_bot.py**
  Automates settlement for a single contract.

* **reward\_claimer.py**
  Handles reward claiming for a single contract.

---

## Usage

### Multi-Contract Settlement Bot (`keeper_bot_iter.py`)

```bash
# Run continuously with default 30 seconds interval
python keeper_bot_iter.py

# Run once for all contracts
python keeper_bot_iter.py once

# Run once for a specific contract
python keeper_bot_iter.py single <contract_name>

# Run continuously with custom interval (seconds)
python keeper_bot_iter.py <seconds>

# Show help and list available contracts
python keeper_bot_iter.py help
```

*Replace `<contract_name>` with one of the predefined contracts, e.g., `topcut_main`.*

---

### Multi-Contract Reward Claimer (`reward_claimer_iter.py`)

```bash
# Show status for all contracts
python reward_claimer_iter.py status

# Show status for a specific contract
python reward_claimer_iter.py status <contract_name>

# Claim all available rewards from all contracts
python reward_claimer_iter.py claim

# Claim rewards from a specific contract
python reward_claimer_iter.py claim <contract_name>

# Claim a specific amount to an optional recipient for a contract
python reward_claimer_iter.py claim <amount> <recipient> <contract_name>

# Claim rewards to a specific recipient, optionally specifying contract
python reward_claimer_iter.py claim <recipient> [<contract_name>]

# Run continuous monitoring with optional interval (seconds), min amount, and contract
python reward_claimer_iter.py monitor [interval] [min_amount] [contract_name]

# Run a single operation on a specific contract with optional arguments
python reward_claimer_iter.py single <contract_name> <operation> [args...]
```

*Examples:*

```bash
python reward_claimer_iter.py claim 0.01 0xRecipientAddress topcut_main
python reward_claimer_iter.py monitor 300 0.001 topcut_secondary
python reward_claimer_iter.py single topcut_test status
```

---

### Single-Contract Settlement Bot (`keeper_bot.py`)

```bash
# Run once
python keeper_bot.py once

# Run continuously with default 30 seconds interval
python keeper_bot.py

# Run continuously with custom interval (seconds)
python keeper_bot.py <seconds>
```

---

### Single-Contract Reward Claimer (`reward_claimer.py`)

```bash
# Show current status
python reward_claimer.py status

# Claim all available rewards
python reward_claimer.py claim

# Claim a specific amount (recipient optional)
python reward_claimer.py claim <amount> [recipient]

# Claim to a specific recipient (no amount specified)
python reward_claimer.py claim <recipient>

# Run continuous monitoring with optional interval (seconds) and min amount
python reward_claimer.py monitor [interval] [min_amount]
```

*Examples:*

```bash
python reward_claimer.py claim 0.05 0xRecipientAddress
python reward_claimer.py monitor 300 0.001
```

## Key Features

### Multi-Contract Benefits
- **Simultaneous monitoring** of multiple TopCut contracts
- **Individual contract targeting** for specific operations
- **Batch operations** across all contracts
- **Contract-specific status reporting**
- **Nonce management** to prevent transaction conflicts
- **Consolidated summary reporting**

### Core Features (All Scripts)
1. **Uses Infura for reliable Arbitrum connection**
2. **Automatic gas price optimization (max 2 gwei)**
3. **Block timestamp usage** instead of system time for accuracy
4. **Reads actual contract values** for precise reward calculations
5. **Profitability checks** before executing transactions
6. **Comprehensive error handling** and retry logic
7. **Clean console output** with detailed status updates
8. **Configurable minimum claim amounts**

## Example .env file
```
infura_api_key=abc123def456ghi789
PRIVATEKEY=1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
ACCOUNT=0x1234567890123456789012345678901234567890
CONTRACT_ADDRESS=0x9A5f16c1f2d6b8c9530144aD23Cfa9B3c4717eF1
```

## File Structure
```
topcut-keeper/
├── .env                        # Environment variables
├── abi.json                   # Contract ABI
├── keeper_bot_iter.py         # Multi-contract settlement automation
├── keeper_bot.py              # Single-contract settlement automation
├── reward_claimer_iter.py     # Multi-contract reward claiming
├── reward_claimer.py          # Single-contract reward claiming
└── README.md                  # This file
```

## Tips & Best Practices

1. **Security:** Never share your .env file or commit it to version control
2. **Gas optimization:** Scripts automatically limit gas price to 2 gwei max
3. **Multi-contract monitoring:** Use the `_iter.py` scripts for production deployment
4. **Single contract testing:** Use the legacy scripts for testing individual contracts
5. **Reliability:** Uses Infura's enterprise-grade infrastructure for blockchain connectivity
6. **Automation:** Can run 24/7 for hands-off keeper operation across all contracts
7. **Accuracy:** Gets real contract values for precise reward calculations
8. **Performance:** Includes delays between contract operations to prevent nonce conflicts
9. **Monitoring:** Both script types provide detailed, contract-specific status updates
10. **Flexibility:** Choose between batch operations or targeted single-contract management

## Troubleshooting

### Common Issues
- **Nonce conflicts:** Use delays between operations or run single-contract mode
- **Gas estimation failures:** Check contract state and ensure sufficient ETH balance
- **Connection issues:** Verify Infura API key and network connectivity
- **ABI errors:** Ensure abi.json contains the complete contract ABI
- **Contract not found:** Verify contract addresses in the CONTRACTS dictionary

### Error Resolution
- **Transaction failures:** Check gas limits and account balance
- **Reward claim failures:** Verify sufficient contract balance and keeper rewards
- **Settlement failures:** Ensure cohort is ready for settlement (time check)
- **Connection timeouts:** Consider using different Infura endpoints or increasing timeouts