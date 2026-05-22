package com.chainforge.mev;

import org.web3j.protocol.Web3j;
import org.web3j.protocol.http.HttpService;
import org.web3j.protocol.core.methods.response.EthBlock;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.tx.RawTransactionManager;
import org.web3j.tx.gas.EIP1559GasProvider;
import org.web3j.utils.Convert;

import java.math.BigInteger;
import java.time.Instant;

/**
 * Secure Swap Service — Flashbots Protect RPC + Slippage Protection
 *
 * 使用 Flashbots Protect RPC 提交交易，避免 MEV front-running。
 * 自动计算滑点保护的最小输出量。
 */
public class SecureSwapService {

    private static final String FLASHBOTS_PROTECT_RPC = "https://rpc.flashbots.net";
    private static final BigInteger BPS = BigInteger.valueOf(10000);

    private final Web3j web3j;
    private final BigInteger maxSlippageBps;
    private final int deadlineMinutes;

    public SecureSwapService(BigInteger maxSlippageBps, int deadlineMinutes) {
        this.maxSlippageBps = maxSlippageBps;
        this.deadlineMinutes = deadlineMinutes;

        // Try Flashbots Protect RPC, fallback to configured RPC
        String rpcUrl = System.getenv().getOrDefault("RPC_URL", FLASHBOTS_PROTECT_RPC);
        this.web3j = Web3j.build(new HttpService(rpcUrl));
    }

    /**
     * 计算滑点保护下的最小输出量
     *
     * @param expectedAmountOut 期望输出量
     * @return 最小可接受输出量
     */
    public BigInteger calcMinAmountOut(BigInteger expectedAmountOut) {
        return expectedAmountOut
                .multiply(BPS.subtract(maxSlippageBps))
                .divide(BPS);
    }

    /**
     * 检查滑点是否在容忍范围内
     */
    public boolean isSlippageAcceptable(BigInteger expectedAmountOut, BigInteger actualAmountOut) {
        BigInteger minOut = calcMinAmountOut(expectedAmountOut);
        return actualAmountOut.compareTo(minOut) >= 0;
    }

    /**
     * 获取当前区块的 deadline 时间戳
     */
    public BigInteger getDeadline() throws Exception {
        EthBlock.Block latestBlock = web3j.ethGetBlockByNumber(
                org.web3j.protocol.core.DefaultBlockParameterName.LATEST, false
        ).send().getBlock();
        long timestamp = latestBlock.getTimestamp().longValue();
        return BigInteger.valueOf(timestamp + deadlineMinutes * 60L);
    }

    /**
     * 构建安全的 swap 交易参数
     */
    public SwapParams buildSecureSwapParams(
            BigInteger amountIn,
            BigInteger expectedAmountOut,
            String tokenIn,
            String tokenOut,
            String recipient
    ) throws Exception {
        return new SwapParams(
                amountIn,
                calcMinAmountOut(expectedAmountOut),
                new String[]{tokenIn, tokenOut},
                recipient,
                getDeadline()
        );
    }

    public Web3j getWeb3j() {
        return web3j;
    }

    public BigInteger getMaxSlippageBps() {
        return maxSlippageBps;
    }

    /**
     * Swap 交易参数
     */
    public static class SwapParams {
        public final BigInteger amountIn;
        public final BigInteger amountOutMin;
        public final String[] path;
        public final String to;
        public final BigInteger deadline;

        public SwapParams(BigInteger amountIn, BigInteger amountOutMin,
                          String[] path, String to, BigInteger deadline) {
            this.amountIn = amountIn;
            this.amountOutMin = amountOutMin;
            this.path = path;
            this.to = to;
            this.deadline = deadline;
        }

        @Override
        public String toString() {
            return String.format(
                    "SwapParams{amountIn=%s, amountOutMin=%s, path=[%s,%s], to=%s, deadline=%d}",
                    amountIn, amountOutMin, path[0], path[1], to, deadline
            );
        }
    }
}
