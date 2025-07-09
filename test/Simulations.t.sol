// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
contract MockLuckyBuy is LuckyBuy {
    constructor(
        uint256 protocolFee_,
        uint256 flatFee_,
        uint256 bulkCommitFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    )
        LuckyBuy(
            protocolFee_,
            flatFee_,
            bulkCommitFee_,
            feeReceiver_,
            prng_,
            feeReceiverManager_
        )
    {}

    function setIsFulfilled(uint256 commitId_, bool isFulfilled_) public {
        isFulfilled[commitId_] = isFulfilled_;
    }

    /// @notice Calculates fee amount based on input amount and fee percentage
    /// @param _amount The amount to calculate fee on
    /// @return The calculated fee amount
    /// @dev Uses fee denominator of 10000 (100% = 10000)
    function calculateProtocolFee(
        uint256 _amount
    ) external view returns (uint256) {
        return _calculateProtocolFee(_amount);
    }

    function _calculateProtocolFee(
        uint256 _amount
    ) internal view returns (uint256) {
        return (_amount * protocolFee) / BASE_POINTS;
    }
}

contract TestLuckyBuyCommit is Test {
    bool skipTest = true;
    PRNG prng;
    MockLuckyBuy luckyBuy;
    address admin = address(0x1);
    address user = address(0x2);

    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    address cosigner;
    uint256 protocolFee = 0;
    uint256 flatFee = 0;
    uint256 bulkCommitFee = 0;
    uint256 seed = 12345;
    address marketplace = address(0);
    uint256 orderAmount = 1 ether;
    bytes32 orderData = hex"00";
    address orderToken = address(0);
    uint256 orderTokenId = 0;
    bytes32 orderHash = hex"";
    uint256 amount = 1 ether;
    uint256 reward = 10 ether; // 10% odds
    address feeReceiverManager = address(0x3);
    string constant OUTPUT_FILE = "./simulation_results.csv";

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new MockLuckyBuy(
            protocolFee,
            flatFee,
            bulkCommitFee,
            msg.sender,
            address(prng),
            feeReceiverManager
        );
        vm.deal(admin, 1000000 ether);
        vm.deal(user, 100000 ether);

        (bool success, ) = address(luckyBuy).call{value: 10000 ether}("");
        require(success, "Failed to deploy contract");

        // Set up cosigner with known private key
        cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
        // Add a cosigner for testing
        luckyBuy.addCosigner(cosigner);
        vm.stopPrank();
    }

    function signCommit(
        uint256 commitId,
        address receiver,
        uint256 seed,
        uint256 counter,
        bytes32 orderHash,
        uint256 amount,
        uint256 reward
    ) public returns (bytes memory) {
        // Create the commit data struct
        ISignatureVerifier.CommitData memory commitData = ISignatureVerifier
            .CommitData({
                id: commitId,
                receiver: receiver,
                cosigner: cosigner,
                seed: seed,
                counter: counter,
                orderHash: orderHash,
                amount: amount,
                reward: reward
            });

        // Get the digest using the LuckyBuy contract's hash function
        bytes32 digest = luckyBuy.hash(commitData);

        // Sign the digest with the cosigner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, digest);

        // Return the signature
        return abi.encodePacked(r, s, v);
    }

    function testSimulatePlay() public {
        if (skipTest) return;

        // out of base points
        uint256 protocolFee = 100;
        vm.prank(admin);
        luckyBuy.setProtocolFee(protocolFee);

        // Create order hash for a simple ETH transfer - this stays the same for all plays
        bytes32 orderHash = luckyBuy.hashOrder(
            address(0), // to address(0)
            1 ether, // amount 1 ether (reward amount)
            "", // no data
            address(0), // no token
            0 // no token id
        );

        // Calculate odds: amount/reward = 0.1/1 = 10%

        uint256 commitAmount = 0.5 ether;
        uint256 rewardAmount = 1 ether;
        uint256 feeAmount = luckyBuy.calculateProtocolFee(rewardAmount); // This should be .005 ether

        uint256 commitTxAmount = commitAmount + feeAmount;
        console.log("commitTxAmount", commitTxAmount);

        uint256 odds = (commitAmount * 100000) / rewardAmount;
        console.log("\nGame Parameters:");
        console.log("Odds of winning (basis points):", odds); // Should be 1000 (10%)
        console.log("Commit Amount:", commitAmount);
        console.log("Reward Amount:", rewardAmount);
        console.log("\nStarting 40k game simulations...\n");

        for (uint256 i = 0; i < 20_000; i++) {
            console.log("Game", i + 1, ":");

            vm.startPrank(user);
            console.log(commitAmount + feeAmount);
            // Create commit
            uint256 commitId = luckyBuy.commit{value: commitTxAmount}(
                user, // receiver
                cosigner, // cosigner
                seed, // random seed
                orderHash, // order hash we just created
                rewardAmount // reward amount (10x the commit for 10% odds)
            );
            vm.stopPrank();

            (
                uint256 _id,
                address _receiver,
                address _cosigner,
                uint256 _seed,
                uint256 _counter,
                bytes32 _orderHash,
                uint256 _amount,
                uint256 _reward
            ) = luckyBuy.luckyBuys(commitId);

            console.log("commitId", _id);
            console.log("receiver", _receiver);
            console.log("cosigner", _cosigner);
            console.log("seed", _seed);
            console.log("counter", _counter);
            console.logBytes32(_orderHash);
            console.log("amount", _amount);
            console.log("reward", _reward);

            // Get the counter for this commit
            uint256 counter = luckyBuy.luckyBuyCount(user) - 1;

            // Sign the commit
            bytes memory signature = signCommit(
                commitId,
                user,
                seed,
                counter,
                orderHash,
                commitAmount,
                rewardAmount
            );

            // Track treasury balance for win/loss determination
            uint256 initialTreasuryBalance = luckyBuy.treasuryBalance();

            // Fulfill the commit
            vm.startPrank(user);
            luckyBuy.fulfill(
                commitId,
                address(0), // marketplace
                "", // orderData
                rewardAmount, // orderAmount
                address(0), // token
                0, // tokenId
                signature,
                address(0),
                0
            );
            vm.stopPrank();

            // Calculate and log results
            bool won = luckyBuy.treasuryBalance() < initialTreasuryBalance;

            console.log("  Commit ID:", commitId);
            console.log("  Counter:", counter);
            console.log("  Won:", won);
            console.log(
                "  Treasury Balance Change:",
                won
                    ? initialTreasuryBalance - luckyBuy.treasuryBalance()
                    : luckyBuy.treasuryBalance() - initialTreasuryBalance
            );
            console.log("  LuckyBuy Balance:", luckyBuy.treasuryBalance());
            console.log("");

            // Write to CSV
            string memory row = string(
                abi.encodePacked(
                    vm.toString(commitId),
                    ",",
                    won ? "true" : "false",
                    ",",
                    vm.toString(
                        won
                            ? initialTreasuryBalance -
                                luckyBuy.treasuryBalance()
                            : luckyBuy.treasuryBalance() -
                                initialTreasuryBalance
                    ),
                    ",",
                    vm.toString(luckyBuy.treasuryBalance())
                )
            );
            vm.writeLine(OUTPUT_FILE, row);
        }
    }
}
