// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {LuckyBuyInitializable} from "../src/LuckyBuyInitializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LuckyBuyInitializableProxyTest is Test {
    address public owner = address(0x1);
    address public feeReceiver = address(0x2);
    address public prng = address(0x3);
    address public feeReceiverManager = address(0x4);

    function test_DeployAndProxy() public {
        LuckyBuyInitializable implementation = new LuckyBuyInitializable();
        bytes memory initData = abi.encodeWithSelector(
            LuckyBuyInitializable.initialize.selector,
            address(0x1),
            100,
            0.01 ether,
            address(0x2),
            address(0x3),
            address(0x4)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        LuckyBuyInitializable proxyContract = LuckyBuyInitializable(
            payable(address(proxy))
        );
        console.log("Proxy contract at:", address(proxyContract));

        console.log("owner", proxyContract.hasRole(0x00, owner));

        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = proxyContract.eip712Domain();
        console.log("name", name);
        console.log("version", version);
        console.log("chainId", chainId);
        console.log("verifyingContract", verifyingContract);
    }
}
