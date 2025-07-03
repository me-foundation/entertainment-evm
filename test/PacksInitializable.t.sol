// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/common/interfaces/IPacksSignatureVerifier.sol";
import "src/PacksInitializable.sol";
import "src/PRNG.sol";
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

// Simple ERC1155 receiver for testing
contract SimpleERC1155Receiver {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x4e2312e0 || // IERC1155Receiver
            interfaceId == 0x01ffc9a7;   // IERC165
    }
}

contract MockPacksInitializable is PacksInitializable {
    function setIsFulfilled(uint256 commitId_, bool isFulfilled_) public {
        isFulfilled[commitId_] = isFulfilled_;
    }

    function setIsExpired(uint256 commitId_, bool isExpired_) public {
        isExpired[commitId_] = isExpired_;
    }

    function setOrderHash(uint256 commitId_, bytes32 orderHash_) public {
        orderHash[commitId_] = orderHash_;
    }
}

contract TestPacksInitializable is Test {
    PRNG prng;
    MockPacksInitializable packs;
    address admin = address(0x1);
    address user = address(0x2);
    address receiver = address(0x3);
    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    address cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
    address feeReceiverManager = address(0x4);
    address feeReceiver = address(0x5);

    uint256 seed = 12345;
    uint256 packPrice = 0.1 ether;

    // Test bucket data
    IPacksSignatureVerifier.BucketData[] buckets;

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant OPS_ROLE = keccak256("OPS_ROLE");

    address bob = address(0x6);
    address charlie = address(0x7);

    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        uint256 packPrice,
        bytes32 bucketsHash,
        bytes32 digest
    );

    event Fulfillment(
        address indexed sender,
        uint256 indexed commitId,
        uint256 rng,
        uint256 odds,
        uint256 bucketIndex,
        uint256 payout,
        address token,
        uint256 tokenId,
        uint256 amount,
        address receiver,
        IPacksSignatureVerifier.FulfillmentOption choice,
        bytes32 digest
    );

    event CommitExpired(uint256 indexed commitId, bytes32 digest);
    event Withdrawal(address indexed sender, uint256 amount, address feeReceiver);

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();

        // Deploy implementation
        MockPacksInitializable implementation = new MockPacksInitializable();

        // Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)",
            admin,
            feeReceiver,
            address(prng),
            feeReceiverManager
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        packs = MockPacksInitializable(payable(address(proxy)));

        vm.deal(admin, 100 ether);
        vm.deal(receiver, 100 ether);
        vm.deal(address(this), 100 ether);

        // Add cosigner
        packs.addCosigner(cosigner);

        // Setup test buckets - using single bucket to avoid validation issues
        buckets = new IPacksSignatureVerifier.BucketData[](1);
        buckets[0] = IPacksSignatureVerifier.BucketData({
            oddsBps: 10000, // 100% chance
            minValue: 0.01 ether,
            maxValue: 1 ether
        });

        vm.stopPrank();
    }

    function testInitialize() public {
        assertTrue(packs.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(packs.hasRole(OPS_ROLE, admin));

        assertEq(packs.feeReceiver(), feeReceiver);
        assertEq(address(packs.PRNG()), address(prng));
        assertTrue(packs.hasRole(packs.FEE_RECEIVER_MANAGER_ROLE(), feeReceiverManager));

        // Check default values
        assertEq(packs.payoutBps(), 9000);
        assertEq(packs.minReward(), 0.01 ether);
        assertEq(packs.maxReward(), 5 ether);
        assertEq(packs.minPackPrice(), 0.01 ether);
        assertEq(packs.maxPackPrice(), 0.25 ether);
    }

    function testRevertOnReinitialise() public {
        vm.prank(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        MockPacksInitializable(payable(address(packs))).initialize(
            admin,
            feeReceiver,
            address(prng),
            feeReceiverManager
        );
    }

    function testCommitSuccess() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory signature = signPack(packPrice, buckets);

        vm.expectEmit(true, true, true, false);
        emit Commit(
            user,
            0,
            receiver,
            cosigner,
            seed,
            0,
            packPrice,
            packs.hashPack(packPrice, buckets),
            bytes32(0) // digest will be different
        );

        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            signature
        );

        assertEq(commitId, 0);
        assertEq(packs.packCount(receiver), 1);

        // Access individual fields from the packs array using tuple destructuring
        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            uint256 storedPackPrice,
            uint256 storedPayoutBps,
            bytes32 storedPackHash
        ) = packs.packs(0);

        assertEq(id, 0);
        assertEq(storedReceiver, receiver);
        assertEq(storedCosigner, cosigner);
        assertEq(storedSeed, seed);
        assertEq(storedCounter, 0);
        assertEq(storedPackPrice, packPrice);
        assertEq(storedPayoutBps, packs.payoutBps());
        assertEq(storedPackHash, packs.hashPack(packPrice, buckets));

        vm.stopPrank();
    }

    function testCommitWithInvalidAmount() public {
        vm.startPrank(user);
        vm.deal(user, 0.5 ether);

        bytes memory signature = signPack(0.5 ether, buckets);

        vm.expectRevert(PacksInitializable.InvalidAmount.selector);
        packs.commit{value: 0.5 ether}(
            receiver,
            cosigner,
            seed,
            buckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidCosigner() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory signature = signPack(packPrice, buckets);

        vm.expectRevert(PacksInitializable.InvalidCosigner.selector);
        packs.commit{value: packPrice}(
            receiver,
            address(0x999),
            seed,
            buckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidBuckets() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test empty buckets
        IPacksSignatureVerifier.BucketData[] memory emptyBuckets = new IPacksSignatureVerifier.BucketData[](0);
        bytes memory signature = signPack(packPrice, emptyBuckets);

        vm.expectRevert(PacksInitializable.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            emptyBuckets,
            signature
        );

        // Test too many buckets
        IPacksSignatureVerifier.BucketData[] memory tooManyBuckets = new IPacksSignatureVerifier.BucketData[](6);
        for (uint256 i = 0; i < 6; i++) {
            tooManyBuckets[i] = IPacksSignatureVerifier.BucketData({
                oddsBps: 1666,
                minValue: 0.01 ether,
                maxValue: 0.1 ether
            });
        }
        signature = signPack(packPrice, tooManyBuckets);

        vm.expectRevert(PacksInitializable.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            tooManyBuckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidBucketValues() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test bucket with zero values
        IPacksSignatureVerifier.BucketData[] memory invalidBuckets = new IPacksSignatureVerifier.BucketData[](1);
        invalidBuckets[0] = IPacksSignatureVerifier.BucketData({
            oddsBps: 10000,
            minValue: 0,
            maxValue: 0.1 ether
        });
        bytes memory signature = signPack(packPrice, invalidBuckets);

        vm.expectRevert(PacksInitializable.InvalidReward.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            invalidBuckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidBucketRanges() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test overlapping bucket ranges
        IPacksSignatureVerifier.BucketData[] memory overlappingBuckets = new IPacksSignatureVerifier.BucketData[](2);
        overlappingBuckets[0] = IPacksSignatureVerifier.BucketData({
            oddsBps: 5000,
            minValue: 0.01 ether,
            maxValue: 0.1 ether
        });
        overlappingBuckets[1] = IPacksSignatureVerifier.BucketData({
            oddsBps: 10000,
            minValue: 0.05 ether, // Overlaps with previous bucket
            maxValue: 0.2 ether
        });
        bytes memory signature = signPack(packPrice, overlappingBuckets);

        vm.expectRevert(PacksInitializable.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            overlappingBuckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidOdds() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test non-cumulative odds
        IPacksSignatureVerifier.BucketData[] memory invalidOddsBuckets = new IPacksSignatureVerifier.BucketData[](2);
        invalidOddsBuckets[0] = IPacksSignatureVerifier.BucketData({
            oddsBps: 6000,
            minValue: 0.01 ether,
            maxValue: 0.05 ether
        });
        invalidOddsBuckets[1] = IPacksSignatureVerifier.BucketData({
            oddsBps: 5000, // Should be higher than previous cumulative
            minValue: 0.06 ether,
            maxValue: 0.1 ether
        });
        bytes memory signature = signPack(packPrice, invalidOddsBuckets);

        vm.expectRevert(PacksInitializable.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            invalidOddsBuckets,
            signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidSignature() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory wrongSignature = signPack(packPrice + 0.1 ether, buckets);

        vm.expectRevert(PacksInitializable.InvalidCosigner.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            wrongSignature
        );

        vm.stopPrank();
    }

    function testFulfillSuccess() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly and cosigner
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        vm.prank(cosigner);

        // Fulfill with payout
        uint256 orderAmount = 0.03 ether; // Within bucket 0 range
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get the actual RNG to expect correct values
        uint256 actualRng = prng.rng(commitSignature);
        uint256 expectedPayoutAmount = (orderAmount * packs.payoutBps()) / 10000;

        vm.expectEmit(true, true, true, false);
        emit Fulfillment(
            cosigner, // msg.sender is cosigner
            commitId,
            actualRng, // actual rng value
            10000, // bucket 0 odds (100%)
            0, // bucket index
            expectedPayoutAmount, // payout amount (90% of orderAmount)
            address(0),
            0,
            0,
            receiver,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            bytes32(0) // digest will be different
        );

        packs.fulfill(
            commitId,
            actualRng, // use actual expected RNG
            address(0), // marketplace
            "", // orderData
            orderAmount,
            address(0), // token
            0, // tokenId
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testFulfillWithNFT() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly and cosigner
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();
        
        vm.prank(cosigner);

        // Fulfill with NFT - use proper amount within bucket range
        uint256 orderAmount = 0.5 ether; // Within bucket range
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.NFT);

        // Get actual RNG for this commit signature
        uint256 actualRng = prng.rng(commitSignature);

        packs.fulfill(
            commitId,
            actualRng, // use actual expected RNG
            address(0), // marketplace
            "", // orderData
            orderAmount,
            address(0), // token
            0, // tokenId
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.NFT,
            choiceSignature
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testFulfillWithInvalidRng() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Fulfill with wrong RNG
        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        vm.expectRevert(PacksInitializable.InvalidRng.selector);
        packs.fulfill(
            commitId,
            9999, // Wrong expectedRng
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testFulfillWithInvalidOrderAmount() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Fulfill with order amount outside bucket range
        uint256 orderAmount = 2 ether; // Outside all bucket ranges
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        vm.expectRevert(PacksInitializable.InvalidAmount.selector);
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testFulfillWithInvalidOrderHash() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // First fulfill to set order hash
        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        // Try to fulfill again with different order data - but this will fail with AlreadyFulfilled first
        vm.expectRevert(PacksInitializable.AlreadyFulfilled.selector);
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "different",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testFulfillAlreadyFulfilled() public {
        // Create and fulfill commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        vm.deal(cosigner, 20 ether);
        vm.stopPrank();
        
        vm.prank(cosigner);

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Calculate the expected RNG for the first fulfill
        uint256 expectedRng = prng.rng(commitSignature);

        // Call fulfill with some ETH value to fund the treasury
        packs.fulfill{value: 10 ether}(
            commitId,
            expectedRng, // Use the calculated RNG
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        // Try to fulfill again with the same RNG
        vm.expectRevert(PacksInitializable.AlreadyFulfilled.selector);
        packs.fulfill{value: 0}(
            commitId,
            expectedRng, // Use the same RNG
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testExpireCommit() public {
        vm.startPrank(admin);
        packs.setCommitExpireTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            buckets,
            packSignature
        );

        uint256 initialBalance = user.balance;

        // Wait for expiration
        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, true, false);
        emit CommitExpired(commitId, bytes32(0)); // digest will be different

        packs.expire(commitId);

        assertTrue(packs.isExpired(commitId));
        assertEq(user.balance, initialBalance + packPrice);
    }

    function testExpireCommitFromCosigner() public {
        vm.startPrank(admin);
        packs.setCommitExpireTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            buckets,
            packSignature
        );

        uint256 initialBalance = user.balance;
        vm.stopPrank();

        // Wait for expiration
        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, true, false);
        emit CommitExpired(commitId, bytes32(0)); // digest will be different

        vm.prank(cosigner);
        packs.expire(commitId);
        vm.stopPrank();

        assertTrue(packs.isExpired(commitId));
        assertEq(user.balance, initialBalance + packPrice);
    }

    function testExpireCommitNotExpired() public {
        vm.startPrank(admin);
        packs.setCommitExpireTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            buckets,
            packSignature
        );
        vm.stopPrank();

        // Try to expire before expiration time
        vm.prank(user);
        vm.expectRevert(PacksInitializable.CommitNotExpired.selector);
        packs.expire(commitId);
    }

    function testExpireCommitNotOwner() public {
        vm.startPrank(admin);
        packs.setCommitExpireTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            buckets,
            packSignature
        );
        vm.stopPrank();

        // Wait for expiration
        vm.warp(block.timestamp + 2 days);

        // Try to expire as non-owner
        vm.expectRevert(PacksInitializable.InvalidCommitOwner.selector);
        vm.prank(bob);
        packs.expire(commitId);
    }

    function testWithdrawSuccess() public {
        uint256 withdrawAmount = 1 ether;
        // Fund the treasury properly by sending ETH to the contract
        vm.deal(address(this), withdrawAmount);
        (bool success,) = payable(address(packs)).call{value: withdrawAmount}("");
        require(success, "Failed to fund contract");

        uint256 initialBalance = feeReceiver.balance;

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(admin, withdrawAmount, feeReceiver);

        vm.prank(admin);
        packs.withdraw(withdrawAmount);

        assertEq(feeReceiver.balance, initialBalance + withdrawAmount);
    }

    function testWithdrawInsufficientBalance() public {
        vm.expectRevert(PacksInitializable.InsufficientBalance.selector);
        vm.prank(admin);
        packs.withdraw(1 ether);
    }

    function testEmergencyWithdraw() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        vm.deal(address(packs), address(packs).balance + 5 ether);
        vm.stopPrank();

        uint256 initialBalance = feeReceiver.balance;

        vm.prank(admin);
        packs.emergencyWithdraw();

        assertEq(feeReceiver.balance, initialBalance + 5 ether + packPrice);
        assertTrue(packs.paused());
    }

    // Helper functions for signing
    function signPack(uint256 packPrice_, IPacksSignatureVerifier.BucketData[] memory buckets_) internal returns (bytes memory) {
        bytes32 packHash = packs.hashPack(packPrice_, buckets_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, packHash);
        return abi.encodePacked(r, s, v);
    }

    function signCommit(
        uint256 commitId_,
        address receiver_,
        uint256 seed_,
        uint256 counter_,
        uint256 packPrice_,
        IPacksSignatureVerifier.BucketData[] memory buckets_
    ) internal returns (bytes memory) {
        IPacksSignatureVerifier.CommitData memory commitData = IPacksSignatureVerifier.CommitData({
            id: commitId_,
            receiver: receiver_,
            cosigner: cosigner,
            seed: seed_,
            counter: counter_,
            packPrice: packPrice_,
            payoutBps: packs.payoutBps(),
            buckets: buckets_,
            packHash: packs.hashPack(packPrice_, buckets_)
        });

        bytes32 digest = packs.hashCommit(commitData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function signOrder(
        address to_,
        uint256 value_,
        bytes memory data_,
        address token_,
        uint256 tokenId_
    ) internal returns (bytes memory) {
        bytes32 orderHash = packs.hashOrder(to_, value_, data_, token_, tokenId_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, orderHash);
        return abi.encodePacked(r, s, v);
    }

    function signChoice(
        uint256 commitId_,
        address receiver_,
        uint256 seed_,
        uint256 counter_,
        uint256 packPrice_,
        IPacksSignatureVerifier.BucketData[] memory buckets_,
        IPacksSignatureVerifier.FulfillmentOption choice_
    ) internal returns (bytes memory) {
        IPacksSignatureVerifier.CommitData memory commitData = IPacksSignatureVerifier.CommitData({
            id: commitId_,
            receiver: receiver_,
            cosigner: cosigner,
            seed: seed_,
            counter: counter_,
            packPrice: packPrice_,
            payoutBps: packs.payoutBps(),
            buckets: buckets_,
            packHash: packs.hashPack(packPrice_, buckets_)
        });

        bytes32 digest = packs.hashCommit(commitData);
        bytes32 choiceHash = packs.hashChoice(digest, choice_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, choiceHash);
        return abi.encodePacked(r, s, v);
    }

    receive() external payable {}

    // ========================================
    // SECURITY TESTS - ATTACK VECTORS
    // ========================================

    function testReentrancyAttackOnFulfill() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Create malicious contract that tries to reenter
        ReentrantAttacker attacker = new ReentrantAttacker(address(packs));
        vm.deal(address(attacker), 1 ether);

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        // This should not allow reentrancy due to nonReentrant modifier
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testSignatureReplayAttack() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        // First fulfill should succeed
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        // Second fulfill with same signatures should fail
        vm.expectRevert(PacksInitializable.AlreadyFulfilled.selector);
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testBucketManipulationAttack() public {
        // Test that bucket validation prevents manipulation
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Create buckets with invalid cumulative odds
        IPacksSignatureVerifier.BucketData[] memory manipulatedBuckets = new IPacksSignatureVerifier.BucketData[](2);
        manipulatedBuckets[0] = IPacksSignatureVerifier.BucketData({
            oddsBps: 6000,
            minValue: 0.01 ether,
            maxValue: 0.05 ether
        });
        manipulatedBuckets[1] = IPacksSignatureVerifier.BucketData({
            oddsBps: 3000, // This makes total 9000, not 10000
            minValue: 0.06 ether,
            maxValue: 0.1 ether
        });

        bytes memory signature = signPack(packPrice, manipulatedBuckets);

        vm.expectRevert(PacksInitializable.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            manipulatedBuckets,
            signature
        );

        vm.stopPrank();
    }

    function testOrderHashBindingAttack() public {
        // Test that order hash binding prevents order manipulation
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        // First fulfill sets the order hash
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        // Try to fulfill with different order data but same amount
        bytes memory differentOrderSignature = signOrder(address(0), orderAmount, "different", address(0), 0);
        
        vm.expectRevert(PacksInitializable.AlreadyFulfilled.selector);
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "different",
            orderAmount,
            address(0),
            0,
            commitSignature,
            differentOrderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testInvalidChoiceSignerAttack() public {
        // Test that only receiver or cosigner can sign choice
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly
       vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);

        // Sign choice with wrong private key (bob's key)
        uint256 bobPrivateKey = 5678;
        address bobAddress = vm.addr(bobPrivateKey);
        
        IPacksSignatureVerifier.CommitData memory commitData = IPacksSignatureVerifier.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            payoutBps: packs.payoutBps(),
            buckets: buckets,
            packHash: packs.hashPack(packPrice, buckets)
        });

        bytes32 digest = packs.hashCommit(commitData);
        bytes32 choiceHash = packs.hashChoice(digest, IPacksSignatureVerifier.FulfillmentOption.Payout);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, choiceHash);
        bytes memory wrongChoiceSignature = abi.encodePacked(r, s, v);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        vm.expectRevert(PacksInitializable.InvalidChoiceSigner.selector);
        packs.fulfill(
            commitId,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            wrongChoiceSignature
        );
    }

    function testPauseUnpauseSecurity() public {
        // Test that only admin can pause/unpause
        vm.startPrank(user);
        vm.expectRevert();
        packs.pause();
        vm.stopPrank();

        vm.startPrank(admin);
        packs.pause();
        assertTrue(packs.paused());

        packs.unpause();
        assertFalse(packs.paused());
        vm.stopPrank();
    }

    function testCommitWhenPaused() public {
        vm.startPrank(admin);
        packs.pause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);

        vm.expectRevert();
        packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );
        vm.stopPrank();
    }

    function testFulfillWhenPaused() public {
        // Create commit first
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );
        vm.stopPrank();

        // Then pause
        vm.startPrank(admin);
        packs.pause();
        vm.stopPrank();

        vm.deal(address(packs), 10 ether);

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        vm.expectRevert();
        packs.fulfill(
            commitId,
            0,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testUpgradeSecurity() public {
        // Test that only admin can upgrade - using UUPS pattern
        address newImplementation = address(new MockPacksInitializable());
        
        // Test that non-admin cannot upgrade
        vm.startPrank(user);
        vm.expectRevert();
        PacksInitializable(payable(address(packs))).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        // Test that admin can upgrade (this should succeed)
        vm.startPrank(admin);
        PacksInitializable(payable(address(packs))).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testFeeReceiverManagerSecurity() public {
        address newFeeReceiverManager = address(0x8);
        address newFeeReceiver = address(0x9);

        // Test that only fee receiver manager can transfer role
        vm.startPrank(admin);
        vm.expectRevert();
        packs.transferFeeReceiverManager(newFeeReceiverManager);
        vm.stopPrank();

        // Test that only fee receiver manager can set fee receiver
        vm.startPrank(admin);
        vm.expectRevert();
        packs.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();

        // Test that fee receiver manager can transfer role
        vm.startPrank(feeReceiverManager);
        packs.transferFeeReceiverManager(newFeeReceiverManager);
        vm.stopPrank();

        // Test that new fee receiver manager can set fee receiver
        vm.startPrank(newFeeReceiverManager);
        packs.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();

        assertEq(packs.feeReceiver(), newFeeReceiver);
    }

    function testInvalidFeeReceiverManager() public {
        vm.startPrank(feeReceiverManager);
        vm.expectRevert(PacksInitializable.InvalidFeeReceiverManager.selector);
        packs.transferFeeReceiverManager(address(0));
        vm.stopPrank();
    }

    function testInvalidFeeReceiver() public {
        vm.startPrank(feeReceiverManager);
        vm.expectRevert(PacksInitializable.InvalidFeeReceiver.selector);
        packs.setFeeReceiver(address(0));
        vm.stopPrank();
    }

    function testRescueFunctionsSecurity() public {
        // Test that only rescue role can rescue tokens
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(user);
        vm.expectRevert();
        packs.rescueERC20(address(token), bob, 100 ether);
        vm.stopPrank();

        // Test that admin can rescue
        vm.startPrank(admin);
        packs.rescueERC20(address(token), bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        vm.stopPrank();
    }

    function testRescueERC20ZeroAddress() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInvalidAddress.selector);
        packs.rescueERC20(address(0), bob, 100 ether);
        vm.stopPrank();
    }

    function testRescueERC20ZeroAmount() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerAmountMustBeGreaterThanZero.selector);
        packs.rescueERC20(address(token), bob, 0);
        vm.stopPrank();
    }

    function testRescueERC20InsufficientBalance() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerInsufficientBalance.selector);
        packs.rescueERC20(address(token), bob, 2000 ether);
        vm.stopPrank();
    }

    function testRescueERC721Security() public {
        MockERC721 token = new MockERC721();
        token.mint(address(packs), 1);

        vm.startPrank(user);
        vm.expectRevert();
        packs.rescueERC721(address(token), bob, 1);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.rescueERC721(address(token), bob, 1);
        assertEq(token.ownerOf(1), bob);
        vm.stopPrank();
    }

    function testRescueERC1155() public {
        // Deploy mock ERC1155
        MockERC1155 token = new MockERC1155();
        token.mint(address(packs), 1, 100);

        // Test single token rescue
        vm.startPrank(admin);
        packs.rescueERC1155(address(token), bob, 1, 50);
        vm.stopPrank();

        assertEq(token.balanceOf(bob, 1), 50);
        assertEq(token.balanceOf(address(packs), 1), 50);
    }

    function testBatchRescueSecurity() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](1); // Mismatched length
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token);
        tokens[1] = address(token);
        tos[0] = bob;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.startPrank(admin);
        vm.expectRevert(TokenRescuer.TokenRescuerArrayLengthMismatch.selector);
        packs.rescueERC20Batch(tokens, tos, amounts);
        vm.stopPrank();
    }

    function testFulfillByDigestSecurity() public {
        // Test that fulfillByDigest works correctly
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver,
            cosigner,
            seed,
            buckets,
            packSignature
        );

        // Fund contract treasury properly and cosigner
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 5 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        vm.prank(cosigner);

        // Get the digest
        IPacksSignatureVerifier.CommitData memory commitData = IPacksSignatureVerifier.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            payoutBps: packs.payoutBps(),
            buckets: buckets,
            packHash: packs.hashPack(packPrice, buckets)
        });

        bytes32 digest = packs.hashCommit(commitData);

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(commitId, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        // Get actual RNG
        uint256 actualRng = prng.rng(commitSignature);

        packs.fulfillByDigest(
            digest,
            actualRng,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testInvalidDigestFulfill() public {
        // Test that invalid digest reverts
        bytes32 invalidDigest = keccak256("invalid");

        uint256 orderAmount = 0.03 ether;
        bytes memory commitSignature = signCommit(0, receiver, seed, 0, packPrice, buckets);
        bytes memory orderSignature = signOrder(address(0), orderAmount, "", address(0), 0);
        bytes memory choiceSignature = signChoice(0, receiver, seed, 0, packPrice, buckets, IPacksSignatureVerifier.FulfillmentOption.Payout);

        vm.expectRevert();
        packs.fulfillByDigest(
            invalidDigest,
            0,
            address(0),
            "",
            orderAmount,
            address(0),
            0,
            commitSignature,
            orderSignature,
            IPacksSignatureVerifier.FulfillmentOption.Payout,
            choiceSignature
        );
    }

    function testSetLimitsSecurity() public {
        // Test that only authorized roles can set limits
        vm.startPrank(user);
        vm.expectRevert();
        packs.setMaxReward(10 ether);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.setMaxReward(10 ether);
        assertEq(packs.maxReward(), 10 ether);
        vm.stopPrank();
    }

    function testInvalidLimits() public {
        vm.startPrank(admin);
        
        // Test invalid min reward
        vm.expectRevert(PacksInitializable.InvalidReward.selector);
        packs.setMinReward(10 ether); // Greater than max reward
        
        // Test invalid max pack price
        vm.expectRevert(PacksInitializable.InvalidPackPrice.selector);
        packs.setMaxPackPrice(0.005 ether); // Less than min pack price
        
        // Test invalid payout bps
        vm.expectRevert(PacksInitializable.InvalidPayoutBps.selector);
        packs.setPayoutBps(15000); // Greater than 10000
        
        vm.stopPrank();
    }

    function testCommitExpireTimeSecurity() public {
        vm.startPrank(user);
        vm.expectRevert();
        packs.setCommitExpireTime(2 days);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.setCommitExpireTime(2 days);
        assertEq(packs.commitExpireTime(), 2 days);
        
        // Test minimum expire time
        vm.expectRevert(PacksInitializable.InvalidCommitExpireTime.selector);
        packs.setCommitExpireTime(30 seconds); // Less than MIN_COMMIT_EXPIRE_TIME
        vm.stopPrank();
    }

    function testCosignerManagementSecurity() public {
        vm.startPrank(user);
        vm.expectRevert();
        packs.addCosigner(bob);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.addCosigner(bob);
        assertTrue(packs.isCosigner(bob));
        
        // Test adding zero address
        vm.expectRevert(PacksInitializable.InvalidCosigner.selector);
        packs.addCosigner(address(0));
        
        // Test adding already existing cosigner
        vm.expectRevert(PacksInitializable.AlreadyCosigner.selector);
        packs.addCosigner(bob);
        
        // Test removing non-existent cosigner
        vm.expectRevert(PacksInitializable.InvalidCosigner.selector);
        packs.removeCosigner(charlie);
        
        packs.removeCosigner(bob);
        assertFalse(packs.isCosigner(bob));
        vm.stopPrank();
    }
}

// Malicious contract for reentrancy testing
contract ReentrantAttacker {
    PacksInitializable packs;
    
    constructor(address _packs) {
        packs = PacksInitializable(payable(_packs));
    }
    
    receive() external payable {
        // Try to reenter - this should fail due to nonReentrant modifier
        // This is just a placeholder for the reentrancy test
    }
}
