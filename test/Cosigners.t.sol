// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract TestLuckyBuyCosigners is Test {
    PRNG prng;
    LuckyBuy luckyBuy;
    address admin = address(0x1);
    address user = address(0x2);
    address cosigner1 = address(0x3);
    address cosigner2 = address(0x4);
    address feeReceiverManager = address(0x5);
    uint256 protocolFee = 0;
    uint256 flatFee = 0;

    // Events for testing
    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new LuckyBuy(
            protocolFee,
            flatFee,
            0,
            msg.sender,
            address(prng),
            feeReceiverManager
        );
        vm.stopPrank();
    }

    function testAddCosignerByAdmin() public {
        // Arrange
        vm.startPrank(admin);

        // Act & Assert - Check event emission
        vm.expectEmit(true, false, false, false);
        emit CosignerAdded(cosigner1);
        luckyBuy.addCosigner(cosigner1);

        // Assert - Check state change
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active after addition"
        );
        vm.stopPrank();
    }

    function testAddCosignerByNonAdmin() public {
        // Arrange
        vm.startPrank(user);

        // Act & Assert - Should revert due to missing admin role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                0x00
            )
        );
        luckyBuy.addCosigner(cosigner1);

        // Assert - State should remain unchanged
        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should not be active"
        );
        vm.stopPrank();
    }

    function testAddSameCosignerTwice() public {
        // Arrange
        vm.startPrank(admin);
        luckyBuy.addCosigner(cosigner1);
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active after first addition"
        );

        vm.expectRevert(LuckyBuy.AlreadyCosigner.selector);
        luckyBuy.addCosigner(cosigner1);

        // Assert - Should still be active
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should still be active after second addition"
        );
        vm.stopPrank();
    }

    function testAddMultipleCosigners() public {
        // Arrange
        vm.startPrank(admin);

        // Act - Add first cosigner
        luckyBuy.addCosigner(cosigner1);

        // Assert
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "First cosigner should be active"
        );
        assertFalse(
            luckyBuy.isCosigner(cosigner2),
            "Second cosigner should not be active yet"
        );

        // Act - Add second cosigner
        luckyBuy.addCosigner(cosigner2);

        // Assert
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "First cosigner should remain active"
        );
        assertTrue(
            luckyBuy.isCosigner(cosigner2),
            "Second cosigner should be active"
        );
        vm.stopPrank();
    }

    function testAddZeroAddressAsCosigner() public {
        vm.startPrank(admin);
        address zeroAddress = address(0);

        vm.expectRevert(LuckyBuy.InvalidCosigner.selector);
        luckyBuy.addCosigner(zeroAddress);

        vm.stopPrank();
    }

    function testRemoveCosignerByAdmin() public {
        // Arrange
        vm.startPrank(admin);
        luckyBuy.addCosigner(cosigner1);
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active before removal"
        );

        // Act & Assert - Check event emission
        vm.expectEmit(true, false, false, false);
        emit CosignerRemoved(cosigner1);
        luckyBuy.removeCosigner(cosigner1);

        // Assert - Check state change
        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be inactive after removal"
        );
        vm.stopPrank();
    }

    function testRemoveCosignerByNonAdmin() public {
        // Arrange
        vm.startPrank(admin);
        luckyBuy.addCosigner(cosigner1);
        vm.stopPrank();

        vm.startPrank(user);

        // Act & Assert - Should revert due to missing admin role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                0x00
            )
        );
        luckyBuy.removeCosigner(cosigner1);

        // Assert - State should remain unchanged
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should remain active"
        );
        vm.stopPrank();
    }

    function testRemoveNonExistentCosigner() public {
        vm.startPrank(admin);
        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should not be active initially"
        );

        vm.expectRevert(LuckyBuy.InvalidCosigner.selector);
        luckyBuy.removeCosigner(cosigner1);

        vm.stopPrank();
    }

    function testRemoveCosignerTwice() public {
        vm.startPrank(admin);
        luckyBuy.addCosigner(cosigner1);
        luckyBuy.removeCosigner(cosigner1);
        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be inactive after first removal"
        );

        vm.expectRevert(LuckyBuy.InvalidCosigner.selector);
        luckyBuy.removeCosigner(cosigner1);

        vm.stopPrank();
    }

    function testAddRemoveAddCosigner() public {
        vm.startPrank(admin);

        luckyBuy.addCosigner(cosigner1);
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active after addition"
        );

        luckyBuy.removeCosigner(cosigner1);
        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be inactive after removal"
        );

        luckyBuy.addCosigner(cosigner1);
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active after re-addition"
        );
        vm.stopPrank();
    }

    function testGrantRoleThenAddCosigner() public {
        address newAdmin = address(0x5);
        vm.startPrank(admin);
        luckyBuy.grantRole(0x00, newAdmin); // DEFAULT_ADMIN_ROLE is 0x00
        vm.stopPrank();

        vm.startPrank(newAdmin);
        luckyBuy.addCosigner(cosigner1);
        vm.stopPrank();

        // Assert
        assertTrue(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should be active after addition by new admin"
        );
    }

    function testRevokeRoleThenFailAddCosigner() public {
        address tempAdmin = address(0x6);
        vm.startPrank(admin);
        luckyBuy.grantRole(0x00, tempAdmin); // Grant DEFAULT_ADMIN_ROLE
        luckyBuy.revokeRole(0x00, tempAdmin); // Revoke DEFAULT_ADMIN_ROLE
        vm.stopPrank();

        vm.startPrank(tempAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                tempAdmin,
                0x00
            )
        );
        luckyBuy.addCosigner(cosigner1);
        vm.stopPrank();

        assertFalse(
            luckyBuy.isCosigner(cosigner1),
            "Cosigner should not be active"
        );
    }
}
