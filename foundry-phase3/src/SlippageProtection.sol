// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SlippageProtection
/// @dev 防三明治攻击的滑点保护库 — 精确控制可接受的价格偏移
library SlippageProtection {
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxSlippageBps);

    uint256 public constant BPS = 10000;

    /// @dev 检查实际输出是否在滑点容忍范围内
    /// @param expectedAmountOut 期望输出量
    /// @param actualAmountOut 实际输出量
    /// @param maxSlippageBps 最大滑点（基点），50 = 0.5%，100 = 1%
    function checkSlippage(
        uint256 expectedAmountOut,
        uint256 actualAmountOut,
        uint256 maxSlippageBps
    ) internal pure {
        require(maxSlippageBps <= BPS, "SlippageBps > 10000");
        uint256 minAmountOut = expectedAmountOut * (BPS - maxSlippageBps) / BPS;
        if (actualAmountOut < minAmountOut) {
            revert SlippageExceeded(expectedAmountOut, actualAmountOut, maxSlippageBps);
        }
    }

    /// @dev 计算给定滑点下的最小输出量
    function minAmountOut(
        uint256 expectedAmountOut,
        uint256 maxSlippageBps
    ) internal pure returns (uint256) {
        require(maxSlippageBps <= BPS, "SlippageBps > 10000");
        return expectedAmountOut * (BPS - maxSlippageBps) / BPS;
    }
}
