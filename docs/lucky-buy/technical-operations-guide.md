# LuckyBuy Technical Operations Guide

This guide is intended for technical operations staff who need to help users understand and verify their LuckyBuy transactions.

## Game Flow Overview

1. **User Selects NFT**

   - User chooses an NFT they want to try to win
   - The system calculates the required commit amount based on the NFT's price and desired odds
   - NFT Price * (1 + protocol fee percentage) + flat fee (to cover open edition mints)
   - User provides a random seed number (We currently generate this )

2. **Commit Transaction**

   - User sends a commit transaction to the LuckyBuy contract
   - The commit includes:
     - Receiver address (who will receive the NFT if they win)
     - Cosigner address (authorized signer)
     - Seed (user's random number)
     - Order hash (hash of the NFT purchase details)
     - Commit amount (amount user is committing)
     - Reward amount (NFT price)

3. **Fulfillment Transaction**
   - After the commit, a separate fulfillment transaction is sent
   - This transaction:
     - Verifies the commit
     - Generates a random number
     - Determines if the user won
     - Either purchases the NFT for the winner or returns funds

## How to Verify Transactions

### 1. Finding the Commit Transaction

1. Go to Etherscan and search for the user's wallet address
2. Look for a transaction to the LuckyBuy contract (0xE6b247ea4dD0C77A3EF8d99a30b4877a779e1c9C)
3. The commit transaction will emit a `Commit` event with the following information:
   - `sender`: The address that sent the commit
   - `commitId`: Unique identifier for this commit
   - `receiver`: Address that will receive the NFT if they win
   - `cosigner`: Authorized signer address
   - `seed`: User's random seed
   - `counter`: User's commit counter
   - `orderHash`: Hash of the NFT purchase details
   - `amount`: Amount committed
   - `reward`: NFT price
   - `protocolFee`: Protocol fee amount
   - `flatFee`: Flat fee amount
   - `digest`: Hash of the commit data

### 2. Finding the Fulfillment Transaction

1. The fulfillment transaction will be a separate transaction to the same contract
2. Look for a transaction that emits a `Fulfillment` event with:
   - `sender`: Address that sent the fulfillment
   - `commitId`: Same commitId from the commit transaction
   - `rng`: Random number generated
   - `odds`: Calculated odds of winning
   - `win`: Whether the user won (true/false)
   - `token`: NFT contract address (if won)
   - `tokenId`: NFT token ID (if won)
   - `amount`: Amount spent on NFT (if won)
   - `receiver`: Address that received the NFT (if won)
   - `fee`: Protocol fee amount
   - `digest`: Hash of the commit data

### 3. Verifying the Result

If the user won:

1. The `win` field in the Fulfillment event will be `true`
2. The `token` and `tokenId` fields will show the NFT details
3. The NFT should be transferred to the `receiver` address

If the user lost:

1. The `win` field in the Fulfillment event will be `false`
2. The `token` and `tokenId` fields will be zero addresses
3. The user's committed amount is kept by the contract

## Important Notes

1. **Commit Expiration**

   - Commits expire after 1 day if not fulfilled
   - Users can call `expire()` to get their funds back after expiration
   - Expired commits emit a `CommitExpired` event

2. **Fee Structure**

   - Flat fee: Fixed amount taken from every commit
   - Protocol fee: Percentage of the commit amount
   - Both fees are shown in the Commit event

3. **Open Edition Tokens**

   - If configured, users who lose receive an open edition token
   - The token details are shown in the `OpenEditionTokenSet` event

4. **Transaction Verification**
   - Always verify both the commit and fulfillment transactions
   - The `commitId` links the two transactions together
   - The `digest` should match between commit and fulfillment

## Common Issues

1. **Missing Fulfillment**

   - If a commit exists but no fulfillment is found, check if it's expired
   - Use the `commitExpiresAt` mapping to check expiration time
   - Guide users to call `expire()` if past expiration

2. **Failed NFT Purchase**

   - If the fulfillment shows `win: true` but no NFT transfer
   - Check if the NFT purchase failed
   - The contract will attempt to send ETH equivalent to the user

3. **Incorrect Odds**
   - Odds are calculated as: `(commitAmount * BASE_POINTS) / reward`
   - Verify the amounts in the Commit event match the user's expectations

## Contract Addresses

- LuckyBuy Contract: 0xE6b247ea4dD0C77A3EF8d99a30b4877a779e1c9C
- Cosigner: 0x993f64E049F95d246dc7B0D196CB5dC419d4e1f1
- Fee Receiver: 0x85d31445AF0b0fF26851bf3C5e27e90058Df3270
- OpenEdition: 0x3e988D49b3dE913FcE7D4ea0037919345ebDC3F8
