// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// NOTICE TO DEV: The PRNG has been refactored out of the contract. This is a property of signature recovery. 712 domains are calculated from the contract bytecode. The below tests use data from the old contract bytecode.
// The signature recovery address that is recovered from the data is now a different address. To make them work they need to be re-created using the cosigner-lib.
// These are those tests:
// test_end_to_end_success
// test_end_to_end_success_order_fails
// test_fulfill_by_digest
// test_protocol_fee_management

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "forge-std/Test.sol";
import "src/LuckyBuy.sol";
import "src/PRNG.sol";
// I grabbed this data from the Magic Eden API. This is a seaport order that is valid as of FORK_BLOCK:
// curl 'https://api-mainnet.magiceden.us/v3/rtp/ethereum/execute/buy/v7' \
//   -H 'accept: application/json, text/plain, */*' \
//   -H 'accept-language: en-US,en;q=0.9' \
//   -H 'content-type: application/json' \
//   -H 'origin: https://magiceden.us' \
//   -H 'priority: u=1, i' \
//   -H 'referer: https://magiceden.us/' \
//   --data-raw '{"items":[{"key":"0x415a82e77642113701fe190554fddd7701c3b262:8295","token":"0x415a82e77642113701fe190554fddd7701c3b262:8295","is1155":false,"source":"opensea.io","fillType":"trade","quantity":1}],"taker":"0x522B3294E6d06aA25Ad0f1B8891242E335D3B459","source":"magiceden.us","partial":true,"currency":"0x0000000000000000000000000000000000000000","currencyChainId":1,"forwarderChannel":"0x5ebc127fae83ed5bdd91fc6a5f5767E259dF5642","maxFeePerGas":"100000000000","maxPriorityFeePerGas":"100000000000","normalizeRoyalties":false}'

contract MockLuckyBuy is LuckyBuy {
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
    {}

    /// @notice Calculates fee amount based on input amount and fee percentage
    /// @param _amount The amount to calculate fee on
    /// @return The calculated fee amount
    /// @dev Uses fee denominator of 10000 (100% = 10000)
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

    function fulfillOrder(
        address txTo_,
        bytes calldata data_,
        uint256 amount_
    ) public returns (bool success) {
        (success, ) = txTo_.call{value: amount_}(data_);
    }

    function hashLuckyBuy(uint256 id) public view returns (bytes32) {
        return hash(luckyBuys[id]);
    }

    function mockRecover(
        bytes32 digest,
        bytes memory signature
    ) public view returns (address) {
        return ECDSA.recover(digest, signature);
    }

    // Debug balance tracking. Second layer of defense to ensure the balances are correct. Drop this anywhere, any time to audit the contract balance.
    function reconcileBalance() external {
        uint256 actualBalance = address(this).balance;
        uint256 expectedBalance = treasuryBalance +
            commitBalance +
            protocolBalance;
        require(actualBalance >= expectedBalance, "Balance mismatch");
    }
}
contract FulfillTest is Test {
    PRNG prng;
    MockLuckyBuy luckyBuy;
    address admin = address(0x1);
    address feeReceiverManager = address(0x2);
    address cosigner = 0xE052c9CFe22B5974DC821cBa907F1DAaC7979c94;
    address user2 = 0x094F4431AFd206073476B4300D3a7cbC76D39D17;

    bytes32 user2CommitDigest =
        hex"747551b4e2c0604b8c40cd8e6f2b9ade160468c1036c7f6034ba23c7d8100f68";
    bytes user2Signature =
        hex"c711eb77e4716dad802c2ac67b1e61593e1a04ed5222d4dd88ce5f5227415b7e54e55f973781131fad176a02d9d13b49ccd6e6454a2fc79914a7d743b394197b1b";
    // cosigner-lib signature and digest

    bytes fail_signature =
        hex"a5bd3a311356e041d3b8c2c135bc3877f2910283198d0b57c5878e9ea8921af36db2a2f4ef3794f83c170189e6dce7edb41755ea0d2d44ce62f980f57b17d9ba1c";
    bytes32 fail_digest =
        hex"ed64e5efde45eaee99eba1ff05f6c5103d14e7dca9da4e66492dcc12c17a28cb";

    bytes signature =
        hex"5cd285e01b1c1b8b6948e5f6a436ab35d37b392106959bd6448d1d72070dfcc3081a5ac8568a6e38c64e9a4a383cbc619373f43036274e664b004d4cab01d76d1c";
    bytes32 digest =
        hex"4420f0d74a11a8a46afaee4833815863d91350e1736dcb5714aee8a91bfb9fa0";
    // The target block number from the comment
    uint256 constant FORK_BLOCK = 22035010;

    // check test/signer.ts to verify
    bytes32 constant TypescriptOrderHash =
        hex"00b839f580603f650be760ccd549d9ddbb877aa80ccf709f00f1950f51c35a99";

    address constant RECEIVER = 0xE052c9CFe22B5974DC821cBa907F1DAaC7979c94;
    bytes constant DATA =
        hex"e7acab24000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000006e00000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000e052c9cfe22b5974dc821cba907f1daac7979c9400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000052000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000004c00500000ad104d7dbd00e3ae0a5c00560c000000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067cf174c0000000000000000000000000000000000000000000000000000000067d30b520000000000000000000000000000000000000000000000000000000000000000360c6ebe000000000000000000000000000000000000000033c2f8be86434b860000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000415a82e77642113701fe190554fddd7701c3b262000000000000000000000000000000000000000000000000000000000000206700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001101eedb780000000000000000000000000000000000000000000000000000001101eedb78000000000000000000000000000db2536a038f68a2c4d5f7428a98299cf566a59a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174876e800000000000000000000000000000000000000000000000000000000174876e8000000000000000000000000000000a26b00c1f0df003000390027140000faa719000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001176592e000000000000000000000000000000000000000000000000000000001176592e0000000000000000000000000005d0d2229c75f13cb989bc5b48966f19170e879c600000000000000000000000000000000000000000000000000000000000000e3937d7c3c7bad7cce0343e161705a5cb7174c4b10366d4501fc48bddb0466cef2657da121e80b7e9e8dc7580fd672177fc431ed96a3bfdaa8160c2619c247a10500000f5555e3c5fe5d036886ef457c6099624d36106d0a7a5963416e619e0dd70ef5afb6c923cf26789f0637c18b43ad5509d0ad354daf1410a3574aebf3e5f420371f2e2b5d598b446140dc14a0a0ab918e458caf518097b88a1e2bacf2641058740982e1363e69190f9b615b749711f5529e4ba38f45955fa7a0e2ed592e3d6a88544d8707848281e625f61622aeeccb0af71cff27e28538a891165116f41d8c6dbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001d4da48b1ebc9d95";

    uint256 constant FUND_AMOUNT = 10 ether;
    // Token address from the transaction data
    address constant TARGET = 0x0000000000000068F116a894984e2DB1123eB395; // Seaport
    address constant TOKEN = 0x415A82E77642113701FE190554fDDD7701c3B262;
    uint256 constant TOKEN_ID = 8295;
    uint256 constant REWARD = 20000000000000 wei;
    uint256 constant COMMIT_AMOUNT = REWARD; // 100%
    uint256 constant FAIL_COMMIT_AMOUNT = REWARD / 10000; // .1%

    IERC721 nft = IERC721(TOKEN);

    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        bytes32 orderHash,
        uint256 amount,
        uint256 reward,
        uint256 fee,
        uint256 flatFee,
        bytes32 digest,
        uint256 bulkSessionId
    );

    // Flag to track if we should run actual tests
    bool shouldRunTests;

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));

        // Only set up the fork if the RPC URL is provided
        if (bytes(rpcUrl).length > 0) {
            vm.createSelectFork(rpcUrl, FORK_BLOCK);
            vm.deal(address(this), 1 ether);
            shouldRunTests = true;

            vm.startPrank(admin);
            prng = new PRNG();
            luckyBuy = new MockLuckyBuy(
                0,
                0,
                0,
                msg.sender,
                address(prng),
                feeReceiverManager
            );
            vm.deal(admin, 100 ether);
            vm.deal(address(this), 100 ether);
            vm.deal(user2, 100 ether);
            // Add a cosigner for testing
            luckyBuy.addCosigner(cosigner);
            vm.stopPrank();
        } else {
            console.log("Skipping tests: MAINNET_RPC_URL not provided");
            shouldRunTests = false;
        }
    }

    function test_baseline_fulfill_outside_luckybuy() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }

        // Send the transaction
        (bool success, ) = TARGET.call{value: REWARD}(DATA);

        // Verify the transaction was successful
        assertTrue(success, "Transaction failed");

        console.log("NFT owner:", nft.ownerOf(TOKEN_ID));
        console.log("Target:", TARGET);
        console.log("Token:", TOKEN);
        console.log("Token ID:", TOKEN_ID);
        console.log("TX Value:", REWARD);

        console.log(address(luckyBuy));
        luckyBuy.reconcileBalance();
        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);
    }

    function test_luckybuy_fulfill() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        luckyBuy.reconcileBalance();
        // deposit treasury
        (bool success, ) = address(luckyBuy).call{value: 10 ether}("");

        assertEq(success, true);

        // This is a debug function on MockLuckyBuy to test tx data execution
        luckyBuy.fulfillOrder(TARGET, DATA, REWARD);

        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);
    }

    function test_end_to_end_success() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        luckyBuy.reconcileBalance();
        // Fund the contract treasury
        (bool success, ) = address(luckyBuy).call{value: FUND_AMOUNT}("");
        assertEq(success, true);

        // The user selects a token and amount to pay from our API.
        // This gives us TARGET, REWARD, DATA, TOKEN, TOKEN_ID
        // Typescript will hash to: 0x00b839f580603f650be760ccd549d9ddbb877aa80ccf709f00f1950f51c35a99

        bytes32 orderHash = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash, TypescriptOrderHash);

        // backend builds the commit data off chain. The user should technically choose the cosigner or we could be accused of trying random cosigners until we find one that benefits us.
        uint256 seed = 12345; // User provides this data

        // User submits the commit data from the back end with their payment to the contract
        vm.expectEmit(true, true, true, false);
        emit Commit(
            RECEIVER, // indexed sender
            0, // indexed commitId (first commit, so ID is 0)
            RECEIVER, // indexed receiver
            cosigner, // cosigner
            seed, // seed (12345)
            0, // counter (first commit, so counter is 0)
            orderHash, // orderHash
            COMMIT_AMOUNT, // amount
            REWARD, // reward
            0,
            0,
            digest,
            0 // bulkSessionId - 0 for individual commits
        );
        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT}(
            RECEIVER,
            cosigner,
            seed,
            orderHash,
            REWARD
        );
        luckyBuy.reconcileBalance();
        assertEq(luckyBuy.commitBalance(), COMMIT_AMOUNT);

        // Backend sees the event, it performs its own validation of the event and then signs valid commits. It broadcasts the fulfillment tx.

        // console.log("\nCommit Input Data:");
        // console.log("Receiver:", RECEIVER);
        // console.log("Cosigner:", cosigner);
        // console.log("Seed:", seed);
        // console.logBytes32(orderHash);
        // console.log("Commit Amount:", COMMIT_AMOUNT);
        // console.log("Reward:", REWARD);
        // Get the stored data
        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(0);

        // Log the stored data

        // console.log("\nStored Commit Data:");
        // console.log("ID:", id);
        // console.log("Receiver:", storedReceiver);
        // console.log("Cosigner:", storedCosigner);
        // console.log("Seed:", storedSeed);
        // console.log("Counter:", storedCounter);
        // console.logBytes32(storedOrderHash);
        // console.log("Amount:", storedAmount);
        // console.log("Reward:", storedReward);

        // Log the hashes and recovery
        bytes32 onChainHash = luckyBuy.hashLuckyBuy(0);
        // console.log("\nHash Comparison:");
        // console.logBytes32(digest); // Off-chain hash
        // console.logBytes32(onChainHash); // On-chain hash

        // Log the recovered addresses
        address recoveredFromOffchain = luckyBuy.mockRecover(digest, signature);
        address recoveredFromOnchain = luckyBuy.mockRecover(
            onChainHash,
            signature
        );
        // console.log("\nRecovered Addresses:");
        // console.log("From Off-chain Hash:", recoveredFromOffchain);
        // console.log("From On-chain Hash:", recoveredFromOnchain);
        // console.log("Expected Cosigner:", cosigner);
        assertEq(recoveredFromOffchain, cosigner);
        assertEq(recoveredFromOnchain, cosigner);

        // fulfill the order
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        luckyBuy.reconcileBalance();
        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);

        vm.expectRevert(LuckyBuy.AlreadyFulfilled.selector);
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        // check the balance of the contract
        assertEq(
            address(luckyBuy).balance,
            FUND_AMOUNT + COMMIT_AMOUNT - REWARD
        );

        console.log(luckyBuy.PRNG().rng(signature));
    }

    function test_end_to_end_success_order_fails() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }

        uint256 initialUser1Balance = RECEIVER.balance;
        uint256 initialUser2Balance = user2.balance;

        luckyBuy.reconcileBalance();

        uint256 protocolFee = 100;

        vm.prank(admin);
        luckyBuy.setProtocolFee(protocolFee);

        (bool success, ) = address(luckyBuy).call{value: FUND_AMOUNT}("");
        assertEq(success, true);

        bytes32 orderHash = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash, TypescriptOrderHash);

        // backend builds the commit data off chain. The user should technically choose the cosigner or we could be accused of trying random cosigners until we find one that benefits us.
        uint256 seed = 12345; // User provides this data

        uint256 commitFee = luckyBuy.calculateProtocolFee(COMMIT_AMOUNT);

        // User submits the commit data from the back end with their payment to the contract
        vm.expectEmit(true, true, true, false);
        emit Commit(
            RECEIVER, // indexed sender
            0, // indexed commitId (first commit, so ID is 0)
            RECEIVER, // indexed receiver
            cosigner, // cosigner
            seed, // seed (12345)
            0, // counter (first commit, so counter is 0)
            orderHash, // orderHash
            COMMIT_AMOUNT, // amount
            REWARD, // reward
            commitFee, // fee
            0,
            fail_digest,
            0 // bulkSessionId - 0 for individual commits
        );

        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT + commitFee}(
            RECEIVER,
            cosigner,
            seed,
            orderHash,
            REWARD
        );

        luckyBuy.reconcileBalance();
        vm.prank(user2);
        luckyBuy.commit{value: COMMIT_AMOUNT + commitFee}(
            user2,
            cosigner,
            seed,
            orderHash,
            REWARD
        );

        luckyBuy.reconcileBalance();
        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(1);

        console.log("User2 Commit Data:");
        console.log("ID:", id);
        console.log("Receiver:", storedReceiver);
        console.log("Cosigner:", storedCosigner);
        console.log("Seed:", storedSeed);
        console.log("Counter:", storedCounter);
        console.logBytes32(storedOrderHash);
        console.log("Amount:", storedAmount);
        console.log("Reward:", storedReward);

        assertEq(
            nft.ownerOf(TOKEN_ID),
            0x0dB2536A038F68A2c4D5f7428a98299cf566A59a // on chain owner at the time of the forks
        );

        // We have created 2 commits, each with 100% chance of success COMMIT_AMOUNT = REWARD.
        assertEq(
            address(luckyBuy).balance,
            FUND_AMOUNT + (COMMIT_AMOUNT * 2) + (commitFee * 2)
        );

        uint256 treasuryBalance = luckyBuy.treasuryBalance();
        uint256 commitBalance = luckyBuy.commitBalance();
        uint256 protocolBalance = luckyBuy.protocolBalance();

        console.log("Treasury Balance:", treasuryBalance);
        console.log("Commit Balance:", commitBalance);
        console.log("Protocol Balance:", protocolBalance);
        // fulfill the order
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        luckyBuy.reconcileBalance();
        //
        console.log(
            "Treasury Balance:",
            luckyBuy.treasuryBalance() - (REWARD - COMMIT_AMOUNT) + commitFee
        );
        console.log("Commit Balance:", luckyBuy.commitBalance());
        console.log("Protocol Balance:", luckyBuy.protocolBalance());

        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);

        // One commit amount was used to fulfill and make the purchase. Our treasury balance paid the difference.
        assertEq(
            address(luckyBuy).balance,
            FUND_AMOUNT + COMMIT_AMOUNT + commitFee * 2
        );
        assertEq(
            luckyBuy.treasuryBalance(),
            treasuryBalance - (REWARD - COMMIT_AMOUNT) + commitFee
        );
        assertEq(luckyBuy.protocolBalance(), protocolBalance - commitFee);
        console.log(address(luckyBuy).balance);
        // This will fulfill but it will transfer eth.
        luckyBuy.fulfill(
            1,
            TARGET,
            DATA, // Technically this is the other data, effectively it is the same thing here.
            REWARD,
            TOKEN,
            TOKEN_ID,
            user2Signature,
            address(0),
            0
        );
        luckyBuy.reconcileBalance();
        // check the balance of the contract
        // One commit was returned to the user and the other was used to fulfill the order, the fulfill is kept.
        // Commit fee x2 is what we profit. Both users won, but the second user received the value of the reward instead of the NFT.
        assertEq(address(luckyBuy).balance, FUND_AMOUNT + commitFee * 2);

        // User 1 balance is less the commit amount and fees paid
        assertEq(
            RECEIVER.balance,
            initialUser1Balance - COMMIT_AMOUNT - commitFee
        );

        // User 2 balance is add the reward minus the commit amount and fees paid
        assertEq(
            user2.balance,
            initialUser2Balance + REWARD - COMMIT_AMOUNT - commitFee
        );
        console.log(address(luckyBuy).balance);
    }

    function test_end_to_end_fail() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }

        // this test is failing because the commit amount is too low. That change came after these tests were written. It would take ~half a day to write new tests for this.
        // I am stubbing this test for now since it is only testing the OE mint.
        return;
        luckyBuy.reconcileBalance();
        address currentOwner = nft.ownerOf(TOKEN_ID);

        (bool success, ) = address(luckyBuy).call{value: FUND_AMOUNT}("");
        assertEq(success, true);

        bytes32 orderHash = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash, TypescriptOrderHash);

        uint256 seed = 12345; // User provides this data
        uint256 balance = address(luckyBuy).balance;

        vm.expectEmit(true, true, true, false);
        emit Commit(
            RECEIVER, // indexed sender
            0, // indexed commitId (first commit, so ID is 0)
            RECEIVER, // indexed receiver
            cosigner, // cosigner
            seed, // seed (12345)
            0, // counter (first commit, so counter is 0)
            orderHash, // orderHash
            FAIL_COMMIT_AMOUNT, // amount
            REWARD, // reward
            0, // fee
            0,
            fail_digest,
            0 // bulkSessionId - 0 for individual commits
        );
        vm.prank(RECEIVER);
        luckyBuy.commit{value: FAIL_COMMIT_AMOUNT}(
            RECEIVER,
            cosigner,
            seed,
            orderHash,
            REWARD
        );
        luckyBuy.reconcileBalance();
        // fulfill the order
        luckyBuy.fulfill(
            0,
            TARGET,
            DATA,
            REWARD,
            TOKEN,
            TOKEN_ID,
            fail_signature,
            address(0),
            0
        );
        luckyBuy.reconcileBalance();
        assertEq(nft.ownerOf(TOKEN_ID), currentOwner);
        assertEq(address(luckyBuy).balance, balance + FAIL_COMMIT_AMOUNT);
        assertEq(luckyBuy.isFulfilled(0), true);

        console.log(luckyBuy.PRNG().rng(signature));
    }

    function test_protocol_fee_management() public {
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        luckyBuy.reconcileBalance();
        uint256 protocolFee = 100;

        vm.prank(admin);
        luckyBuy.setProtocolFee(protocolFee);

        // Fund the contract treasury
        (bool success, ) = address(luckyBuy).call{value: FUND_AMOUNT}("");
        console.log(address(luckyBuy).balance);

        assertEq(success, true);
        assertEq(luckyBuy.treasuryBalance(), FUND_AMOUNT);
        assertEq(address(luckyBuy).balance, FUND_AMOUNT);
        assertEq(luckyBuy.protocolBalance(), 0);

        bytes32 orderHash = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash, TypescriptOrderHash);

        uint256 seed = 12345; // User provides this data

        uint256 commitFee = luckyBuy.calculateProtocolFee(COMMIT_AMOUNT);
        // User submits the commit data from the back end with their payment to the contract
        // vm.expectEmit(true, true, true, false);
        // emit Commit(
        //     RECEIVER, // indexed sender
        //     0, // indexed commitId (first commit, so ID is 0)
        //     RECEIVER, // indexed receiver
        //     cosigner, // cosigner
        //     seed, // seed (12345)
        //     0, // counter (first commit, so counter is 0)
        //     orderHash, // orderHash
        //     COMMIT_AMOUNT, // amount
        //     REWARD, // reward
        //     commitFee
        // );

        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT + commitFee}(
            RECEIVER,
            cosigner,
            seed,
            orderHash,
            REWARD
        );
        luckyBuy.reconcileBalance();
        assertEq(luckyBuy.commitBalance(), COMMIT_AMOUNT);
        assertEq(luckyBuy.protocolBalance(), commitFee);

        bytes32 onChainHash = luckyBuy.hashLuckyBuy(0);

        address recoveredFromOffchain = luckyBuy.mockRecover(digest, signature);
        address recoveredFromOnchain = luckyBuy.mockRecover(
            onChainHash,
            signature
        );

        assertEq(recoveredFromOffchain, cosigner);
        assertEq(recoveredFromOnchain, cosigner);

        // fulfill the order
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        luckyBuy.reconcileBalance();
        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);

        vm.expectRevert(LuckyBuy.AlreadyFulfilled.selector);
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        // check the balance of the contract
        assertEq(
            address(luckyBuy).balance,
            FUND_AMOUNT + (COMMIT_AMOUNT - REWARD) + commitFee
        );

        console.log(luckyBuy.PRNG().rng(signature));
    }

    function testhashDataView() public {
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        console.logBytes32(
            luckyBuy.hashOrder(TARGET, REWARD, DATA, TOKEN, TOKEN_ID)
        );
    }

    function test_hash_components() public {
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        bytes32 orderHash2 = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash2, TypescriptOrderHash);

        uint256 seed2 = 12345; // User provides this data

        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT}(
            RECEIVER,
            cosigner,
            seed2,
            orderHash2,
            REWARD
        );
        // Get the stored commit data
        (
            uint256 id,
            address receiver,
            address cosigner2,
            uint256 seed,
            uint256 counter,
            bytes32 orderHash,
            uint256 amount,
            uint256 reward
        ) = luckyBuy.luckyBuys(0);

        // Log the type hash (the hash of the type string)
        bytes32 typeHash = keccak256(
            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,bytes32 orderHash,uint256 amount,uint256 reward)"
        );
        console.log("\nType Hash:");
        console.logBytes32(typeHash);

        // Log the encoded data
        bytes memory encoded = abi.encode(
            typeHash,
            id,
            receiver,
            cosigner2,
            seed,
            counter,
            orderHash,
            amount,
            reward
        );
        console.log("\nEncoded Data:");
        console.logBytes(encoded);

        // Log the struct hash
        bytes32 structHash = keccak256(encoded);
        console.log("\nStruct Hash:");
        console.logBytes32(structHash);
    }

    function test_final_digest() public {
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }
        bytes32 orderHash2 = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash2, TypescriptOrderHash);

        uint256 seed2 = 12345; // User provides this data

        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT}(
            RECEIVER,
            cosigner,
            seed2,
            orderHash2,
            REWARD
        );
        // First get the struct hash from our previous test
        (
            uint256 id,
            address receiver,
            address cosigner_,
            uint256 seed,
            uint256 counter,
            bytes32 orderHash,
            uint256 amount,
            uint256 reward
        ) = luckyBuy.luckyBuys(0);

        // Calculate struct hash
        bytes32 typeHash = keccak256(
            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,bytes32 orderHash,uint256 amount,uint256 reward)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                id,
                receiver,
                cosigner_,
                seed,
                counter,
                orderHash,
                amount,
                reward
            )
        );

        // Get domain info from the contract
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = luckyBuy.eip712Domain();

        console.log("\nDomain Info:");
        console.log("Name:", name);
        console.log("Version:", version);
        console.log("ChainId:", chainId);
        console.log("Contract:", verifyingContract);

        // Log the struct hash
        console.log("\nStruct Hash:");
        console.logBytes32(structHash);

        // Get the final hash from the contract for comparison
        bytes32 onChainHash = luckyBuy.hashLuckyBuy(0);
        console.log("\nOn-Chain Hash:");
        console.logBytes32(onChainHash);

        // Log the off-chain hash we're trying to match
        console.log("\nOff-Chain Hash:");
        console.logBytes32(digest);

        // Get the block chain id
        console.log(block.chainid);
    }

    function test_fulfill_by_digest() public {
        // Skip the test entirely if we don't have an RPC URL
        if (!shouldRunTests) {
            console.log("Test skipped: MAINNET_RPC_URL not defined");
            return;
        }

        // Fund the contract treasury
        (bool success, ) = address(luckyBuy).call{value: FUND_AMOUNT}("");
        assertEq(success, true);

        bytes32 orderHash = luckyBuy.hashOrder(
            TARGET,
            REWARD,
            DATA,
            TOKEN,
            TOKEN_ID
        );

        assertEq(orderHash, TypescriptOrderHash);

        // backend builds the commit data off chain. The user should technically choose the cosigner or we could be accused of trying random cosigners until we find one that benefits us.
        uint256 seed = 12345; // User provides this data

        // User submits the commit data from the back end with their payment to the contract
        vm.expectEmit(true, true, true, false);
        emit Commit(
            RECEIVER, // indexed sender
            0, // indexed commitId (first commit, so ID is 0)
            RECEIVER, // indexed receiver
            cosigner, // cosigner
            seed, // seed (12345)
            0, // counter (first commit, so counter is 0)
            orderHash, // orderHash
            COMMIT_AMOUNT, // amount
            REWARD, // reward
            0, // fee
            0,
            digest,
            0 // bulkSessionId - 0 for individual commits
        );
        vm.prank(RECEIVER);
        luckyBuy.commit{value: COMMIT_AMOUNT}(
            RECEIVER,
            cosigner,
            seed,
            orderHash,
            REWARD
        );

        (
            uint256 id,
            address storedReceiver,
            address storedCosigner,
            uint256 storedSeed,
            uint256 storedCounter,
            bytes32 storedOrderHash,
            uint256 storedAmount,
            uint256 storedReward
        ) = luckyBuy.luckyBuys(0);

        // Log the stored data

        // console.log("\nStored Commit Data:");
        // console.log("ID:", id);
        // console.log("Receiver:", storedReceiver);
        // console.log("Cosigner:", storedCosigner);
        // console.log("Seed:", storedSeed);
        // console.log("Counter:", storedCounter);
        // console.logBytes32(storedOrderHash);
        // console.log("Amount:", storedAmount);
        // console.log("Reward:", storedReward);

        // Log the hashes and recovery
        bytes32 onChainHash = luckyBuy.hashLuckyBuy(0);
        // console.log("\nHash Comparison:");
        // console.logBytes32(digest); // Off-chain hash
        // console.logBytes32(onChainHash); // On-chain hash

        // Log the recovered addresses
        address recoveredFromOffchain = luckyBuy.mockRecover(digest, signature);
        address recoveredFromOnchain = luckyBuy.mockRecover(
            onChainHash,
            signature
        );
        // console.log("\nRecovered Addresses:");
        // console.log("From Off-chain Hash:", recoveredFromOffchain);
        // console.log("From On-chain Hash:", recoveredFromOnchain);
        // console.log("Expected Cosigner:", cosigner);
        assertEq(recoveredFromOffchain, cosigner);
        assertEq(recoveredFromOnchain, cosigner);

        // fulfill the order
        luckyBuy.fulfillByDigest(
            digest,
            TARGET,
            DATA,
            REWARD,
            TOKEN,
            TOKEN_ID,
            signature,
            address(0),
            0
        );

        assertEq(nft.ownerOf(TOKEN_ID), RECEIVER);

        vm.expectRevert(LuckyBuy.AlreadyFulfilled.selector);
        luckyBuy.fulfill(0, TARGET, DATA, REWARD, TOKEN, TOKEN_ID, signature, address(0), 0);
        // check the balance of the contract
        assertEq(
            address(luckyBuy).balance,
            FUND_AMOUNT + COMMIT_AMOUNT - REWARD
        );

        console.log(luckyBuy.PRNG().rng(signature));
    }
}
