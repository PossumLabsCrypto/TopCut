# TopCut Keeper Bot Setup
Full Credits for providing this awesome work to MahdiRostami!
[MahdiRostami on Github](https://github.com/0xmahdirostami)
[MahdiRostami on X](https://x.com/0xmahdirostami)


## Required Files

### 1. Create `.env` file:
```
infura_api_key=your_infura_api_key_here
PRIVATEKEY=your_private_key_here_without_0x
ACCOUNT=your_account_address_here
```

### 2. Create `abi.json` file:
Copy the complete ABI provided in the abi.json artifact. It contains all the necessary function signatures for the TopCut contract including:
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
chmod +x keeper_bot.py
chmod +x reward_claimer.py
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
   - TopCut contract address

3. **Save the ABI:**
   - Copy the provided abi.json content to a file named `abi.json`

4. **Add TopCutMarket contract addresses**
   - Find the latest list of active markets in the TopCut documentation `topcut.finance/docs`
   - Copy addresses of target markets to the `CONTRACTS` dictionary in `keeper_bot.py` and `reward_claimer.py`


## Usage

### Settlement Bot (keeper_bot.py)

**Run once to check/settle:**
```bash
python keeper_bot.py once
```

**Run continuously (default 30 seconds interval):**
```bash
python keeper_bot.py
```

**Run continuously with custom interval:**
```bash
python keeper_bot.py 60  # Check every 60 seconds
```

### Reward Claimer (reward_claimer.py)

**Check current status:**
```bash
python reward_claimer.py status
```

**Claim all available rewards:**
```bash
python reward_claimer.py claim
```

**Claim specific amount:**
```bash
python reward_claimer.py claim 0.01  # Claim 0.01 ETH
```

**Claim to specific address:**
```bash
python reward_claimer.py claim 0x1234567890123456789012345678901234567890
```

**Claim specific amount to specific address:**
```bash
python reward_claimer.py claim 0.01 0x1234567890123456789012345678901234567890
```

**Run continuous monitoring:**
```bash
python reward_claimer.py monitor  # Default: check every 300 seconds, min 0.001 ETH
python reward_claimer.py monitor 120 0.005  # Check every 120 seconds, min 0.005 ETH
```

## Key Features

1. **Uses Infura for reliable Arbitrum connection**
2. **Automatic gas price optimization (max 2 gwei)**
3. **Reads actual contract values for accurate reward calculation**
4. **Profitability checks before executing transactions**
5. **Error handling and retry logic**
6. **Clean console output with status updates**

## Example .env file
```
infura_api_key=abc123def456ghi789
PRIVATEKEY=1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
ACCOUNT=0x1234567890123456789012345678901234567890
CONTRACT_ADDRESS=0xYourTopCutContractAddress
```

## File Structure
```
topcut-keeper/
├── .env                 # Environment variables
├── abi.json            # Contract ABI
├── keeper_bot.py       # Settlement automation
├── reward_claimer.py   # Reward claiming
└── README.md           # This file
```

## Running Both Together

You can run both scripts simultaneously for full automation:

**Terminal 1 (Settlement):**
```bash
python keeper_bot.py
```

**Terminal 2 (Reward Claiming):**
```bash
python reward_claimer.py monitor
```

This setup will:
- Automatically settle cohorts when ready
- Automatically claim rewards when they accumulate above threshold
- Use Infura for reliable blockchain connection
- Read actual contract values for precise calculations
- Optimize gas costs and check profitability

## Tips

1. **Security:** Never share your .env file or commit it to version control
2. **Gas optimization:** Scripts automatically limit gas price to 2 gwei max
3. **Monitoring:** Both scripts provide detailed status updates
4. **Reliability:** Uses Infura's enterprise-grade infrastructure
5. **Automation:** Can run 24/7 for hands-off keeper operation
6. **Accuracy:** Gets real contract values for precise reward calculations