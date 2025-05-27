import { ethers } from "ethers";
import { abi as luckyBuyAbi } from "../out/LuckyBuy.sol/LuckyBuy.json";
import dotenv from "dotenv";

dotenv.config();

interface FetchEventsOptions {
  provider: ethers.Provider;
  contractAddress: string;
  eventName?: string;
  startBlock?: number;
  endBlock?: number | "current";
  abi?: any[];
}

export function getMainnetProvider(): ethers.Provider {
  const rpcUrl = process.env.MAINNET_RPC_URL;
  if (!rpcUrl) {
    throw new Error("MAINNET_RPC_URL environment variable is not set");
  }
  return new ethers.JsonRpcProvider(rpcUrl);
}

function formatValue(value: any, type: string): string {
  if (type.includes("address")) {
    return value.toString();
  }
  if (type.includes("uint") || type.includes("int")) {
    if (type.includes("256")) {
      // For large numbers, format as ETH if it's a reasonable amount
      const ethValue = ethers.formatEther(value);
      if (parseFloat(ethValue) < 1000000) {
        // Only format as ETH if less than 1M ETH
        return `${ethValue} ETH`;
      }
    }
    return value.toString();
  }
  if (type.includes("bool")) {
    return value ? "true" : "false";
  }
  if (type.includes("bytes")) {
    return `0x${value.slice(2)}`;
  }
  return value.toString();
}

export async function logEvents(events: ethers.Log[]) {
  const iface = new ethers.Interface(luckyBuyAbi);
  console.log(`Found ${events.length} events:\n`);

  events.forEach((event, index) => {
    try {
      const parsed = iface.parseLog(event);
      if (!parsed) {
        throw new Error("Failed to parse log");
      }
      console.log(`Event #${index + 1}: ${parsed.name}`);
      console.log(`Block: ${event.blockNumber}`);
      console.log(`Transaction: ${event.transactionHash}`);
      console.log("Args:");
      // Get the event fragment to get the parameter names
      const fragment = iface.getEvent(parsed.name);
      if (fragment) {
        fragment.inputs.forEach((input, i) => {
          const formattedValue = formatValue(parsed.args[i], input.type);
          console.log(`  ${input.name}: ${formattedValue}`);
        });
      }
      console.log("-------------------\n");
    } catch (e) {
      console.log(`Event #${index + 1}:`);
      console.log(`Block: ${event.blockNumber}`);
      console.log(`Transaction: ${event.transactionHash}`);
      console.log(`Log Index: ${event.index}`);
      console.log(`Topics: ${event.topics.join(", ")}`);
      console.log(`Data: ${event.data}`);
      console.log("-------------------\n");
    }
  });
}

export async function fetchContractEvents({
  provider = getMainnetProvider(),
  contractAddress = "0x0178070d088C235e1Dc2696D257f90B3ded475a3",
  eventName = "Fulfillment",
  startBlock = 22518617,
  endBlock = "current",
  abi = luckyBuyAbi,
}: FetchEventsOptions): Promise<ethers.Log[]> {
  try {
    // Create contract instance
    const contract = new ethers.Contract(contractAddress, abi || [], provider);

    // Get the current block number if endBlock is "current"
    const currentBlock = await provider.getBlockNumber();
    const toBlock = endBlock === "current" ? currentBlock : endBlock;
    const fromBlock = startBlock || 0;

    // Fetch events
    if (eventName) {
      return await contract.queryFilter(
        contract.filters[eventName](),
        fromBlock,
        toBlock
      );
    } else {
      // For fetching all events, we need to use the provider's getLogs
      const logs = await provider.getLogs({
        address: contractAddress,
        fromBlock,
        toBlock,
      });
      return logs;
    }
  } catch (error) {
    console.error("Error fetching contract events:", error);
    throw error;
  }
}

// Main execution
async function main() {
  try {
    const provider = getMainnetProvider();
    const events = await fetchContractEvents({
      provider,
      contractAddress: "0x0178070d088C235e1Dc2696D257f90B3ded475a3",
      eventName: "Fulfillment",
      startBlock: 22518617,
      endBlock: "current",
    });
    await logEvents(events);
  } catch (error) {
    console.error("Failed to fetch events:", error);
    process.exit(1);
  }
}

main();
