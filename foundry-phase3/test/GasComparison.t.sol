// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/SimpleAMM.sol";
import "../src/SimpleAMM_Optimized.sol";
import "../src/MyNFT.sol";
import "../src/MyNFT_Optimized.sol";
import "../src/ChainForgeRouter.sol";
import "../src/ChainForgeRouter_Optimized.sol";
import "../src/MyToken.sol";

/**
 * @title GasComparisonTest
 * @dev Week 10 Gas 优化对比测试 — 原版 vs 优化版
 *
 * 使用 gasleft() 测量每个关键函数的 Gas 消耗，
 * 验证优化效果并输出对比报告。
 */
contract GasComparisonTest is Test {
    // ─── 原版合约 ─────────────────────────────────────────
    SimpleAMM ammOriginal;
    MyNFT nftOriginal;
    ChainForgeRouter routerOriginal;

    // ─── 优化版合约 ───────────────────────────────────────
    SimpleAMM_Optimized ammOptimized;
    MyNFT_Optimized nftOptimized;
    ChainForgeRouter_Optimized routerOptimized;

    // ─── 辅助代币 ─────────────────────────────────────────
    MyToken tokenA;
    MyToken tokenB;
    MyToken cft;
    MyToken weth;
    MyToken usdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // ─── 创建代币 ───────────────────────────────────
        tokenA = new MyToken("Token A", "TKA", 1_000_000, 0);
        tokenB = new MyToken("Token B", "TKB", 1_000_000, 0);
        cft = new MyToken("CFT", "CFT", 1_000_000, 0);
        weth = new MyToken("WETH", "WETH", 1_000_000, 0);
        usdc = new MyToken("USDC", "USDC", 1_000_000, 0);

        // ─── 部署原版 AMM ───────────────────────────────
        ammOriginal = new SimpleAMM(address(tokenA), address(tokenB));

        // ─── 部署优化版 AMM ─────────────────────────────
        ammOptimized = new SimpleAMM_Optimized(address(tokenA), address(tokenB));

        // ─── 部署原版 NFT ───────────────────────────────
        nftOriginal = new MyNFT("ChainForge NFT", "CFNFT", "ipfs://test/", 10000);

        // ─── 部署优化版 NFT ─────────────────────────────
        nftOptimized = new MyNFT_Optimized("ChainForge NFT Opt", "CFNOPT", "ipfs://test/", 10000);

        // ─── 部署原版 Router ─────────────────────────────
        routerOriginal = new ChainForgeRouter();

        // ─── 部署优化版 Router ───────────────────────────
        routerOptimized = new ChainForgeRouter_Optimized();

        // ─── 准备代币 ───────────────────────────────────
        tokenA.transfer(alice, 200_000 * 1e18);
        tokenB.transfer(alice, 200_000 * 1e18);
        tokenA.transfer(bob, 200_000 * 1e18);
        tokenB.transfer(bob, 200_000 * 1e18);
        cft.transfer(alice, 200_000 * 1e18);
        weth.transfer(alice, 200_000 * 1e18);
        usdc.transfer(alice, 200_000 * 1e18);
        cft.transfer(bob, 200_000 * 1e18);
        weth.transfer(bob, 200_000 * 1e18);
        usdc.transfer(bob, 200_000 * 1e18);
    }

    // ─── 辅助函数 ──────────────────────────────────────────

    function _addLiquidityOriginal(address user, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(user);
        tokenA.approve(address(ammOriginal), amountA);
        tokenB.approve(address(ammOriginal), amountB);
        ammOriginal.addLiquidity(amountA, amountB, block.timestamp + 300);
        vm.stopPrank();
    }

    function _addLiquidityOptimized(address user, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(user);
        tokenA.approve(address(ammOptimized), amountA);
        tokenB.approve(address(ammOptimized), amountB);
        ammOptimized.addLiquidity(amountA, amountB, block.timestamp + 300);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════
    // 1. addLiquidity 对比
    // ═══════════════════════════════════════════════════════

    function testGasAddLiquidity() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;

        // 原版
        vm.prank(alice);
        tokenA.approve(address(ammOriginal), amountA);
        vm.prank(alice);
        tokenB.approve(address(ammOriginal), amountB);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        ammOriginal.addLiquidity(amountA, amountB, block.timestamp + 300);
        uint256 gasOriginal = gasBefore - gasleft();

        // 优化版
        vm.prank(alice);
        tokenA.approve(address(ammOptimized), amountA);
        vm.prank(alice);
        tokenB.approve(address(ammOptimized), amountB);

        uint256 gasBefore2 = gasleft();
        vm.prank(alice);
        ammOptimized.addLiquidity(amountA, amountB, block.timestamp + 300);
        uint256 gasOptimized = gasBefore2 - gasleft();

        console.log("=== addLiquidity Gas Comparison ===");
        console.log("Original: ", gasOriginal);
        console.log("Optimized:", gasOptimized);
        console.log("Saved:    ", gasOriginal - gasOptimized);
        console.log("Saved %:  ", (gasOriginal - gasOptimized) * 100 / gasOriginal, "%");
    }

    // ═══════════════════════════════════════════════════════
    // 2. swap 对比
    // ═══════════════════════════════════════════════════════

    function testGasSwap() public {
        _addLiquidityOriginal(alice, 10_000 * 1e18, 10_000 * 1e18);
        _addLiquidityOptimized(alice, 10_000 * 1e18, 10_000 * 1e18);

        uint256 swapAmount = 100 * 1e18;

        // 原版 swap
        vm.startPrank(bob);
        tokenA.approve(address(ammOriginal), swapAmount);
        uint256 gasBefore = gasleft();
        ammOriginal.swap(address(tokenA), swapAmount, 0, block.timestamp + 300);
        uint256 gasOriginal = gasBefore - gasleft();
        vm.stopPrank();

        // 优化版 swap
        vm.startPrank(bob);
        tokenA.approve(address(ammOptimized), swapAmount);
        uint256 gasBefore2 = gasleft();
        ammOptimized.swap(address(tokenA), swapAmount, 0, block.timestamp + 300);
        uint256 gasOptimized = gasBefore2 - gasleft();
        vm.stopPrank();

        console.log("=== swap Gas Comparison ===");
        console.log("Original: ", gasOriginal);
        console.log("Optimized:", gasOptimized);
        console.log("Saved:    ", gasOriginal - gasOptimized);
        if (gasOriginal > 0) {
            console.log("Saved %:  ", (gasOriginal - gasOptimized) * 100 / gasOriginal, "%");
        }
    }

    // ═══════════════════════════════════════════════════════
    // 3. removeLiquidity 对比
    // ═══════════════════════════════════════════════════════

    function testGasRemoveLiquidity() public {
        _addLiquidityOriginal(alice, 10_000 * 1e18, 10_000 * 1e18);
        _addLiquidityOptimized(alice, 10_000 * 1e18, 10_000 * 1e18);

        uint256 lpOriginal = ammOriginal.balanceOf(alice);
        uint256 lpOptimized = ammOptimized.balanceOf(alice);

        // 原版
        vm.startPrank(alice);
        ammOriginal.approve(address(ammOriginal), lpOriginal);
        uint256 gasBefore = gasleft();
        ammOriginal.removeLiquidity(lpOriginal, block.timestamp + 300);
        uint256 gasOriginal = gasBefore - gasleft();
        vm.stopPrank();

        // 优化版
        vm.startPrank(alice);
        ammOptimized.approve(address(ammOptimized), lpOptimized);
        uint256 gasBefore2 = gasleft();
        ammOptimized.removeLiquidity(lpOptimized, block.timestamp + 300);
        uint256 gasOptimized = gasBefore2 - gasleft();
        vm.stopPrank();

        console.log("=== removeLiquidity Gas Comparison ===");
        console.log("Original: ", gasOriginal);
        console.log("Optimized:", gasOptimized);
        console.log("Saved:    ", gasOriginal - gasOptimized);
        if (gasOriginal > 0) {
            console.log("Saved %:  ", (gasOriginal - gasOptimized) * 100 / gasOriginal, "%");
        }
    }

    // ═══════════════════════════════════════════════════════
    // 4. batchMint 对比（最显著的优化）
    // ═══════════════════════════════════════════════════════

    function testGasBatchMint5() public {
        _compareBatchMint(5);
    }

    function testGasBatchMint10() public {
        _compareBatchMint(10);
    }

    function testGasBatchMint20() public {
        _compareBatchMint(20);
    }

    function _compareBatchMint(uint256 quantity) internal {
        // 原版
        uint256 gasBefore = gasleft();
        nftOriginal.batchMint(alice, quantity);
        uint256 gasOriginal = gasBefore - gasleft();

        // 优化版
        uint256 gasBefore2 = gasleft();
        nftOptimized.batchMint(alice, quantity);
        uint256 gasOptimized = gasBefore2 - gasleft();

        console.log("=== batchMint(%s) Gas Comparison ===", quantity);
        console.log("Original: ", gasOriginal);
        console.log("Optimized:", gasOptimized);
        console.log("Saved:    ", gasOriginal - gasOptimized);
        if (gasOriginal > 0) {
            console.log("Saved %:  ", (gasOriginal - gasOptimized) * 100 / gasOriginal, "%");
        }
    }

    // ═══════════════════════════════════════════════════════
    // 5. Router swap 对比
    // ═══════════════════════════════════════════════════════

    function testGasRouterSwap() public {
        // ─── 创建 AMM 池（原版和优化版共用，因为 Router 优化在路由层）───
        SimpleAMM amm1 = new SimpleAMM(address(cft), address(weth));
        SimpleAMM amm2 = new SimpleAMM(address(weth), address(usdc));

        // 添加流动性
        vm.startPrank(alice);
        cft.approve(address(amm1), 10_000 * 1e18);
        weth.approve(address(amm1), 10_000 * 1e18);
        amm1.addLiquidity(10_000 * 1e18, 10_000 * 1e18, block.timestamp + 300);

        weth.approve(address(amm2), 10_000 * 1e18);
        usdc.approve(address(amm2), 10_000 * 1e18);
        amm2.addLiquidity(10_000 * 1e18, 10_000 * 1e18, block.timestamp + 300);
        vm.stopPrank();

        // ─── 原版 Router ────────────────────────────────
        routerOriginal.addPool(address(cft), address(weth), address(amm1));
        routerOriginal.addPool(address(weth), address(usdc), address(amm2));

        address[] memory path = new address[](3);
        path[0] = address(cft);
        path[1] = address(weth);
        path[2] = address(usdc);

        vm.startPrank(bob);
        cft.approve(address(routerOriginal), 100 * 1e18);
        uint256 gasBefore = gasleft();
        routerOriginal.swapExactTokensForTokens(100 * 1e18, 0, path, bob, block.timestamp + 300);
        uint256 gasOriginal = gasBefore - gasleft();
        vm.stopPrank();

        // ─── 优化版 Router ──────────────────────────────
        routerOptimized.addPool(address(cft), address(weth), address(amm1));
        routerOptimized.addPool(address(weth), address(usdc), address(amm2));

        vm.startPrank(bob);
        cft.approve(address(routerOptimized), 100 * 1e18);
        uint256 gasBefore2 = gasleft();
        routerOptimized.swapExactTokensForTokens(100 * 1e18, 0, path, bob, block.timestamp + 300);
        uint256 gasOptimized = gasBefore2 - gasleft();
        vm.stopPrank();

        console.log("=== Router swap (2-hop) Gas Comparison ===");
        console.log("Original: ", gasOriginal);
        console.log("Optimized:", gasOptimized);
        console.log("Saved:    ", gasOriginal - gasOptimized);
        if (gasOriginal > 0) {
            console.log("Saved %:  ", (gasOriginal - gasOptimized) * 100 / gasOriginal, "%");
        }
    }

    // ═══════════════════════════════════════════════════════
    // 6. setBaseURI: calldata vs memory 对比
    // ═══════════════════════════════════════════════════════

    function testGasSetBaseURI() public {
        string memory uri = "ipfs://QmNewBaseURI123456789/";

        // 原版 (memory)
        uint256 gasBefore = gasleft();
        nftOriginal.setBaseURI(uri);
        uint256 gasOriginal = gasBefore - gasleft();

        // 优化版 (calldata)
        uint256 gasBefore2 = gasleft();
        nftOptimized.setBaseURI(uri);
        uint256 gasOptimized = gasBefore2 - gasleft();

        console.log("=== setBaseURI (calldata vs memory) ===");
        console.log("Original (memory):  ", gasOriginal);
        console.log("Optimized (calldata):", gasOptimized);
        console.log("Saved:              ", gasOriginal - gasOptimized);
    }

    // ═══════════════════════════════════════════════════════
    // 7. 综合对比报告
    // ═══════════════════════════════════════════════════════

    function testFullComparisonReport() public {
        console.log("");
        console.log("==============================================");
        console.log("  Week 10 Gas Optimization Comparison Report  ");
        console.log("==============================================");
        console.log("");

        // addLiquidity
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;

        vm.prank(alice);
        tokenA.approve(address(ammOriginal), amountA);
        vm.prank(alice);
        tokenB.approve(address(ammOriginal), amountB);
        uint256 g1 = gasleft();
        vm.prank(alice);
        ammOriginal.addLiquidity(amountA, amountB, block.timestamp + 300);
        uint256 addLiqOrig = g1 - gasleft();

        vm.prank(alice);
        tokenA.approve(address(ammOptimized), amountA);
        vm.prank(alice);
        tokenB.approve(address(ammOptimized), amountB);
        uint256 g2 = gasleft();
        vm.prank(alice);
        ammOptimized.addLiquidity(amountA, amountB, block.timestamp + 300);
        uint256 addLiqOpt = g2 - gasleft();

        _printRow("SimpleAMM.addLiquidity", addLiqOrig, addLiqOpt);

        // swap
        vm.startPrank(bob);
        tokenA.approve(address(ammOriginal), 100 * 1e18);
        g1 = gasleft();
        ammOriginal.swap(address(tokenA), 100 * 1e18, 0, block.timestamp + 300);
        uint256 swapOrig = g1 - gasleft();
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(ammOptimized), 100 * 1e18);
        g2 = gasleft();
        ammOptimized.swap(address(tokenA), 100 * 1e18, 0, block.timestamp + 300);
        uint256 swapOpt = g2 - gasleft();
        vm.stopPrank();

        _printRow("SimpleAMM.swap", swapOrig, swapOpt);

        // removeLiquidity
        uint256 lpOrig = ammOriginal.balanceOf(alice);
        uint256 lpOpt = ammOptimized.balanceOf(alice);
        vm.startPrank(alice);
        ammOriginal.approve(address(ammOriginal), lpOrig);
        g1 = gasleft();
        ammOriginal.removeLiquidity(lpOrig, block.timestamp + 300);
        uint256 rmLiqOrig = g1 - gasleft();
        vm.stopPrank();

        vm.startPrank(alice);
        ammOptimized.approve(address(ammOptimized), lpOpt);
        g2 = gasleft();
        ammOptimized.removeLiquidity(lpOpt, block.timestamp + 300);
        uint256 rmLiqOpt = g2 - gasleft();
        vm.stopPrank();

        _printRow("SimpleAMM.removeLiquidity", rmLiqOrig, rmLiqOpt);

        // batchMint(10)
        g1 = gasleft();
        nftOriginal.batchMint(alice, 10);
        uint256 batchOrig = g1 - gasleft();

        g2 = gasleft();
        nftOptimized.batchMint(alice, 10);
        uint256 batchOpt = g2 - gasleft();

        _printRow("MyNFT.batchMint(10)", batchOrig, batchOpt);

        // batchMint(20)
        g1 = gasleft();
        nftOriginal.batchMint(bob, 20);
        uint256 batch20Orig = g1 - gasleft();

        g2 = gasleft();
        nftOptimized.batchMint(bob, 20);
        uint256 batch20Opt = g2 - gasleft();

        _printRow("MyNFT.batchMint(20)", batch20Orig, batch20Opt);

        console.log("");
        console.log("==============================================");
    }

    function _printRow(string memory name, uint256 origGas, uint256 optGas) internal view {
        uint256 saved = origGas > optGas ? origGas - optGas : 0;
        uint256 pct = origGas > 0 ? saved * 100 / origGas : 0;
        console.log("Function:", name);
        console.log("  Original:", origGas);
        console.log("  Optimized:", optGas);
        console.log("  Saved:", saved);
        console.log("  Percent:", pct);
    }
}
