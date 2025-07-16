# LuckyBuy EVM Contracts

LuckyBuy is a decentralized protocol that enables probabilistic NFT purchases. Users can commit a fraction of an NFT's price for a proportional chance to win the NFT. If they win, they receive the NFT at a discount. If they don't win, they lose their committed amount.

## Deployments

Current Mainnet: 0x0178070d088c235e1dc2696d257f90b3ded475a3
PRNG Mainnet: 0xBdAa680FcD544acc373c5f190449575768Ac4822
Cosigner: 0x993f64E049F95d246dc7B0D196CB5dC419d4e1f1

OpenEdition: 0x3e988D49b3dE913FcE7D4ea0037919345ebDC3F8
Token Id: 0
Amount: 1

## Overview

The protocol works in three steps:

1. **Commit**: Users commit ETH with a proportional chance to win (e.g., commit 0.1 ETH on a 1 ETH NFT for a 10% chance to win)
2. **Verify**: Trusted cosigners verify and sign valid commits
3. **Fulfill**: The protocol attempts to purchase the NFT if the user wins, or keeps the ETH if they lose

### Key Features

- Trustless probability calculation based on commit amount
- Secure random number generation using signature-based PRNG
- Support for any NFT marketplace that accepts Off Chain Orders
- Fallback ETH transfer if NFT purchase fails
- Multi-cosigner support for redundancy
- Commit expiration system
- Configurable protocol fees and minimum rewards
- Access control system
- Fee Receiver: 0x85d31445AF0b0fF26851bf3C5e27e90058Df3270

## Architecture

![swimlane](./docs/swimlane.png)

The system consists of the following components:

### Core Contracts

- **LuckyBuy.sol**: Core contract handling commits, verification, and fulfillment
- **PRNG.sol**: Secure random number generation using commit/reveal, CRC32 and signatures

### Common Components

- **SignatureVerifier.sol**: EIP-712 compliant signature verification
- **MEAccessControl.sol**: Role-based access control system
- **CRC32.sol**: CRC32 implementation for random number generation

### Security Features

- EIP-712 structured data signing
- Unbiased random number generation
- Advanced role-based access control
- Atomic execution of NFT purchases
- Protected against signature malleability
- Commit expiration mechanism
- Configurable protocol parameters

#### Security Notes

The protocol has several critical security considerations that should be carefully reviewed:

1. **Cosigner Security**

   - The cosigner is tremendously important. If the cosigner is compromised, the protocol is compromised.
   - We discussed ways to lock down the transaction in fulfillment, including whitelisting addresses, but ultimately decided against it.
   - Regardless of whitelisting, a compromised cosigner can be used to grind different orders in different protocols (e.g., Seaport) and could still drain the contract through the commit/fulfill grinding process.
   - The attacker could simply rotate addresses they control and treat that as a nonce in the commit/reveal process.
   - We opted to leave it flexible so the order to/data/amount is arbitrary and relies on protecting our cosigner and enforcing tight key management/rotation procedures.

2. **Random Number Generation**

   - The PRNG implementation uses a combination of keccak256 and CRC32 to generate random numbers.
   - The system implements modulo bias prevention by rejecting values above MAX_CRC32_HASH_VALUE.
   - Cosigners must ensure their signature generation process is truly random and not predictable.
   - The commit/reveal scheme adds an additional layer of randomness through user-provided seeds.

3. **Balance Management**

   - The contract maintains separate balances for treasury, commits, and protocol fees.
   - Each commit's fee is tracked individually to handle fee changes gracefully.

4. **Expiration Mechanism**

   - Commits have a configurable expiration time (default 1 day).
   - The expiration mechanism prevents funds from being locked indefinitely.

5. **Access Control**

   - The contract uses a role-based access control system for administrative functions.
   - Critical functions are protected by appropriate access controls.

6. **Marketplace Interaction**

   - The contract can interact with any NFT marketplace that accepts off-chain orders.
   - This flexibility comes with risks - careful validation of marketplace interactions on web2 in the magic eden back end is crucial.
   - Failed NFT purchases must be handled gracefully to ensure user funds are returned.

7. **Front-Running Protection**
   - The commit/reveal scheme helps protect against front-running.

These security considerations should be carefully reviewed during the security audit, with particular attention to the cosigner system and random number generation implementation.

## Fee Calculations

The LuckyBuy protocol implements a two-tier fee structure:

### Fee Structure

1. **Flat Fee**: A fixed amount taken off the top of every commit. This pays for the transfer fee of the Open Edition token

   - This fee is added directly to the treasury balance
   - It is not subject to the protocol fee calculation
   - It is not returned to the user, even if the commit expires

2. **Protocol Fee**: A percentage-based fee calculated on the amount after the flat fee
   - This fee is calculated using the formula: `protocolFee = (amount * protocolFee) / BASE_POINTS`
   - The protocol fee is tracked separately in the `protocolBalance`
   - It is returned to the user if the commit expires

### Fee Calculation Process

When a user commits funds, the following calculations occur:

1. The flat fee is subtracted from the total amount sent: `amountAfterFlatFee = msg.value - flatFee`
2. The commit amount is calculated by applying the protocol fee formula to the amount after flat fee: `commitAmount = (amountAfterFlatFee * BASE_POINTS) / (BASE_POINTS + protocolFee)`
3. The protocol fee is calculated as the difference: `protocolFee = amountAfterFlatFee - commitAmount`

### Example Calculation

For a commit with:

- Total amount sent: 1.01 ETH
- Flat fee: 0.01 ETH
- Protocol fee: 5% (500 basis points)

The calculation would be:

1. Amount after flat fee: 1.01 ETH - 0.01 ETH = 1 ETH
2. Protocol fee: 1 ETH \* 5% = 0.05 ETH
3. Commit amount: 0.95 ETH

### Fee Configuration

The fees can be configured by the contract admin:

- `setFlatFee(uint256 flatFee_)`: Sets the flat fee amount
- `setProtocolFee(uint256 protocolFee_)`: Sets the protocol fee percentage (in basis points)

The protocol fee is limited to a maximum of 100% (10000 basis points).

## Deployment

LuckyBuy uses the [ERC1967](https://docs.openzeppelin.com/contracts/5.x/api/proxy#ERC1967Proxy) proxy implementation pattern, meaning the contract is upgradeable.

Example depoyment script for Ethereum Sepolia testnet:

`forge script ./script/Deploy.s.sol:DeployLuckyBuy --chain-id 11155111 --rpc-url https://sepolia.drpc.org --verify --broadcast`

## Verification

`forge verify-contract 0x0178070d088C235e1Dc2696D257f90B3ded475a3 src/LuckyBuy.sol:LuckyBuy --constructor-args $(cast abi-encode "constructor(uint256,uint256,address,address,address)" 500 825000000000000 0x2918F39540df38D4c33cda3bCA9edFccd8471cBE 0xBdAa680FcD544acc373c5f190449575768Ac4822 0x7C51fAEe5666B47b2F7E81b7a6A8DEf4C76D47E3) --chain-id 1 --watch`
