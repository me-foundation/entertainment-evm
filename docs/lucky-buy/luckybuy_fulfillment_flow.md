# LuckyBuy Fulfillment Flow

## LuckyBuy Individual Fulfillment Flow

```mermaid
sequenceDiagram
    participant C as Cosigner
    participant L as LuckyBuy Contract
    participant M as Marketplace
    participant U as User (receiver)
    participant F as feeReceiver
    participant FS as feeSplitReceiver
    
    C->>L: fulfill(commitId, marketplace, orderData, orderAmount, ..., feeSplitReceiver, feeSplitPercentage)
    
    Note over L: Validate:<br/>- commitId valid<br/>- not fulfilled<br/>- not expired<br/>- cosigner authorized<br/>- orderHash matches
    
    L->>L: Mark isFulfilled = true
    L->>L: treasuryBalance += commitAmount + protocolFees
    L->>L: commitBalance -= commitAmount
    L->>L: protocolBalance -= protocolFees
    
    L->>L: Calculate odds = (commitAmount * 10000) / reward
    L->>L: rng = PRNG.rng(signature)
    L->>L: win = rng < odds
    
    alt User Wins
        L->>L: _handleWin()
        L->>M: call{value: orderAmount}(orderData)
        
        alt NFT Order Success
            M->>U: Transfer NFT
            L->>L: treasuryBalance -= orderAmount
            L->>L: emit Fulfillment (win=true, orderSuccess=true)
        else NFT Order Fails
            alt Fallback Transfer Success
                L->>U: Transfer orderAmount (ETH fallback)
                L->>L: treasuryBalance -= orderAmount
            else Fallback Transfer Fails
                L->>L: emit TransferFailure
            end
            L->>L: emit Fulfillment (win=true, orderSuccess=false)
        end
        
    else User Loses
        alt openEditionToken != address(0)
            L->>U: Mint consolation NFT
        end
        L->>L: emit Fulfillment (win=false, orderSuccess=false)
    end
    
    Note over L: Handle Protocol Fees
    
    alt feeSplitReceiver != address(0) && feeSplitPercentage > 0
        L->>L: splitAmount = (protocolFees * feeSplitPercentage) / 10000
        
        alt Fee Split Success
            L->>FS: Transfer splitAmount
            L->>L: treasuryBalance -= splitAmount
        else Fee Split Fails
            L->>L: emit FeeTransferFailure
        end
        
        L->>L: remainingFees = protocolFees - splitAmount
        L->>L: _sendProtocolFees(remainingFees)
        L->>L: emit FeeSplit
    else
        L->>L: _sendProtocolFees(protocolFees)
    end
    
    Note over L: _sendProtocolFees attempts transfer to feeReceiver<br/>If fails, keeps in treasury + emits FeeTransferFailure
```

## LuckyBuy Bulk Fulfillment Flow

```mermaid
sequenceDiagram
    participant C as Cosigner
    participant L as LuckyBuy Contract
    participant M as Marketplace
    participant U as Users
    participant F as feeReceiver
    
    C->>L: bulkFulfill(requests[])
    
    loop For each FulfillRequest
        Note over L: Each request has its own:<br/>- commitDigest<br/>- marketplace<br/>- orderData<br/>- feeSplitReceiver<br/>- feeSplitPercentage
        
        L->>L: commitId = commitIdByDigest[request.commitDigest]
        L->>L: _checkFulfiller(commitId)
        L->>L: _fulfill(individual fulfillment logic)
        
        Note over L: Same individual fulfillment flow<br/>as above for each request
    end
```

## LuckyBuy Fee Structure Flow

```mermaid
flowchart TD
    A[User Commits Amount] --> B{Commit Type}
    
    B -->|Individual| C[Deduct flatFee<br/>Apply protocolFee]
    B -->|Bulk| D[Deduct flatFee<br/>Apply protocolFee + bulkCommitFee]
    
    C --> E[flatFee → feeReceiver immediately<br/>protocolFee → protocolBalance]
    D --> F[flatFee → feeReceiver immediately<br/>(protocolFee + bulkCommitFee) → protocolBalance]
    
    E --> G[Fulfillment Time]
    F --> G
    
    G --> H{Fee Split?}
    
    H -->|No Split| I[All protocolFees → feeReceiver<br/>via _sendProtocolFees]
    H -->|Split| J[splitAmount → feeSplitReceiver<br/>remainder → feeReceiver<br/>via _sendProtocolFees]
    
    I --> K[If transfer fails:<br/>Fees stay in treasury<br/>emit FeeTransferFailure]
    J --> K
    
    K --> L[Admin can withdraw<br/>treasury via withdraw()]
    
    style A fill:#e1f5fe
    style E fill:#fff3e0
    style F fill:#fff3e0
    style K fill:#ffebee
    style L fill:#f3e5f5
```

## LuckyBuy Treasury Management

```mermaid
flowchart TD
    A[Multiple Sources] --> B[treasuryBalance]
    
    A1[Failed flat fee transfers] --> B
    A2[Collected commit amounts] --> B
    A3[Collected protocol fees] --> B
    A4[Failed protocol fee transfers] --> B
    A5[Failed user transfers] --> B
    A6[Manual deposits via receive()] --> B
    
    B --> C{Admin Actions}
    
    C -->|withdraw(amount)| D[Transfer amount to feeReceiver<br/>treasuryBalance -= amount]
    C -->|emergencyWithdraw()| E[Transfer all balance to feeReceiver<br/>Reset all balances to 0<br/>Pause contract]
    
    D --> F[If transfer fails:<br/>revert WithdrawalFailed]
    E --> G[Contract paused<br/>All funds rescued]
    
    style B fill:#e3f2fd
    style D fill:#e8f5e8
    style E fill:#ffebee
    style F fill:#ffcdd2
    style G fill:#ffcdd2
```
