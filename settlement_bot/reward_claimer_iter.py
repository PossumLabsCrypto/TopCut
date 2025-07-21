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

# Contract addresses - moved from .env to file
# check the most up to date list of active markets in the docs
# https://www.topcut.finance/docs/resources/smart-contracts
CONTRACTS = {
    "Market: BTC/USD, 24h, 0.01 ETH": "0x9A5f16c1f2d6b8c9530144aD23Cfa9B3c4717eF1",  
    "Market: BTC/USD, 24h, 0.05 ETH": "0x8B64Cf63B08f7eB3ad163282bf61d382DfFF0586",  
    "Market: BTC/USD, 7days (Monday), 0.01 ETH": "0x10EF281AAc569Cb011BfcB4e1C6cA490011486a5",  
    "Market: BTC/USD, 7days (Wednesday), 0.01 ETH": "0xB8eC8622D8B7924337CA7B143683459fE5a13f79",  
    "Market: BTC/USD, 7days (Friday), 0.01 ETH": "0xE8B9a818D57E2413E05144311E2d4d190c3f711c", 
}

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

def setup_contracts():
    """Setup contract instance"""
    try:
        # Test connection by getting chain ID
        chain_id = w3.eth.chain_id
        print(f"Connected to Arbitrum. Chain ID: {chain_id}")
    except Exception as e:
        print(f"ERROR: Failed to connect to blockchain: {e}")
        exit(1)
    
    abi = load_abi()
    abi = load_abi()
    contracts = {}
    
    # Create contract instances for each address
    for name, address in CONTRACTS.items():
        try:
            contract = w3.eth.contract(address=address, abi=abi)
            contracts[name] = {
                'contract': contract,
                'address': address
            }
            print(f"Setup contract '{name}' at {address}")
        except Exception as e:
            print(f"ERROR: Failed to setup contract '{name}' at {address}: {e}")
    
    account = Account.from_key(private_key)
    print(f"Using account: {account.address}")
    
    return contracts, account

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

def claim_rewards(contract, account, amount, recipient, contract_name):
    """Claim keeper rewards"""
    try:
        if recipient is None:
            recipient = account.address
        
        # Get gas estimates
        gas_info = estimate_gas_cost(contract, amount, recipient, account.address)
        if not gas_info:
            print(f"[{contract_name}] Failed to estimate gas costs")
            return None
        
        print(f"[{contract_name}] Claiming {amount/1e18} ETH to {recipient}")
        print(f"[{contract_name}] Estimated gas cost: {gas_info['gas_cost_eth']} ETH")
        
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
        
        print(f"[{contract_name}] Claim transaction sent: {tx_hash_hex}")
        
        # Wait for confirmation
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        
        if receipt.status == 1:
            print(f"[{contract_name}] Claim successful! Gas used: {receipt.gasUsed}")
            return tx_hash_hex
        else:
            print(f"[{contract_name}] Claim failed! Transaction: {tx_hash_hex}")
            return None
            
    except Exception as e:
        print(f"[{contract_name}] Error claiming rewards: {e}")
        return None

def show_status_single_contract(contract_info, contract_name, account_addr):
    """Show status for a single contract"""
    try:
        contract = contract_info['contract']
        address = contract_info['address']
        
        print(f"\n[{contract_name}] Contract: {address}")
        
        reward_info = get_reward_info(contract, account_addr)
        if reward_info:
            claimable_amount = calculate_claimable_amount(reward_info)
            claimable_eth = claimable_amount/1e18
            
            print(f"[{contract_name}] Keeper rewards: {reward_info['keeper_rewards_eth']:.6f} ETH")
            print(f"[{contract_name}] Contract balance: {reward_info['contract_balance_eth']:.6f} ETH") 
            print(f"[{contract_name}] Claimable amount: {claimable_eth:.6f} ETH")
            
            if claimable_amount > 0:
                gas_info = estimate_gas_cost(contract, claimable_amount, 
                                           account_addr, account_addr)
                if gas_info:
                    net_profit = claimable_amount - gas_info['gas_cost']
                    net_profit_eth = net_profit/1e18
                    print(f"[{contract_name}] Estimated gas cost: {gas_info['gas_cost_eth']:.6f} ETH")
                    print(f"[{contract_name}] Net profit: {net_profit_eth:.6f} ETH")
            
            return {
                'contract_name': contract_name,
                'claimable_amount': claimable_amount,
                'claimable_eth': claimable_eth,
                'reward_info': reward_info
            }
        else:
            print(f"[{contract_name}] Failed to get reward info")
            return None
            
    except Exception as e:
        print(f"[{contract_name}] Error showing status: {e}")
        return None

def show_status(contract_name=None):
    """Show current reward status for all contracts or specific contract"""
    try:
        contracts, account = setup_contracts()
        
        print(f"\nChecking rewards for account: {account.address}")
        
        if contract_name:
            # Show status for specific contract
            if contract_name not in contracts:
                print(f"Error: Contract '{contract_name}' not found.")
                print(f"Available contracts: {list(contracts.keys())}")
                return
            
            print(f"\n=== REWARD STATUS FOR {contract_name.upper()} ===")
            show_status_single_contract(contracts[contract_name], contract_name, account.address)
            print("=" * 50)
        else:
            # Show status for all contracts
            print("\n" + "=" * 60)
            print("REWARD STATUS FOR ALL CONTRACTS")
            print("=" * 60)
            
            total_claimable = 0
            contract_summaries = []
            
            for name, contract_info in contracts.items():
                result = show_status_single_contract(contract_info, name, account.address)
                if result:
                    total_claimable += result['claimable_eth']
                    contract_summaries.append(result)
            
            # Show summary
            print(f"\n--- SUMMARY ---")
            print(f"Account balance: {w3.eth.get_balance(account.address)/1e18:.6f} ETH")
            print(f"Total claimable across all contracts: {total_claimable:.6f} ETH")
            
            profitable_contracts = sum(1 for c in contract_summaries if c['claimable_eth'] > 0.001)
            print(f"Contracts with claimable rewards (>0.001 ETH): {profitable_contracts}/{len(contracts)}")
            print("=" * 60)
            
    except Exception as e:
        print(f"Error showing status: {e}")

def check_and_claim_single_contract(contract_info, contract_name, account, 
                                   min_claim_amount_eth=0.001, recipient=None):
    """Check and claim rewards for a single contract"""
    try:
        contract = contract_info['contract']
        
        # Get current reward info
        reward_info = get_reward_info(contract, account.address)
        if not reward_info:
            print(f"[{contract_name}] Failed to get reward info")
            return None
        
        # Calculate claimable amount
        claimable_amount = calculate_claimable_amount(reward_info)
        claimable_eth = claimable_amount/1e18
        
        print(f"[{contract_name}] Claimable amount: {claimable_eth:.6f} ETH")
        
        # Check if there's anything to claim
        if claimable_amount == 0:
            print(f"[{contract_name}] No rewards to claim")
            return None
        
        # Check if above minimum threshold
        if float(claimable_eth) < min_claim_amount_eth:
            print(f"[{contract_name}] Claimable amount ({claimable_eth:.6f} ETH) below minimum threshold ({min_claim_amount_eth} ETH)")
            return None
        
        # Check profitability
        gas_info = estimate_gas_cost(contract, claimable_amount, 
                                   recipient or account.address, account.address)
        if gas_info:
            net_profit = claimable_amount - gas_info['gas_cost']
            net_profit_eth = net_profit/1e18
            
            print(f"[{contract_name}] Net profit after gas: {net_profit_eth:.6f} ETH")
            
            if net_profit <= 0:
                print(f"[{contract_name}] Claiming would not be profitable due to gas costs")
                return None
        
        # Claim rewards
        return claim_rewards(contract, account, claimable_amount, recipient, contract_name)
        
    except Exception as e:
        print(f"[{contract_name}] Error in check_and_claim: {e}")
        return None

def check_and_claim(min_claim_amount_eth=0.001, recipient=None, contract_name=None):
    """Check rewards and claim if above minimum threshold"""
    try:
        contracts, account = setup_contracts()
        
        if contract_name:
            # Process single contract
            if contract_name not in contracts:
                print(f"Error: Contract '{contract_name}' not found.")
                print(f"Available contracts: {list(contracts.keys())}")
                return None
            
            return check_and_claim_single_contract(
                contracts[contract_name], contract_name, account, 
                min_claim_amount_eth, recipient
            )
        else:
            # Process all contracts
            results = {}
            successful_claims = 0
            
            print("=" * 60)
            print("CHECKING ALL CONTRACTS FOR CLAIMABLE REWARDS")
            print("=" * 60)
            
            for name, contract_info in contracts.items():
                print(f"\n--- Checking {name} ---")
                result = check_and_claim_single_contract(
                    contract_info, name, account, min_claim_amount_eth, recipient
                )
                results[name] = result
                if result:
                    successful_claims += 1
                
                # Add delay between claims to avoid nonce issues
                time.sleep(2)
            
            # Summary
            print("\n" + "=" * 60)
            print("CLAIM SUMMARY:")
            for name, result in results.items():
                if result:
                    print(f"✓ {name}: Claim successful - {result}")
                else:
                    print(f"✗ {name}: No claim")
            
            print(f"Total successful claims: {successful_claims}/{len(contracts)}")
            print("=" * 60)
            
            return results
        
    except Exception as e:
        print(f"Error in check_and_claim: {e}")
        return None

def claim_specific_amount(amount_eth, recipient=None, contract_name=None):
    """Claim specific amount of rewards"""
    try:
        contracts, account = setup_contracts()
        
        amount_wei = int(amount_eth * 1e18)
        
        if contract_name:
            # Claim from specific contract
            if contract_name not in contracts:
                print(f"Error: Contract '{contract_name}' not found.")
                print(f"Available contracts: {list(contracts.keys())}")
                return None
            
            contract = contracts[contract_name]['contract']
            
            # Check if amount is available
            reward_info = get_reward_info(contract, account.address)
            if not reward_info:
                print(f"[{contract_name}] Failed to get reward info")
                return None
            
            claimable_amount = calculate_claimable_amount(reward_info)
            
            if amount_wei > claimable_amount:
                print(f"[{contract_name}] Requested amount ({amount_eth} ETH) exceeds claimable amount "
                      f"({claimable_amount/1e18} ETH)")
                return None
            
            return claim_rewards(contract, account, amount_wei, recipient, contract_name)
        else:
            print("Error: Must specify contract_name when claiming specific amount")
            print(f"Available contracts: {list(contracts.keys())}")
            return None
        
    except Exception as e:
        print(f"Error claiming specific amount: {e}")
        return None

def run_continuous_monitoring(check_interval=300, min_claim_amount_eth=0.001, contract_name=None):
    """Run continuous monitoring and claiming"""
    if contract_name:
        print(f"Starting continuous reward monitoring for {contract_name}...")
    else:
        print("Starting continuous reward monitoring for all contracts...")
    
    print(f"Check interval: {check_interval} seconds")
    print(f"Minimum claim amount: {min_claim_amount_eth} ETH")
    print("Press Ctrl+C to stop")
    
    while True:
        try:
            print(f"\nChecking for claimable rewards...")
            results = check_and_claim(min_claim_amount_eth, contract_name=contract_name)
            
            if results:
                if isinstance(results, dict) and not contract_name:
                    # Multiple contracts
                    successful = sum(1 for r in results.values() if r)
                    if successful > 0:
                        print(f"Successfully claimed rewards from {successful} contracts")
                elif results and contract_name:
                    # Single contract
                    print(f"Successfully claimed rewards: {results}")
            
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

def run_single_contract_operation(contract_name, operation, *args):
    """Run operation for a single specific contract"""
    if contract_name not in CONTRACTS:
        print(f"Error: Contract '{contract_name}' not found.")
        print(f"Available contracts: {list(CONTRACTS.keys())}")
        return None
    
    if operation == "status":
        show_status(contract_name)
    elif operation == "claim":
        if len(args) > 0:
            try:
                amount = float(args[0])
                recipient = args[1] if len(args) > 1 else None
                result = claim_specific_amount(amount, recipient, contract_name)
            except ValueError:
                recipient = args[0]
                result = check_and_claim(recipient=recipient, contract_name=contract_name)
        else:
            result = check_and_claim(contract_name=contract_name)
        
        if result:
            print(f"Claim successful for {contract_name}: {result}")
        else:
            print(f"Claim failed or no rewards available for {contract_name}")
    elif operation == "monitor":
        interval = int(args[0]) if len(args) > 0 and args[0].isdigit() else 300
        min_amount = float(args[1]) if len(args) > 1 else 0.001
        run_continuous_monitoring(interval, min_amount, contract_name)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            contract_name = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] in CONTRACTS else None
            show_status(contract_name)
            
        elif command == "claim":
            if len(sys.argv) > 2:
                try:
                    amount = float(sys.argv[2])
                    # Amount specified
                    recipient = sys.argv[3] if len(sys.argv) > 3 else None
                    contract_name = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] in CONTRACTS else None
                    
                    if contract_name:
                        result = claim_specific_amount(amount, recipient, contract_name)
                    else:
                        print("Error: Must specify contract name when claiming specific amount")
                        print(f"Available contracts: {list(CONTRACTS.keys())}")
                        result = None
                except ValueError:
                    # Not an amount, could be recipient or contract name
                    if sys.argv[2] in CONTRACTS:
                        # Contract name specified
                        contract_name = sys.argv[2]
                        recipient = sys.argv[3] if len(sys.argv) > 3 else None
                        result = check_and_claim(recipient=recipient, contract_name=contract_name)
                    else:
                        # Recipient address specified
                        recipient = sys.argv[2]
                        contract_name = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] in CONTRACTS else None
                        result = check_and_claim(recipient=recipient, contract_name=contract_name)
            else:
                result = check_and_claim()
            
            if result:
                print(f"Claim operation completed")
            else:
                print("Claim failed or no rewards available")
                
        elif command == "monitor":
            interval = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 300
            min_amount = float(sys.argv[3]) if len(sys.argv) > 3 else 0.001
            contract_name = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] in CONTRACTS else None
            run_continuous_monitoring(interval, min_amount, contract_name)
            
        elif command == "single" and len(sys.argv) > 3:
            # Single contract operations
            contract_name = sys.argv[2]
            operation = sys.argv[3]
            args = sys.argv[4:]
            run_single_contract_operation(contract_name, operation, *args)
            
        else:
            print("Usage:")
            print("  python reward_claimer_iter.py status [contract_name]                    # Show status")
            print("  python reward_claimer_iter.py claim                                     # Claim from all contracts")
            print("  python reward_claimer_iter.py claim <contract_name>                     # Claim from specific contract")
            print("  python reward_claimer_iter.py claim <amount> <recipient> <contract>     # Claim specific amount")
            print("  python reward_claimer_iter.py claim <recipient> [contract_name]         # Claim to specific address")
            print("  python reward_claimer_iter.py monitor [interval] [min] [contract]       # Continuous monitoring")
            print("  python reward_claimer_iter.py single <contract> <operation> [args]     # Single contract operation")
            print(f"\nAvailable contracts: {list(CONTRACTS.keys())}")
    else:
        # Default: show status for all contracts
        show_status()