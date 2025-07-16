// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
import "src/common/interfaces/ISignatureVerifier.sol";
import {TokenRescuer} from "../src/common/TokenRescuer.sol";
import {MEAccessControl} from "../src/common/MEAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock ERC20", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock ERC721", "MOCK") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

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
    PRNG prng;
    MockLuckyBuy luckyBuy;
    address admin = address(0x1);
    address user = address(0x2);
    address receiver = address(0x3);
    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    address cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
    address feeReceiverManager = address(0x4);
    uint256 protocolFee = 0;
    uint256 flatFee = 0;

    uint256 seed = 12345;
    bytes32 orderHash = hex"1234";
    uint256 amount = 1 ether;
    uint256 reward = 10 ether; // 10% odds

    // Add missing variables for fee split tests
    address marketplace = address(0);
    bytes orderData = hex"00";
    uint256 orderAmount = 1 ether;
    address orderToken = address(0);
    uint256 orderTokenId = 0;

    address bob = address(0xB0B);
    address charlie = address(0xC0FFEE);

    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        bytes32 orderHash,
        uint256 amount,
        uint256 reward,
        uint256 fee,
        uint256 flatFee,
        bytes32 digest,
        uint256 bulkSessionId
    );
    event CommitExpireTimeUpdated(
        uint256 oldCommitExpireTime,
        uint256 newCommitExpireTime
    );
    event CommitExpired(uint256 indexed commitId);

    event Withdrawal(
        address indexed sender,
        uint256 amount,
        address feeReceiver
    );

    event MaxRewardUpdated(uint256 oldMaxReward, uint256 newMaxReward);

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new MockLuckyBuy(
            protocolFee,
            flatFee,
            0,
            admin,
            address(prng),
            feeReceiverManager
        );
        vm.deal(admin, 100 ether);
        vm.deal(receiver, 100 ether);
        vm.deal(address(this), 100 ether);
        // Add a cosigner for testing
        luckyBuy.addCosigner(cosigner);
        vm.stopPrank();
    }

    function testCommitSuccess() public {
        vm.startPrank(user);
        vm.deal(user, amount);

        // Note: We can't easily check the hash in the event since it's calculated inside the contract
        vm.expectEmit(true, true, true, false); // We don't check the non-indexed parameters
        emit Commit(
            user,
            0, // First commit ID should be 0
            receiver,
            cosigner,
            seed,
            0, // First counter for this receiver should be 0
            orderHash,
            amount,
            reward,
            0,
            0,
            bytes32(0),
            0 // bulkSessionId - 0 for individual commits
        );

        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            1,
            "Receiver counter should be incremented"
        );

        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(0);

        assertEq(id, 0, "Commit ID should be 0");
        assertEq(storedReceiver, receiver, "Receiver should match");
        assertEq(storedCosigner, cosigner, "Cosigner should match");
        assertEq(storedSeed, seed, "Seed should match");
        assertEq(storedCounter, 0, "Counter should be 0");
        assertEq(storedOrderHash, orderHash, "Order hash should match");
        assertEq(storedAmount, amount, "Amount should match");
        assertEq(storedReward, reward, "Reward should match");
        vm.stopPrank();
    }

    function testCommitSuccessWithFlatFee() public {
        uint256 flatFeeAmount = 0.01 ether;
        vm.startPrank(admin);
        luckyBuy.setFlatFee(flatFeeAmount);
        vm.stopPrank();

        assertEq(luckyBuy.flatFee(), flatFeeAmount);

        assertEq(luckyBuy.protocolBalance(), 0);

        console.log("protocolFee", luckyBuy.protocolFee());

        vm.deal(address(luckyBuy), 100 ether);

        vm.startPrank(user);
        vm.deal(user, amount + flatFeeAmount);

        // Note: We can't easily check the hash in the event since it's calculated inside the contract
        vm.expectEmit(true, true, true, false); // We don't check the non-indexed parameters
        emit Commit(
            user,
            0, // First commit ID should be 0
            receiver,
            cosigner,
            seed,
            0, // First counter for this receiver should be 0
            orderHash,
            amount,
            reward,
            0,
            flatFeeAmount,
            bytes32(0),
            0 // bulkSessionId - 0 for individual commits
        );

        luckyBuy.commit{value: amount + flatFeeAmount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            1,
            "Receiver counter should be incremented"
        );

        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(0);

        assertEq(id, 0, "Commit ID should be 0");
        assertEq(storedReceiver, receiver, "Receiver should match");
        assertEq(storedCosigner, cosigner, "Cosigner should match");
        assertEq(storedSeed, seed, "Seed should match");
        assertEq(storedCounter, 0, "Counter should be 0");
        assertEq(storedOrderHash, orderHash, "Order hash should match");
        assertEq(storedAmount, amount, "Amount should match");
        assertEq(storedReward, reward, "Reward should match");

        // Flat Fee goes straight to fee receiver
        assertEq(admin.balance, 100 ether + flatFeeAmount);
        vm.stopPrank();
    }

    function testCommitMultipleTimes() public {
        vm.startPrank(user);
        vm.deal(user, amount * 2);

        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            1,
            "Receiver counter should be 1 after first commit"
        );

        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed + 1,
            "secondOrderHash",
            reward
        );

        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            2,
            "Receiver counter should be 2 after second commit"
        );

        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(1);

        assertEq(id, 1, "Second commit ID should be 1");
        assertEq(storedReceiver, receiver, "Receiver should match");
        assertEq(storedCosigner, cosigner, "Cosigner should match");
        assertEq(storedSeed, seed + 1, "Seed should match");
        assertEq(storedCounter, 1, "Counter should be 1 for second commit");
        assertEq(storedOrderHash, "secondOrderHash", "Order hash should match");
        assertEq(storedAmount, amount, "Amount should match");
        assertEq(storedReward, reward, "Reward should match");
        vm.stopPrank();
    }

    function testCommitWithZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(LuckyBuy.InvalidAmount.selector);
        luckyBuy.commit{value: 0}(receiver, cosigner, seed, orderHash, reward);

        vm.stopPrank();
    }

    function testCommitWithInvalidCosigner() public {
        address invalidCosigner = address(0x5);
        vm.startPrank(user);
        vm.deal(user, amount);

        // Act & Assert - Should revert with InvalidCosigner
        vm.expectRevert(LuckyBuy.InvalidCosigner.selector);
        luckyBuy.commit{value: amount}(
            receiver,
            invalidCosigner,
            seed,
            orderHash,
            reward
        );

        vm.stopPrank();
    }

    function testCommitWithZeroAddressReceiver() public {
        vm.startPrank(user);
        vm.deal(user, amount);

        vm.expectRevert(LuckyBuy.InvalidReceiver.selector);
        luckyBuy.commit{value: amount}(
            address(0),
            cosigner,
            seed,
            orderHash,
            reward
        );

        vm.stopPrank();
    }

    function testCommitWithRemovedCosigner() public {
        vm.startPrank(admin);
        luckyBuy.removeCosigner(cosigner);
        vm.stopPrank();

        vm.startPrank(user);
        vm.deal(user, amount);

        vm.expectRevert(LuckyBuy.InvalidCosigner.selector);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        vm.stopPrank();
    }

    function testCommitFromDifferentUsers() public {
        address user2 = address(0x6);

        vm.startPrank(user);
        vm.deal(user, amount);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
        vm.stopPrank();

        vm.startPrank(user2);
        vm.deal(user2, amount);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed + 1,
            orderHash,
            reward
        );
        vm.stopPrank();
        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            2,
            "Receiver counter should be 2 after commits from two users"
        );

        (
            uint256 id1,
            address receiver1,
            address cosigner1,
            ,
            ,
            bytes32 orderHash1,
            uint256 amount1,
            uint256 reward1
        ) = luckyBuy.luckyBuys(0);

        (
            uint256 id2,
            address receiver2,
            address cosigner2,
            ,
            ,
            bytes32 orderHash2,
            uint256 amount2,
            uint256 reward2
        ) = luckyBuy.luckyBuys(1);

        assertEq(id1, 0, "First commit ID should be 0");
        assertEq(id2, 1, "Second commit ID should be 1");
        assertEq(receiver1, receiver, "First receiver should match");
        assertEq(receiver2, receiver, "Second receiver should match");
        assertEq(orderHash1, orderHash, "First order hash should match");
        assertEq(orderHash2, orderHash, "Second order hash should match");
        assertEq(amount1, amount, "First amount should match");
        assertEq(amount2, amount, "Second amount should match");
        assertEq(reward1, reward, "First reward should match");
        assertEq(reward2, reward, "Second reward should match");
    }

    function testCommitToDifferentReceivers() public {
        address receiver2 = address(0x7);

        vm.startPrank(user);
        vm.deal(user, amount * 2);

        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        luckyBuy.commit{value: amount}(
            receiver2,
            cosigner,
            seed + 1,
            orderHash,
            reward
        );

        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            1,
            "First receiver counter should be 1"
        );
        assertEq(
            luckyBuy.luckyBuyCount(receiver2),
            1,
            "Second receiver counter should be 1"
        );

        (
            ,
            address storedReceiver1,
            ,
            ,
            uint256 storedCounter1,
            ,
            ,
            uint256 storedReward1
        ) = luckyBuy.luckyBuys(0);

        (
            ,
            address storedReceiver2,
            ,
            ,
            uint256 storedCounter2,
            ,
            ,
            uint256 storedReward2
        ) = luckyBuy.luckyBuys(1);

        assertEq(
            storedReceiver1,
            receiver,
            "First stored receiver should match"
        );
        assertEq(
            storedReceiver2,
            receiver2,
            "Second stored receiver should match"
        );
        assertEq(storedCounter1, 0, "First receiver counter should be 0");
        assertEq(storedCounter2, 0, "Second receiver counter should be 0");
        assertEq(storedReward1, reward, "First reward should match");
        assertEq(storedReward2, reward, "Second reward should match");

        vm.stopPrank();
    }

    function testCommitWithVaryingAmounts() public {
        uint256 amount1 = 0.5 ether;
        uint256 amount2 = 2 ether;

        vm.startPrank(user);
        vm.deal(user, amount1 + amount2);

        luckyBuy.commit{value: amount1}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        luckyBuy.commit{value: amount2}(
            receiver,
            cosigner,
            seed + 1,
            orderHash,
            reward
        );

        (, , , , , , uint256 storedAmount1, uint256 storedReward1) = luckyBuy
            .luckyBuys(0);

        (, , , , , , uint256 storedAmount2, uint256 storedReward2) = luckyBuy
            .luckyBuys(1);

        assertEq(storedAmount1, amount1, "First stored amount should match");
        assertEq(storedAmount2, amount2, "Second stored amount should match");
        assertEq(storedReward1, reward, "First stored reward should match");
        assertEq(storedReward2, reward, "Second stored reward should match");

        vm.stopPrank();
    }

    function testCommitCounterIncrement() public {
        vm.startPrank(user);
        vm.deal(user, amount * 5);
        for (uint i = 0; i < 5; i++) {
            console.log("Here:");
            luckyBuy.commit{value: amount}(
                receiver,
                cosigner,
                seed + i,
                orderHash,
                reward
            );

            assertEq(
                luckyBuy.luckyBuyCount(receiver),
                i + 1,
                "Receiver counter should increment correctly"
            );

            (, , , , uint256 storedCounter, , , ) = luckyBuy.luckyBuys(i);
            console.log(storedCounter);
            assertEq(storedCounter, i, "Stored counter should match index");
        }

        vm.stopPrank();
    }

    function testSetMaxReward() public {
        uint256 startMaxReward = luckyBuy.maxReward();

        vm.expectRevert();
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            startMaxReward * 2
        );

        vm.expectRevert();
        luckyBuy.setMaxReward(startMaxReward * 2);

        vm.startPrank(admin);
        luckyBuy.setMaxReward(startMaxReward * 2);

        assertEq(luckyBuy.maxReward(), startMaxReward * 2);

        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            startMaxReward * 2
        );

        vm.expectRevert();
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            startMaxReward * 3
        );
    }

    function testDepositTreasury() public {
        // Initial balance check
        uint256 initialBalance = address(luckyBuy).balance;

        // Test direct ETH transfer
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success, ) = address(luckyBuy).call{value: 1 ether}("");

        assertTrue(success, "ETH transfer should succeed");
        assertEq(
            address(luckyBuy).balance,
            initialBalance + 1 ether,
            "Contract balance should increase by 1 ether"
        );
    }

    function testDepositTreasuryFromDifferentAccounts() public {
        address user2 = address(0x8);
        uint256 initialBalance = address(luckyBuy).balance;

        // First deposit from user1
        vm.deal(user, 0.5 ether);
        vm.prank(user);
        (bool success1, ) = address(luckyBuy).call{value: 0.5 ether}("");

        // Second deposit from user2
        vm.deal(user2, 1.5 ether);
        vm.prank(user2);
        (bool success2, ) = address(luckyBuy).call{value: 1.5 ether}("");

        assertTrue(success1 && success2, "Both transfers should succeed");
        assertEq(
            address(luckyBuy).balance,
            initialBalance + 2 ether,
            "Contract balance should increase by total amount"
        );
    }

    function testPredictAddressAndPreFund() public {
        // Calculate the future address of LuckyBuy contract
        address predictedAddress = computeCreateAddress(
            admin,
            vm.getNonce(admin)
        );

        // Pre-fund the future contract address
        vm.deal(predictedAddress, 5 ether);
        assertEq(
            predictedAddress.balance,
            5 ether,
            "Predicted address should be funded"
        );

        // Deploy LuckyBuy from admin account
        vm.prank(admin);
        LuckyBuy newLuckyBuy = new LuckyBuy(
            protocolFee,
            flatFee,
            0,
            msg.sender,
            address(prng),
            feeReceiverManager
        );

        // Verify the deployment address matches prediction
        assertEq(
            address(newLuckyBuy),
            predictedAddress,
            "Deployed address should match prediction"
        );

        // Verify the contract balance is preserved
        assertEq(
            address(newLuckyBuy).balance,
            5 ether,
            "Contract should maintain pre-funded balance"
        );
    }

    function testCommitWithEqualValueAndReward() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);

        // Try to commit with msg.value equal to reward
        // Guarantee win, but they pay a fee
        luckyBuy.commit{value: 1 ether}(
            receiver,
            cosigner,
            seed,
            orderHash,
            1 ether // reward equal to msg.value
        );

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(admin);
        luckyBuy.pause();
        vm.stopPrank();

        assertEq(luckyBuy.paused(), true);

        vm.expectRevert();
        luckyBuy.pause();

        vm.startPrank(admin);
        luckyBuy.unpause();
        vm.stopPrank();

        vm.expectRevert();
        luckyBuy.unpause();

        assertEq(luckyBuy.paused(), false);
    }

    function testCommitWhenPaused() public {
        vm.startPrank(admin);
        luckyBuy.pause();
        vm.stopPrank();

        vm.expectRevert();
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
    }

    function testFulfillWhenPaused() public {
        // First create a valid commit
        vm.startPrank(receiver);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
        vm.stopPrank();

        // Then pause and try to fulfill
        vm.startPrank(admin);
        luckyBuy.pause();
        vm.stopPrank();

        vm.expectRevert();
        luckyBuy.fulfill(
            0,
            receiver,
            new bytes(0),
            reward,
            address(0),
            0,
            new bytes(0),
            address(0),
            0
        );
    }

    function testMaxRewardUpdate() public {
        vm.startPrank(admin);
        uint256 newMaxReward = 50 ether;

        vm.expectEmit(true, true, true, false);
        emit MaxRewardUpdated(reward, newMaxReward);

        luckyBuy.setMaxReward(newMaxReward);
        assertEq(luckyBuy.maxReward(), newMaxReward);
        vm.stopPrank();
    }

    function testCommitWithRewardBelowMinimum() public {
        uint256 belowMinReward = luckyBuy.BASE_POINTS() - 1;

        vm.expectRevert(LuckyBuy.InvalidReward.selector);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            belowMinReward
        );
    }

    function testTreasuryBalanceManagement() public {
        uint256 initialBalance = address(luckyBuy).balance;
        uint256 depositAmount = 5 ether;

        // Test direct ETH transfer
        (bool success, ) = address(luckyBuy).call{value: depositAmount}("");
        assertTrue(success);
        assertEq(luckyBuy.treasuryBalance(), initialBalance + depositAmount);

        // Test balance update during commit
        vm.startPrank(receiver);
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
        vm.stopPrank();

        assertEq(luckyBuy.treasuryBalance(), depositAmount);
        assertEq(luckyBuy.commitBalance(), amount);
        assertEq(luckyBuy.protocolBalance(), 0);
    }

    function testCommitId() public {
        vm.startPrank(user);
        vm.deal(user, amount);

        uint256 commitId = luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(luckyBuy.luckyBuyCount(receiver), 1);

        vm.stopPrank();

        assertEq(commitId, 0);

        (uint256 id, , , , , , , ) = luckyBuy.luckyBuys(commitId);
        assertEq(id, commitId);
    }

    function testInvalidAmountOverOdds() public {
        vm.startPrank(user);
        vm.deal(user, 2 ether);

        // Try to commit with amount that would result in >100% odds
        // If amount * BASE_POINTS / reward > BASE_POINTS, it should revert
        vm.expectRevert(LuckyBuy.InvalidAmount.selector);
        luckyBuy.commit{value: 2 ether}(
            receiver,
            cosigner,
            seed,
            orderHash,
            1 ether // This would result in 200% odds
        );

        vm.stopPrank();
    }

    function testProtocolFee() public {
        vm.startPrank(admin);
        luckyBuy.setProtocolFee(100);
        vm.stopPrank();

        assertEq(luckyBuy.protocolFee(), 100);
    }

    function testCalculateFee() public {
        uint256 amount = 1 ether;
        uint256 protocolFee = 100;

        vm.startPrank(admin);
        luckyBuy.setProtocolFee(protocolFee);
        vm.stopPrank();

        uint256 fee = luckyBuy.calculateProtocolFee(amount);
        assertEq(fee, (amount * protocolFee) / luckyBuy.BASE_POINTS());
    }

    // The contract will use a reverse fee calculation based on msg.value because msg.value = commit amount + fee.
    // However, that math should be the same as knowing the commit amount and calculating the fee from it.
    function testCommitWithFee() public {
        uint256 amount = 1 ether;
        uint256 protocolFee = 100;
        // reward is 10 eth;

        vm.startPrank(admin);
        luckyBuy.setProtocolFee(protocolFee);
        vm.stopPrank();

        assertNotEq(amount, reward);

        uint256 fee = luckyBuy.calculateProtocolFee(amount);
        uint256 rewardFee = luckyBuy.calculateProtocolFee(reward);

        assertNotEq(fee, rewardFee);

        uint256 amountWithFee = amount + fee;

        uint256 amountWithoutFeeCheck = luckyBuy
            .calculateContributionWithoutFee(amountWithFee, protocolFee);

        assertEq(amountWithoutFeeCheck, amount);

        vm.startPrank(user);
        vm.deal(user, amountWithFee);

        luckyBuy.commit{value: amountWithFee}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        (
            uint256 id,
            ,
            ,
            ,
            ,
            ,
            uint256 amountWithoutFee,
            uint256 reward
        ) = luckyBuy.luckyBuys(0);

        assertEq(amountWithoutFee, amount);
        assertEq(amountWithFee, address(luckyBuy).balance);

        assertEq(
            luckyBuy.calculateProtocolFee(amount),
            amountWithFee - amount,
            "Fee should be the same"
        );

        assertEq(luckyBuy.protocolBalance(), fee);
    }

    function testWithdrawSuccess() public {
        uint256 withdrawAmount = 1 ether;
        address feeReceiver = luckyBuy.feeReceiver();
        // Fund the contract first
        vm.deal(address(this), withdrawAmount);
        (bool success, ) = address(luckyBuy).call{value: withdrawAmount}("");
        assertTrue(success, "Initial funding should succeed");

        uint256 initialBalance = address(luckyBuy).balance;
        uint256 initialAdminBalance = address(admin).balance;

        vm.expectEmit(true, true, true, false);
        emit Withdrawal(admin, withdrawAmount, feeReceiver);

        vm.prank(admin);
        luckyBuy.withdraw(withdrawAmount);

        assertEq(
            address(luckyBuy).balance,
            initialBalance - withdrawAmount,
            "Contract balance should decrease"
        );
        assertEq(
            address(admin).balance,
            initialAdminBalance + withdrawAmount,
            "Admin balance should increase"
        );
        assertEq(
            luckyBuy.treasuryBalance(),
            initialBalance - withdrawAmount,
            "Contract balance state should update"
        );
    }

    function testWithdrawInsufficientBalance() public {
        uint256 withdrawAmount = 1 ether;

        // Try to withdraw without funding
        vm.startPrank(admin);
        vm.expectRevert(LuckyBuy.InsufficientBalance.selector);
        luckyBuy.withdraw(withdrawAmount);
        vm.stopPrank();

        // Fund with less than withdraw amount
        vm.deal(address(this), withdrawAmount / 2);
        (bool success, ) = address(luckyBuy).call{value: withdrawAmount / 2}(
            ""
        );
        assertTrue(success, "Initial funding should succeed");

        // Try to withdraw more than available
        vm.startPrank(admin);
        vm.expectRevert(LuckyBuy.InsufficientBalance.selector);
        luckyBuy.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    function testWithdrawNonAdmin() public {
        uint256 withdrawAmount = 1 ether;

        // Fund the contract
        vm.deal(address(this), withdrawAmount);
        (bool success, ) = address(luckyBuy).call{value: withdrawAmount}("");
        assertTrue(success, "Initial funding should succeed");

        // Try to withdraw as non-admin
        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    function testWithdrawMultiple() public {
        uint256 totalAmount = 5 ether;
        uint256 withdrawAmount = 1 ether;

        // Fund the contract
        vm.deal(address(this), totalAmount);
        (bool success, ) = address(luckyBuy).call{value: totalAmount}("");
        assertTrue(success, "Initial funding should succeed");

        uint256 initialBalance = address(luckyBuy).balance;
        uint256 initialAdminBalance = address(admin).balance;

        // Perform multiple withdrawals
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(admin);
            luckyBuy.withdraw(withdrawAmount);
            vm.stopPrank();

            assertEq(
                address(luckyBuy).balance,
                initialBalance - (withdrawAmount * (i + 1)),
                "Contract balance should decrease correctly"
            );
            assertEq(
                address(admin).balance,
                initialAdminBalance + (withdrawAmount * (i + 1)),
                "Admin balance should increase correctly"
            );
            assertEq(
                luckyBuy.treasuryBalance(),
                initialBalance - (withdrawAmount * (i + 1)),
                "Contract balance state should update correctly"
            );
        }
    }

    function testWithdrawZeroAmount() public {
        // Try to withdraw zero amount
        vm.startPrank(admin);
        luckyBuy.withdraw(0);
        vm.stopPrank();

        // State should remain unchanged
        assertEq(
            address(luckyBuy).balance,
            0,
            "Contract balance should remain 0"
        );
        assertEq(
            luckyBuy.treasuryBalance(),
            0,
            "Contract balance state should remain 0"
        );
    }

    function testEmergencyWithdraw() public {
        luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );

        uint256 initialBalance = address(admin).balance;

        vm.startPrank(admin);
        luckyBuy.emergencyWithdraw();
        vm.stopPrank();

        assertEq(address(luckyBuy).balance, 0);
        assertEq(address(admin).balance, initialBalance + amount);
        assertEq(luckyBuy.treasuryBalance(), 0);
        assertEq(luckyBuy.commitBalance(), 0);
        assertEq(luckyBuy.protocolBalance(), 0);
        assertEq(luckyBuy.paused(), true);
    }

    function testInvalidProtocolFee() public {
        vm.startPrank(admin);
        uint256 invalidProtocolFee = luckyBuy.BASE_POINTS() + 1;
        vm.expectRevert(LuckyBuy.InvalidProtocolFee.selector);
        luckyBuy.setProtocolFee(invalidProtocolFee);
        vm.stopPrank();
    }

    function testProtocolFeeUpdate() public {
        vm.startPrank(admin);
        luckyBuy.setProtocolFee(100);
        vm.stopPrank();
    }

    function testMinRewardUpdate() public {
        vm.startPrank(admin);
        luckyBuy.setMinReward(luckyBuy.BASE_POINTS());
        vm.stopPrank();

        assertEq(luckyBuy.minReward(), luckyBuy.BASE_POINTS());
    }

    function testMinRewardUpdateBelowBase() public {
        vm.startPrank(admin);
        vm.expectRevert(LuckyBuy.InvalidReward.selector);
        luckyBuy.setMinReward(0);
        vm.stopPrank();
    }

    function testMinRewardUpdateAboveMax() public {
        vm.startPrank(admin);

        uint256 maxReward = luckyBuy.minReward() * 2;

        luckyBuy.setMaxReward(maxReward);

        vm.expectRevert(LuckyBuy.InvalidReward.selector);
        luckyBuy.setMinReward(maxReward + 1);
        vm.stopPrank();
    }
    function testSetCommitExpireTime() public {
        uint256 expireTime = 10 days;
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(expireTime);
        vm.stopPrank();
        assertEq(luckyBuy.commitExpireTime(), expireTime);
    }

    function testSetCommitExpireTimeZero() public {
        vm.startPrank(admin);
        vm.expectRevert(LuckyBuy.InvalidCommitExpireTime.selector);
        luckyBuy.setCommitExpireTime(0);
    }

    function testExpireCommit() public {
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(1 days);

        vm.expectRevert(LuckyBuy.InvalidCommitExpireTime.selector);
        luckyBuy.setCommitExpireTime(0);

        vm.stopPrank();

        uint256 initialTreasuryBalance = luckyBuy.treasuryBalance();
        uint256 initialCommitBalance = luckyBuy.commitBalance();
        uint256 initialProtocolBalance = luckyBuy.protocolBalance();

        vm.deal(address(this), amount);

        uint256 initialBalance = address(this).balance;

        luckyBuy.commit{value: amount}(
            address(this),
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(address(this).balance, initialBalance - amount);

        vm.warp(block.timestamp + 2 days);

        luckyBuy.expire(0);

        assertEq(address(this).balance, initialBalance);
        assertEq(luckyBuy.treasuryBalance(), initialTreasuryBalance);
        assertEq(luckyBuy.commitBalance(), initialCommitBalance);
        assertEq(luckyBuy.protocolBalance(), initialProtocolBalance);

        vm.expectRevert(LuckyBuy.CommitIsExpired.selector);
        luckyBuy.expire(0);
    }

    function testExpireCommitCosigner() public {
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(1 days);

        vm.expectRevert(LuckyBuy.InvalidCommitExpireTime.selector);
        luckyBuy.setCommitExpireTime(0);

        vm.stopPrank();

        uint256 initialTreasuryBalance = luckyBuy.treasuryBalance();
        uint256 initialCommitBalance = luckyBuy.commitBalance();
        uint256 initialProtocolBalance = luckyBuy.protocolBalance();

        vm.deal(address(this), amount);

        uint256 initialBalance = address(this).balance;
        address initialReceiver = address(this);

        luckyBuy.commit{value: amount}(
            address(this),
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(address(this).balance, initialBalance - amount);

        vm.warp(block.timestamp + 2 days);

        vm.prank(cosigner);
        luckyBuy.expire(0);

        assertEq(initialReceiver.balance, initialBalance);
        assertEq(luckyBuy.treasuryBalance(), initialTreasuryBalance);
        assertEq(luckyBuy.commitBalance(), initialCommitBalance);
        assertEq(luckyBuy.protocolBalance(), initialProtocolBalance);
    }

    function testExpireCommitNotOwner() public {
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(1 days);
        vm.stopPrank();

        vm.deal(address(this), amount);
        luckyBuy.commit{value: amount}(
            address(this),
            cosigner,
            seed,
            orderHash,
            reward
        );

        vm.expectRevert(LuckyBuy.CommitNotExpired.selector);
        luckyBuy.expire(0);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(LuckyBuy.InvalidCommitOwner.selector);
        vm.prank(user);
        luckyBuy.expire(0);
    }

    function testExpireCommitAlreadyFulfilled() public {
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(1 days);
        vm.stopPrank();

        vm.deal(address(this), amount);
        luckyBuy.commit{value: amount}(
            address(this),
            cosigner,
            seed,
            orderHash,
            reward
        );

        luckyBuy.setIsFulfilled(0, true);
        assertEq(luckyBuy.isFulfilled(0), true);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(LuckyBuy.AlreadyFulfilled.selector);
        luckyBuy.expire(0);
    }

    function testFulfillIsExpired() public {
        vm.startPrank(admin);
        luckyBuy.setCommitExpireTime(1 days);
        vm.stopPrank();

        vm.deal(address(this), 100 ether);
        (bool success, ) = address(luckyBuy).call{value: 10 ether}("");
        assertTrue(success, "Initial funding should succeed");
        luckyBuy.commit{value: amount}(
            address(this),
            cosigner,
            seed,
            orderHash,
            reward
        );

        assertEq(luckyBuy.isFulfilled(0), false);

        vm.warp(block.timestamp + 2 days);

        luckyBuy.expire(0);

        assertEq(luckyBuy.isExpired(0), true);

        vm.expectRevert(LuckyBuy.CommitIsExpired.selector);
        luckyBuy.fulfill(
            0,
            address(this),
            new bytes(0),
            reward,
            address(0),
            0,
            new bytes(0),
            address(0),
            0
        );
    }

    function testOpenEditionTokenSet() public {
        vm.startPrank(admin);
        luckyBuy.setOpenEditionToken(address(0), 0, 0);
        vm.stopPrank();

        vm.expectRevert();
        luckyBuy.setOpenEditionToken(address(1), 1, 1);

        //add this contract as ops
        vm.startPrank(admin);
        luckyBuy.addOpsUser(address(this));
        vm.stopPrank();

        assertEq(luckyBuy.openEditionToken(), address(0));
        assertEq(luckyBuy.openEditionTokenId(), 0);
        assertEq(luckyBuy.openEditionTokenAmount(), 0);

        vm.expectRevert(LuckyBuy.InvalidAmount.selector);
        luckyBuy.setOpenEditionToken(address(1), 1, 0);

        luckyBuy.setOpenEditionToken(address(1), 1, 1);
        assertEq(luckyBuy.openEditionToken(), address(1));
        assertEq(luckyBuy.openEditionTokenId(), 1);
        assertEq(luckyBuy.openEditionTokenAmount(), 1);
    }

    function testFeeReceiver() public {
        assertEq(luckyBuy.feeReceiver(), admin);

        vm.startPrank(admin);
        vm.expectRevert();
        luckyBuy.setFeeReceiver(address(this));
        vm.stopPrank();

        vm.startPrank(feeReceiverManager);
        luckyBuy.setFeeReceiver(address(this));
        vm.stopPrank();

        assertEq(luckyBuy.feeReceiver(), address(this));

        uint256 initialBalance = address(this).balance;

        vm.startPrank(admin);
        (bool success, ) = address(luckyBuy).call{value: 10 ether}("");
        require(success, "Treasury funding failed");

        luckyBuy.withdraw(10 ether);
        vm.stopPrank();

        uint256 finalBalance = address(this).balance;

        assertEq(finalBalance, initialBalance + 10 ether);
    }

    function testFeeSplitSuccess() public {
        address collectionCreator = address(0x1);
        uint256 creatorFeeSplitPercentage = 5000; // 50%

        vm.prank(feeReceiverManager);
        luckyBuy.setFeeReceiver(address(this));

        vm.startPrank(admin);

        luckyBuy.setProtocolFee(1000); // 10%
        luckyBuy.setFlatFee(0);

        (bool success, ) = address(luckyBuy).call{value: 10 ether}("");
        assertTrue(success, "Initial funding should succeed");

        uint256 commitAmount = 0.01 ether;
        uint256 rewardAmount = 1 ether;
        uint256 protocolFee = luckyBuy.calculateProtocolFee(commitAmount);
        // Create order hash for a simple ETH transfer - this stays the same for all plays
        bytes32 orderHash = luckyBuy.hashOrder(
            address(0), // to address(0)
            rewardAmount, // amount 1 ether (reward amount)
            "", // no data
            address(0), // no token
            0 // no token id
        );
        vm.stopPrank();
        vm.deal(user, 100 ether);

        vm.startPrank(user);

        // Create commit
        uint256 commitId = luckyBuy.commit{value: commitAmount + protocolFee}(
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

        // Get the counter for this commit
        uint256 counter = 0;

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

        assertEq(luckyBuy.protocolBalance(), protocolFee);

        uint256 treasuryBalance = luckyBuy.treasuryBalance();
        // Fulfill the commit
        vm.startPrank(user);

        uint256 _collectionCreatorBalance = collectionCreator.balance;
        uint256 _treasuryBalance = luckyBuy.treasuryBalance();
        uint256 _protocolBalance = luckyBuy.protocolBalance();
        uint256 _feeReceiverBalance = address(this).balance;
        luckyBuy.fulfill(
            commitId,
            address(0), // marketplace
            "", // orderData
            rewardAmount, // orderAmount
            address(0), // token
            0, // tokenId
            signature,
            collectionCreator,
            creatorFeeSplitPercentage
        );
        vm.stopPrank();

        uint256 splitAmount = (protocolFee * creatorFeeSplitPercentage) /
            luckyBuy.BASE_POINTS();

        assertEq(
            collectionCreator.balance,
            _collectionCreatorBalance + splitAmount
        );

        assertEq(luckyBuy.protocolBalance(), _protocolBalance - protocolFee);
        assertEq(
            luckyBuy.treasuryBalance(),
            _treasuryBalance + commitAmount
        );
        assertEq(luckyBuy.commitBalance(), 0);
        assertEq(
            address(this).balance,
            _feeReceiverBalance + (protocolFee - splitAmount)
        );
    }

    function testFeeSplitInvalidPercentage() public {
        // Setup
        uint256 protocolFee = 100; // 1%
        uint256 commitAmount = 1 ether;
        uint256 rewardAmount = 10 ether; // Must match reward
        uint256 invalidFeeSplitPercentage = luckyBuy.BASE_POINTS() + 1; // Over 100%
        address feeSplitReceiver = address(0x9);

        vm.startPrank(admin);
        luckyBuy.setProtocolFee(protocolFee);
        vm.stopPrank();

        // Fund contract treasury with exactly the reward amount needed
        vm.deal(address(this), 10 ether);
        (bool success, ) = address(luckyBuy).call{value: 10 ether}("");
        require(success, "Treasury funding failed");

        // Calculate correct orderHash
        bytes32 correctOrderHash = luckyBuy.hashOrder(
            marketplace,
            rewardAmount,
            orderData,
            orderToken,
            orderTokenId
        );

        // Create commit
        vm.startPrank(user);
        vm.deal(user, commitAmount + luckyBuy.calculateProtocolFee(commitAmount));
        uint256 commitId = luckyBuy.commit{value: commitAmount + luckyBuy.calculateProtocolFee(commitAmount)}(
            receiver,
            cosigner,
            seed,
            correctOrderHash,
            rewardAmount
        );
        vm.stopPrank();

        // Fulfill with invalid fee split percentage
        bytes memory signature = signCommit(
            commitId,
            receiver,
            seed,
            0,
            correctOrderHash,
            commitAmount,
            rewardAmount
        );
        vm.expectRevert(LuckyBuy.InvalidFeeSplitPercentage.selector);
        luckyBuy.fulfill(
            commitId,
            marketplace,
            orderData,
            rewardAmount,
            orderToken,
            orderTokenId,
            signature,
            feeSplitReceiver,
            invalidFeeSplitPercentage
        );
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

    function testFeeReceiverManagerRole() public {
        // Test that only fee receiver manager can set fee receiver
        address newFeeReceiver = address(0x9);

        // Try to set fee receiver as admin (should fail)
        vm.startPrank(admin);
        vm.expectRevert();
        luckyBuy.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();

        // Set fee receiver as fee receiver manager (should succeed)
        vm.startPrank(feeReceiverManager);
        luckyBuy.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();

        assertEq(luckyBuy.feeReceiver(), newFeeReceiver);
    }

    function testFeeReceiverManagerTransfer() public {
        address newFeeReceiverManager = address(0xA);

        // Try to transfer role as admin (should fail)
        vm.startPrank(admin);
        vm.expectRevert();
        luckyBuy.transferFeeReceiverManager(newFeeReceiverManager);
        vm.stopPrank();

        // Transfer role as current fee receiver manager (should succeed)
        vm.startPrank(feeReceiverManager);
        luckyBuy.transferFeeReceiverManager(newFeeReceiverManager);
        vm.stopPrank();

        // Verify new fee receiver manager can set fee receiver
        address newFeeReceiver = address(0xB);
        vm.startPrank(newFeeReceiverManager);
        luckyBuy.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();

        assertEq(luckyBuy.feeReceiver(), newFeeReceiver);
    }

    function testInvalidFeeReceiverManager() public {
        // Try to set fee receiver manager to zero address
        vm.startPrank(feeReceiverManager);
        vm.expectRevert(LuckyBuy.InvalidFeeReceiverManager.selector);
        luckyBuy.transferFeeReceiverManager(address(0));
        vm.stopPrank();
    }

    function testRescueERC20() public {
        // Deploy mock ERC20
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        // Test single token rescue
        vm.startPrank(admin);
        luckyBuy.rescueERC20(address(token), bob, 100 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(address(luckyBuy)), 900 ether);
    }

    function testRescueERC20Batch() public {
        // Deploy mock ERC20s
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        token1.mint(address(luckyBuy), 1000 ether);
        token2.mint(address(luckyBuy), 500 ether);

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);
        to[0] = bob;
        to[1] = charlie;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.startPrank(admin);
        luckyBuy.rescueERC20Batch(tokens, to, amounts);
        vm.stopPrank();

        assertEq(token1.balanceOf(bob), 100 ether);
        assertEq(token2.balanceOf(charlie), 200 ether);
        assertEq(token1.balanceOf(address(luckyBuy)), 900 ether);
        assertEq(token2.balanceOf(address(luckyBuy)), 300 ether);
    }

    function testRescueERC721() public {
        // Deploy mock ERC721
        MockERC721 token = new MockERC721();
        token.mint(address(luckyBuy), 1);

        // Test single token rescue
        vm.startPrank(admin);
        luckyBuy.rescueERC721(address(token), bob, 1);
        vm.stopPrank();

        assertEq(token.ownerOf(1), bob);
    }

    function testRescueERC721Batch() public {
        // Deploy mock ERC721s
        MockERC721 token1 = new MockERC721();
        MockERC721 token2 = new MockERC721();
        token1.mint(address(luckyBuy), 1);
        token2.mint(address(luckyBuy), 2);

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);
        to[0] = bob;
        to[1] = charlie;
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.startPrank(admin);
        luckyBuy.rescueERC721Batch(tokens, to, tokenIds);
        vm.stopPrank();

        assertEq(token1.ownerOf(1), bob);
        assertEq(token2.ownerOf(2), charlie);
    }

    function testRescueERC1155() public {
        // Deploy mock ERC1155
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        // Test single token rescue
        vm.startPrank(admin);
        luckyBuy.rescueERC1155(address(token), bob, 1, 50);
        vm.stopPrank();

        assertEq(token.balanceOf(bob, 1), 50);
        assertEq(token.balanceOf(address(luckyBuy), 1), 50);
    }

    function testRescueERC1155Batch() public {
        // Deploy mock ERC1155
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);
        token.mint(address(luckyBuy), 2, 200);

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token);
        tokens[1] = address(token);
        tos[0] = bob;
        tos[1] = bob;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 50;
        amounts[1] = 100;

        vm.startPrank(admin);
        luckyBuy.rescueERC1155Batch(tokens, tos, tokenIds, amounts);
        vm.stopPrank();

        assertEq(token.balanceOf(bob, 1), 50);
        assertEq(token.balanceOf(bob, 2), 100);
        assertEq(token.balanceOf(address(luckyBuy), 1), 50);
        assertEq(token.balanceOf(address(luckyBuy), 2), 100);
    }

    function testRescueERC20NonAdmin() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC20(address(token), bob, 100 ether);
        vm.stopPrank();
    }

    function testRescueERC721NonAdmin() public {
        MockERC721 token = new MockERC721();
        token.mint(address(luckyBuy), 1);

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC721(address(token), bob, 1);
        vm.stopPrank();
    }

    function testRescueERC1155NonAdmin() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC1155(address(token), bob, 1, 50);
        vm.stopPrank();
    }

    function testRescueERC20BatchNonAdmin() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(token);
        to[0] = bob;
        amounts[0] = 100 ether;

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC20Batch(tokens, to, amounts);
        vm.stopPrank();
    }

    function testRescueERC721BatchNonAdmin() public {
        MockERC721 token = new MockERC721();
        token.mint(address(luckyBuy), 1);

        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = address(token);
        to[0] = bob;
        tokenIds[0] = 1;

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC721Batch(tokens, to, tokenIds);
        vm.stopPrank();
    }

    function testRescueERC1155BatchNonAdmin() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(token);
        tos[0] = bob;
        tokenIds[0] = 1;
        amounts[0] = 50;

        vm.startPrank(user);
        vm.expectRevert();
        luckyBuy.rescueERC1155Batch(tokens, tos, tokenIds, amounts);
        vm.stopPrank();
    }

    function testRescueERC20ZeroAddress() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInvalidAddress.selector);
        luckyBuy.rescueERC20(address(0), bob, 100 ether);
        vm.stopPrank();
    }

    function testRescueERC721ZeroAddress() public {
        MockERC721 token = new MockERC721();
        token.mint(address(luckyBuy), 1);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInvalidAddress.selector);
        luckyBuy.rescueERC721(address(0), bob, 1);
        vm.stopPrank();
    }

    function testRescueERC1155ZeroAddress() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInvalidAddress.selector);
        luckyBuy.rescueERC1155(address(0), bob, 1, 50);
        vm.stopPrank();
    }

    function testRescueERC20ZeroAmount() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(
            TokenRescuer.TokenRescuerAmountMustBeGreaterThanZero.selector
        );
        luckyBuy.rescueERC20(address(token), bob, 0);
        vm.stopPrank();
    }

    function testRescueERC1155ZeroAmount() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        vm.startPrank(admin);
        vm.expectRevert(
            TokenRescuer.TokenRescuerAmountMustBeGreaterThanZero.selector
        );
        luckyBuy.rescueERC1155(address(token), bob, 1, 0);
        vm.stopPrank();
    }

    function testRescueERC20InsufficientBalance() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInsufficientBalance.selector);
        luckyBuy.rescueERC20(address(token), bob, 2000 ether);
        vm.stopPrank();
    }

    function testRescueERC1155InsufficientBalance() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInsufficientBalance.selector);
        luckyBuy.rescueERC1155(address(token), bob, 1, 200);
        vm.stopPrank();
    }

    function testRescueERC20BatchArrayLengthMismatch() public {
        MockERC20 token = new MockERC20();
        token.mint(address(luckyBuy), 1000 ether);

        address[] memory tokens = new address[](2);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token);
        tokens[1] = address(token);
        to[0] = bob;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerArrayLengthMismatch.selector);
        luckyBuy.rescueERC20Batch(tokens, to, amounts);
        vm.stopPrank();
    }

    function testRescueERC721BatchArrayLengthMismatch() public {
        MockERC721 token = new MockERC721();
        token.mint(address(luckyBuy), 1);

        address[] memory tokens = new address[](2);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](2);

        tokens[0] = address(token);
        tokens[1] = address(token);
        to[0] = bob;
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerArrayLengthMismatch.selector);
        luckyBuy.rescueERC721Batch(tokens, to, tokenIds);
        vm.stopPrank();
    }

    function testRescueERC1155BatchArrayLengthMismatch() public {
        MockERC1155 token = new MockERC1155();
        token.mint(address(luckyBuy), 1, 100);

        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(token);
        tokens[1] = address(token);
        tos[0] = bob;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 50;

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerArrayLengthMismatch.selector);
        luckyBuy.rescueERC1155Batch(tokens, tos, tokenIds, amounts);
        vm.stopPrank();
    }

    function testFulfillWithTopOff() public {
        bytes32 correctOrderHash = luckyBuy.hashOrder(
            marketplace,
            reward,
            orderData,
            orderToken,
            orderTokenId
        );
        
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 commitId = luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            correctOrderHash,
            reward
        );
        vm.stopPrank();

        // Empty the treasury so there's not enough to cover the reward
        vm.startPrank(admin);
        uint256 treasuryBalance = luckyBuy.treasuryBalance();
        if (treasuryBalance > 0) {
            luckyBuy.withdraw(treasuryBalance);
        }
        vm.stopPrank();

        bytes memory signature = signCommit(
            commitId,
            receiver,
            seed,
            0,
            correctOrderHash,
            amount,
            reward
        );

        uint256 topOffAmount = reward - amount;
        vm.deal(user, topOffAmount);
        vm.startPrank(user);
        
        luckyBuy.fulfill{value: topOffAmount}(
            commitId,
            marketplace,
            orderData,
            reward,
            orderToken,
            orderTokenId,
            signature,
            address(0),
            0
        );
        
        vm.stopPrank();

        assertTrue(luckyBuy.isFulfilled(commitId));
    }

    receive() external payable {}

    function testBulkCommitAndBulkExpire() public {
        // Create bulk commit requests
        LuckyBuy.CommitRequest[] memory commitRequests = new LuckyBuy.CommitRequest[](3);
        for (uint256 i = 0; i < 3; i++) {
            commitRequests[i] = LuckyBuy.CommitRequest({
                receiver: receiver,
                cosigner: cosigner,
                seed: seed + i,
                orderHash: orderHash,
                reward: reward,
                amount: 1 ether
            });
        }

        // Execute bulk commit
        vm.startPrank(user);
        vm.deal(user, 3 ether);
        uint256[] memory commitIds = luckyBuy.bulkCommit{value: 3 ether}(commitRequests);
        vm.stopPrank();

        // Verify all commits were created
        assertEq(commitIds.length, 3);
        assertEq(luckyBuy.luckyBuyCount(receiver), 3);

        // Advance time to make commits expirable
        vm.warp(block.timestamp + 25 hours);

        // Get initial receiver balance
        uint256 initialReceiverBalance = receiver.balance;

        // Execute bulk expire
        vm.prank(receiver);
        luckyBuy.bulkExpire(commitIds);

        // Verify all commits are expired
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(luckyBuy.isExpired(commitIds[i]));
        }

        // Verify receiver got refunds (commit amount + fees)
        uint256 expectedRefund = 3 ether; // 3 ether total commits (no fees in this test)
        assertEq(receiver.balance, initialReceiverBalance + expectedRefund);
    }

    function testBulkCommitAndBulkFulfill() public {
        // Set up bulk commit fee
        vm.startPrank(admin);
        luckyBuy.setBulkCommitFee(250); // 2.5%
        luckyBuy.setProtocolFee(500); // 5%
        vm.stopPrank();

        // Create the correct order hash for fulfillment
        bytes32 correctOrderHash = luckyBuy.hashOrder(
            address(0), // marketplace
            reward, // orderAmount
            "", // orderData
            address(0), // token
            0 // tokenId
        );

        // Create bulk commit requests
        LuckyBuy.CommitRequest[] memory commitRequests = new LuckyBuy.CommitRequest[](3);
        for (uint256 i = 0; i < 3; i++) {
            commitRequests[i] = LuckyBuy.CommitRequest({
                receiver: receiver,
                cosigner: cosigner,
                seed: seed + i,
                orderHash: correctOrderHash,
                reward: reward,
                amount: 1 ether
            });
        }

        // Execute bulk commit
        vm.startPrank(user);
        vm.deal(user, 3 ether);
        uint256[] memory commitIds = luckyBuy.bulkCommit{value: 3 ether}(commitRequests);
        vm.stopPrank();

        // Verify all commits were created
        assertEq(commitIds.length, 3);
        assertEq(luckyBuy.luckyBuyCount(receiver), 3);

        // Fund contract for fulfillments - need to deposit to treasury
        vm.deal(address(this), 50 ether);
        (bool success, ) = address(luckyBuy).call{value: 50 ether}("");
        assertTrue(success, "Initial funding should succeed");

        // Create bulk fulfill requests
        LuckyBuy.FulfillRequest[] memory fulfillRequests = new LuckyBuy.FulfillRequest[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            (, , , , , , uint256 commitAmount, ) = luckyBuy.luckyBuys(commitIds[i]);
            
            bytes32 digest = luckyBuy.hash(ISignatureVerifier.CommitData({
                id: commitIds[i],
                receiver: receiver,
                cosigner: cosigner,
                seed: seed + i,
                counter: i,
                orderHash: correctOrderHash,
                amount: commitAmount,
                reward: reward
            }));

            fulfillRequests[i] = LuckyBuy.FulfillRequest({
                commitDigest: digest,
                marketplace: address(0),
                orderData: "",
                orderAmount: reward,
                token: address(0),
                tokenId: 0,
                signature: signCommit(commitIds[i], receiver, seed + i, i, correctOrderHash, commitAmount, reward),
                feeSplitReceiver: address(0),
                feeSplitPercentage: 0
            });
        }

        // Execute bulk fulfill
        luckyBuy.bulkFulfill(fulfillRequests);

        // Verify all commits are fulfilled
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(luckyBuy.isFulfilled(commitIds[i]));
        }
    }
}
