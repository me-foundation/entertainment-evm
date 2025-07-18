// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {LuckyBuyInitializable} from "../src/LuckyBuyInitializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPRNG} from "../src/common/interfaces/IPRNG.sol";
import {PRNG} from "../src/PRNG.sol";
import {LuckyBuy} from "../src/LuckyBuy.sol";
import {LuckyBuySignatureVerifierUpgradeable} from "../src/common/SignatureVerifier/LuckyBuySignatureVerifierUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract LuckyBuyProxy is ERC1967Proxy {
    constructor(
        address implementation,
        bytes memory data
    ) ERC1967Proxy(implementation, data) {}

    function upgradeTo(address newImplementation) public {
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) public {
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    function implementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}

contract MockLuckyBuyInitializable is LuckyBuyInitializable {
    function setIsFulfilled(uint256 commitId_, bool isFulfilled_) public {
        isFulfilled[commitId_] = isFulfilled_;
    }

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

contract MockLuckyBuy is LuckyBuy {
    constructor(
        uint256 protocolFee_,
        uint256 flatFee_,
        address feeReceiver_,
        uint256 bulkCommitFee_,
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

contract LuckyBuyInitializableProxyTest is Test {
    PRNG prng;
    MockLuckyBuyInitializable luckyBuy;
    MockLuckyBuy regularLuckyBuy;
    address admin = address(0x1);
    address user = address(0x2);
    address receiver = address(0x3);
    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    address cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
    address feeReceiverManager = address(0x4);
    uint256 protocolFee = 0;
    uint256 flatFee = 0;
    uint256 bulkCommitFee = 0;
    uint256 seed = 12345;
    bytes32 orderHash = hex"1234";
    uint256 amount = 1 ether;
    uint256 reward = 1.5 ether; // 66% odds

    // Add missing variables for fee split tests
    address marketplace = address(0);
    bytes orderData = hex"00";
    uint256 orderAmount = 1 ether;
    address orderToken = address(0);
    uint256 orderTokenId = 0;

    address bob = address(0xB0B);
    address charlie = address(0xC0FFEE);

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();

        // Deploy implementation
        MockLuckyBuyInitializable implementation = new MockLuckyBuyInitializable();

        // Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,uint256,uint256,uint256,address,address,address)",
            admin,
            protocolFee,
            flatFee,
            bulkCommitFee,
            admin,
            address(prng),
            feeReceiverManager
        );

        // Deploy proxy and cast the address for convenience
        LuckyBuyProxy proxy = new LuckyBuyProxy(
            address(implementation),
            initData
        );
        luckyBuy = MockLuckyBuyInitializable(payable(address(proxy)));

        vm.deal(admin, 100 ether);
        vm.deal(receiver, 100 ether);
        vm.deal(address(this), 100 ether);
        // Add a cosigner for testing
        luckyBuy.addCosigner(cosigner);
        // Deploy regular LuckyBuy for comparison
        regularLuckyBuy = new MockLuckyBuy(
            protocolFee,
            flatFee,
            admin,
            bulkCommitFee,
            address(prng),
            feeReceiverManager
        );
        regularLuckyBuy.addCosigner(cosigner);
        vm.stopPrank();
    }

    function test_DeployAndProxy() public {
        console.log("Proxy deployed at:", address(luckyBuy));
        console.log("owner", luckyBuy.hasRole(0x00, admin));
    }

    function test_InitialValuesMatch() public {
        // Compare initial values between regular and initializable contracts
        assertEq(
            luckyBuy.protocolFee(),
            regularLuckyBuy.protocolFee(),
            "protocolFee should match"
        );
        assertEq(
            luckyBuy.flatFee(),
            regularLuckyBuy.flatFee(),
            "flatFee should match"
        );
        assertEq(
            luckyBuy.feeReceiver(),
            regularLuckyBuy.feeReceiver(),
            "feeReceiver should match"
        );
        assertEq(
            address(luckyBuy.PRNG()),
            address(regularLuckyBuy.PRNG()),
            "PRNG should match"
        );
        assertTrue(
            luckyBuy.hasRole(0x00, admin),
            "initializable should have admin role"
        );
        assertTrue(
            regularLuckyBuy.hasRole(0x00, admin),
            "regular should have admin role"
        );
        assertTrue(
            luckyBuy.hasRole(keccak256("OPS_ROLE"), admin),
            "initializable should have ops role"
        );
        assertTrue(
            regularLuckyBuy.hasRole(keccak256("OPS_ROLE"), admin),
            "regular should have ops role"
        );
        assertTrue(
            luckyBuy.hasRole(keccak256("RESCUE_ROLE"), admin),
            "initializable should have rescue role"
        );
        assertTrue(
            regularLuckyBuy.hasRole(keccak256("RESCUE_ROLE"), admin),
            "regular should have rescue role"
        );
        assertTrue(
            luckyBuy.hasRole(
                luckyBuy.FEE_RECEIVER_MANAGER_ROLE(),
                feeReceiverManager
            ),
            "initializable should have fee receiver manager role"
        );
        assertTrue(
            regularLuckyBuy.hasRole(
                regularLuckyBuy.FEE_RECEIVER_MANAGER_ROLE(),
                feeReceiverManager
            ),
            "regular should have fee receiver manager role"
        );
    }

    function test_BehaviorParity_commit() public {
        // Check min/max reward values
        console.log("Initializable minReward:", luckyBuy.minReward());
        console.log("Initializable maxReward:", luckyBuy.maxReward());
        console.log("Regular minReward:", regularLuckyBuy.minReward());
        console.log("Regular maxReward:", regularLuckyBuy.maxReward());
        console.log("Reward:", reward);

        // Fund users
        vm.deal(user, amount * 2);
        vm.startPrank(user);

        // Commit on both contracts
        uint256 id1 = luckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
        uint256 id2 = regularLuckyBuy.commit{value: amount}(
            receiver,
            cosigner,
            seed,
            orderHash,
            reward
        );
        vm.stopPrank();

        // Compare state after commit
        assertEq(
            luckyBuy.luckyBuyCount(receiver),
            regularLuckyBuy.luckyBuyCount(receiver),
            "luckyBuyCount should match"
        );
        (
            uint256 idA,
            address recvA,
            address cosA,
            uint256 seedA,
            uint256 ctrA,
            bytes32 hashA,
            uint256 amtA,
            uint256 rewA
        ) = luckyBuy.luckyBuys(id1);
        (
            uint256 idB,
            address recvB,
            address cosB,
            uint256 seedB,
            uint256 ctrB,
            bytes32 hashB,
            uint256 amtB,
            uint256 rewB
        ) = regularLuckyBuy.luckyBuys(id2);
        assertEq(idA, idB, "commit id");
        assertEq(recvA, recvB, "receiver");
        assertEq(cosA, cosB, "cosigner");
        assertEq(seedA, seedB, "seed");
        assertEq(ctrA, ctrB, "counter");
        assertEq(hashA, hashB, "orderHash");
        assertEq(amtA, amtB, "amount");
        assertEq(rewA, rewB, "reward");
    }

    function test_DigestDifference() public {
        // Create the same commit data for both contracts
        LuckyBuySignatureVerifierUpgradeable.CommitData memory commitData = LuckyBuySignatureVerifierUpgradeable.CommitData({
                id: 0,
                receiver: receiver,
                cosigner: cosigner,
                seed: seed,
                counter: 0,
                orderHash: orderHash,
                amount: amount,
                reward: reward
            });

        // Get digests from both contracts
        bytes32 digest1 = luckyBuy.hash(commitData);
        bytes32 digest2 = regularLuckyBuy.hash(commitData);

        // The digests should be different because they have different EIP712 domains
        assertTrue(
            digest1 != digest2,
            "Digests should be different due to different EIP712 domains"
        );

        console.log("Initializable digest:", uint256(digest1));
        console.log("Regular digest:", uint256(digest2));
    }

    function test_EIP712DomainValues() public {
        // Get EIP712 domain values for both contracts
        (
            bytes1 fields1,
            string memory name1,
            string memory version1,
            uint256 chainId1,
            address verifyingContract1,
            bytes32 salt1,
            uint256[] memory extensions1
        ) = luckyBuy.eip712Domain();
        (
            bytes1 fields2,
            string memory name2,
            string memory version2,
            uint256 chainId2,
            address verifyingContract2,
            bytes32 salt2,
            uint256[] memory extensions2
        ) = regularLuckyBuy.eip712Domain();

        // Log the values
        console.log("Initializable name:", name1);
        console.log("Regular name:", name2);
        console.log("Initializable version:", version1);
        console.log("Regular version:", version2);
        console.log("Initializable chainId:", chainId1);
        console.log("Regular chainId:", chainId2);
        console.log("Initializable verifyingContract:", verifyingContract1);
        console.log("Regular verifyingContract:", verifyingContract2);
        console.log("Initializable salt:", uint256(salt1));
        console.log("Regular salt:", uint256(salt2));
        // Extensions are usually empty, but you can log their lengths
        console.log("Initializable extensions length:", extensions1.length);
        console.log("Regular extensions length:", extensions2.length);
    }

    function test_ProxyUpgrade() public {
        // Deploy a new implementation
        MockLuckyBuyInitializable newImplementation = new MockLuckyBuyInitializable();
        LuckyBuyProxy proxy = LuckyBuyProxy(payable(address(luckyBuy)));

        // Read current implementation
        address currentImpl = proxy.implementation();
        console.log("Current implementation:", currentImpl);
        assertTrue(currentImpl != address(0), "Implementation should be set");

        // Upgrade the proxy to the new implementation
        vm.startPrank(admin);
        proxy.upgradeTo(address(newImplementation));
        vm.stopPrank();

        // Read the implementation address after upgrade
        address impl = proxy.implementation();
        assertEq(
            impl,
            address(newImplementation),
            "Proxy should point to new implementation"
        );
        console.log("New implementation:", impl);
    }

    function test_DoubleInitializationReverts() public {
        // Deploy a new implementation and proxy
        MockLuckyBuyInitializable implementation = new MockLuckyBuyInitializable();

        // Deploy proxy without initialization
        LuckyBuyProxy proxy = new LuckyBuyProxy(address(implementation), "");
        MockLuckyBuyInitializable uninitializedLuckyBuy = MockLuckyBuyInitializable(
                payable(address(proxy))
            );

        // Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,uint256,uint256,uint256,address,address,address)",
            admin,
            protocolFee,
            flatFee,
            bulkCommitFee,
            admin,
            address(prng),
            feeReceiverManager
        );

        // First initialization should succeed
        vm.startPrank(admin);
        (bool success1, ) = address(uninitializedLuckyBuy).call(initData);
        assertTrue(success1, "First initialization should succeed");

        // Second initialization should fail
        (bool success2, ) = address(uninitializedLuckyBuy).call(initData);
        assertFalse(success2, "Second initialization should fail");
        vm.stopPrank();
    }
}