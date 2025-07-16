// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "src/PayoutContract.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
import {ISignatureVerifier} from "../src/common/interfaces/ISignatureVerifier.sol";

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
            0,  // bulkCommitFee
            feeReceiver_,
            prng_,
            feeReceiverManager_
        )
    {}

    function fulfillOrder(
        address txTo_,
        bytes calldata data_,
        uint256 amount_
    ) public returns (bool success) {
        (success, ) = txTo_.call{value: amount_}(data_);
    }
}

contract PayoutContractTest is Test {
    PayoutContract private payoutContract;
    MockLuckyBuy private luckyBuy;
    PRNG private prng;

    address private receiver = address(0x2);
    address private feeReceiver = address(0x3);
    address private admin = address(0x1);
    address private feeReceiverManager = address(0x4);
    
    // Test cosigner with known private key for fulfill testing
    uint256 constant COSIGNER_PRIVATE_KEY = 12345;
    address cosigner = vm.addr(COSIGNER_PRIVATE_KEY);

    function setUp() public {
        payoutContract = new PayoutContract();
        
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new MockLuckyBuy(
            0, // protocolFee
            0, // flatFee
            0, // bulkCommitFee
            admin, // feeReceiver
            address(prng),
            feeReceiverManager
        );
        luckyBuy.addCosigner(cosigner);
        vm.stopPrank();
        
        // Fund the contracts and test addresses
        vm.deal(address(luckyBuy), 10 ether);
        vm.deal(address(this), 10 ether);
        vm.deal(receiver, 10 ether); // Fund the receiver for the commit
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

        bytes32 digest = luckyBuy.hash(commitData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Successful payout with a non-zero fee fraction.
    function test_fulfillPayout_success_with_fee() public {
        uint256 totalAmount = 1 ether;
        uint256 fee = 0.02 ether; // 2% fee
        uint256 receiverAmount = totalAmount - fee;

        vm.deal(address(this), totalAmount);

        uint256 receiverBefore = receiver.balance;
        uint256 feeReceiverBefore = feeReceiver.balance;

        vm.expectEmit(true, true, true, true);
        emit PayoutContract.PayoutFulfilled(
            keccak256("order"),
            receiver,
            feeReceiver,
            receiverAmount,
            fee
        );

        payoutContract.fulfillPayout{value: totalAmount}(
            keccak256("order"),
            receiver,
            receiverAmount,
            feeReceiver,
            fee
        );

        assertEq(receiver.balance, receiverBefore + receiverAmount);
        assertEq(feeReceiver.balance, feeReceiverBefore + fee);
        assertEq(address(payoutContract).balance, 0);
    }

    /// @dev Successful payout when no fee is charged.
    function test_fulfillPayout_success_zero_fee() public {
        uint256 amount = 1 ether;

        vm.deal(address(this), amount);

        uint256 receiverBefore = receiver.balance;

        payoutContract.fulfillPayout{value: amount}(
            keccak256("order2"),
            receiver,
            amount,
            feeReceiver,
            0
        );

        assertEq(receiver.balance, receiverBefore + amount);
        assertEq(address(payoutContract).balance, 0);
    }

    /// @dev Reverts when the receiver address is zero.
    function test_fulfillPayout_reverts_on_invalid_receiver() public {
        vm.expectRevert(PayoutContract.InvalidReceiver.selector);

        payoutContract.fulfillPayout{value: 1 ether}(
            keccak256("order3"),
            address(0),
            1 ether,
            feeReceiver,
            0
        );
    }

    /// @dev Reverts when the value sent is less than the expected payout.
    function test_fulfillPayout_reverts_on_insufficient_funds() public {
        vm.expectRevert(PayoutContract.InsufficientFunds.selector);

        payoutContract.fulfillPayout{value: 0.5 ether}(
            keccak256("order4"),
            receiver,
            1 ether,
            feeReceiver,
            0
        );
    }

    /// @dev End-to-end test showing LuckyBuy calling PayoutContract for order fulfillment with actual fulfill.
    function test_end_to_end_luckybuy_payout_with_fulfill() public {
        // Fund the LuckyBuy contract treasury first
        (bool success, ) = address(luckyBuy).call{value: 5 ether}("");
        assertTrue(success, "Failed to fund LuckyBuy treasury");
        
        uint256 PAYOUT_REWARD = 1 ether;
        uint256 PAYOUT_FEE = 0.05 ether; // 5% fee
        uint256 PAYOUT_RECEIVER_AMOUNT = PAYOUT_REWARD - PAYOUT_FEE;
        
        address PAYOUT_RECEIVER = receiver;
        address PAYOUT_FEE_RECEIVER = feeReceiver;

        bytes memory PAYOUT_ORDER_DATA = abi.encodeWithSelector(
            PayoutContract.fulfillPayout.selector,
            keccak256("payout_order"),
            PAYOUT_RECEIVER,
            PAYOUT_RECEIVER_AMOUNT,
            PAYOUT_FEE_RECEIVER,
            PAYOUT_FEE
        );

        bytes32 PAYOUT_ORDER_HASH = luckyBuy.hashOrder(
            address(payoutContract),
            PAYOUT_REWARD,
            PAYOUT_ORDER_DATA,
            address(0),
            0
        );

        uint256 PAYOUT_SEED = 54321;
        uint256 PAYOUT_COMMIT_AMOUNT = (PAYOUT_REWARD * 75) / 100; // 75% odds

        vm.prank(receiver);
        uint256 commitId = luckyBuy.commit{value: PAYOUT_COMMIT_AMOUNT}(
            receiver,
            cosigner,
            PAYOUT_SEED,
            PAYOUT_ORDER_HASH,
            PAYOUT_REWARD
        );

        // Generate proper signature using the test cosigner
        bytes memory payoutSignature = signCommit(
            commitId,
            receiver,
            PAYOUT_SEED,
            0,
            PAYOUT_ORDER_HASH,
            PAYOUT_COMMIT_AMOUNT,
            PAYOUT_REWARD
        );

        uint256 PAYOUT_ODDS = (PAYOUT_COMMIT_AMOUNT * 10000) / PAYOUT_REWARD; // 75% = 7500
        uint256 rngResult = luckyBuy.PRNG().rng(payoutSignature);
        bool expectedWin = rngResult < PAYOUT_ODDS;

        console.log("LuckyBuy -> PayoutContract fulfill test:");
        console.log("Commit amount:", PAYOUT_COMMIT_AMOUNT);
        console.log("Reward:", PAYOUT_REWARD);
        console.log("Calculated odds:", PAYOUT_ODDS, "/ 10000 (75%)");
        console.log("RNG result:", rngResult);
        console.log("Expected win:", expectedWin);

        uint256 payoutReceiverBalanceBefore = PAYOUT_RECEIVER.balance;
        uint256 payoutFeeReceiverBalanceBefore = PAYOUT_FEE_RECEIVER.balance;

        // Fulfill the order - this will call PayoutContract.fulfillPayout if the user wins
        luckyBuy.fulfill(
            commitId,
            address(payoutContract),
            PAYOUT_ORDER_DATA,
            PAYOUT_REWARD,
            address(0),
            0,
            payoutSignature,
            address(0), // feeSplitReceiver
            0           // feeSplitPercentage
        );

        if (expectedWin) {
            assertEq(PAYOUT_RECEIVER.balance, payoutReceiverBalanceBefore + PAYOUT_RECEIVER_AMOUNT);
            assertEq(PAYOUT_FEE_RECEIVER.balance, payoutFeeReceiverBalanceBefore + PAYOUT_FEE);
            assertEq(address(payoutContract).balance, 0); // Should be 0 after payout
            
            console.log("SUCCESS: Payout distributed correctly!");
            console.log("Receiver got:", PAYOUT_RECEIVER_AMOUNT);
            console.log("Fee receiver got:", PAYOUT_FEE);
        } else {
            console.log("User lost - no payout distributed");
            // Verify balances didn't change
            assertEq(PAYOUT_RECEIVER.balance, payoutReceiverBalanceBefore);
            assertEq(PAYOUT_FEE_RECEIVER.balance, payoutFeeReceiverBalanceBefore);
        }
        
        // Verify the commit was processed
        assertTrue(luckyBuy.isFulfilled(commitId));
    }
}