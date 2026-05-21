// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleAMM.sol";

/**
 * @title ChainForgeRouter_Optimized
 * @dev Week 10 Gas 优化版 ChainForgeRouter
 *
 * 优化项：
 *   1. 缓存 path.length 到局部变量（避免循环中重复 SLOAD）
 *   2. unchecked { ++i } 消除循环溢出检查
 *   3. external view 函数已使用 calldata（原版也是）
 *   4. 内联 reserve 读取逻辑减少外部调用开销
 */
contract ChainForgeRouter_Optimized {
    using SafeERC20 for IERC20;

    struct Pool {
        address pair;
        address token0;
        address token1;
    }

    Pool[] public pools;
    mapping(address => mapping(address => address)) public pairFor;

    event PoolAdded(address indexed token0, address indexed token1, address indexed pair);
    event SwapExecuted(address indexed sender, uint256 amountIn, uint256 amountOut, address[] path);

    function addPool(address tokenA, address tokenB, address pair) external {
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        require(tokenA != tokenB, "Identical addresses");
        require(pair != address(0), "Zero pair address");
        require(pairFor[tokenA][tokenB] == address(0), "Pool already exists");

        pairFor[tokenA][tokenB] = pair;
        pairFor[tokenB][tokenA] = pair;
        pools.push(Pool({pair: pair, token0: tokenA, token1: tokenB}));

        emit PoolAdded(tokenA, tokenB, pair);
    }

    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    // ─── 优化: 缓存 path.length + unchecked ++i ────────────
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        uint256 pathLen = path.length;   // 缓存到 memory
        require(pathLen >= 2, "Invalid path");
        amounts = new uint256[](pathLen);
        amounts[0] = amountIn;

        for (uint256 i; i < pathLen - 1;) {
            address tokenIn = path[i];
            address tokenOut = path[i + 1];
            address pair = pairFor[tokenIn][tokenOut];
            require(pair != address(0), "Pool not found");

            SimpleAMM amm = SimpleAMM(pair);
            address tA = amm.tokenA();
            uint256 reserveIn = tokenIn == tA ? amm.reserveA() : amm.reserveB();
            uint256 reserveOut = tokenIn == tA ? amm.reserveB() : amm.reserveA();
            amounts[i + 1] = amm.getAmountOut(amounts[i], reserveIn, reserveOut);

            unchecked { ++i; }
        }
    }

    // ─── 优化: 缓存 + unchecked + 局部变量 ──────────────────
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        uint256 pathLen = path.length;   // 缓存到 memory
        require(pathLen >= 2, "Invalid path");
        require(to != address(0), "Zero address");

        amounts = new uint256[](pathLen);
        amounts[0] = amountIn;

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        for (uint256 i; i < pathLen - 1;) {
            address tokenIn = path[i];
            address tokenOut = path[i + 1];
            address pair = pairFor[tokenIn][tokenOut];
            require(pair != address(0), "Pool not found");

            SimpleAMM amm = SimpleAMM(pair);
            address tA = amm.tokenA();
            uint256 reserveIn = tokenIn == tA ? amm.reserveA() : amm.reserveB();
            uint256 reserveOut = tokenIn == tA ? amm.reserveB() : amm.reserveA();
            amounts[i + 1] = amm.getAmountOut(amounts[i], reserveIn, reserveOut);

            IERC20(tokenIn).forceApprove(pair, amounts[i]);
            amm.swap(tokenIn, amounts[i], 0, deadline);

            unchecked { ++i; }
        }

        require(amounts[pathLen - 1] >= amountOutMin, "Slippage exceeded");

        IERC20(path[pathLen - 1]).safeTransfer(to, amounts[pathLen - 1]);

        emit SwapExecuted(msg.sender, amountIn, amounts[pathLen - 1], path);
    }

    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction expired");
        _;
    }
}
