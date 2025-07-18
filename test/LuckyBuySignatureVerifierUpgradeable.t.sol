// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import "../src/common/SignatureVerifier/LuckyBuySignatureVerifierUpgradeable.sol";

contract MockLuckyBuySignatureVerifierUpgradeable is LuckyBuySignatureVerifierUpgradeable {
    function initialize(
        string memory name,
        string memory version
    ) public initializer {
        __LuckyBuySignatureVerifier_init(name, version);
    }

    function getEIP712Name() public view returns (string memory) {
        return _EIP712Name();
    }

    function getVersion() public view returns (string memory) {
        return _EIP712Version();
    }

    function debugVerify(
        bytes32 digest,
        bytes memory signature
    ) public view returns (address) {
        return _verify(digest, signature);
    }
}

contract TestLuckyBuySignatureVerifierUpgradeable is Test {
    MockLuckyBuySignatureVerifierUpgradeable sigVerifier;
    uint256 cosignerPrivateKey = 0x1; //vm.envUint("PRIVATE_KEY");
    address cosignerAddress;
    address user = makeAddr("user");

    // Sample commit data for testing
    LuckyBuySignatureVerifierUpgradeable.CommitData commitData;

    function setUp() public {
        sigVerifier = new MockLuckyBuySignatureVerifierUpgradeable();
        sigVerifier.initialize("MagicSigner", "1");
        cosignerAddress = vm.addr(cosignerPrivateKey);

        // Initialize sample commit data
        commitData = LuckyBuySignatureVerifierUpgradeable.CommitData({
            id: 1,
            receiver: 0xE052c9CFe22B5974DC821cBa907F1DAaC7979c94,
            cosigner: cosignerAddress,
            seed: 1,
            counter: 1,
            orderHash: hex"1234",
            amount: 100,
            reward: 1000 // 10% odds
        });

        console.log("Commit data:");
        console.log("id:", commitData.id);
        console.log("receiver:", commitData.receiver);
        console.log("cosigner:", commitData.cosigner);
        console.log("seed:", commitData.seed);
        console.log("counter:", commitData.counter);
        console.logBytes32(commitData.orderHash);
        console.log("amount:", commitData.amount);
        console.log("reward:", commitData.reward);

        console.logBytes32(sigVerifier.hash(commitData));
    }

    /*//////////////////////////////////////////////////////////////
                               INITIALISER
    //////////////////////////////////////////////////////////////*/

    function test_InitializerSetsNameAndVersion() public {
        assertEq(sigVerifier.getEIP712Name(), "MagicSigner");
        assertEq(sigVerifier.getVersion(), "1");
    }

    function test_RevertOnReinitialise() public {
        vm.prank(user);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        MockLuckyBuySignatureVerifierUpgradeable(address(sigVerifier)).initialize("MagicSigner", "1");
    }

    /*//////////////////////////////////////////////////////////////
                            SIGNATURE VERIFIER
    //////////////////////////////////////////////////////////////*/

    function testOrderHash2() public {
        address testTo = 0x0000000000000068F116a894984e2DB1123eB395;
        uint256 testValue = 20000000000000;
        bytes
            memory testData = hex"e7acab24000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000006e00000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000e052c9cfe22b5974dc821cba907f1daac7979c9400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000052000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000004c00500000ad104d7dbd00e3ae0a5c00560c000000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067cf174c0000000000000000000000000000000000000000000000000000000067d30b520000000000000000000000000000000000000000000000000000000000000000360c6ebe000000000000000000000000000000000000000033c2f8be86434b860000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000415a82e77642113701fe190554fddd7701c3b262000000000000000000000000000000000000000000000000000000000000206700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001101eedb780000000000000000000000000000000000000000000000000000001101eedb78000000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174876e800000000000000000000000000000000000000000000000000000000174876e8000000000000000000000000000000a26b00c1f0df003000390027140000faa719000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001176592e000000000000000000000000000000000000000000000000000000001176592e0000000000000000000000000005d0d2229c75f13cb989bc5b48966f19170e879c600000000000000000000000000000000000000000000000000000000000000e3937d7c3c7bad7cce0343e161705a5cb7174c4b10366d4501fc48bddb0466cef2657da121e80b7e9e8dc7580fd672177fc431ed96a3bfdaa8160c2619c247a10500000f5555e3c5fe5d036886ef457c6099624d36106d0a7a5963416e619e0dd70ef5afb6c923cf26789f0637c18b43ad5509d0ad354daf1410a3574aebf3e5f420371f2e2b5d598b446140dc14a0a0ab918e458caf518097b88a1e2bacf2641058740982e1363e69190f9b615b749711f5529e4ba38f45955fa7a0e2ed592e3d6a88544d8707848281e625f61622aeeccb0af71cff27e28538a891165116f41d8c6dbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001d4da48b1ebc9d95";
        address testTokenAddress = 0x415A82E77642113701FE190554fDDD7701c3B262; // Example token address
        uint256 testTokenId = 8295;

        bytes32 digest = sigVerifier.hashOrder(
            testTo,
            testValue,
            testData,
            testTokenAddress,
            testTokenId
        );
        console.log("Digest:");
        console.logBytes32(digest);
    }

    function _signCommit(
        LuckyBuySignatureVerifierUpgradeable.CommitData memory commit
    ) internal returns (bytes memory signature) {
        // Sign voucher with cosigner's private key
        bytes32 digest = sigVerifier.hash(commit);
        console.logBytes32(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function testHashConsistency() public {
        bytes32 hash1 = sigVerifier.hash(commitData);
        bytes32 hash2 = sigVerifier.hash(commitData);

        assertEq(hash1, hash2, "Hash function should be idempotent");
    }

    function testVerifyValidSignature() public {
        // Create a signature using the cosigner's private key
        bytes memory signature = _signCommit(commitData);

        // Verify the signature
        address recoveredSigner = sigVerifier.verify(commitData, signature);

        // The recovered signer should match our cosigner address
        assertEq(
            recoveredSigner,
            cosignerAddress,
            "Signature verification should recover the correct signer"
        );
    }

    function testVerifyModifiedCommitFails() public {
        // Sign the original commit data
        bytes memory signature = _signCommit(commitData);

        // Create a modified commit with a different id
        LuckyBuySignatureVerifierUpgradeable.CommitData memory modifiedCommit = commitData;
        modifiedCommit.id = 999;

        // Verify the signature with modified commit data
        address recoveredSigner = sigVerifier.verify(modifiedCommit, signature);

        // The recovered signer should not match our cosigner address
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Verification with modified commit data should fail"
        );
    }

    // Malleability tests
    function testVerifyDifferentCommitFields() public {
        // Test that each field of the commit data affects the signature

        // Original signature
        bytes memory originalSignature = _signCommit(commitData);

        // Test id field
        LuckyBuySignatureVerifierUpgradeable.CommitData memory modifiedCommit = commitData;
        modifiedCommit.id = commitData.id + 1;
        address recoveredSigner = sigVerifier.verify(
            modifiedCommit,
            originalSignature
        );
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing id should invalidate signature"
        );

        // Test receiver field
        modifiedCommit = commitData;
        modifiedCommit.receiver = address(0x1111);
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing receiver should invalidate signature"
        );

        // Test cosigner field
        modifiedCommit = commitData;
        modifiedCommit.cosigner = address(0x2222);
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing cosigner should invalidate signature"
        );

        // Test seed field
        modifiedCommit = commitData;
        modifiedCommit.seed = commitData.seed + 1;
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing seed should invalidate signature"
        );

        // Test counter field
        modifiedCommit = commitData;
        modifiedCommit.counter = commitData.counter + 1;
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing counter should invalidate signature"
        );

        // Test orderHash field
        modifiedCommit = commitData;
        modifiedCommit.orderHash = "0x1";
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing orderHash should invalidate signature"
        );

        // Test amount field
        modifiedCommit = commitData;
        modifiedCommit.amount = 1000;
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing amount should invalidate signature"
        );

        // Test reward field
        modifiedCommit = commitData;
        modifiedCommit.reward = 10000;
        recoveredSigner = sigVerifier.verify(modifiedCommit, originalSignature);
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Changing reward should invalidate signature"
        );
    }

    function testSignatureWithDifferentPrivateKey() public {
        // Create a different private key
        uint256 differentPrivateKey = 0x5678;
        address differentAddress = vm.addr(differentPrivateKey);

        // Sign with different private key
        bytes32 digest = sigVerifier.hash(commitData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(differentPrivateKey, digest);
        bytes memory differentSignature = abi.encodePacked(r, s, v);

        // Verify the signature
        address recoveredSigner = sigVerifier.verify(
            commitData,
            differentSignature
        );

        // Should recover the different address, not the original cosigner
        assertEq(
            recoveredSigner,
            differentAddress,
            "Should recover the correct different signer"
        );
        assertTrue(
            recoveredSigner != cosignerAddress,
            "Should not recover the original cosigner"
        );
    }

    function testMalformedSignature() public {
        // Create a malformed signature (too short)
        bytes memory malformedSignature = bytes("malformed");

        // This should revert when trying to decode the signature
        vm.expectRevert();
        sigVerifier.verify(commitData, malformedSignature);
    }

    function testOrderHash() public {
        bytes
            memory data = hex"e7acab24000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000006e00000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000e052c9cfe22b5974dc821cba907f1daac7979c9400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000052000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000004c00500000ad104d7dbd00e3ae0a5c00560c000000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067cf174c0000000000000000000000000000000000000000000000000000000067d30b520000000000000000000000000000000000000000000000000000000000000000360c6ebe000000000000000000000000000000000000000033c2f8be86434b860000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000415a82e77642113701fe190554fddd7701c3b262000000000000000000000000000000000000000000000000000000000000206700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001101eedb780000000000000000000000000000000000000000000000000000001101eedb78000000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174876e800000000000000000000000000000000000000000000000000000000174876e8000000000000000000000000000000a26b00c1f0df003000390027140000faa719000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001176592e000000000000000000000000000000000000000000000000000000001176592e0000000000000000000000000005d0d2229c75f13cb989bc5b48966f19170e879c600000000000000000000000000000000000000000000000000000000000000e3937d7c3c7bad7cce0343e161705a5cb7174c4b10366d4501fc48bddb0466cef2657da121e80b7e9e8dc7580fd672177fc431ed96a3bfdaa8160c2619c247a10500000f5555e3c5fe5d036886ef457c6099624d36106d0a7a5963416e619e0dd70ef5afb6c923cf26789f0637c18b43ad5509d0ad354daf1410a3574aebf3e5f420371f2e2b5d598b446140dc14a0a0ab918e458caf518097b88a1e2bacf2641058740982e1363e69190f9b615b749711f5529e4ba38f45955fa7a0e2ed592e3d6a88544d8707848281e625f61622aeeccb0af71cff27e28538a891165116f41d8c6dbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001d4da48b1ebc9d95";

        bytes32 digest = sigVerifier.hashOrder(
            0x0000000000000068F116a894984e2DB1123eB395,
            20000000000000 wei,
            data,
            0x415A82E77642113701FE190554fDDD7701c3B262,
            8295
        );
        console.log("Digest:");
        console.logBytes32(digest);
    }
}