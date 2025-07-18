// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title MEAccessControlUpgradeable
 * @dev Contract that inherits from OpenZeppelin's AccessControlUpgradeable and exposes role management
 * functions at the top level for improved developer experience.
 */
contract MEAccessControlUpgradeable is AccessControlUpgradeable {
    bytes32 public constant OPS_ROLE = keccak256("OPS_ROLE");
    bytes32 public constant RESCUE_ROLE = keccak256("RESCUE_ROLE");

    error InvalidOwner();

    function __MEAccessControl_init() internal {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPS_ROLE, msg.sender);
        _grantRole(RESCUE_ROLE, msg.sender);
    }

    /// @notice Transfers admin rights to a new address. Admin functions are intentionally not paused
    /// @param newAdmin Address of the new admin
    function transferAdmin(
        address newAdmin
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert InvalidOwner();

        // Grant new admin the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _grantRole(OPS_ROLE, newAdmin);

        // Revoke old admin's roles
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _revokeRole(OPS_ROLE, msg.sender);
    }
    /// @notice Adds a new operations user
    /// @param user Address to grant operations role to
    function addOpsUser(address user) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPS_ROLE, user);
    }

    /// @notice Removes an operations user
    /// @param user Address to revoke operations role from
    function removeOpsUser(address user) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(OPS_ROLE, user);
    }

    /// @notice Adds a new rescue user
    /// @param user Address to grant rescue role to
    function addRescueUser(address user) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(RESCUE_ROLE, user);
    }

    /// @notice Removes a rescue user
    /// @param user Address to revoke rescue role from
    function removeRescueUser(
        address user
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(RESCUE_ROLE, user);
    }

    /**
     * @notice Explicitly re-expose the inherited functions to make them more discoverable
     * in developer tools and documentation.
     */

    // Just uncomment any methods you want to make obviously available:

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    // modifier onlyRole(bytes32 role) {
    //     _checkRole(role);
    //     _;
    // }

    /**
     * @dev Makes `hasRole` visible at the top level of our contract.
     * @param role The role to check
     * @param account The account to check the role for
     * @return bool True if account has the role
     */
    // function hasRole(bytes32 role, address account) public view override returns (bool) {
    //     return super.hasRole(role, account);
    // }

    /**
     * @dev Makes `getRoleAdmin` visible at the top level of our contract.
     * @param role The role to get the admin role for
     * @return bytes32 The admin role
     */
    // function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
    //     return super.getRoleAdmin(role);
    // }

    /**
     * @dev Makes `grantRole` visible at the top level of our contract.
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    // function grantRole(bytes32 role, address account) public override {
    //     super.grantRole(role, account);
    // }

    /**
     * @dev Makes `revokeRole` visible at the top level of our contract.
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    // function revokeRole(bytes32 role, address account) public override {
    //     super.revokeRole(role, account);
    // }

    /**
     * @dev Makes `renounceRole` visible at the top level of our contract.
     * @param role The role to renounce
     * @param callerConfirmation The confirmation address (must be the sender)
     */
    // function renounceRole(bytes32 role, address callerConfirmation) public override {
    //     super.renounceRole(role, callerConfirmation);
    // }
}