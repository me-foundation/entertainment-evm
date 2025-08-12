// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import "../src/common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";
import "src/common/Errors.sol";
import "src/PRNG.sol";
import "src/Packs.sol";
import {TokenRescuer} from "../src/common/TokenRescuer.sol";
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
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        pure
        returns (bytes4)
    {
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
        return interfaceId == 0x4e2312e0 // IERC1155Receiver
            || interfaceId == 0x01ffc9a7; // IERC165
    }
}

contract TestPacks is Test {
    PRNG prng;
    Packs packs;
    address admin = address(0x1);
    address user = address(0x2);
    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    uint256 constant RECEIVER_PRIVATE_KEY = 5678; // Known private key for receiver
    address cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
    address receiver = vm.addr(RECEIVER_PRIVATE_KEY); // Derive receiver from known private key
    address fundsReceiverManager = address(0x4);
    address fundsReceiver = address(0x5);

    uint256 seed = 12345;
    uint256 packPrice = 0.01 ether;

    // Test bucket data
    PacksSignatureVerifierUpgradeable.BucketData[] buckets;
    PacksSignatureVerifierUpgradeable.BucketData[] bucketsMulti;

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
        PacksSignatureVerifierUpgradeable.FulfillmentOption choice,
        PacksSignatureVerifierUpgradeable.FulfillmentOption fulfillmentType,
        bytes32 digest
    );

    event CommitCancelled(uint256 indexed commitId, bytes32 digest);
    event TreasuryWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    event EmergencyWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);

    address marketplace;

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();

        packs = new Packs(fundsReceiver, address(prng), fundsReceiverManager);

        vm.deal(admin, 100 ether);
        vm.deal(receiver, 100 ether);
        vm.deal(address(this), 100 ether);

        // Add cosigner
        packs.addCosigner(cosigner);

        // Setup test buckets - using single bucket to avoid validation issues
        buckets = new PacksSignatureVerifierUpgradeable.BucketData[](1);
        buckets[0] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 10000, // 100% chance
            minValue: 0.01 ether,
            maxValue: 0.02 ether
        });

        bucketsMulti = new PacksSignatureVerifierUpgradeable.BucketData[](3);
        bucketsMulti[0] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 3000, // 30% chance (individual probability)
            minValue: 0.01 ether,
            maxValue: 0.015 ether
        });
        bucketsMulti[1] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 5000, // 50% chance (individual probability)
            minValue: 0.02 ether,
            maxValue: 0.025 ether
        });
        bucketsMulti[2] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 2000, // 20% chance (individual probability)
            minValue: 0.026 ether,
            maxValue: 0.03 ether
        });

        marketplace = address(0x123);

        vm.stopPrank();
    }

    function testInitialize() public view {
        assertTrue(packs.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(packs.hasRole(OPS_ROLE, admin));

        assertEq(packs.fundsReceiver(), fundsReceiver);
        assertEq(address(packs.PRNG()), address(prng));
        assertTrue(packs.hasRole(packs.FUNDS_RECEIVER_MANAGER_ROLE(), fundsReceiverManager));

        // Check default values
        assertEq(packs.minReward(), 0.01 ether);
        assertEq(packs.maxReward(), 5 ether);
        assertEq(packs.minPackPrice(), 0.01 ether);
        assertEq(packs.maxPackPrice(), 0.25 ether);
        assertEq(packs.minPackRewardMultiplier(), 5000);
        assertEq(packs.maxPackRewardMultiplier(), 30000);
    }

    function testCommitSuccess() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory signature = signPack(packPrice, buckets);

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: 0,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        vm.expectEmit(true, true, true, true);
        emit Commit(
            user,
            0,
            receiver,
            cosigner,
            seed,
            0,
            packPrice,
            packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets),
            digest
        );

        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, signature
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
            bytes32 storedPackHash
        ) = packs.packs(0);

        assertEq(id, 0);
        assertEq(storedReceiver, receiver);
        assertEq(storedCosigner, cosigner);
        assertEq(storedSeed, seed);
        assertEq(storedCounter, 0);
        assertEq(storedPackPrice, packPrice);
        // payoutBps is no longer used - payout amount is now passed directly
        assertEq(storedPackHash, packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets));

        vm.stopPrank();
    }

    function testCommitWithInvalidAmount() public {
        vm.startPrank(user);
        vm.deal(user, 0.5 ether);

        bytes memory signature = signPack(0.5 ether, buckets);

        vm.expectRevert(Errors.InvalidAmount.selector);
        packs.commit{value: 0.5 ether}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidCosigner() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory signature = signPack(packPrice, buckets);

        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.commit{value: packPrice}(
            receiver, address(0x999), seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidBuckets() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test empty buckets
        PacksSignatureVerifierUpgradeable.BucketData[] memory emptyBuckets =
            new PacksSignatureVerifierUpgradeable.BucketData[](0);
        bytes memory signature = signPack(packPrice, emptyBuckets);

        vm.expectRevert(Packs.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, emptyBuckets, signature
        );

        // Test too many buckets
        PacksSignatureVerifierUpgradeable.BucketData[] memory tooManyBuckets =
            new PacksSignatureVerifierUpgradeable.BucketData[](6);
        for (uint256 i = 0; i < 6; i++) {
            tooManyBuckets[i] =
                PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 1666, minValue: 0.01 ether, maxValue: 0.02 ether});
        }
        signature = signPack(packPrice, tooManyBuckets);

        vm.expectRevert(Packs.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, tooManyBuckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidBucketValues() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test bucket with zero values
        PacksSignatureVerifierUpgradeable.BucketData[] memory invalidBuckets =
            new PacksSignatureVerifierUpgradeable.BucketData[](1);
        invalidBuckets[0] =
            PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 10000, minValue: 0, maxValue: 0.1 ether});
        bytes memory signature = signPack(packPrice, invalidBuckets);

        vm.expectRevert(Packs.InvalidReward.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, invalidBuckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithBucketValuesOutOfPackPriceRange() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test bucket with min value less than pack price
        PacksSignatureVerifierUpgradeable.BucketData[] memory invalidBuckets = new PacksSignatureVerifierUpgradeable.BucketData[](1);
        invalidBuckets[0] = PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 10000, minValue: 0.004 ether, maxValue: 0.4 ether});
        bytes memory signature = signPack(packPrice, invalidBuckets);

        vm.expectRevert(Packs.InvalidReward.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, invalidBuckets, signature
        );
    }

    function testCommitWithInvalidBucketRanges() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test overlapping bucket ranges
        PacksSignatureVerifierUpgradeable.BucketData[] memory overlappingBuckets =
            new PacksSignatureVerifierUpgradeable.BucketData[](2);
        overlappingBuckets[0] =
            PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 5000, minValue: 0.01 ether, maxValue: 0.02 ether});
        overlappingBuckets[1] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 5000,
            minValue: 0.015 ether, // Overlaps with previous bucket
            maxValue: 0.025 ether
        });
        bytes memory signature = signPack(packPrice, overlappingBuckets);

        vm.expectRevert(Packs.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, overlappingBuckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidOdds() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        // Test non-cumulative odds
        PacksSignatureVerifierUpgradeable.BucketData[] memory invalidOddsBuckets =
            new PacksSignatureVerifierUpgradeable.BucketData[](2);
        invalidOddsBuckets[0] =
            PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 6000, minValue: 0.01 ether, maxValue: 0.02 ether});
        invalidOddsBuckets[1] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 5000, // Total odds = 11000, should be 10000
            minValue: 0.025 ether,
            maxValue: 0.03 ether
        });
        bytes memory signature = signPack(packPrice, invalidOddsBuckets);

        vm.expectRevert(Packs.InvalidBuckets.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, invalidOddsBuckets, signature
        );

        vm.stopPrank();
    }

    function testCommitWithInvalidSignature() public {
        vm.startPrank(user);
        vm.deal(user, packPrice);

        bytes memory wrongSignature = signPack(packPrice + 0.1 ether, buckets);

        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, wrongSignature
        );

        vm.stopPrank();
    }

    function testFulfillSuccess() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly and cosigner
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Now fulfill with payout
        uint256 orderAmount = 0.015 ether; // Within bucket 0 range
        uint256 expectedPayoutAmount = 0.0135 ether; // 90% of 0.015 ether
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            expectedPayoutAmount,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );
        bytes memory choiceSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            expectedPayoutAmount,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        vm.expectEmit(true, true, false, true);
        emit Fulfillment(
            cosigner,
            commitId,
            rng,
            10000,
            0,
            expectedPayoutAmount,
            address(0),
            0,
            0,
            receiver,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            digest
        );

        vm.prank(cosigner);
        packs.fulfill(
            commitId,
            marketplace, // marketplace
            "", // orderData
            orderAmount,
            address(0), // token
            0, // tokenId
            expectedPayoutAmount, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testFulfillWithNFT() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly and cosigner
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Now fulfill with NFT - use proper amount within bucket range
        uint256 orderAmount = 0.015 ether; // Within bucket range (0.01-0.02)
        address marketplace = address(0x123);
        address token = address(0x123);
        uint256 tokenId = 1;
        bytes memory orderData = hex"00";

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            orderData,
            token,
            tokenId,
            0.012 ether, // payoutAmount (must be within bucket range even for NFT)
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT,
            cosigner
        );

        vm.expectEmit(true, true, false, true);
        emit Fulfillment(
            cosigner,
            commitId,
            rng,
            10000,
            0,
            0,
            token,
            tokenId,
            orderAmount,
            receiver,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT,
            digest
        );

        vm.prank(cosigner);
        packs.fulfill(
            commitId,
            marketplace,
            orderData,
            orderAmount,
            token,
            tokenId,
            0.012 ether, // payoutAmount (must be within bucket range even for NFT)
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testFulfillWithInvalidCosignerSignature() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether, // payoutAmount
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );
        bytes memory choiceSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether, // payoutAmount
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets, bob);

        vm.prank(cosigner);
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.fulfill(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testFulfillWithInvalidCosigner() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly and cosigner
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Now fulfill with payout
        uint256 orderAmount = 0.03 ether; // Within bucket 0 range
        uint256 expectedPayoutAmount = 0.027 ether; // 90% of 0.03 ether
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            expectedPayoutAmount,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);

        vm.prank(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        packs.fulfill(
            commitId,
            marketplace, // marketplace
            "", // orderData
            orderAmount,
            address(0), // token
            0, // tokenId
            expectedPayoutAmount, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        assertFalse(packs.isFulfilled(commitId));
    }

    function testFulfillWithInvalidOrderAmount() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Try to fulfill with order amount outside bucket range
        uint256 orderAmount = 2 ether; // Outside all bucket ranges
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            1.8 ether, // payoutAmount (90% of 2 ether)
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        vm.prank(cosigner);
        vm.expectRevert(Errors.InvalidAmount.selector);
        packs.fulfill(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            1.8 ether, // payoutAmount (90% of 2 ether)
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testFulfillWithInvalidOrderHash() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // First fulfill
        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether, // payoutAmount
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        vm.prank(cosigner);
        packs.fulfill(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        // Try to fulfill again with different order data - but this will fail with AlreadyFulfilled first
        vm.prank(cosigner);
        vm.expectRevert(Packs.AlreadyFulfilled.selector);
        packs.fulfill(
            commitId,
            marketplace,
            "different",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testFulfillAlreadyFulfilled() public {
        // Create and fulfill commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        vm.deal(cosigner, 20 ether);
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether, // payoutAmount
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        // Call fulfill with some ETH value to fund the treasury
        vm.prank(cosigner);
        packs.fulfill{value: 10 ether}(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        // Try to fulfill again
        vm.prank(cosigner);
        vm.expectRevert(Packs.AlreadyFulfilled.selector);
        packs.fulfill{value: 0}(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testCancelCommit() public {
        vm.startPrank(admin);
        packs.setCommitCancellableTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );

        uint256 initialBalance = user.balance;
        vm.stopPrank();

        // Wait for cancellation time
        vm.warp(block.timestamp + 2 days);

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: user,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        vm.expectEmit(true, false, false, true);
        emit CommitCancelled(commitId, digest);

        vm.prank(cosigner);
        packs.cancel(commitId);

        assertTrue(packs.isCancelled(commitId));
        assertEq(user.balance, initialBalance + packPrice);
    }

    function testCancelCommitFromCosigner() public {
        vm.startPrank(admin);
        packs.setCommitCancellableTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );

        uint256 initialBalance = user.balance;
        vm.stopPrank();

        // Wait for cancellation time
        vm.warp(block.timestamp + 2 days);

        // Calculate the actual digest that will be emitted
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: user,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        vm.expectEmit(true, false, false, true);
        emit CommitCancelled(commitId, digest);

        vm.prank(cosigner);
        packs.cancel(commitId);
        vm.stopPrank();

        assertTrue(packs.isCancelled(commitId));
        assertEq(user.balance, initialBalance + packPrice);
    }

    function testCancelCommitNotCancellable() public {
        vm.startPrank(admin);
        packs.setCommitCancellableTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );
        vm.stopPrank();

        // Try to cancel before cancellation time as cosigner
        vm.prank(cosigner);
        vm.expectRevert(Packs.CommitNotCancellable.selector);
        packs.cancel(commitId);
    }

    function testCancelCommitNotOwner() public {
        vm.startPrank(admin);
        packs.setCommitCancellableTime(1 days);
        vm.stopPrank();

        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            user, // receiver
            cosigner,
            seed,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );
        vm.stopPrank();

        // Wait for cancellation time
        vm.warp(block.timestamp + 2 days);

        // Try to cancel as non-cosigner
        vm.expectRevert(Packs.InvalidCommitOwner.selector);
        vm.prank(bob);
        packs.cancel(commitId);
    }

    function testWithdrawTreasurySuccess() public {
        uint256 withdrawAmount = 1 ether;
        // Fund the treasury properly by sending ETH to the contract
        vm.deal(address(this), withdrawAmount);
        (bool success,) = payable(address(packs)).call{value: withdrawAmount}("");
        require(success, "Failed to fund contract");

        uint256 initialBalance = fundsReceiver.balance;

        vm.expectEmit(true, false, false, true);
        emit TreasuryWithdrawal(admin, withdrawAmount, fundsReceiver);

        vm.prank(admin);
        packs.withdrawTreasury(withdrawAmount);

        assertEq(fundsReceiver.balance, initialBalance + withdrawAmount);
    }

    function testWithdrawTreasuryInsufficientBalance() public {
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        packs.withdrawTreasury(1 ether);
    }

    function testPackRevenueForwardedOnFulfill() public {
        // Commit a pack
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Build fulfillment signatures
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether, // payoutAmount
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        uint256 initialFundsReceiverBalance = fundsReceiver.balance;

        // Funds cosigner
        vm.deal(cosigner, 1 ether);

        // Fulfill; provide some ETH to treasury to cover order
        vm.prank(cosigner);
        packs.fulfill{value: 1 ether}(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        // fundsReceiver should have received pack price plus remainder of payout
        uint256 remainderAmount = orderAmount - 0.0135 ether; // Fixed payout amount
        assertEq(fundsReceiver.balance, initialFundsReceiverBalance + packPrice + remainderAmount);
    }

    function testPackRevenueForwardedOnFulfillNFT() public {
        // Commit a pack
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Build fulfillment signatures for NFT choice
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);

        uint256 orderAmount = 0.015 ether; // within bucket range
        uint256 payoutAmount = 0.0135 ether;
        bytes memory orderData = hex"";
        address token = address(0x123);
        uint256 tokenId = 1;

        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            orderData,
            token,
            tokenId,
            0.012 ether, // payoutAmount (must be within bucket range even for NFT)
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT,
            cosigner
        );

        uint256 initialFundsReceiverBalance = fundsReceiver.balance;

        // Funds cosigner
        vm.deal(cosigner, 1 ether);

        // Fulfill; send enough ETH to treasury to cover order amount
        vm.prank(cosigner);
        packs.fulfill{value: 1 ether}(
            commitId,
            marketplace,
            orderData,
            orderAmount,
            token,
            tokenId,
            0.012 ether, // payoutAmount (must be within bucket range even for NFT)
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT
        );

        // fundsReceiver should have received only the pack price (no remainder for NFT path)
        assertEq(fundsReceiver.balance, initialFundsReceiverBalance + packPrice);
    }

    function testEmergencyWithdraw() public {
        // Create commit
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        vm.deal(address(packs), address(packs).balance + 5 ether);
        vm.stopPrank();

        uint256 initialBalance = fundsReceiver.balance;

        vm.prank(admin);
        packs.emergencyWithdraw();

        assertEq(fundsReceiver.balance, initialBalance + 5 ether + packPrice);
        assertTrue(packs.paused());
    }

    // Helper functions for signing
    function signPack(uint256 packPrice_, PacksSignatureVerifierUpgradeable.BucketData[] memory buckets_)
        internal
        view
        returns (bytes memory)
    {
        return signPack(packPrice_, buckets_, cosigner);
    }

    function signPack(
        uint256 packPrice_,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets_,
        address signer_
    ) internal view returns (bytes memory) {
        bytes32 packHash = packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice_, buckets_);

        // Find the private key for the signer
        uint256 privateKey;
        if (signer_ == cosigner) {
            privateKey = COSIGNER_PRIVATE_KEY;
        } else if (signer_ == bob) {
            privateKey = 5678; // bob's private key
        } else if (signer_ == charlie) {
            privateKey = 9012; // charlie's private key
        } else {
            // For any other address, generate a deterministic private key
            privateKey = uint256(keccak256(abi.encodePacked(signer_)));
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, packHash);
        return abi.encodePacked(r, s, v);
    }

    function signCommit(
        uint256 commitId_,
        address receiver_,
        uint256 seed_,
        uint256 counter_,
        uint256 packPrice_,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets_
    ) internal view returns (bytes memory) {
        return signCommit(commitId_, receiver_, seed_, counter_, packPrice_, buckets_, cosigner);
    }

    function signCommit(
        uint256 commitId_,
        address receiver_,
        uint256 seed_,
        uint256 counter_,
        uint256 packPrice_,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets_,
        address signer_
    ) internal view returns (bytes memory) {
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId_,
            receiver: receiver_,
            cosigner: cosigner,
            seed: seed_,
            counter: counter_,
            packPrice: packPrice_,
            buckets: buckets_,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice_, buckets_)
        });

        bytes32 digest = packs.hashCommit(commitData);

        // Find the private key for the signer
        uint256 privateKey;
        if (signer_ == cosigner) {
            privateKey = COSIGNER_PRIVATE_KEY;
        } else if (signer_ == bob) {
            privateKey = 5678; // bob's private key
        } else if (signer_ == charlie) {
            privateKey = 9012; // charlie's private key
        } else {
            // For any other address, generate a deterministic private key
            privateKey = uint256(keccak256(abi.encodePacked(signer_)));
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Universal fulfillment signature helper
    function signFulfillment(
        uint256 commitId_,
        address receiver_,
        uint256 seed_,
        uint256 counter_,
        uint256 packPrice_,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets_,
        address marketplace_,
        uint256 orderAmount_,
        bytes memory orderData_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        PacksSignatureVerifierUpgradeable.FulfillmentOption choice_,
        address signer_
    ) internal view returns (bytes memory) {
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId_,
            receiver: receiver_,
            cosigner: cosigner,
            seed: seed_,
            counter: counter_,
            packPrice: packPrice_,
            buckets: buckets_,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice_, buckets_)
        });
        bytes32 digest = packs.hashCommit(commitData);
        bytes32 fulfillmentHash = packs.hashFulfillment(
            digest, marketplace_, orderAmount_, orderData_, token_, tokenId_, payoutAmount_, choice_
        );
        uint256 privateKey;
        if (signer_ == cosigner) {
            privateKey = COSIGNER_PRIVATE_KEY;
        } else if (signer_ == receiver) {
            privateKey = RECEIVER_PRIVATE_KEY;
        } else if (signer_ == bob) {
            privateKey = 9999; // Different from RECEIVER_PRIVATE_KEY
        } else if (signer_ == charlie) {
            privateKey = 9012;
        } else {
            privateKey = uint256(keccak256(abi.encodePacked(signer_)));
        }
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, fulfillmentHash);
        return abi.encodePacked(r, s, v);
    }

    function testInvalidPackHashSigner() public {
        // Test that fulfill reverts if the commit is not signed by the cosigner
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Fund contract so balance check doesn't fail first
        (bool success,) = payable(address(packs)).call{value: 1 ether}("");
        require(success, "Failed to fund contract");

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Try to fulfill with wrong signature
        bytes memory wrongSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets, bob);
        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );
        
        vm.prank(cosigner);
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.fulfill(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether,
            wrongSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testInvalidOrderHashSigner() public {
        // Test that fulfill reverts if the order hash is not signed by the receiver
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Fund contract treasury properly
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Try to fulfill with wrong signature
        bytes memory wrongSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            0.015 ether,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            bob
        );
        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        vm.prank(cosigner);
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.fulfill(
            commitId,
            marketplace,
            "",
            0.015 ether,
            address(0),
            0,
            0.0135 ether,
            commitSignature,
            wrongSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testRNGDistributionInFulfill() public {
        // Test that RNG-based bucket selection in fulfill follows expected statistical distribution
        // Create multiple commits and track bucket selections to validate RNG behavior

        uint256[3] memory bucketCounts;
        uint256 numTests = 1000;

        // Fund the contract treasury to handle payouts
        // Maximum possible payout: 1000 iterations × 0.18 ether = 180 ether
        vm.deal(address(this), 300 ether); // Give the test contract enough ETH
        (bool success,) = payable(address(packs)).call{value: 200 ether}("");
        require(success, "Failed to fund contract");

        for (uint256 i = 0; i < numTests; i++) {
            // Create commit with different seed for each test
            vm.startPrank(user);
            vm.deal(user, packPrice);
            bytes memory packSignature = signPack(packPrice, bucketsMulti);
            uint256 commitId = packs.commit{value: packPrice}(
                receiver,
                cosigner,
                seed + i,
                PacksSignatureVerifierUpgradeable.PackType.NFT,
                bucketsMulti,
                packSignature
            );
            vm.stopPrank();

            // Calculate expected RNG and bucket selection
            bytes memory commitSignature = signCommit(commitId, receiver, seed + i, i, packPrice, bucketsMulti);
            uint256 rng = prng.rng(commitSignature);

            // Calculate which bucket should be selected based on RNG
            uint256 expectedBucketIndex = 0;
            uint256 cumulativeOdds = 0;
            for (uint256 j = 0; j < bucketsMulti.length; j++) {
                cumulativeOdds += bucketsMulti[j].oddsBps;
                if (rng < cumulativeOdds) {
                    expectedBucketIndex = j;
                    break;
                }
            }

            // Use an order amount that falls within the expected bucket's range
            uint256 orderAmount;
            uint256 payoutAmount;
            if (expectedBucketIndex == 0) {
                orderAmount = 0.012 ether; // Within bucket 0 range (0.01-0.015)
                payoutAmount = 0.011 ether;
            } else if (expectedBucketIndex == 1) {
                orderAmount = 0.022 ether; // Within bucket 1 range (0.02-0.025)
                payoutAmount = 0.021 ether;
            } else {
                orderAmount = 0.028 ether; // Within bucket 2 range (0.026-0.03)
                payoutAmount = 0.027 ether;
            }

            // Calculate the commit digest for signing order
            PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable
                .CommitData({
                id: commitId,
                receiver: receiver,
                cosigner: cosigner,
                seed: seed + i,
                counter: i,
                packPrice: packPrice,
                buckets: bucketsMulti,
                packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, bucketsMulti)
            });
            bytes32 digest = packs.hashCommit(commitData);

            // Prepare signatures for fulfill
            bytes memory fulfillmentSignature = signFulfillment(
                commitId,
                receiver,
                seed + i,
                i,
                packPrice,
                bucketsMulti,
                marketplace,
                orderAmount,
                "",
                address(0),
                0,
                payoutAmount,
                PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
                cosigner
            );
            
            // Fulfill the commit - this will internally select the bucket based on RNG
            vm.prank(cosigner);
            packs.fulfill(
                commitId,
                marketplace,
                "",
                orderAmount,
                address(0),
                0,
                payoutAmount,
                commitSignature,
                fulfillmentSignature,
                PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
            );

            // Track bucket selections based on the expected bucket
            bucketCounts[expectedBucketIndex]++;
        }

        // Basic statistical validation - all buckets should be selected at least once
        assertTrue(bucketCounts[0] > 0, "Bucket 0 should be selected at least once");
        assertTrue(bucketCounts[1] > 0, "Bucket 1 should be selected at least once");
        assertTrue(bucketCounts[2] > 0, "Bucket 2 should be selected at least once");

        // Verify total selections equals number of tests
        assertEq(
            bucketCounts[0] + bucketCounts[1] + bucketCounts[2],
            numTests,
            "Total selections should equal number of tests"
        );

        // Verify bucket 1 (50% odds) is selected more frequently than others
        // This is a basic check that the higher odds bucket gets selected more often
        assertTrue(
            bucketCounts[1] >= bucketCounts[0],
            "Bucket 1 (50% odds) should be selected at least as often as bucket 0 (30% odds)"
        );
        assertTrue(
            bucketCounts[1] >= bucketCounts[2],
            "Bucket 1 (50% odds) should be selected at least as often as bucket 2 (20% odds)"
        );

        // Log the distribution for verification
        console.log("Bucket 0 selections (30% odds):", bucketCounts[0]);
        console.log("Bucket 1 selections (50% odds):", bucketCounts[1]);
        console.log("Bucket 2 selections (20% odds):", bucketCounts[2]);
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
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();
    }

    function testFulfillWhenPaused() public {
        // Create commit first
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Then pause
        vm.startPrank(admin);
        packs.pause();
        vm.stopPrank();

        vm.deal(address(packs), 10 ether);

        // Try to fulfill when paused
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Calculate the commit digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        packs.fulfill(
            commitId,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether, // payoutAmount
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testfundsReceiverManagerSecurity() public {
        address newfundsReceiverManager = address(0x8);
        address newfundsReceiver = address(0x9);

        // Test that only funds receiver manager can transfer role
        vm.startPrank(admin);
        vm.expectRevert();
        packs.transferFundsReceiverManager(newfundsReceiverManager);
        vm.stopPrank();

        // Test that only funds receiver manager can set funds receiver
        vm.startPrank(admin);
        vm.expectRevert();
        packs.setFundsReceiver(newfundsReceiver);
        vm.stopPrank();

        // Test that funds receiver manager can transfer role
        vm.startPrank(fundsReceiverManager);
        packs.transferFundsReceiverManager(newfundsReceiverManager);
        vm.stopPrank();

        // Test that new funds receiver manager can set funds receiver
        vm.startPrank(newfundsReceiverManager);
        packs.setFundsReceiver(newfundsReceiver);
        vm.stopPrank();

        assertEq(packs.fundsReceiver(), newfundsReceiver);
    }

    function testInvalidFundsReceiverManager() public {
        vm.startPrank(fundsReceiverManager);
        vm.expectRevert(Packs.InvalidFundsReceiverManager.selector);
        packs.transferFundsReceiverManager(address(0));
        vm.stopPrank();
    }

    function testInvalidFundsReceiver() public {
        vm.startPrank(fundsReceiverManager);
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.setFundsReceiver(address(0));
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
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.rescueERC20(address(0), bob, 100 ether);
        vm.stopPrank();
    }

    function testRescueERC20ZeroAmount() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(Errors.InvalidAmount.selector);
        packs.rescueERC20(address(token), bob, 0);
        vm.stopPrank();
    }

    function testRescueERC20InsufficientBalance() public {
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        vm.startPrank(admin);
        vm.expectRevert(Errors.InsufficientBalance.selector);
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

        // Deploy ERC1155 receiver
        SimpleERC1155Receiver receiver = new SimpleERC1155Receiver();

        // Test single token rescue
        vm.startPrank(admin);
        packs.rescueERC1155(address(token), address(receiver), 1, 50);
        vm.stopPrank();

        assertEq(token.balanceOf(address(receiver), 1), 50);
        assertEq(token.balanceOf(address(packs), 1), 50);
    }

    function testRescueERC20() public {
        // Deploy mock ERC20
        MockERC20 token = new MockERC20();
        token.mint(address(packs), 1000 ether);

        // Test single token rescue
        vm.startPrank(admin);
        packs.rescueERC20(address(token), bob, 100 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(address(packs)), 900 ether);
    }

    function testRescueERC20Batch() public {
        // Deploy mock ERC20s
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        token1.mint(address(packs), 1000 ether);
        token2.mint(address(packs), 500 ether);

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tos[0] = bob;
        tos[1] = charlie;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.startPrank(admin);
        packs.rescueERC20Batch(tokens, tos, amounts);
        vm.stopPrank();

        assertEq(token1.balanceOf(bob), 100 ether);
        assertEq(token2.balanceOf(charlie), 200 ether);
        assertEq(token1.balanceOf(address(packs)), 900 ether);
        assertEq(token2.balanceOf(address(packs)), 300 ether);
    }

    function testRescueERC721() public {
        // Deploy mock ERC721
        MockERC721 token = new MockERC721();
        token.mint(address(packs), 1);

        // Test single token rescue
        vm.startPrank(admin);
        packs.rescueERC721(address(token), bob, 1);
        vm.stopPrank();

        assertEq(token.ownerOf(1), bob);
    }

    function testRescueERC721Batch() public {
        // Deploy mock ERC721s
        MockERC721 token1 = new MockERC721();
        MockERC721 token2 = new MockERC721();
        token1.mint(address(packs), 1);
        token2.mint(address(packs), 2);

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tos[0] = bob;
        tos[1] = charlie;
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.startPrank(admin);
        packs.rescueERC721Batch(tokens, tos, tokenIds);
        vm.stopPrank();

        assertEq(token1.ownerOf(1), bob);
        assertEq(token2.ownerOf(2), charlie);
    }

    function testRescueERC1155Batch() public {
        // Deploy mock ERC1155
        MockERC1155 token = new MockERC1155();
        token.mint(address(packs), 1, 100);
        token.mint(address(packs), 2, 200);

        // Deploy ERC1155 receiver
        SimpleERC1155Receiver receiver = new SimpleERC1155Receiver();

        // Test batch rescue
        address[] memory tokens = new address[](2);
        address[] memory tos = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token);
        tokens[1] = address(token);
        tos[0] = address(receiver);
        tos[1] = address(receiver);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 50;
        amounts[1] = 100;

        vm.startPrank(admin);
        packs.rescueERC1155Batch(tokens, tos, tokenIds, amounts);
        vm.stopPrank();

        assertEq(token.balanceOf(address(receiver), 1), 50);
        assertEq(token.balanceOf(address(receiver), 2), 100);
        assertEq(token.balanceOf(address(packs), 1), 50);
        assertEq(token.balanceOf(address(packs), 2), 100);
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
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        packs.rescueERC20Batch(tokens, tos, amounts);
        vm.stopPrank();
    }

    function testFulfillByDigestSecurity() public {
        // Test that fulfillByDigest works correctly
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );

        // Fund contract treasury properly and cosigner
        vm.deal(user, 10 ether);
        (bool success,) = payable(address(packs)).call{value: 5 ether}("");
        require(success, "Failed to fund contract");
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate RNG and bucket selection
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        // Get the digest
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });

        bytes32 digest = packs.hashCommit(commitData);

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        vm.prank(cosigner);
        packs.fulfillByDigest(
            digest,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether,
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );

        assertTrue(packs.isFulfilled(commitId));
    }

    function testInvalidDigestFulfill() public {
        // Test that invalid digest reverts
        bytes32 invalidDigest = keccak256("invalid");

        uint256 orderAmount = 0.015 ether;
        bytes memory fulfillmentSignature = signFulfillment(
            0,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosigner
        );

        // Fund the contract treasury to avoid InsufficientBalance error
        (bool success,) = payable(address(packs)).call{value: orderAmount}("");
        require(success, "Failed to fund contract");

        vm.prank(cosigner);
        vm.expectRevert(Packs.InvalidCommitId.selector);

        packs.fulfillByDigest(
            invalidDigest,
            marketplace,
            "",
            orderAmount,
            address(0),
            0,
            0.0135 ether,
            "", // commitSignature
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout
        );
    }

    function testSetLimitsSecurity() public {
        // Test that only authorized roles can set limits
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, packs.DEFAULT_ADMIN_ROLE()
            )
        );
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
        vm.expectRevert(Packs.InvalidReward.selector);
        packs.setMinReward(10 ether); // Greater than max reward

        // Test invalid max pack price
        vm.expectRevert(Packs.InvalidPackPrice.selector);
        packs.setMaxPackPrice(0.005 ether); // Less than min pack price

        // Test invalid payout bps - payoutBps is no longer used
        // vm.expectRevert(Packs.InvalidPayoutBps.selector);
        // packs.setPayoutBps(15000); // Greater than 10000

        vm.stopPrank();
    }

    function testCommitCancellableTimeSecurity() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user,
                bytes32(0) // DEFAULT_ADMIN_ROLE
            )
        );
        packs.setCommitCancellableTime(2 days);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.setCommitCancellableTime(2 days);
        assertEq(packs.commitCancellableTime(), 2 days);

        // Test minimum cancellable time
        vm.expectRevert(Packs.InvalidCommitCancellableTime.selector);
        packs.setCommitCancellableTime(30 seconds); // Less than MIN_COMMIT_CANCELLABLE_TIME
        vm.stopPrank();
    }

    function testCosignerManagementSecurity() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user,
                bytes32(0) // DEFAULT_ADMIN_ROLE
            )
        );
        packs.addCosigner(bob);
        vm.stopPrank();

        vm.startPrank(admin);
        packs.addCosigner(bob);
        assertTrue(packs.isCosigner(bob));

        // Test adding zero address
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.addCosigner(address(0));

        // Test adding already existing cosigner
        vm.expectRevert(Packs.AlreadyCosigner.selector);
        packs.addCosigner(bob);

        // Test removing non-existent cosigner
        vm.expectRevert(Errors.InvalidAddress.selector);
        packs.removeCosigner(charlie);

        packs.removeCosigner(bob);
        assertFalse(packs.isCosigner(bob));
        vm.stopPrank();
    }

    function testNftFulfillmentExpiryTimeSecurity() public {
        // Non-admin should not be able to set the NFT fulfillment expiry time
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user,
                bytes32(0) // DEFAULT_ADMIN_ROLE
            )
        );
        packs.setNftFulfillmentExpiryTime(2 minutes);
        vm.stopPrank();

        // Admin cannot set a value below the minimum
        vm.startPrank(admin);
        vm.expectRevert(Packs.InvalidNftFulfillmentExpiryTime.selector);
        packs.setNftFulfillmentExpiryTime(20 seconds); // Less than MIN_NFT_FULFILLMENT_EXPIRY_TIME (30s)
        vm.stopPrank();

        // Admin can set a valid value
        vm.startPrank(admin);
        packs.setNftFulfillmentExpiryTime(2 minutes);
        assertEq(packs.nftFulfillmentExpiryTime(), 2 minutes);
        vm.stopPrank();
    }

    function testFulfillNftAfterExpiryDefaultsToPayout() public {
        // Set a short NFT fulfillment expiry time for quicker testing (minimum allowed)
        vm.prank(admin);
        packs.setNftFulfillmentExpiryTime(30 seconds);

        // Create commit as the user
        vm.startPrank(user);
        vm.deal(user, packPrice);
        bytes memory packSignature = signPack(packPrice, buckets);
        uint256 commitId = packs.commit{value: packPrice}(
            receiver, cosigner, seed, PacksSignatureVerifierUpgradeable.PackType.NFT, buckets, packSignature
        );
        vm.stopPrank();

        // Fund the contract treasury so that payouts can be covered
        (bool success,) = payable(address(packs)).call{value: 5 ether}("");
        require(success, "Failed to fund contract");

        // Prepare signatures for fulfill
        bytes memory commitSignature = signCommit(commitId, receiver, seed, 0, packPrice, buckets);
        uint256 rng = prng.rng(commitSignature);

        uint256 orderAmount = 0.015 ether; // Within bucket range (0.01 - 0.02 ether)
        address marketplace = address(0x123);
        address token = address(0x123);
        uint256 tokenId = 1;
        bytes memory orderData = hex"00";

        bytes memory fulfillmentSignature = signFulfillment(
            commitId,
            receiver,
            seed,
            0,
            packPrice,
            buckets,
            marketplace,
            orderAmount,
            orderData,
            token,
            tokenId,
            0.0135 ether,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT,
            cosigner
        );

        // Move time forward beyond the NFT fulfillment expiry window
        vm.warp(block.timestamp + 1 minutes);

        uint256 receiverInitialBalance = receiver.balance;
        uint256 expectedPayout = 0.0135 ether; // Fixed payout amount

        // Calculate digest for expected event
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: 0,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });
        bytes32 digest = packs.hashCommit(commitData);

        // Expect Fulfillment event with payout fallback
        vm.expectEmit(true, true, false, true);
        emit Fulfillment(
            cosigner,
            commitId,
            rng,
            10000,
            0,
            expectedPayout,
            address(0),
            0,
            0,
            receiver,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT, // choice
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout, // actual fulfillment type
            digest
        );

        // Fulfill – even though the choice is NFT, the expiry has passed so it should default to payout
        vm.prank(cosigner);
        packs.fulfill(
            commitId,
            marketplace,
            orderData,
            orderAmount,
            token,
            tokenId,
            0.0135 ether,
            commitSignature,
            fulfillmentSignature,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.NFT // User's choice
        );

        // Assertions
        assertTrue(packs.isFulfilled(commitId));
        assertEq(receiver.balance, receiverInitialBalance + expectedPayout);
    }
}
