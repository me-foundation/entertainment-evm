// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/LuckyBuy.sol";
import "../src/PRNG.sol";
import "../src/common/MEAccessControlUpgradeable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
contract AccessControlTest is Test {
    PRNG public prng;
    LuckyBuy public luckyBuy;
    address public admin;
    address public ops;
    address public user;
    address public feeReceiverManager;

    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);
    event MaxRewardUpdated(uint256 oldMaxReward, uint256 newMaxReward);
    event ProtocolFeeUpdated(uint256 oldProtocolFee, uint256 newProtocolFee);

    function setUp() public {
        admin = makeAddr("admin");
        ops = makeAddr("ops");
        user = makeAddr("user");
        feeReceiverManager = makeAddr("feeReceiverManager");
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new LuckyBuy(
            0,
            0,
            0,
            msg.sender,
            address(prng),
            feeReceiverManager
        ); // Initialize with 0 protocol fee

        vm.stopPrank();
    }

    function test_InitialRoles() public {
        assertTrue(luckyBuy.hasRole(luckyBuy.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), admin));
        assertFalse(luckyBuy.hasRole(luckyBuy.DEFAULT_ADMIN_ROLE(), ops));
        assertFalse(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), ops));
    }

    function test_AddOpsUser() public {
        vm.startPrank(admin);
        luckyBuy.addOpsUser(ops);
        vm.stopPrank();

        assertTrue(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), ops));
        assertFalse(luckyBuy.hasRole(luckyBuy.DEFAULT_ADMIN_ROLE(), ops));
    }

    function test_RemoveOpsUser() public {
        vm.startPrank(admin);
        luckyBuy.addOpsUser(ops);
        luckyBuy.removeOpsUser(ops);
        vm.stopPrank();

        assertFalse(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), ops));
    }

    function test_TransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);
        luckyBuy.transferAdmin(newAdmin);
        vm.stopPrank();

        assertTrue(luckyBuy.hasRole(luckyBuy.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertTrue(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), newAdmin));
        assertFalse(luckyBuy.hasRole(luckyBuy.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(luckyBuy.hasRole(luckyBuy.OPS_ROLE(), admin));
    }

    function test_RevertWhen_NonAdminAddsOpsUser() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                luckyBuy.DEFAULT_ADMIN_ROLE()
            )
        );
        luckyBuy.addOpsUser(ops);
        vm.stopPrank();
    }

    function test_RevertWhen_NonAdminRemovesOpsUser() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                luckyBuy.DEFAULT_ADMIN_ROLE()
            )
        );
        luckyBuy.removeOpsUser(ops);
        vm.stopPrank();
    }

    function test_RevertWhen_NonAdminTransfersAdmin() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                luckyBuy.DEFAULT_ADMIN_ROLE()
            )
        );
        luckyBuy.transferAdmin(ops);
        vm.stopPrank();
    }

    function test_AdminCanAddCosigner() public {
        vm.startPrank(admin);
        vm.expectEmit(true, false, false, false);
        emit CosignerAdded(ops);
        luckyBuy.addCosigner(ops);
        vm.stopPrank();

        assertTrue(luckyBuy.isCosigner(ops));
    }

    function test_AdminCanRemoveCosigner() public {
        vm.startPrank(admin);
        luckyBuy.addCosigner(ops);
        vm.expectEmit(true, false, false, false);
        emit CosignerRemoved(ops);
        luckyBuy.removeCosigner(ops);
        vm.stopPrank();

        assertFalse(luckyBuy.isCosigner(ops));
    }

    function test_OpsCanSetMaxReward() public {
        vm.startPrank(admin);
        luckyBuy.addOpsUser(ops);
        vm.stopPrank();

        vm.startPrank(ops);
        uint256 newMaxReward = 50 ether;
        vm.expectEmit(false, false, false, true);
        emit MaxRewardUpdated(50 ether, newMaxReward);
        luckyBuy.setMaxReward(newMaxReward);
        vm.stopPrank();

        assertEq(luckyBuy.maxReward(), newMaxReward);
    }

    function test_OpsCanSetProtocolFee() public {
        vm.startPrank(admin);
        luckyBuy.addOpsUser(ops);
        vm.stopPrank();

        vm.startPrank(ops);
        uint256 newFee = 500; // 5%
        vm.expectEmit(false, false, false, true);
        emit ProtocolFeeUpdated(0, newFee);
        luckyBuy.setProtocolFee(newFee);
        vm.stopPrank();

        assertEq(luckyBuy.protocolFee(), newFee);
    }

    function test_RevertWhen_NonOpsSetMaxReward() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                luckyBuy.OPS_ROLE()
            )
        );
        luckyBuy.setMaxReward(50 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOpsSetProtocolFee() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                luckyBuy.OPS_ROLE()
            )
        );
        luckyBuy.setProtocolFee(500);
        vm.stopPrank();
    }

    function test_RevertWhen_ProtocolFeeExceedsBasePoints() public {
        vm.startPrank(admin);
        luckyBuy.addOpsUser(ops);
        vm.stopPrank();

        vm.startPrank(ops);
        vm.expectRevert(LuckyBuy.InvalidProtocolFee.selector);
        luckyBuy.setProtocolFee(10001); // Base points is 10000
        vm.stopPrank();
    }
}
