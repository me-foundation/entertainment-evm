// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/PacksInitializable.sol";
import "../../src/PRNG.sol";
import "../../src/common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PacksBurnInTest is Test {
    // Fork configuration
    uint256 public baseFork;
    string public BASE_RPC_URL = vm.envString("RPC_URL");
    
    // Production contract addresses on Base mainnet
    address public constant PACKS_V1_IMPLEMENTATION = 0x06bb79bFcBA7CaCEA2A2604E224ab6218CA81338;
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
        // Create fork of Base mainnet
        baseFork = vm.createFork(BASE_RPC_URL);
        vm.selectFork(baseFork);
        
        // Set up test accounts
        admin = vm.addr(adminPrivateKey);
        cosigner = vm.addr(cosignerPrivateKey);
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        
        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(cosigner, 10 ether);
        vm.deal(user1, 50 ether);
        vm.deal(user2, 50 ether);
        
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
        
        // Bucket 1: 80% chance, low value
        buckets[0] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 8000,
            minValue: 0.01 ether,
            maxValue: 0.011 ether
        });
        
        // Bucket 2: 15% chance, medium value
        buckets[1] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 1500,
            minValue: 0.012 ether,
            maxValue: 0.05 ether
        });
        
        // Bucket 3: 5% chance, high value
        buckets[2] = PacksSignatureVerifierUpgradeable.BucketData({
            oddsBps: 500,
            minValue: 0.051 ether,
            maxValue: 0.1 ether
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
        
    // ============ PLACEHOLDER FOR FUTURE TESTS ============
    
    // Tests will verify:
    // 1. Basic functionality works on forked mainnet
    // 2. Upgrade scenarios  
    // 3. State consistency after upgrades
    // 4. Integration with existing mainnet state
}
