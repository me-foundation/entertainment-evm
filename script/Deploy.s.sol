// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
// import "../src/LuckyBuy.sol";
import "../src/LuckyBuyInitializable.sol";
import "../src/PRNG.sol";
import "../src/PayoutContract.sol";

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract OpenEdition is ERC1155 {
    constructor() ERC1155("") {}

    function mint(
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public {
        _mint(to, id, value, data);
    }
}

// deprecated
contract DeployPRNG is Script {
    function run() external {
        // vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // PRNG prng = new PRNG();
        // console.log(address(prng));
        // vm.stopBroadcast();
    }
}

// deprecated
contract DeployLuckyBuyLegacy is Script {
    address feeReceiver = 0x0178070d088C235e1Dc2696D257f90B3ded475a3;
    address prng = 0xBdAa680FcD544acc373c5f190449575768Ac4822;
    address feeReceiverManager = 0x7C51fAEe5666B47b2F7E81b7a6A8DEf4C76D47E3;

    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // uint256 protocolFee = 500; // 5%
        // uint256 flatFee = 825000000000000;

        // vm.startBroadcast(deployerPrivateKey);

        // LuckyBuy luckyBuy = new LuckyBuy(
        //     protocolFee,
        //     flatFee,
        //     feeReceiver,
        //     address(prng),
        //     feeReceiverManager
        // );

        // console.log(address(luckyBuy));

        // vm.stopBroadcast();
    }
}

// Deploy initial LuckyBuyInitializable implementation with proxy
// Supports optional reuse of existing contracts via environment variables:
// - EXISTING_PRNG: reuse existing PRNG contract
// - EXISTING_IMPLEMENTATION: reuse existing implementation contract
contract DeployLuckyBuy is Script {
    // EOA
    address feeReceiver = 0x2918F39540df38D4c33cda3bCA9edFccd8471cBE;
    // Gnosis Safe contract
    address feeReceiverManager = 0x7C51fAEe5666B47b2F7E81b7a6A8DEf4C76D47E3;
   
    function run() external {
        address admin = msg.sender; // When using --account, msg.sender is the keystore address
        console.log("Admin", admin);

        uint256 protocolFee = 500; // 5%
        uint256 flatFee = 825000000000000;
        uint256 bulkCommitFee = 250; // 2.5% example, adjust as needed

        vm.startBroadcast(); // No need to pass private key when using --account

        // Check if PRNG address is provided, otherwise deploy new one
        address prngAddress;
        try vm.envAddress("EXISTING_PRNG") returns (address existingPrng) {
            prngAddress = existingPrng;
            console.log("Using existing PRNG", prngAddress);
        } catch {
            PRNG prng = new PRNG();
            prngAddress = address(prng);
            console.log("Deployed new PRNG", prngAddress);
        }

        // Check if implementation address is provided, otherwise deploy new one
        address implementationAddress;
        try vm.envAddress("EXISTING_IMPLEMENTATION") returns (address existingImpl) {
            implementationAddress = existingImpl;
            console.log("Using existing Implementation", implementationAddress);
        } catch {
            LuckyBuyInitializable implementation = new LuckyBuyInitializable();
            implementationAddress = address(implementation);
            console.log("Deployed new Implementation", implementationAddress);
        }

        // Encode initializer call with
        // address initialOwner_
        // uint256 protocolFee_
        // uint256 flatFee_
        // uint256 bulkCommitFee_
        // address feeReceiver_
        // address prng_
        // address feeReceiverManager_
        bytes memory initData =
            abi.encodeWithSignature(
                "initialize(address,uint256,uint256,uint256,address,address,address)",
                admin,
                protocolFee,
                flatFee,
                bulkCommitFee,
                feeReceiver,
                prngAddress,
                feeReceiverManager
            );

        // Deploy proxy and cast the address for convenience
        ERC1967Proxy proxy = new ERC1967Proxy(implementationAddress, initData);
        console.log("Deployed new Proxy", address(proxy));
        
        vm.stopBroadcast();
    }
}

// deprecated
contract DeployOpenEdition is Script {
    address luckyBuy = 0x85d31445AF0b0fF26851bf3C5e27e90058Df3270;

    function run() external {
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        //
        //vm.startBroadcast(deployerPrivateKey);
        //
        //OpenEdition openEditionToken = new OpenEdition();
        //
        //openEditionToken.mint(luckyBuy, 1, 1000 ether, "");
        //
        //vm.stopBroadcast();
    }
}

// deprecated
contract MintOpenEdition is Script {
    address luckyBuy = 0x0178070d088C235e1Dc2696D257f90B3ded475a3;
    address openEditionToken = 0x3e988D49b3dE913FcE7D4ea0037919345ebDC3F8;

    function run() external {
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        //
        //vm.startBroadcast(deployerPrivateKey);
        //
        //OpenEdition(openEditionToken).mint(luckyBuy, 1, 1000 ether, "");
        //
        //vm.stopBroadcast();
    }
}

contract SetOpenEditionToken is Script {
    address payable luckyBuy =
        payable(0x0178070d088C235e1Dc2696D257f90B3ded475a3);
    address openEditionToken = 0x4CB756f71A63785a40d2d2D5a7AE56caAb9f9BCa;
    uint256 tokenId = 0;
    uint32 amount = 1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable(luckyBuy).setOpenEditionToken(
            openEditionToken,
            tokenId,
            amount
        );

        vm.stopBroadcast();
    }
}

contract SetFeeReceiverAddress is Script {
    address payable luckyBuy =
        payable(0x0178070d088C235e1Dc2696D257f90B3ded475a3);
    address feeReceiver = 0x2918F39540df38D4c33cda3bCA9edFccd8471cBE;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable(luckyBuy).setFeeReceiver(feeReceiver);

        vm.stopBroadcast();
    }
}
contract SetFlatFee is Script {
    address payable luckyBuy =
        payable(0x0178070d088C235e1Dc2696D257f90B3ded475a3);
    uint256 flatFee = 0.000825 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable(luckyBuy).setFlatFee(flatFee);

        vm.stopBroadcast();
    }
}
contract SetCommitExpireTime is Script {
    address payable luckyBuy =
        payable(0x0178070d088C235e1Dc2696D257f90B3ded475a3);
    uint256 commitExpireTime = 3 minutes;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable(luckyBuy).setCommitExpireTime(commitExpireTime);

        vm.stopBroadcast();
    }
}

contract AddCosigner is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable luckyBuyContract = payable(vm.envAddress("LUCKY_BUY_CONTRACT"));
        address cosigner = vm.envAddress("COSIGNER_ADDRESS");

        console.log("Adding cosigner:", cosigner);
        console.log("To contract:", luckyBuyContract);

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable(luckyBuyContract).addCosigner(cosigner);

        vm.stopBroadcast();

        console.log("Cosigner added successfully!");
    }
}

contract DeployPayout is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PayoutContract payoutContract = new PayoutContract();
        console.log("PayoutContract deployed at:", address(payoutContract));

        vm.stopBroadcast();
    }
}



// Deploy only implementation (for upgrades)
contract DeployImplementationOnly is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LuckyBuyInitializable implementation = new LuckyBuyInitializable();
        console.log("Implementation deployed at:", address(implementation));

        vm.stopBroadcast();
    }
}

// Deploy only PRNG
contract DeployPRNGOnly is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PRNG prng = new PRNG();
        console.log("PRNG deployed at:", address(prng));

        vm.stopBroadcast();
    }
}

contract getLuckyBuy is Script {
    address payable luckyBuy =
        payable(0x0178070d088C235e1Dc2696D257f90B3ded475a3);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        (
            uint256 id,
            address receiver,
            address cosigner,
            uint256 seed,
            uint256 counter,
            bytes32 orderHash,
            uint256 amount,
            uint256 reward
        ) = LuckyBuyInitializable(luckyBuy).luckyBuys(0);
        console.log(id);
        console.log(receiver);
        console.log(cosigner);
        console.log(seed);
        console.log(counter);
        console.logBytes32(orderHash);
        console.log(amount);
        console.log(reward);

        console.log(LuckyBuyInitializable(luckyBuy).feesPaid(0));
        console.log(LuckyBuyInitializable(luckyBuy).protocolFee());

        console.log("########################");
        console.log(LuckyBuyInitializable(luckyBuy).treasuryBalance());
        console.log(LuckyBuyInitializable(luckyBuy).commitBalance());

        console.log(LuckyBuyInitializable(luckyBuy).protocolBalance());

        vm.stopBroadcast();
    }
}
