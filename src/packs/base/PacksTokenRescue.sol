// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TokenRescuer} from "../../common/TokenRescuer.sol";

/// @title PacksTokenRescue
/// @notice Handles token rescue functions for Packs contract
/// @dev Abstract contract providing public interfaces for token rescue operations
abstract contract PacksTokenRescue is TokenRescuer {
    
    /// @dev Must be implemented by inheriting contract to check RESCUE_ROLE
    function _checkRescueRole() internal view virtual;
    
    // ============================================================
    // RESCUE FUNCTIONS (Token Recovery)
    // ============================================================

    function rescueERC20(address token, address to, uint256 amount) external {
        _checkRescueRole();
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        amounts[0] = amount;

        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721(address token, address to, uint256 tokenId) external {
        _checkRescueRole();
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;

        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155(address token, address to, uint256 tokenId, uint256 amount) external {
        _checkRescueRole();
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;
        amounts[0] = amount;

        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }

    function rescueERC20Batch(address[] calldata tokens, address[] calldata tos, uint256[] calldata amounts)
        external
    {
        _checkRescueRole();
        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721Batch(address[] calldata tokens, address[] calldata tos, uint256[] calldata tokenIds)
        external
    {
        _checkRescueRole();
        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external {
        _checkRescueRole();
        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }
}

