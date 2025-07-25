// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PacksInitializable} from "../src/PacksInitializable.sol";
import {Packs} from "../src/Packs.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PRNG} from "../src/PRNG.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract PacksProxy is ERC1967Proxy {
    constructor(
        address implementation,
        bytes memory data
    ) ERC1967Proxy(implementation, data) {}

    function implementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}

contract MockPacksInitializable is PacksInitializable {
    function setIsFulfilled(uint256 commitId_, bool isFulfilled_) public {
        isFulfilled[commitId_] = isFulfilled_;
    }

    function setIsCancelled(uint256 commitId_, bool isCancelled_) public {
        isCancelled[commitId_] = isCancelled_;
    }
}

contract PacksInitializableProxyTest is Test {
    PRNG prng;
    MockPacksInitializable packs;
    address admin = address(0x1);
    address user = address(0x2);
    uint256 constant RECEIVER_PRIVATE_KEY = 5678; // Known private key for receiver
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant OPS_ROLE = keccak256("OPS_ROLE");

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();

        // Deploy implementation
        MockPacksInitializable implementation = new MockPacksInitializable();

        // Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)", admin, address(0x5), address(prng), address(0x4)
        );

        // Deploy proxy and cast the address for convenience
        PacksProxy proxy = new PacksProxy(
            address(implementation),
            initData
        );
        packs = MockPacksInitializable(payable(address(proxy)));
        vm.stopPrank();
    }

    function test_DeployAndProxy() public {
        console.log("Proxy deployed at:", address(packs));
        console.log("owner", packs.hasRole(0x00, admin));
    }

    function test_ProxyUpgrade() public {
        // Deploy a new implementation
        MockPacksInitializable newImplementation = new MockPacksInitializable();
        PacksProxy proxy = PacksProxy(payable(address(packs)));

        // Read current implementation
        address currentImpl = proxy.implementation();
        console.log("Current implementation:", currentImpl);
        assertTrue(currentImpl != address(0), "Implementation should be set");

        // Upgrade the proxy to the new implementation using the implementation's upgrade function
        vm.startPrank(admin);
        PacksInitializable(payable(address(packs))).upgradeToAndCall(address(newImplementation), "");
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
        MockPacksInitializable implementation = new MockPacksInitializable();

        // Deploy proxy without initialization
        PacksProxy proxy = new PacksProxy(address(implementation), "");
        MockPacksInitializable uninitializedPacks = MockPacksInitializable(
                payable(address(proxy))
            );

        // Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)",
            admin,
            address(0x5),
            address(prng),
            address(0x4)
        );

        // First initialization should succeed
        vm.startPrank(admin);
        (bool success1, ) = address(uninitializedPacks).call(initData);
        assertTrue(success1, "First initialization should succeed");

        // Second initialization should fail
        (bool success2, ) = address(uninitializedPacks).call(initData);
        assertFalse(success2, "Second initialization should fail");
        vm.stopPrank();
    }

    function testRevertOnReinitialise() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        MockPacksInitializable(payable(address(packs))).initialize(
            admin, address(0x5), address(prng), address(0x4)
        );
    }

    function testUpgradeSecurity() public {
        // Test that only admin can upgrade - using UUPS pattern
        address newImplementation = address(new MockPacksInitializable());

        // Test that non-admin cannot upgrade
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user,
                DEFAULT_ADMIN_ROLE
            )
        );
        PacksInitializable(payable(address(packs))).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        // Test that admin can upgrade (this should succeed)
        vm.startPrank(admin);
        PacksInitializable(payable(address(packs))).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }
}
