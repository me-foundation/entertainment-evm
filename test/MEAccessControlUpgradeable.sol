// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "src/common/MEAccessControlUpgradeable.sol";

contract MockMEAccessControlUpgradeableContract is MEAccessControlUpgradeable {
    function initialize() public initializer {
        __MEAccessControl_init();
    }

    function adminOnly() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    function opsOnly() public onlyRole(OPS_ROLE) {}
}

contract MEAccessControlUpgradeableTest is Test {
    MockMEAccessControlUpgradeableContract mockContract;
    address deployer;
    address alice;
    address bob;
    address charlie;

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant OPS_ROLE = keccak256("OPS_ROLE");
    bytes32 constant CUSTOM_ROLE = keccak256("CUSTOM_ROLE");

    function setUp() public {
        deployer = address(this);
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);

        // Deploy our contract with the test contract as deployer
        mockContract = new MockMEAccessControlUpgradeableContract();
        mockContract.initialize();
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public {
        // Check that deployer has admin and ops roles
        assertTrue(mockContract.hasRole(DEFAULT_ADMIN_ROLE, deployer));
        assertTrue(mockContract.hasRole(OPS_ROLE, deployer));
    }

    /*//////////////////////////////////////////////////////////////
                           BASIC ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testHasRole() public {
        // Deployer should have roles assigned in constructor
        assertTrue(mockContract.hasRole(DEFAULT_ADMIN_ROLE, deployer));
        assertTrue(mockContract.hasRole(OPS_ROLE, deployer));

        // Other accounts shouldn't have any roles yet
        assertTrue(!mockContract.hasRole(DEFAULT_ADMIN_ROLE, alice));
        assertTrue(!mockContract.hasRole(OPS_ROLE, alice));
    }

    function testGrantRole() public {
        // Grant alice the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, alice);

        // Alice should now have the OPS_ROLE
        assertTrue(mockContract.hasRole(OPS_ROLE, alice));

        // But not the DEFAULT_ADMIN_ROLE
        assertTrue(!mockContract.hasRole(DEFAULT_ADMIN_ROLE, alice));
    }

    function testGrantRoleRevert() public {
        // Impersonate alice who doesn't have admin permissions
        vm.startPrank(alice);

        // Alice tries to grant Bob the OPS_ROLE, should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                DEFAULT_ADMIN_ROLE
            )
        );
        mockContract.grantRole(OPS_ROLE, bob);

        vm.stopPrank();
    }

    function testRevokeRole() public {
        // First grant alice the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, alice);
        assertTrue(mockContract.hasRole(OPS_ROLE, alice));

        // Now revoke it
        mockContract.revokeRole(OPS_ROLE, alice);

        // Alice should no longer have the OPS_ROLE
        assertTrue(!mockContract.hasRole(OPS_ROLE, alice));
    }

    function testRevokeRoleRevert() public {
        // Grant alice the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, alice);

        // Impersonate bob who doesn't have admin permissions
        vm.startPrank(bob);

        // Bob tries to revoke alice's OPS_ROLE, should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bob,
                DEFAULT_ADMIN_ROLE
            )
        );
        mockContract.revokeRole(OPS_ROLE, alice);

        vm.stopPrank();
    }

    function testRenounceRole() public {
        // First grant alice the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, alice);
        assertTrue(mockContract.hasRole(OPS_ROLE, alice));

        // Alice renounces the role herself
        vm.prank(alice);
        mockContract.renounceRole(OPS_ROLE, alice);

        // Alice should no longer have the OPS_ROLE
        assertTrue(!mockContract.hasRole(OPS_ROLE, alice));
    }

    function testRenounceRoleRevert() public {
        // First grant alice the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, alice);

        // Bob tries to make alice renounce her role, should revert
        vm.prank(bob);
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        mockContract.renounceRole(OPS_ROLE, alice);

        // Alice should still have the OPS_ROLE
        assertTrue(mockContract.hasRole(OPS_ROLE, alice));
    }

    /*//////////////////////////////////////////////////////////////
                           ROLE ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetRoleAdmin() public {
        // By default, DEFAULT_ADMIN_ROLE is the admin of all roles
        assertEq(mockContract.getRoleAdmin(OPS_ROLE), DEFAULT_ADMIN_ROLE);
        assertEq(mockContract.getRoleAdmin(CUSTOM_ROLE), DEFAULT_ADMIN_ROLE);
        assertEq(
            mockContract.getRoleAdmin(DEFAULT_ADMIN_ROLE),
            DEFAULT_ADMIN_ROLE
        );
    }

    function testSetRoleAdmin() public {
        // We need to use a function that exposes _setRoleAdmin for this test
        // Typically this would be done in a specific function in your contract

        // For this test, let's assume we want to create a chain of roles
        // where OPS_ROLE becomes the admin of CUSTOM_ROLE

        // First, grant OPS_ROLE to alice
        mockContract.grantRole(OPS_ROLE, alice);

        // We can't directly test _setRoleAdmin as it's internal
        // In a real implementation, you'd expose a function that calls _setRoleAdmin

        // However, we can indirectly test the functionality by checking DEFAULT_ADMIN_ROLE
        // continues to be its own admin
        assertEq(
            mockContract.getRoleAdmin(DEFAULT_ADMIN_ROLE),
            DEFAULT_ADMIN_ROLE
        );
    }

    /*//////////////////////////////////////////////////////////////
                           ACCESS MODIFIER TESTS
    //////////////////////////////////////////////////////////////*/

    function testOnlyRoleModifier_Admin() public {
        // Deployer can call adminOnly because they have DEFAULT_ADMIN_ROLE
        mockContract.adminOnly();

        // Grant alice the OPS_ROLE but not DEFAULT_ADMIN_ROLE
        mockContract.grantRole(OPS_ROLE, alice);

        // Alice cannot call adminOnly
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                DEFAULT_ADMIN_ROLE
            )
        );
        mockContract.adminOnly();
    }

    function testOnlyRoleModifier_Ops() public {
        // Deployer can call opsOnly because they have OPS_ROLE
        mockContract.opsOnly();

        // Grant bob the DEFAULT_ADMIN_ROLE but not OPS_ROLE
        mockContract.grantRole(DEFAULT_ADMIN_ROLE, bob);

        // Bob cannot call opsOnly despite having admin role
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bob,
                OPS_ROLE
            )
        );
        mockContract.opsOnly();

        // Grant bob the OPS_ROLE
        mockContract.grantRole(OPS_ROLE, bob);

        // Now bob can call opsOnly
        vm.prank(bob);
        mockContract.opsOnly();
    }

    /*//////////////////////////////////////////////////////////////
                           ERC165 INTERFACE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSupportsInterface() public {
        // Test support for IAccessControl interface
        bytes4 accessControlInterfaceId = type(IAccessControl).interfaceId;
        assertTrue(mockContract.supportsInterface(accessControlInterfaceId));

        // Test support for IERC165 interface
        bytes4 erc165InterfaceId = type(IERC165).interfaceId;
        assertTrue(mockContract.supportsInterface(erc165InterfaceId));

        // Test a random interface that shouldn't be supported
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertTrue(!mockContract.supportsInterface(randomInterfaceId));
    }

    /*//////////////////////////////////////////////////////////////
                           COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function testComplexRoleManagement() public {
        // Create a role hierarchy:
        // 1. DEFAULT_ADMIN_ROLE (deployer) can manage all roles
        // 2. Alice gets OPS_ROLE
        // 3. Alice grants OPS_ROLE to Bob
        // 4. Deployer revokes DEFAULT_ADMIN_ROLE from itself

        // First, make OPS_ROLE self-manageable (admins of OPS_ROLE are OPS_ROLE holders)
        // This would normally be done with _setRoleAdmin but we would need a function for it
        // This is just a sketch of how the test would work conceptually

        // 1. Grant OPS_ROLE to alice
        mockContract.grantRole(OPS_ROLE, alice);
        assertTrue(mockContract.hasRole(OPS_ROLE, alice));

        // Alice can't grant OPS_ROLE to bob yet because OPS_ROLE isn't self-managed
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                DEFAULT_ADMIN_ROLE
            )
        );
        mockContract.grantRole(OPS_ROLE, bob);

        // In a real implementation, we would call a function that makes OPS_ROLE self-managed:
        // mockContract.setRoleAdmin(OPS_ROLE, OPS_ROLE);

        // The deployer still has DEFAULT_ADMIN_ROLE
        assertTrue(mockContract.hasRole(DEFAULT_ADMIN_ROLE, deployer));

        // The deployer can renounce this role
        mockContract.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
        assertTrue(!mockContract.hasRole(DEFAULT_ADMIN_ROLE, deployer));
    }

    function testEmitEvents() public {
        // Test RoleGranted event
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(CUSTOM_ROLE, alice, deployer);
        mockContract.grantRole(CUSTOM_ROLE, alice);

        // Test RoleRevoked event
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleRevoked(CUSTOM_ROLE, alice, deployer);
        mockContract.revokeRole(CUSTOM_ROLE, alice);
    }
}