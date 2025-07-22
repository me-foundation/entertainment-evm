// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/common/TokenRescuer.sol";
import "forge-std/interfaces/IERC20.sol";
import "forge-std/interfaces/IERC721.sol";
import "forge-std/interfaces/IERC1155.sol";
import "../src/common/MEAccessControlUpgradeable.sol";
import {Errors} from "../src/common/Errors.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    string public name = "Mock ERC20";
    string public symbol = "M20";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) public {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock ERC721 token for testing
contract MockERC721 is IERC721 {
    string public name = "Mock ERC721";
    string public symbol = "M721";
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) private _getApproved;
    mapping(address => mapping(address => bool)) private _isApprovedForAll;

    function mint(address to, uint256 tokenId) public {
        ownerOf[tokenId] = to;
        balanceOf[to]++;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external payable {
        require(ownerOf[tokenId] == from, "Not owner");
        require(
            msg.sender == from ||
                msg.sender == address(this) ||
                msg.sender == _getApproved[tokenId] ||
                _isApprovedForAll[from][msg.sender],
            "Not approved"
        );
        ownerOf[tokenId] = to;
        balanceOf[from]--;
        balanceOf[to]++;
    }

    function approve(address to, uint256 tokenId) external payable {
        require(ownerOf[tokenId] == msg.sender, "Not owner");
        _getApproved[tokenId] = to;
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _getApproved[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _isApprovedForAll[msg.sender][operator] = approved;
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool) {
        return _isApprovedForAll[owner][operator];
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external payable {
        this.transferFrom{value: msg.value}(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata
    ) external payable {
        this.transferFrom{value: msg.value}(from, to, tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return interfaceId == type(IERC721).interfaceId;
    }
}

// Mock ERC1155 token for testing
contract MockERC1155 is IERC1155 {
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _isApprovedForAll;

    function mint(address to, uint256 id, uint256 amount) public {
        _balances[id][to] += amount;
    }

    function balanceOf(
        address owner,
        uint256 id
    ) external view returns (uint256) {
        return _balances[id][owner];
    }

    function balanceOfBatch(
        address[] calldata owners,
        uint256[] calldata ids
    ) external view returns (uint256[] memory) {
        require(owners.length == ids.length, "Length mismatch");
        uint256[] memory batchBalances = new uint256[](owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            batchBalances[i] = _balances[ids[i]][owners[i]];
        }
        return batchBalances;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _isApprovedForAll[msg.sender][operator] = approved;
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool) {
        return _isApprovedForAll[owner][operator];
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata
    ) external {
        require(
            from == msg.sender || _isApprovedForAll[from][msg.sender],
            "Not approved"
        );
        _balances[id][from] -= amount;
        _balances[id][to] += amount;
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata
    ) external {
        require(
            from == msg.sender || _isApprovedForAll[from][msg.sender],
            "Not approved"
        );
        require(ids.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            _balances[ids[i]][from] -= amounts[i];
            _balances[ids[i]][to] += amounts[i];
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return interfaceId == type(IERC1155).interfaceId;
    }
}

// Concrete implementation of TokenRescuer for testing
contract TestTokenRescuer is TokenRescuer, MEAccessControlUpgradeable {
    function initialize() public initializer {
        __MEAccessControl_init();
    }
    function rescueERC20Batch(
        address[] calldata tokens,
        address[] calldata to,
        uint256[] calldata amounts
    ) external onlyRole(RESCUE_ROLE) {
        _rescueERC20Batch(tokens, to, amounts);
    }

    function rescueERC721Batch(
        address[] calldata tokens,
        address[] calldata to,
        uint256[] calldata tokenIds
    ) external onlyRole(RESCUE_ROLE) {
        _rescueERC721Batch(tokens, to, tokenIds);
    }

    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata to,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyRole(RESCUE_ROLE) {
        _rescueERC1155Batch(tokens, to, tokenIds, amounts);
    }
}

contract TokenRescuerTest is Test {
    TestTokenRescuer public rescuer;
    MockERC20 public erc20;
    MockERC20 public erc20_2;
    MockERC721 public erc721;
    MockERC721 public erc721_2;
    MockERC1155 public erc1155;
    MockERC1155 public erc1155_2;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    bytes32 public constant RESCUE_ROLE = keccak256("RESCUE_ROLE");

    function setUp() public {
        rescuer = new TestTokenRescuer();
        rescuer.initialize();
        erc20 = new MockERC20();
        erc20_2 = new MockERC20();
        erc721 = new MockERC721();
        erc721_2 = new MockERC721();
        erc1155 = new MockERC1155();
        erc1155_2 = new MockERC1155();

        // Mint tokens to the rescuer contract
        erc20.mint(address(rescuer), 1000 ether);
        erc20_2.mint(address(rescuer), 500 ether);
        erc721.mint(address(rescuer), 1);
        erc721_2.mint(address(rescuer), 2);
        erc1155.mint(address(rescuer), 1, 100);
        erc1155_2.mint(address(rescuer), 2, 200);

        // Allow the rescuer contract to transfer its own tokens
        erc721.setApprovalForAll(address(rescuer), true);
        erc721_2.setApprovalForAll(address(rescuer), true);
        erc1155.setApprovalForAll(address(rescuer), true);
        erc1155_2.setApprovalForAll(address(rescuer), true);

        // Grant RESCUE_ROLE to alice for testing
        rescuer.addRescueUser(alice);
    }

    function test_RescueERC20Batch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(erc20);
        tokens[1] = address(erc20_2);
        to[0] = bob;
        to[1] = charlie;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        uint256 initialBalanceBob = erc20.balanceOf(bob);
        uint256 initialBalanceCharlie = erc20_2.balanceOf(charlie);

        rescuer.rescueERC20Batch(tokens, to, amounts);

        assertEq(erc20.balanceOf(bob), initialBalanceBob + amounts[0]);
        assertEq(
            erc20_2.balanceOf(charlie),
            initialBalanceCharlie + amounts[1]
        );
        assertEq(erc20.balanceOf(address(rescuer)), 1000 ether - amounts[0]);
        assertEq(erc20_2.balanceOf(address(rescuer)), 500 ether - amounts[1]);
    }

    function test_RescueERC20Batch_InvalidAddress() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(0);
        to[0] = bob;
        amounts[0] = 100 ether;

        vm.expectRevert(Errors.InvalidAddress.selector);
        rescuer.rescueERC20Batch(tokens, to, amounts);
    }

    function test_RescueERC20Batch_ZeroAmount() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(erc20);
        to[0] = bob;
        amounts[0] = 0;

        vm.expectRevert(Errors.InvalidAmount.selector);
        rescuer.rescueERC20Batch(tokens, to, amounts);
    }

    function test_RescueERC20Batch_ArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(erc20);
        tokens[1] = address(erc20_2);
        to[0] = bob;
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        rescuer.rescueERC20Batch(tokens, to, amounts);
    }

    function test_RescueERC721Batch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        tokens[0] = address(erc721);
        tokens[1] = address(erc721_2);
        to[0] = bob;
        to[1] = charlie;
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        rescuer.rescueERC721Batch(tokens, to, tokenIds);

        assertEq(erc721.ownerOf(tokenIds[0]), bob);
        assertEq(erc721_2.ownerOf(tokenIds[1]), charlie);
    }

    function test_RescueERC721Batch_InvalidAddress() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = address(0);
        to[0] = bob;
        tokenIds[0] = 1;

        vm.expectRevert(Errors.InvalidAddress.selector);
        rescuer.rescueERC721Batch(tokens, to, tokenIds);
    }

    function test_RescueERC721Batch_ArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](2);

        tokens[0] = address(erc721);
        tokens[1] = address(erc721_2);
        to[0] = bob;
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        rescuer.rescueERC721Batch(tokens, to, tokenIds);
    }

    function test_RescueERC1155Batch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(erc1155);
        tokens[1] = address(erc1155_2);
        to[0] = bob;
        to[1] = charlie;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 50;
        amounts[1] = 100;

        rescuer.rescueERC1155Batch(tokens, to, tokenIds, amounts);

        assertEq(MockERC1155(address(erc1155)).balanceOf(bob, 1), 50);
        assertEq(MockERC1155(address(erc1155_2)).balanceOf(charlie, 2), 100);
        assertEq(
            MockERC1155(address(erc1155)).balanceOf(address(rescuer), 1),
            50
        );
        assertEq(
            MockERC1155(address(erc1155_2)).balanceOf(address(rescuer), 2),
            100
        );
    }

    function test_RescueERC1155Batch_InvalidAddress() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(0);
        to[0] = bob;
        tokenIds[0] = 1;
        amounts[0] = 50;

        vm.expectRevert(Errors.InvalidAddress.selector);
        rescuer.rescueERC1155Batch(tokens, to, tokenIds, amounts);
    }

    function test_RescueERC1155Batch_ArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(erc1155);
        tokens[1] = address(erc1155_2);
        to[0] = bob;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        amounts[0] = 50;
        amounts[1] = 100;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        rescuer.rescueERC1155Batch(tokens, to, tokenIds, amounts);
    }

    // Role-based access control tests
    function test_RescueERC20Batch_OnlyRescueRole() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(erc20);
        to[0] = bob;
        amounts[0] = 100 ether;

        // Test that bob (without RESCUE_ROLE) cannot call the function
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "AccessControlUnauthorizedAccount(address,bytes32)"
                    )
                ),
                bob,
                RESCUE_ROLE
            )
        );
        rescuer.rescueERC20Batch(tokens, to, amounts);

        // Test that alice (with RESCUE_ROLE) can call the function
        vm.prank(alice);
        rescuer.rescueERC20Batch(tokens, to, amounts);
    }

    function test_RescueERC721Batch_OnlyRescueRole() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = address(erc721);
        to[0] = bob;
        tokenIds[0] = 1;

        // Test that bob (without RESCUE_ROLE) cannot call the function
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "AccessControlUnauthorizedAccount(address,bytes32)"
                    )
                ),
                bob,
                RESCUE_ROLE
            )
        );
        rescuer.rescueERC721Batch(tokens, to, tokenIds);

        // Test that alice (with RESCUE_ROLE) can call the function
        vm.prank(alice);
        rescuer.rescueERC721Batch(tokens, to, tokenIds);
    }

    function test_RescueERC1155Batch_OnlyRescueRole() public {
        address[] memory tokens = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(erc1155);
        to[0] = bob;
        tokenIds[0] = 1;
        amounts[0] = 50;

        // Test that bob (without RESCUE_ROLE) cannot call the function
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "AccessControlUnauthorizedAccount(address,bytes32)"
                    )
                ),
                bob,
                RESCUE_ROLE
            )
        );
        rescuer.rescueERC1155Batch(tokens, to, tokenIds, amounts);

        // Test that alice (with RESCUE_ROLE) can call the function
        vm.prank(alice);
        rescuer.rescueERC1155Batch(tokens, to, tokenIds, amounts);
    }
}