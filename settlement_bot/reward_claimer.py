#!/usr/bin/env python3
"""
TopCut Keeper Reward Claimer
Simple version using dotenv
"""

import json
import time
import sys
import os
from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account

# Variables
load_dotenv()  # Load .env file
infura_api_key = os.getenv("infura_api_key")  # Create account in Infura and get it
w3 = Web3(Web3.HTTPProvider(f"{infura_api_key}"))
private_key = os.getenv("PRIVATEKEY")  # Your wallet Private Key
account_address = os.getenv("ACCOUNT")  # Your Account Address
contract_address = os.getenv("CONTRACT_ADDRESS")  # TopCut contract address

current_directory = os.path.dirname(__file__)  # Get the current directory of the script
abi_path = os.path.join(current_directory, "abi.json")

def load_abi():
    """Load contract ABI from abi.json"""
    try:
        with open(abi_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print("ERROR: abi.json file not found!")
        print("Please create abi.json with the full contract ABI")
        exit(1)

def setup_contract():
    """Setup contract instance"""
    try:
        # Test connection by getting chain ID
        chain_id = w3.eth.chain_id
        print(f"Connected to Arbitrum. Chain ID: {chain_id}")
    except Exception as e:
        print(f"ERROR: Failed to connect to blockchain: {e}")
        exit(1)
    
    abi = load_abi()
    contract = w3.eth.contract(address=contract_address, abi=abi)
    
    account = Account.from_key(private_key)
    print(f"Using account: {account.address}")
    
    return contract, account

def get_reward_info(contract, account_addr):
    """Get current reward and contract balance information"""
    try:
        # Get keeper rewards for this account
        keeper_rewards = contract.functions.keeperRewards(account_addr).call()
        
        # Get contract balance
        contract_balance = w3.eth.get_balance(contract.address)

        # Get account balance
        account_balance = w3.eth.get_balance(account_addr)
        
        return {
            'keeper_rewards': keeper_rewards,
            'contract_balance': contract_balance,
            'account_balance': account_balance,
            'keeper_rewards_eth': keeper_rewards / 1e18,
            'contract_balance_eth': contract_balance/ 1e18,
            'account_balance_eth': account_balance/ 1e18
        }
    except Exception as e:
        print(f"Error getting reward info: {e}")
        return None

def calculate_claimable_amount(reward_info):
    """Calculate the maximum claimable amount"""
    if not reward_info:
        return 0
    
    keeper_rewards = reward_info['keeper_rewards']
    contract_balance = reward_info['contract_balance']
    
    # Can claim up to the minimum of keeper rewards and contract balance
    return min(keeper_rewards, contract_balance)

def estimate_gas_cost(contract, amount, recipient, account_addr):
    """Estimate gas cost for claiming rewards"""
    try:
        current_gas_price = w3.eth.gas_price
        gas_price = current_gas_price
        gas_price = int(gas_price * 1.2)
        gas_limit = 1_000_000  # Default gas limit
        
        gas_cost = gas_limit * gas_price
        
        return {
            'gas_price': gas_price,
            'gas_limit': gas_limit,
            'gas_cost': gas_cost,
            'gas_cost_eth': gas_cost/1e18
        }
    except Exception as e:
        print(f"Error estimating gas cost: {e}")
        return None

def claim_rewards(contract, account, amount, recipient=None):
    """Claim keeper rewards"""
    try:
        if recipient is None:
            recipient = account.address
        
        # Get gas estimates
        gas_info = estimate_gas_cost(contract, amount, recipient, account.address)
        if not gas_info:
            print("Failed to estimate gas costs")
            return None
        
        print(f"Claiming {amount/1e18} ETH to {recipient}")
        print(f"Estimated gas cost: {gas_info['gas_cost_eth']} ETH")
        
        # Build transaction
        nonce = w3.eth.get_transaction_count(account.address)
        
        transaction = contract.functions.claimKeeperReward(
            recipient, int(amount)
        ).build_transaction({
            'gas': gas_info['gas_limit'],
            'gasPrice': gas_info['gas_price'],
            'nonce': nonce,
            'value': 0
        })
        
        # Sign and send transaction
        signed_txn = account.sign_transaction(transaction)
        tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
        tx_hash_hex = tx_hash.hex()
        
        print(f"Claim transaction sent: {tx_hash_hex}")
        
        # Wait for confirmation
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        
        if receipt.status == 1:
            print(f"Claim successful! Gas used: {receipt.gasUsed}")
            return tx_hash_hex
        else:
            print(f"Claim failed! Transaction: {tx_hash_hex}")
            return None
            
    except Exception as e:
        print(f"Error claiming rewards: {e}")
        return None

def show_status():
    """Show current reward status without claiming"""
    try:
        contract, account = setup_contract()
        
        print(f"\nChecking rewards for account: {account.address}")
        
        reward_info = get_reward_info(contract, account.address)
        if reward_info:
            claimable_amount = calculate_claimable_amount(reward_info)
            claimable_eth = claimable_amount/1e18
            
            print("\n=== REWARD STATUS ===")
            print(f"Keeper rewards: {reward_info['keeper_rewards_eth']} ETH")
            print(f"Contract balance: {reward_info['contract_balance_eth']} ETH") 
            print(f"Account balance: {reward_info['account_balance_eth']} ETH")
            print(f"Claimable amount: {claimable_eth} ETH")
            
            if claimable_amount > 0:
                gas_info = estimate_gas_cost(contract, claimable_amount, 
                                           account.address, account.address)
                if gas_info:
                    net_profit = claimable_amount - gas_info['gas_cost']
                    net_profit_eth = net_profit/1e18
                    print(f"Estimated gas cost: {gas_info['gas_cost_eth']} ETH")
                    print(f"Net profit: {net_profit_eth} ETH")
            print("=====================\n")
        else:
            print("Failed to get reward info")
            
    except Exception as e:
        print(f"Error showing status: {e}")

def check_and_claim(min_claim_amount_eth=0.001, recipient=None):
    """Check rewards and claim if above minimum threshold"""
    try:
        contract, account = setup_contract()
        
        # Get current reward info
        reward_info = get_reward_info(contract, account.address)
        if not reward_info:
            print("Failed to get reward info")
            return None
        
        # Show current status
        print(f"Keeper rewards: {reward_info['keeper_rewards_eth']} ETH")
        print(f"Contract balance: {reward_info['contract_balance_eth']} ETH")
        print(f"Account balance: {reward_info['account_balance_eth']} ETH")
        
        # Calculate claimable amount
        claimable_amount = calculate_claimable_amount(reward_info)
        claimable_eth = claimable_amount/1e18
        
        print(f"Claimable amount: {claimable_eth} ETH")
        
        # Check if there's anything to claim
        if claimable_amount == 0:
            print("No rewards to claim")
            return None
        
        # Check if above minimum threshold
        if float(claimable_eth) < min_claim_amount_eth:
            print(f"Claimable amount ({claimable_eth} ETH) below minimum threshold ({min_claim_amount_eth} ETH)")
            return None
        
        # Check profitability
        gas_info = estimate_gas_cost(contract, claimable_amount, 
                                   recipient or account.address, account.address)
        if gas_info:
            net_profit = claimable_amount - gas_info['gas_cost']
            net_profit_eth = net_profit/1e18
            
            print(f"Net profit after gas: {net_profit_eth} ETH")
            
            if net_profit <= 0:
                print("Claiming would not be profitable due to gas costs")
                return None
        
        # Claim rewards
        return claim_rewards(contract, account, claimable_amount, recipient)
        
    except Exception as e:
        print(f"Error in check_and_claim: {e}")
        return None

def claim_specific_amount(amount_eth, recipient=None):
    """Claim specific amount of rewards"""
    try:
        contract, account = setup_contract()
        
        amount_wei = amount_eth*1e18
        
        # Check if amount is available
        reward_info = get_reward_info(contract, account.address)
        if not reward_info:
            print("Failed to get reward info")
            return None
        
        claimable_amount = calculate_claimable_amount(reward_info)
        
        if amount_wei > claimable_amount:
            print(f"Requested amount ({amount_eth} ETH) exceeds claimable amount "
                  f"({claimable_amount/1e18} ETH)")
            return None
        
        return claim_rewards(contract, account, amount_wei, recipient)
        
    except Exception as e:
        print(f"Error claiming specific amount: {e}")
        return None

def run_continuous_monitoring(check_interval=300, min_claim_amount_eth=0.001):
    """Run continuous monitoring and claiming"""
    print("Starting continuous reward monitoring...")
    print(f"Check interval: {check_interval} seconds")
    print(f"Minimum claim amount: {min_claim_amount_eth} ETH")
    print("Press Ctrl+C to stop")
    
    while True:
        try:
            print("\nChecking for claimable rewards...")
            tx_hash = check_and_claim(min_claim_amount_eth)
            
            if tx_hash:
                print(f"Successfully claimed rewards: {tx_hash}")
            
            # Wait before next check
            print(f"Waiting {check_interval} seconds before next check...")
            time.sleep(check_interval)
            
        except KeyboardInterrupt:
            print("Stopping reward monitor...")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
            print("Retrying in 60 seconds...")
            time.sleep(60)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            show_status()
        elif command == "claim":
            if len(sys.argv) > 2:
                try:
                    amount = float(sys.argv[2])
                    recipient = sys.argv[3] if len(sys.argv) > 3 else None
                    result = claim_specific_amount(amount, recipient)
                except ValueError:
                    # sys.argv[2] is recipient address, not amount
                    recipient = sys.argv[2]
                    result = check_and_claim(recipient=recipient)
            else:
                result = check_and_claim()
            
            if result:
                print(f"Claim successful: {result}")
            else:
                print("Claim failed or no rewards available")
        elif command == "monitor":
            interval = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 300
            min_amount = float(sys.argv[3]) if len(sys.argv) > 3 else 0.001
            run_continuous_monitoring(interval, min_amount)
        else:
            print("Usage:")
            print("  python reward_claimer.py status                        # Show current status")
            print("  python reward_claimer.py claim                         # Claim all available")
            print("  python reward_claimer.py claim <amount>                # Claim specific amount")
            print("  python reward_claimer.py claim <recipient>             # Claim to specific address")
            print("  python reward_claimer.py claim <amount> <recipient>    # Claim amount to address")
            print("  python reward_claimer.py monitor [interval] [min]      # Continuous monitoring")
    else:
        # Default: show status
        show_status()