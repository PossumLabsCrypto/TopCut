#!/usr/bin/env python3
"""
TopCut Keeper Bot - Automated Settlement Script
Modified to use block.timestamp instead of time.time()
"""

import json
import time
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

def get_current_block_timestamp():
    """Get the timestamp of the latest block (block.timestamp equivalent)"""
    try:
        latest_block = w3.eth.get_block('latest')
        return latest_block.timestamp
    except Exception as e:
        print(f"Error getting latest block timestamp: {e}")
        return None

def get_contract_state(contract):
    """Get current contract state"""
    try:
        next_settlement = contract.functions.nextSettlement().call()
        active_cohort_id = contract.functions.activeCohortID().call()
        cohort_size_1 = contract.functions.cohortSize_1().call()
        cohort_size_2 = contract.functions.cohortSize_2().call()
        
        # Use block.timestamp instead of time.time()
        current_block_timestamp = get_current_block_timestamp()
        if current_block_timestamp is None:
            return None
        
        return {
            'next_settlement': next_settlement,
            'active_cohort_id': active_cohort_id,
            'cohort_size_1': cohort_size_1,
            'cohort_size_2': cohort_size_2,
            'current_timestamp': current_block_timestamp 
        }
    except Exception as e:
        print(f"Error getting contract state: {e}")
        return None

def can_settle(state):
    """Check if settlement is possible"""
    if not state:
        return False
    return state['current_timestamp'] >= state['next_settlement']

def estimate_costs_and_rewards(contract, state):
    """Estimate gas cost and potential keeper reward"""
    try:
        # Get current gas price (with max limit)
        current_gas_price = w3.eth.gas_price
        gas_price = current_gas_price
        gas_price = int(gas_price * 1.2)

        
        # Get active cohort size
        active_cohort_size = (state['cohort_size_2'] if state['active_cohort_id'] == 2 
                            else state['cohort_size_1'])
        
        keeper_reward = int(1e14) # 0.0001 ETH for each user
        min_keeper_reward = int(1e15)  # 0.001 ETH minimum
        
        estimated_reward = max(active_cohort_size * keeper_reward, min_keeper_reward)
        
        # Estimate gas cost
        gas_limit = 1_000_000  # Default gas limit
        estimated_gas_cost = gas_limit * gas_price
        
        return {
            'gas_price': gas_price,
            'gas_limit': gas_limit,
            'estimated_gas_cost': estimated_gas_cost,
            'estimated_reward': estimated_reward,
            'profit_estimate': estimated_reward - estimated_gas_cost,
            'active_cohort_size': active_cohort_size
        }
    except Exception as e:
        print(f"Error estimating costs: {e}")
        return None

def settle_cohort(contract, account):
    """Attempt to settle the cohort"""
    try:
        # Get current state
        state = get_contract_state(contract)
        if not state:
            print("Failed to get contract state")
            return None
        
        # Check if settlement is possible
        if not can_settle(state):
            time_until = state['next_settlement'] - state['current_timestamp']
            print(f"Settlement not ready. Time remaining: {time_until} seconds")
            print(f"Settlement not ready. Time remaining: {time_until/3600} hours")
            return None
        
        # Estimate costs and rewards
        cost_info = estimate_costs_and_rewards(contract, state)
        if not cost_info:
            print("Failed to estimate costs")
            return None
        
        print(f"Settlement ready! Active cohort: {state['active_cohort_id']}")
        print(f"Cohort size: {cost_info['active_cohort_size']}")
        print(f"Estimated reward: {cost_info['estimated_reward']/1e18} ETH")
        print(f"Estimated gas cost: {cost_info['estimated_gas_cost']/1e18} ETH")
        print(f"Estimated profit: {cost_info['profit_estimate']/1e18} ETH")
        
        # Build transaction
        nonce = w3.eth.get_transaction_count(account.address)
        
        transaction = contract.functions.settleCohort().build_transaction({
            'from': account.address,
            'gas': cost_info['gas_limit'],
            'gasPrice': cost_info['gas_price'],
            'nonce': nonce,
        })
        
        # Sign and send transaction
        signed_txn = account.sign_transaction(transaction)
        tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
        tx_hash_hex = tx_hash.hex()
        
        print(f"Settlement transaction sent: {tx_hash_hex}")
        
        # Wait for confirmation
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        
        if receipt.status == 1:
            print(f"Settlement successful! Gas used: {receipt.gasUsed}")
            return tx_hash_hex
        else:
            print(f"Settlement failed! Transaction: {tx_hash_hex}")
            return None
            
    except Exception as e:
        print(f"Error in settle_cohort: {e}")
        return None

def run_once():
    """Run one settlement check"""
    try:
        contract, account = setup_contract()
        
        print("Checking settlement status...")
        
        # Get current state
        state = get_contract_state(contract)
        if not state:
            return None
        
        # Show current state
        from datetime import datetime, timezone
        settlement_time = datetime.fromtimestamp(state['next_settlement'], timezone.utc)
        current_time = datetime.fromtimestamp(state['current_timestamp'], timezone.utc)
        
        print(f"Active cohort: {state['active_cohort_id']}")
        print(f"Current block time: {current_time}")
        print(f"Settlement time: {settlement_time}")
        
        # Check if we can settle
        if can_settle(state):
            print("Settlement is ready! Attempting to settle...")
            tx_hash = settle_cohort(contract, account)
            if tx_hash:
                print(f"Settlement successful: {tx_hash}")
                return tx_hash
            else:
                print("Settlement failed")
        else:
            time_until = state['next_settlement'] - state['current_timestamp']
            print(f"Settlement not ready. Time remaining: {time_until} seconds")
            print(f"Settlement not ready. Time remaining: {time_until/3600} hours")

            
    except Exception as e:
        print(f"Error in run_once: {e}")
    
    return None

def run_continuously(check_interval=30):
    """Run the keeper bot continuously"""
    print("Starting TopCut Keeper Bot...")
    print(f"Check interval: {check_interval} seconds")
    print("Press Ctrl+C to stop")
    
    while True:
        try:
            run_once()
            
            # Wait before next check
            print(f"Waiting {check_interval} seconds...")
            time.sleep(check_interval)
            
        except KeyboardInterrupt:
            print("Stopping keeper bot...")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
            print("Retrying in 60 seconds...")
            time.sleep(60)

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "once":
        # Run once
        result = run_once()
        if result:
            print(f"Settlement transaction: {result}")
        else:
            print("No settlement occurred")
    else:
        # Run continuously
        interval = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 30
        run_continuously(interval)