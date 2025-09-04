// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155MInitializableV1_0_2} from "src/common/interfaces/IERC1155MInitializableV1_0_2.sol";
import "../src/common/SignatureVerifier/LuckyBuySignatureVerifierUpgradeable.sol";
contract MockLuckyBuy is LuckyBuy {
    address public owner;
    constructor(
        uint256 protocolFee_,
        uint256 flatFee_,
        uint256 bulkCommitFee_,
        address feeReceiver_,
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
    {
        owner = msg.sender;
    }

    function setIsFulfilled(uint256 commitId_, bool isFulfilled_) public {
        isFulfilled[commitId_] = isFulfilled_;
    }

    function transferOwnership(address newOwner) public {
        owner = newOwner;
    }
}

// Some of these changes may be redundant, e.g. owner/admin but we are quickly swapping out implementations right now
contract MockERC1155 is ERC1155, IERC1155MInitializableV1_0_2 {
    address public admin;
    address public owner;
    modifier onlyAuthorizedMinter() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(string memory uri_, address admin_) ERC1155(uri_) {
        admin = admin_;
        owner = msg.sender;
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) public onlyAuthorizedMinter {
        _mint(to, id, amount, "");
    }
    function ownerMint(
        address to,
        uint256 tokenId,
        uint32 qty
    ) external onlyAuthorizedMinter {
        _mint(to, tokenId, qty, "");
    }

    function transferOwnership(address newOwner) public onlyOwner {
        owner = newOwner;
    }
}

contract TestLuckyBuyOpenEdition is Test {
    PRNG prng;
    MockLuckyBuy luckyBuy;
    MockERC1155 openEditionToken;
    address admin = address(0x1);
    address user = address(0x2);
    address feeReceiverManager = address(0x3);

    uint256 constant COSIGNER_PRIVATE_KEY = 1234;
    address cosigner;
    uint256 protocolFee = 0;
    uint256 flatFee = 0;

    uint256 seed = 12345;
    address marketplace = address(0);
    uint256 orderAmount = 1 ether;
    bytes32 orderData = hex"00";
    address orderToken = address(0);
    uint256 orderTokenId = 0;
    bytes32 orderHash = hex"";
    uint256 amount = 1 ether;
    uint256 reward = 10 ether; // 10% odds

    function setUp() public {
        vm.startPrank(admin);
        prng = new PRNG();
        luckyBuy = new MockLuckyBuy(
            protocolFee,
            flatFee,
            0,
            msg.sender,
            address(prng),
            feeReceiverManager
        );
        vm.deal(admin, 1000000 ether);
        vm.deal(user, 100000 ether);

        // set luckybuy as the minter
        openEditionToken = new MockERC1155("", address(luckyBuy));
        openEditionToken.transferOwnership(address(luckyBuy));

        (bool success, ) = address(luckyBuy).call{value: 10000 ether}("");
        require(success, "Failed to deploy contract");

        // Set up cosigner with known private key
        cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
        // Add a cosigner for testing
        luckyBuy.addCosigner(cosigner);
        // Mint 1 open edition token id 1 on failures
        luckyBuy.setOpenEditionToken(address(openEditionToken), 1, 1);
        vm.stopPrank();
    }

    function signCommit(
        uint256 commitId,
        address receiver,
        uint256 seed,
        uint256 counter,
        bytes32 orderHash,
        uint256 amount,
        uint256 reward
    ) public returns (bytes memory) {
        // Create the commit data struct
        LuckyBuySignatureVerifierUpgradeable.CommitData memory commitData = LuckyBuySignatureVerifierUpgradeable.CommitData({
                id: commitId,
                receiver: receiver,
                cosigner: cosigner,
                seed: seed,
                counter: counter,
                orderHash: orderHash,
                amount: amount,
                reward: reward
            });

        // Get the digest using the LuckyBuy contract's hash function
        bytes32 digest = luckyBuy.hash(commitData);

        // Sign the digest with the cosigner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, digest);

        // Return the signature
        return abi.encodePacked(r, s, v);
    }

    function testOpenEdition() public {
        // out of base points
        vm.prank(admin);

        uint256 commitAmount = 0.01 ether;
        uint256 rewardAmount = 1 ether;
        // Create order hash for a simple ETH transfer - this stays the same for all plays
        bytes32 orderHash = luckyBuy.hashOrder(
            address(0), // to address(0)
            rewardAmount, // amount 1 ether (reward amount)
            "", // no data
            address(0), // no token
            0 // no token id
        );

        vm.startPrank(user);

        // Create commit
        uint256 commitId = luckyBuy.commit{value: commitAmount}(
            user, // receiver
            cosigner, // cosigner
            seed, // random seed
            orderHash, // order hash we just created
            rewardAmount // reward amount (10x the commit for 10% odds)
        );
        vm.stopPrank();

        (
            uint256 _id,
            address _receiver,
            address _cosigner,
            uint256 _seed,
            uint256 _counter,
            bytes32 _orderHash,
            uint256 _amount,
            uint256 _reward
        ) = luckyBuy.luckyBuys(commitId);

        // Get the counter for this commit
        uint256 counter = 0;

        // Sign the commit
        bytes memory signature = signCommit(
            commitId,
            user,
            seed,
            counter,
            orderHash,
            commitAmount,
            rewardAmount
        );

        // Fulfill the commit as cosigner
        vm.startPrank(cosigner);
        luckyBuy.fulfill(
            commitId,
            address(0), // marketplace
            "", // orderData
            rewardAmount, // orderAmount
            address(0), // token
            0, // tokenId
            signature,
            address(0),
            0
        );
        vm.stopPrank();

        console.log(luckyBuy.PRNG().rng(signature));
        // log the recovered cosigner

        console.log(cosigner);
        console.log(_cosigner);
        assertEq(openEditionToken.balanceOf(address(user), 1), 1);
    }
    function testOpenEditionTransferFail() public {
        // out of base points

        vm.prank(admin);
        luckyBuy.setOpenEditionToken(address(1), 1, 1);

        uint256 commitAmount = 0.01 ether;
        uint256 rewardAmount = 1 ether;
        // Create order hash for a simple ETH transfer - this stays the same for all plays
        bytes32 orderHash = luckyBuy.hashOrder(
            address(0), // to address(0)
            rewardAmount, // amount 1 ether (reward amount)
            "", // no data
            address(0), // no token
            0 // no token id
        );

        vm.startPrank(user);

        // Create commit
        uint256 commitId = luckyBuy.commit{value: commitAmount}(
            user, // receiver
            cosigner, // cosigner
            seed, // random seed
            orderHash, // order hash we just created
            rewardAmount // reward amount (10x the commit for 10% odds)
        );
        vm.stopPrank();

        (
            uint256 _id,
            address _receiver,
            address _cosigner,
            uint256 _seed,
            uint256 _counter,
            bytes32 _orderHash,
            uint256 _amount,
            uint256 _reward
        ) = luckyBuy.luckyBuys(commitId);

        // Get the counter for this commit
        uint256 counter = 0;

        // Sign the commit
        bytes memory signature = signCommit(
            commitId,
            user,
            seed,
            counter,
            orderHash,
            commitAmount,
            rewardAmount
        );

        // Fulfill the commit
        vm.startPrank(user);
        // This revert happens because there is no code at the address. The error will be different in different cases. E.g. bad address vs no balance
        vm.expectRevert();
        luckyBuy.fulfill(
            commitId,
            address(0), // marketplace
            "", // orderData
            rewardAmount, // orderAmount
            address(0), // token
            0, // tokenId
            signature,
            address(0),
            0
        );
        vm.stopPrank();

        assertEq(openEditionToken.balanceOf(address(user), 1), 0);
    }

    // This is a very obtuse test.
    // LuckyBuy Contract is the owner of the open edition token
    // The owner of LuckyBuy Contract can tell LuckyBuy Contract to transfer ownership of the open edition token
    // OwnerOf -> LuckyBuyContract
    // LuckyBuyContract is OwnerOf -> OpenEditionToken
    function testOpenEditionContractTransfer() public {
        assertEq(openEditionToken.owner(), address(luckyBuy));

        vm.prank(admin);
        luckyBuy.transferOpenEditionContractOwnership(address(user));
        // luckyBuyOwner is still the same.
        assertEq(openEditionToken.owner(), address(user));
    }
}
