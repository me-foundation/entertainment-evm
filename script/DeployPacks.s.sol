// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/PacksInitializable.sol";
import "../src/PRNG.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployPacks is Script {
    address public constant fundsReceiver = 0x2918F39540df38D4c33cda3bCA9edFccd8471cBE;
    address public constant fundsReceiverManager = 0x7C51fAEe5666B47b2F7E81b7a6A8DEf4C76D47E3;

    function run() external {
        // Load deployer private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PACKS_DEPLOYER_PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);
        console.log("Admin", admin);

        // print balance of admin
        console.log("Admin balance", admin.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PRNG dependency
        PRNG prng = new PRNG();
        console.log("PRNG", address(prng));

        // 2. Deploy Packs implementation (logic contract)
        PacksInitializable implementation = new PacksInitializable();
        console.log("Implementation", address(implementation));

        // 3. Prepare initializer calldata
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)",
            admin, // initialOwner_
            fundsReceiver, // fundsReceiver_
            address(prng), // prng_
            fundsReceiverManager // fundsReceiverManager_
        );

        // 4. Deploy ERC1967 proxy pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy", address(proxy));

        vm.stopBroadcast();
    }
}
