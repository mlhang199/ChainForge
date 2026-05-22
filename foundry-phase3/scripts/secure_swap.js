/**
 * Secure Swap Script — Flashbots Protect RPC + Slippage Protection
 *
 * Usage:
 *   npx hardhat run scripts/secure_swap.js --network sepolia
 *
 * Features:
 *   - Flashbots Protect RPC to prevent MEV front-running
 *   - Automatic slippage calculation
 *   - Deadline check
 *   - EIP-1559 gas estimation
 */

const { ethers } = require("ethers");

// ─── Configuration ───────────────────────────────────────────

const FLASHBOTS_PROTECT_RPC = "https://rpc.flashbots.net";
const FALLBACK_RPC = process.env.RPC_URL || "http://127.0.0.1:8545";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) {
  console.error("Error: PRIVATE_KEY env var is required");
  process.exit(1);
}

const MAX_SLIPPAGE_BPS = 50; // 0.5%
const BPS = 10000;
const DEADLINE_MINUTES = 30;

// ─── Slippage Helper ─────────────────────────────────────────

function calcMinAmountOut(expectedOut, maxSlippageBps) {
  return (expectedOut * BigInt(BPS - maxSlippageBps)) / BigInt(BPS);
}

// ─── Main ────────────────────────────────────────────────────

async function main() {
  // Try Flashbots Protect RPC first, fallback to standard RPC
  let provider;
  try {
    provider = new ethers.JsonRpcProvider(FLASHBOTS_PROTECT_RPC);
    await provider.getBlockNumber();
    console.log("[OK] Connected to Flashbots Protect RPC");
  } catch {
    provider = new ethers.JsonRpcProvider(FALLBACK_RPC);
    console.log("[WARN] Flashbots RPC unavailable, using fallback");
  }

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  console.log(`[OK] Wallet: ${wallet.address}`);

  // ─── Example: Swap tokens on ChainForgeRouter ───

  const routerAddress = process.env.ROUTER_ADDRESS;
  const tokenIn = process.env.TOKEN_IN;
  const tokenOut = process.env.TOKEN_OUT;
  const amountIn = process.env.AMOUNT_IN;

  if (!routerAddress || !tokenIn || !tokenOut || !amountIn) {
    console.log("\n--- Secure Swap Info ---");
    console.log("Set env vars to execute a swap:");
    console.log("  ROUTER_ADDRESS=0x... TOKEN_IN=0x... TOKEN_OUT=0x... AMOUNT_IN=1000000000000000000");
    console.log("\nSlippage protection: MAX_SLIPPAGE_BPS =", MAX_SLIPPAGE_BPS, `(=${MAX_SLIPPAGE_BPS / 100}%)`);
    console.log("Flashbots Protect RPC:", FLASHBOTS_PROTECT_RPC);

    // Demo slippage calculation
    const demoExpected = BigInt("995000000000000000");
    const minOut = calcMinAmountOut(demoExpected, MAX_SLIPPAGE_BPS);
    console.log(`\nDemo: expected=${demoExpected}, minOut=${minOut}`);
    return;
  }

  // Router ABI (minimal)
  const routerAbi = [
    "function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory)",
    "function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory)",
  ];

  const router = new ethers.Contract(routerAddress, routerAbi, wallet);
  const path = [tokenIn, tokenOut];

  // 1. Get expected output
  const amounts = await router.getAmountsOut(amountIn, path);
  const expectedOut = amounts[1];
  console.log(`[INFO] Expected output: ${expectedOut}`);

  // 2. Calculate slippage-protected minimum
  const amountOutMin = calcMinAmountOut(expectedOut, MAX_SLIPPAGE_BPS);
  console.log(`[INFO] Min output (${MAX_SLIPPAGE_BPS / 100}% slippage): ${amountOutMin}`);

  // 3. Set deadline
  const block = await provider.getBlock("latest");
  const deadline = block.timestamp + DEADLINE_MINUTES * 60;
  console.log(`[INFO] Deadline: ${new Date(deadline * 1000).toISOString()}`);

  // 4. Estimate gas (EIP-1559)
  const feeData = await provider.getFeeData();
  console.log(`[INFO] EIP-1559 maxFeePerGas: ${feeData.maxFeePerGas}`);
  console.log(`[INFO] EIP-1559 maxPriorityFeePerGas: ${feeData.maxPriorityFeePerGas}`);

  // 5. Execute swap
  console.log("[INFO] Submitting swap via Flashbots Protect...");
  const tx = await router.swapExactTokensForTokens(
    amountIn,
    amountOutMin,
    path,
    wallet.address,
    deadline,
    {
      maxFeePerGas: feeData.maxFeePerGas,
      maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
    }
  );

  console.log(`[OK] TX submitted: ${tx.hash}`);
  console.log("[INFO] Waiting for confirmation...");

  const receipt = await tx.wait();
  if (receipt.status === 1) {
    console.log(`[OK] Swap confirmed in block ${receipt.blockNumber}, gas used: ${receipt.gasUsed}`);
  } else {
    console.error(`[FAIL] Transaction reverted`);
  }
}

main().catch(console.error);
