# Cancel Flow Swimlanes

## Packs Cancel Flow

```mermaid
sequenceDiagram
    participant U as User/Cosigner
    participant P as Packs Contract
    participant F as fundsReceiver
    
    U->>P: cancel(commitId)
    
    Note over P: Validate:<br/>- commitId valid<br/>- not fulfilled<br/>- not cancelled<br/>- past cancellable time
    
    P->>P: Set isCancelled = true
    P->>P: commitBalance -= packPrice
    
    alt Transfer Success
        P->>U: Transfer packPrice
    else Transfer Fails
        P->>P: treasuryBalance += packPrice
        P->>P: emit TransferFailure
    end
    
    P->>P: emit CommitCancelled
```

## LuckyBuy Expire Flow

```mermaid
sequenceDiagram
    participant U as User/Cosigner
    participant L as LuckyBuy Contract
    participant F as feeReceiver
    
    U->>L: expire(commitId)
    
    Note over L: Validate:<br/>- commitId valid<br/>- not fulfilled<br/>- not expired<br/>- past expire time
    
    L->>L: Set isExpired = true
    L->>L: commitBalance -= amount
    L->>L: protocolBalance -= fees
    L->>L: transferAmount = amount + fees
    
    alt Transfer Success
        L->>U: Transfer (amount + fees)
    else Transfer Fails
        L->>L: treasuryBalance += transferAmount
        L->>L: emit TransferFailure
    end
    
    L->>L: emit CommitExpired
```

## LuckyBuy Bulk Expire Flow

```mermaid
sequenceDiagram
    participant U as User/Cosigner
    participant L as LuckyBuy Contract
    participant F as feeReceiver
    
    U->>L: bulkExpire(commitIds[])
    
    loop For each commitId
        Note over L: Validate ownership:<br/>receiver == msg.sender OR<br/>cosigner == msg.sender
        
        Note over L: Validate commit:<br/>- commitId valid<br/>- not fulfilled<br/>- not expired<br/>- past expire time
        
        L->>L: Set isExpired = true
        L->>L: commitBalance -= amount
        L->>L: protocolBalance -= fees
        L->>L: transferAmount = amount + fees
        
        alt Transfer Success
            L->>U: Transfer (amount + fees)
        else Transfer Fails
            L->>L: treasuryBalance += transferAmount
            L->>L: emit TransferFailure
        end
        
        L->>L: emit CommitExpired
    end
```

## Key Differences Summary

| Aspect | Packs | LuckyBuy |
|--------|-------|----------|
| **Function** | `cancel()` | `expire()` / `bulkExpire()` |
| **State Flag** | `isCancelled` | `isExpired` |
| **Default Time** | 1 hour | 1 day |
| **Refund Amount** | Pack price only | Commit amount + protocol fees |
| **Balance Updates** | `commitBalance` only | Both `commitBalance` and `protocolBalance` |
| **Bulk Support** | No | Yes |
| **Fallback** | Treasury + TransferFailure event | Treasury + TransferFailure event |
