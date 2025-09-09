// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/PacksInitializable.sol";
import "../../src/PRNG.sol";
import "../../src/common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PacksBurnInTest is Test {
    // Events
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
    
    event TransferFailure(
        uint256 indexed commitId,
        address indexed receiver,
        uint256 amount,
        bytes32 digest
    );
    // Fork configuration
    uint256 public baseFork;
    string public BURN_IN_RPC_URL = vm.envString("BURN_IN_RPC_URL");
    
    // Production contract addresses on Base mainnet
    address public constant PACKS_V1_IMPLEMENTATION = 0x06bb79bFcBA7CaCEA2A2604E224ab6218CA81338;
    address public constant PACKS_NEXT_IMPLEMENTATION = 0x06bb79bFcBA7CaCEA2A2604E224ab6218CA81338;


    address public constant PACKS_PROXY = 0xf541d82630A5ba513eB709c41d06ac3D009C0248;
    address public constant FUNDS_RECEIVER = 0x2918F39540df38D4c33cda3bCA9edFccd8471cBE;
    address public constant FUNDS_RECEIVER_MANAGER = 0x7C51fAEe5666B47b2F7E81b7a6A8DEf4C76D47E3;
    
    // Test contracts
    PacksInitializable public packs;
    PRNG public prng;
    
    // Test accounts
    address public admin;
    address public cosigner;
    address public user1;
    address public user2;
    
    // Private keys for testing
    uint256 public adminPrivateKey = 0x1;
    uint256 public cosignerPrivateKey = 0x2;
    uint256 public user1PrivateKey = 0x3;
    uint256 public user2PrivateKey = 0x4;
    
    function setUp() public {
        // Skip all tests if BURN_IN_RPC_URL is not set
        if (bytes(BURN_IN_RPC_URL).length == 0) {
            vm.skip(true);
            return;
        }
        
        // Create fork of Base mainnet
        baseFork = vm.createFork(BURN_IN_RPC_URL);
        vm.selectFork(baseFork);
        
        // Set up test accounts  
        admin = vm.addr(adminPrivateKey);
        cosigner = vm.addr(cosignerPrivateKey);
        // Use a simple address that can receive ETH instead of vm.addr()
        user1 = address(0x1234567890123456789012345678901234567890);
        user2 = vm.addr(user2PrivateKey);
        
        console.log("User1 is an EOA:", user1.code.length == 0);
        
        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(cosigner, 10 ether);
        vm.deal(user1, 50 ether);
        vm.deal(user2, 50 ether);
        
        console.log("=== INITIAL BALANCES ===");
        console.log("User1 initial balance (wei):", user1.balance);
        
        // Connect to existing Packs proxy on mainnet
        packs = PacksInitializable(payable(PACKS_PROXY));
        
        // Get PRNG address from the deployed contract
        prng = PRNG(address(packs.PRNG()));
        
        console.log("Fork setup complete");
        console.log("Packs proxy:", address(packs));
        console.log("PRNG:", address(prng));
        console.log("Admin:", admin);
        console.log("Cosigner:", cosigner);
    }
    
    // Helper functions for test setup
    function _createBuckets() internal pure returns (PacksSignatureVerifierUpgradeable.BucketData[] memory buckets) {
        buckets = new PacksSignatureVerifierUpgradeable.BucketData[](3);
        
        // For 0.25 ETH pack price, valid bucket range is 0.125 ETH to 5 ETH
        // Bucket 1: 80% chance, low value
        buckets[0] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 8000,
            minValue: 0.125 ether, // Min allowed for 0.25 ETH pack
            maxValue: 0.5 ether
        });
        
        // Bucket 2: 15% chance, medium value
        buckets[1] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 1500,
            minValue: 0.6 ether,
            maxValue: 2.0 ether
        });
        
        // Bucket 3: 5% chance, high value
        buckets[2] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 500,
            minValue: 2.1 ether,
            maxValue: 5.0 ether // Max allowed reward
        });
    }
    
    function _signPack(
        uint256 packPrice,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        bytes32 packHash = packs.hashPack(
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            packPrice,
            buckets
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, packHash);
        return abi.encodePacked(r, s, v);
    }
    
    function _signCommit(
        PacksSignatureVerifierUpgradeable.CommitData memory commitData,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        bytes32 digest = packs.hashCommit(commitData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _signFulfillment(
        bytes32 commitDigest,
        address marketplace,
        uint256 orderAmount,
        bytes memory orderData,
        address token,
        uint256 tokenId,
        uint256 payoutAmount,
        PacksSignatureVerifierUpgradeable.FulfillmentOption choice,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        bytes32 fulfillmentHash = packs.hashFulfillment(
            commitDigest,
            marketplace,
            orderAmount,
            orderData,
            token,
            tokenId,
            payoutAmount,
            choice
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, fulfillmentHash);
        return abi.encodePacked(r, s, v);
    }
    
    // ============ PROXY IMPLEMENTATION TESTS ============
    
    function testCurrentImplementationIsV1() public {
        // Get the implementation address from the proxy
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(PACKS_PROXY, implementationSlot))));
        
        // Verify it matches our expected V1 implementation
        assertEq(currentImplementation, PACKS_V1_IMPLEMENTATION, "Current implementation should be V1");
        
        console.log("Current implementation:", currentImplementation);
        console.log("Expected V1 implementation:", PACKS_V1_IMPLEMENTATION);
    }
        
    // ============ HAPPY PATH END-TO-END TESTS ============
    
    function testHappyPathCommitAndFulfillPayout() public {        
        
        address currentAdmin = 0x794A0a8fa41D64657cBa59E060408c84ddBF05Af; // From deployment
        vm.startPrank(currentAdmin);
        packs.addCosigner(cosigner);
        vm.stopPrank();
        
        // Setup test parameters
        uint256 packPrice = 0.25 ether; // Max allowed pack price
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets = _createBuckets();
        
        // Step 1: User creates a commit
        vm.startPrank(user1);
        
        // Get initial balances
        uint256 initialUserBalance = user1.balance;
        uint256 initialTreasuryBalance = packs.treasuryBalance();
        uint256 initialCommitBalance = packs.commitBalance();
        
        // Create commit
        console.log("User1 balance before commit (wei):", user1.balance);
        console.log("Pack price (wei):", packPrice);
        
        bytes memory packSignature = _signPack(packPrice, buckets, cosignerPrivateKey);
        uint256 commitId = packs.commit{value: packPrice}(
            user1,
            cosigner,
            12345,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );
        
        console.log("User1 balance after commit (wei):", user1.balance);

        // Fund contract treasury properly and cosigner
        console.log("User1 balance before treasury funding (wei):", user1.balance);
        
        console.log("User1 balance after vm.deal 10 ether (wei):", user1.balance);
        (bool success, ) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        console.log("User1 balance after treasury funding (wei):", user1.balance);
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate the actual digest that will be emitted
        uint256 userCounter = packs.packCount(user1) - 1; // Get the counter that was used for mainnet fork
        PacksSignatureVerifierUpgradeable.CommitData
            memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
                id: commitId,
                receiver: user1,
                cosigner: cosigner,
                seed: 12345,
                counter: userCounter,
                packPrice: packPrice,
                buckets: buckets,
                packHash: packs.hashPack(
                    PacksSignatureVerifierUpgradeable.PackType.NFT,
                    packPrice,
                    buckets
                )
            });
        bytes32 digest = packs.hashCommit(commitData);

        // Now fulfill with payout  
        address marketplace = address(0x123); // Mock marketplace
        // Since RNG will select bucket 1 (0.6-2.0 ETH range), use a value in that range
        uint256 orderAmount = 1.0 ether; // Within bucket 1 range
        uint256 expectedPayoutAmount = 1.0 ether; // Full payout
        bytes memory fulfillmentSignature = _signFulfillment(
            digest,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            expectedPayoutAmount,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosignerPrivateKey
        );

        // Calculate RNG and bucket selection
        bytes memory commitSignature = _signCommit(commitData, cosignerPrivateKey);
        uint256 rng = prng.rng(commitSignature);
        
        // Log fulfillment details
        console.log("=== FULFILLMENT DETAILS ===");
        console.log("RNG Roll:", rng);
        console.log("RNG Roll (out of 10000):", rng);
        
        // Determine which bucket was selected
        uint256 cumulativeOdds = 0;
        uint256 selectedBucket = 0;
        for (uint256 i = 0; i < buckets.length; i++) {
            cumulativeOdds += buckets[i].oddsBps;
            console.log("Bucket", i, "- Odds:", buckets[i].oddsBps);
            console.log("  Cumulative Odds:", cumulativeOdds);
            console.log("  Min Value:", buckets[i].minValue);
            console.log("  Max Value:", buckets[i].maxValue);
            if (rng < cumulativeOdds && selectedBucket == 0) {
                selectedBucket = i;
                console.log("  >>> SELECTED BUCKET <<<");
            }
        }
        
        console.log("Selected Bucket Index:", selectedBucket);
        console.log("Order Amount (wei):", orderAmount);
        console.log("Expected Payout (wei):", expectedPayoutAmount);
        console.log("Marketplace:", marketplace);
        console.log("Commit Digest:", vm.toString(digest));
        console.log("========================");

        vm.expectEmit(true, true, false, true);
        emit Fulfillment(
            cosigner,     // sender
            commitId,     // commitId
            rng,          // rng
            1500,         // odds (bucket 1 odds - 15%)
            1,            // bucketIndex (bucket 1)
            expectedPayoutAmount, // payout
            address(0),   // token
            0,            // tokenId  
            0,            // amount
            user1,        // receiver
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout, // choice
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout, // fulfillmentType
            digest        // digest
        );

        // Log user balance before fulfillment
        uint256 userBalanceBeforeFulfillment = user1.balance;
        console.log("User balance BEFORE fulfillment (wei):", userBalanceBeforeFulfillment);

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

        // Log fulfillment results
        console.log("=== FULFILLMENT RESULTS ===");
        console.log("Commit ID:", commitId);
        console.log("Is fulfilled:", packs.isFulfilled(commitId));
        console.log("User balance BEFORE fulfillment (wei):", userBalanceBeforeFulfillment);
        console.log("User balance AFTER fulfillment (wei):", user1.balance);
        console.log("User balance CHANGE (wei):", user1.balance - userBalanceBeforeFulfillment);
        console.log("Treasury balance after fulfillment (wei):", packs.treasuryBalance());
        console.log("Commit balance after fulfillment (wei):", packs.commitBalance());
        console.log("========================");

        assertTrue(packs.isFulfilled(commitId));
    }

    function testUpgradeTo() public {
        // Skip if RPC URL not set
        if (bytes(BURN_IN_RPC_URL).length == 0) {
            vm.skip(true);
            return;
        }
        
        // Get current implementation
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(PACKS_PROXY, implementationSlot))));
        
        console.log("Current implementation before upgrade:", currentImplementation);
        console.log("Target implementation:", PACKS_NEXT_IMPLEMENTATION);
        
        // Impersonate the admin to perform upgrade
        address currentAdmin = 0x794A0a8fa41D64657cBa59E060408c84ddBF05Af;
        vm.startPrank(currentAdmin);
        
        // Perform the upgrade
        packs.upgradeToAndCall(PACKS_NEXT_IMPLEMENTATION, "");
        
        vm.stopPrank();
        
        // Verify the upgrade
        address newImplementation = address(uint160(uint256(vm.load(PACKS_PROXY, implementationSlot))));
        assertEq(newImplementation, PACKS_NEXT_IMPLEMENTATION, "Implementation should be upgraded");
        
        console.log("Implementation after upgrade:", newImplementation);
        console.log("Upgrade successful!");
    }

    function testUpgradeToAndHappyPath() public {
        // Skip if RPC URL not set
        if (bytes(BURN_IN_RPC_URL).length == 0) {
            vm.skip(true);
            return;
        }
        
        // ============ UPGRADE PHASE ============
        
        // Get current implementation
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(PACKS_PROXY, implementationSlot))));
        
        console.log("=== UPGRADE PHASE ===");
        console.log("Current implementation before upgrade:", currentImplementation);
        console.log("Target implementation:", PACKS_NEXT_IMPLEMENTATION);
        
        // Impersonate the admin to perform upgrade
        address currentAdmin = 0x794A0a8fa41D64657cBa59E060408c84ddBF05Af;
        vm.startPrank(currentAdmin);
        
        // Perform the upgrade
        packs.upgradeToAndCall(PACKS_NEXT_IMPLEMENTATION, "");
        
        // Add our test cosigner to the upgraded contract
        packs.addCosigner(cosigner);
        vm.stopPrank();
        
        // Verify the upgrade
        address newImplementation = address(uint160(uint256(vm.load(PACKS_PROXY, implementationSlot))));
        assertEq(newImplementation, PACKS_NEXT_IMPLEMENTATION, "Implementation should be upgraded");
        
        console.log("Implementation after upgrade:", newImplementation);
        console.log("Upgrade successful!");
        console.log("==================");
        
        // ============ HAPPY PATH PHASE ============
        
        console.log("=== HAPPY PATH ON UPGRADED IMPLEMENTATION ===");
        
        // Setup test parameters
        uint256 packPrice = 0.25 ether;
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets = _createBuckets();
        
        // Step 1: User creates a commit
        vm.startPrank(user1);
        
        // Get initial balances
        uint256 initialUserBalance = user1.balance;
        uint256 initialTreasuryBalance = packs.treasuryBalance();
        uint256 initialCommitBalance = packs.commitBalance();
        
        // Create commit
        console.log("User1 balance before commit (wei):", user1.balance);
        console.log("Pack price (wei):", packPrice);
        
        bytes memory packSignature = _signPack(packPrice, buckets, cosignerPrivateKey);
        uint256 commitId = packs.commit{value: packPrice}(
            user1,
            cosigner,
            12345,
            PacksSignatureVerifierUpgradeable.PackType.NFT,
            buckets,
            packSignature
        );
        
        console.log("User1 balance after commit (wei):", user1.balance);

        // Fund contract treasury properly and cosigner
        console.log("User1 balance before treasury funding (wei):", user1.balance);
        
        console.log("User1 balance after vm.deal 10 ether (wei):", user1.balance);
        (bool success, ) = payable(address(packs)).call{value: 10 ether}("");
        require(success, "Failed to fund contract");
        console.log("User1 balance after treasury funding (wei):", user1.balance);
        vm.deal(cosigner, 5 ether);
        vm.stopPrank();

        // Calculate the actual digest that will be emitted
        uint256 userCounter = packs.packCount(user1) - 1;
        PacksSignatureVerifierUpgradeable.CommitData
            memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
                id: commitId,
                receiver: user1,
                cosigner: cosigner,
                seed: 12345,
                counter: userCounter,
                packPrice: packPrice,
                buckets: buckets,
                packHash: packs.hashPack(
                    PacksSignatureVerifierUpgradeable.PackType.NFT,
                    packPrice,
                    buckets
                )
            });
        bytes32 digest = packs.hashCommit(commitData);

        // Now fulfill with payout  
        address marketplace = address(0x123);
        uint256 orderAmount = 1.0 ether;
        uint256 expectedPayoutAmount = 1.0 ether;
        bytes memory fulfillmentSignature = _signFulfillment(
            digest,
            marketplace,
            orderAmount,
            "",
            address(0),
            0,
            expectedPayoutAmount,
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout,
            cosignerPrivateKey
        );

        // Calculate RNG and bucket selection
        bytes memory commitSignature = _signCommit(commitData, cosignerPrivateKey);
        uint256 rng = prng.rng(commitSignature);
        
        // Log fulfillment details
        console.log("=== FULFILLMENT DETAILS ===");
        console.log("RNG Roll:", rng);
        console.log("RNG Roll (out of 10000):", rng);
        
        // Determine which bucket was selected
        uint256 cumulativeOdds = 0;
        uint256 selectedBucket = 0;
        for (uint256 i = 0; i < buckets.length; i++) {
            cumulativeOdds += buckets[i].oddsBps;
            console.log("Bucket", i, "- Odds:", buckets[i].oddsBps);
            console.log("  Cumulative Odds:", cumulativeOdds);
            console.log("  Min Value:", buckets[i].minValue);
            console.log("  Max Value:", buckets[i].maxValue);
            if (rng < cumulativeOdds && selectedBucket == 0) {
                selectedBucket = i;
                console.log("  >>> SELECTED BUCKET <<<");
            }
        }
        
        console.log("Selected Bucket Index:", selectedBucket);
        console.log("Order Amount (wei):", orderAmount);
        console.log("Expected Payout (wei):", expectedPayoutAmount);
        console.log("Marketplace:", marketplace);
        console.log("Commit Digest:", vm.toString(digest));
        console.log("========================");

        vm.expectEmit(true, true, false, true);
        emit Fulfillment(
            cosigner,     // sender
            commitId,     // commitId
            rng,          // rng
            1500,         // odds (bucket 1 odds - 15%)
            1,            // bucketIndex (bucket 1)
            expectedPayoutAmount, // payout
            address(0),   // token
            0,            // tokenId  
            0,            // amount
            user1,        // receiver
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout, // choice
            PacksSignatureVerifierUpgradeable.FulfillmentOption.Payout, // fulfillmentType
            digest        // digest
        );

        // Log user balance before fulfillment
        uint256 userBalanceBeforeFulfillment = user1.balance;
        console.log("User balance BEFORE fulfillment (wei):", userBalanceBeforeFulfillment);

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

        // Log fulfillment results
        console.log("=== FULFILLMENT RESULTS ===");
        console.log("Commit ID:", commitId);
        console.log("Is fulfilled:", packs.isFulfilled(commitId));
        console.log("User balance BEFORE fulfillment (wei):", userBalanceBeforeFulfillment);
        console.log("User balance AFTER fulfillment (wei):", user1.balance);
        console.log("User balance CHANGE (wei):", user1.balance - userBalanceBeforeFulfillment);
        console.log("Treasury balance after fulfillment (wei):", packs.treasuryBalance());
        console.log("Commit balance after fulfillment (wei):", packs.commitBalance());
        console.log("========================");

        assertTrue(packs.isFulfilled(commitId));
        console.log("Happy path test completed successfully on upgraded implementation!");
    }

    
    // ============ PLACEHOLDER FOR FUTURE TESTS ============
    
    // Tests will verify:
    // 1. Basic functionality works on forked mainnet (completed above)
    // 2. Upgrade scenarios  
    // 3. State consistency after upgrades
    // 4. Integration with existing mainnet state
}
