// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/lucky_buy/LuckyBuyInitializable.sol";

contract UpgradeLuckyBuy is Script {
    function run(address proxyAddress) external {
        _run(proxyAddress, address(0), bytes(""));
    }

    function run(address proxyAddress, address newImplementation) external {
        _run(proxyAddress, newImplementation, bytes(""));
    }

    function run(address proxyAddress, address newImplementation, bytes memory upgradeCallData) external {
        _run(proxyAddress, newImplementation, upgradeCallData);
    }

    function run() external {
        address proxyAddress = vm.envAddress("LUCKYBUY_PROXY_ADDRESS");

        address newImplementation;
        try vm.envAddress("LUCKYBUY_NEW_IMPLEMENTATION") returns (address existingImpl) {
            newImplementation = existingImpl;
        } catch {}

        bytes memory upgradeCallData;
        try vm.envBytes("LUCKYBUY_UPGRADE_CALLDATA") returns (bytes memory callData) {
            upgradeCallData = callData;
        } catch {}

        _run(proxyAddress, newImplementation, upgradeCallData);
    }

    function _run(address proxyAddress, address newImplementation, bytes memory upgradeCallData) internal {
        uint256 upgraderPrivateKey;
        bool hasPrivateKey;
        try vm.envUint("LUCKYBUY_UPGRADER_PRIVATE_KEY") returns (uint256 pk) {
            upgraderPrivateKey = pk;
            hasPrivateKey = true;
        } catch {}

        if (hasPrivateKey) {
            vm.startBroadcast(upgraderPrivateKey);
        } else {
            vm.startBroadcast();
        }

        address implementationAddress = newImplementation;

        if (implementationAddress == address(0)) {
            try vm.envAddress("LUCKYBUY_NEW_IMPLEMENTATION") returns (address existingImpl) {
                implementationAddress = existingImpl;
                console.log("Using provided implementation", implementationAddress);
            } catch {}
        }

        if (implementationAddress == address(0)) {
            LuckyBuyInitializable implementation = new LuckyBuyInitializable();
            implementationAddress = address(implementation);
            console.log("Deployed new implementation", implementationAddress);
        } else {
            console.log("Using implementation", implementationAddress);
        }

        bytes memory data = upgradeCallData;
        bool hasUpgradeCallData = data.length > 0;

        if (!hasUpgradeCallData) {
            try vm.envBytes("LUCKYBUY_UPGRADE_CALLDATA") returns (bytes memory callData) {
                if (callData.length > 0) {
                    data = callData;
                    hasUpgradeCallData = true;
                }
            } catch {}
        }

        LuckyBuyInitializable proxy = LuckyBuyInitializable(payable(proxyAddress));

        if (!hasUpgradeCallData) {
            console.log("No upgrade calldata supplied, using empty payload");
        } else {
            console.log("Using upgrade calldata of length", data.length);
        }

        proxy.upgradeToAndCall(implementationAddress, data);

        console.log("Proxy upgraded", proxyAddress);
        console.log("Current implementation", implementationAddress);

        vm.stopBroadcast();
    }
}
