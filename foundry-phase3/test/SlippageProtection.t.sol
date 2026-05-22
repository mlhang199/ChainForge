// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/SlippageProtection.sol";
import "../src/ChainForgeRouter.sol";
import "../src/SimpleAMM.sol";
import "../src/MyToken.sol";

// 测试载体合约 — library 需要嵌入合约才能测试
contract SlippageChecker {
    using SlippageProtection for uint256;

    function checkSlippage(
        uint256 expected,
        uint256 actual,
        uint256 maxBps
    ) external pure {
        SlippageProtection.checkSlippage(expected, actual, maxBps);
    }

    function calcMinAmountOut(
        uint256 expected,
        uint256 maxBps
    ) external pure returns (uint256) {
        return SlippageProtection.minAmountOut(expected, maxBps);
    }
}

contract SlippageProtectionTest is Test {
    SlippageChecker checker;

    function setUp() public {
        checker = new SlippageChecker();
    }

    // ── checkSlippage: normal pass ──

    function testPassExactMatch() public {
        checker.checkSlippage(1000, 1000, 50);
    }

    function testPassWithinSlippage() public {
        // 0.5% slippage on 1000 → min 995
        checker.checkSlippage(1000, 996, 50);
    }

    function testPassAtMinBoundary() public {
        // 0.5% on 1000 → min = 1000 * 9950 / 10000 = 995
        checker.checkSlippage(1000, 995, 50);
    }

    function testPassZeroSlippage() public {
        // 0% slippage → actual must == expected
        checker.checkSlippage(1000, 1000, 0);
    }

    function testPass100PercentSlippage() public {
        // 100% slippage → anything >= 0 passes
        checker.checkSlippage(1000, 1, 10000);
    }

    // ── checkSlippage: revert ──

    function testRevertExceedsSlippage() public {
        vm.expectRevert(
            abi.encodeWithSelector(SlippageProtection.SlippageExceeded.selector, 1000, 994, 50)
        );
        checker.checkSlippage(1000, 994, 50);
    }

    function testRevertZeroActual() public {
        vm.expectRevert(
            abi.encodeWithSelector(SlippageProtection.SlippageExceeded.selector, 1000, 0, 50)
        );
        checker.checkSlippage(1000, 0, 50);
    }

    function testRevertZeroSlippageMismatch() public {
        vm.expectRevert(
            abi.encodeWithSelector(SlippageProtection.SlippageExceeded.selector, 1000, 999, 0)
        );
        checker.checkSlippage(1000, 999, 0);
    }

    function testRevertBpsExceeds10000() public {
        vm.expectRevert("SlippageBps > 10000");
        checker.checkSlippage(1000, 500, 10001);
    }

    // ── minAmountOut calculation ──

    function testMinAmountOutHalfPercent() public {
        // 0.5% on 10000 → min = 10000 * 9950 / 10000 = 9950
        assertEq(checker.calcMinAmountOut(10000, 50), 9950);
    }

    function testMinAmountOutOnePercent() public {
        // 1% on 10000 → min = 9900
        assertEq(checker.calcMinAmountOut(10000, 100), 9900);
    }

    function testMinAmountOutZeroSlippage() public {
        assertEq(checker.calcMinAmountOut(10000, 0), 10000);
    }

    function testMinAmountOutFullSlippage() public {
        assertEq(checker.calcMinAmountOut(10000, 10000), 0);
    }

    function testMinAmountOutSmallValue() public {
        // 1% on 100 → 99 (integer division)
        assertEq(checker.calcMinAmountOut(100, 100), 99);
    }

    // ── Fuzz ──

    function testFuzz_MinAmountOut(uint256 expected, uint16 bps) public pure {
        bps = uint16(bound(bps, 0, 10000));
        expected = bound(expected, 1, 1e27);
        uint256 minOut = SlippageProtection.minAmountOut(expected, bps);
        assertLe(minOut, expected);
        assertEq(minOut, expected * (10000 - bps) / 10000);
    }

    function testFuzz_CheckSlippagePass(uint256 expected, uint16 bps) public {
        bps = uint16(bound(bps, 0, 10000));
        expected = bound(expected, 1, 1e27);
        uint256 minOut = SlippageProtection.minAmountOut(expected, bps);
        // exact min should pass
        SlippageProtection.checkSlippage(expected, minOut, bps);
    }

    function testFuzz_CheckSlippageFail(uint256 expected, uint256 bpsRaw) public {
        uint256 bps = bound(bpsRaw, 1, 9999);
        expected = bound(expected, 100, 1e27);
        uint256 minOut = checker.calcMinAmountOut(expected, bps);
        vm.assume(minOut > 0);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageProtection.SlippageExceeded.selector, expected, minOut - 1, bps)
        );
        checker.checkSlippage(expected, minOut - 1, bps);
    }
}

// ── Router 集成测试 — 在 swap 中使用 SlippageProtection ──

contract RouterSlippageIntegrationTest is Test {
    ChainForgeRouter router;
    SimpleAMM amm;
    MyToken tokenA;
    MyToken tokenB;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant LIQUIDITY = 10_000 * 1e18;

    function setUp() public {
        tokenA = new MyToken("TKA", "TKA", 1_000_000, 0);
        tokenB = new MyToken("TKB", "TKB", 1_000_000, 0);
        amm = new SimpleAMM(address(tokenA), address(tokenB));
        router = new ChainForgeRouter();
        router.addPool(address(tokenA), address(tokenB), address(amm));

        tokenA.transfer(alice, 100_000 * 1e18);
        tokenB.transfer(alice, 100_000 * 1e18);
        tokenA.transfer(bob, 100_000 * 1e18);
        tokenB.transfer(bob, 100_000 * 1e18);

        vm.startPrank(alice);
        tokenA.approve(address(amm), LIQUIDITY);
        tokenB.approve(address(amm), LIQUIDITY);
        amm.addLiquidity(LIQUIDITY, LIQUIDITY, block.timestamp + 300);
        vm.stopPrank();
    }

    /// @dev 使用 SlippageProtection 计算合理的 amountOutMin
    function testSwapWithSlippageCalc() public {
        uint256 amountIn = 100 * 1e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        uint256 expectedOut = amounts[1];

        // 计算 0.5% 滑点保护下的 minAmountOut
        uint256 amountOutMin = SlippageProtection.minAmountOut(expectedOut, 50);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);
        uint256[] memory result = router.swapExactTokensForTokens(
            amountIn, amountOutMin, path, bob, block.timestamp + 300
        );
        vm.stopPrank();

        assertGe(result[1], amountOutMin);
    }

    /// @dev 三明治模拟：front-run 改变价格后，用户交易滑点超标
    function testSandwichSlippageRevert() public {
        uint256 amountIn = 100 * 1e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 用户预期输出
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        uint256 expectedOut = amounts[1];
        // 严格的 0.3% 滑点保护
        uint256 amountOutMin = SlippageProtection.minAmountOut(expectedOut, 30);

        // 模拟 front-run：alice 大量买入 tokenA，推高 tokenB 价格
        vm.startPrank(alice);
        tokenA.approve(address(router), 5000 * 1e18);
        router.swapExactTokensForTokens(
            5000 * 1e18, 0, path, alice, block.timestamp + 300
        );
        vm.stopPrank();

        // bob 的 swap 现在因为价格变动，实际输出低于 amountOutMin
        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);
        vm.expectRevert("Slippage exceeded");
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, path, bob, block.timestamp + 300
        );
        vm.stopPrank();
    }
}
