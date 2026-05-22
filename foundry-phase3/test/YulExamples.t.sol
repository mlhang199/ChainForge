// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/YulExamples.sol";

/**
 * @title YulExamplesTest
 * @dev Week 11 Yul 内联汇编实验 — 正确性验证 + Gas 对比
 */
contract YulExamplesTest is Test {
    YulExamples yul;

    function setUp() public {
        yul = new YulExamples();
    }

    // ═══════════════════════════════════════════════════════
    // 1. 读取 Storage 正确性
    // ═══════════════════════════════════════════════════════

    function testGetValueMatches() public {
        yul.setValueSolidity(42);
        uint256 sol = yul.getValueSolidity();
        uint256 yulVal = yul.getValueYul();
        assertEq(sol, yulVal, "Yul read should match Solidity read");
        assertEq(yulVal, 42);
    }

    function testGetValueGasComparison() public {
        yul.setValueSolidity(100);

        uint256 gasBefore = gasleft();
        uint256 sol = yul.getValueSolidity();
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        uint256 yulVal = yul.getValueYul();
        uint256 gasYul = gasBefore2 - gasleft();

        assertEq(sol, yulVal);
        console.log("=== getValue Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
        console.log("Diff:    ", int256(gasSolidity) - int256(gasYul));
    }

    // ═══════════════════════════════════════════════════════
    // 2. 写入 Storage 正确性
    // ═══════════════════════════════════════════════════════

    function testSetValueMatches() public {
        yul.setValueYul(99);
        assertEq(yul.getValueYul(), 99);
        assertEq(yul.getValueSolidity(), 99);
    }

    function testSetValueGasComparison() public {
        // Solidity 版（带 event）
        uint256 gasBefore = gasleft();
        yul.setValueSolidity(100);
        uint256 gasSolidity = gasBefore - gasleft();

        // Yul 版（纯写入，无 event）
        uint256 gasBefore2 = gasleft();
        yul.setValueYul(200);
        uint256 gasYul = gasBefore2 - gasleft();

        // Yul 版（带 event）
        uint256 gasBefore3 = gasleft();
        yul.setValueYulWithEvent(300);
        uint256 gasYulEvent = gasBefore3 - gasleft();

        console.log("=== setValue Gas Comparison ===");
        console.log("Solidity (with event):", gasSolidity);
        console.log("Yul (raw sstore):    ", gasYul);
        console.log("Yul (with event):    ", gasYulEvent);
    }

    // ═══════════════════════════════════════════════════════
    // 3. 条件判断正确性
    // ═══════════════════════════════════════════════════════

    function testMaxMatches() public {
        assertEq(yul.maxSolidity(5, 3), yul.maxYul(5, 3));
        assertEq(yul.maxSolidity(3, 5), yul.maxYul(3, 5));
        assertEq(yul.maxSolidity(5, 5), yul.maxYul(5, 5));
        assertEq(yul.maxSolidity(0, 100), yul.maxYul(0, 100));
    }

    function testMaxSwitchMatches() public {
        assertEq(yul.maxSolidity(5, 3), yul.maxYulSwitch(5, 3));
        assertEq(yul.maxSolidity(3, 5), yul.maxYulSwitch(3, 5));
        assertEq(yul.maxSolidity(5, 5), yul.maxYulSwitch(5, 5));
    }

    function testMaxGasComparison() public {
        uint256 gasBefore = gasleft();
        yul.maxSolidity(100, 200);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.maxYul(100, 200);
        uint256 gasYul = gasBefore2 - gasleft();

        uint256 gasBefore3 = gasleft();
        yul.maxYulSwitch(100, 200);
        uint256 gasYulSwitch = gasBefore3 - gasleft();

        console.log("=== max Gas Comparison ===");
        console.log("Solidity:  ", gasSolidity);
        console.log("Yul if:    ", gasYul);
        console.log("Yul switch:", gasYulSwitch);
    }

    // ═══════════════════════════════════════════════════════
    // 4. 循环正确性
    // ═══════════════════════════════════════════════════════

    function testSumMatches() public {
        assertEq(yul.sumSolidity(10), yul.sumYul(10));
        assertEq(yul.sumSolidity(100), yul.sumYul(100));
        assertEq(yul.sumSolidity(0), yul.sumYul(0));
        assertEq(yul.sumSolidity(1), yul.sumYul(1));
    }

    function testSumGasComparison() public {
        uint256 gasBefore = gasleft();
        yul.sumSolidity(100);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.sumYul(100);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== sum(100) Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
    }

    // ═══════════════════════════════════════════════════════
    // 5. 内存操作正确性
    // ═══════════════════════════════════════════════════════

    function testHashMatches() public {
        bytes memory data = "Hello, Yul!";
        bytes32 solHash = yul.hashSolidity(data);
        bytes32 yulHash = yul.hashYul(data);
        assertEq(solHash, yulHash, "Yul hash should match Solidity hash");
    }

    function testHashEmptyMatches() public {
        bytes memory data = "";
        assertEq(yul.hashSolidity(data), yul.hashYul(data));
    }

    function testHashGasComparison() public {
        bytes memory data = "Hello, Yul! This is a longer string for hash testing.";

        uint256 gasBefore = gasleft();
        yul.hashSolidity(data);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.hashYul(data);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== hash Gas Comparison ===");
        console.log("Solidity keccak256:", gasSolidity);
        console.log("Yul keccak256:     ", gasYul);
    }

    // ═══════════════════════════════════════════════════════
    // 6. Mapping 读取正确性
    // ═══════════════════════════════════════════════════════

    function testGetBalanceMatches() public {
        address alice = makeAddr("alice");
        yul.setBalanceSolidity(alice, 1000);

        uint256 sol = yul.getBalanceSolidity(alice);
        uint256 yulVal = yul.getBalanceYul(alice);
        assertEq(sol, yulVal, "Yul balance read should match Solidity");
        assertEq(yulVal, 1000);
    }

    function testGetBalanceGasComparison() public {
        address alice = makeAddr("alice");
        yul.setBalanceSolidity(alice, 5000);

        uint256 gasBefore = gasleft();
        yul.getBalanceSolidity(alice);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.getBalanceYul(alice);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== balanceOf Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
    }

    // ═══════════════════════════════════════════════════════
    // 7. Mapping 写入正确性
    // ═══════════════════════════════════════════════════════

    function testSetBalanceMatches() public {
        address bob = makeAddr("bob");
        yul.setBalanceYul(bob, 2000);
        assertEq(yul.getBalanceSolidity(bob), 2000);
        assertEq(yul.getBalanceYul(bob), 2000);
    }

    function testSetBalanceGasComparison() public {
        address alice = makeAddr("alice_set");

        uint256 gasBefore = gasleft();
        yul.setBalanceSolidity(alice, 1000);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.setBalanceYul(alice, 2000);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== setBalance Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
    }

    // ═══════════════════════════════════════════════════════
    // 8. Packed Storage 正确性
    // ═══════════════════════════════════════════════════════

    function testPackedSolidityMatchesYul() public {
        yul.setPackedSolidity(123, 456);
        (uint128 a1, uint128 b1) = yul.getPackedSolidity();
        (uint128 a2, uint128 b2) = yul.getPackedYul();
        assertEq(a1, a2);
        assertEq(b1, b2);
        assertEq(a1, 123);
        assertEq(b1, 456);
    }

    function testPackedYulWriteMatches() public {
        yul.setPackedYul(789, 101112);
        (uint128 a, uint128 b) = yul.getPackedSolidity();
        assertEq(a, 789);
        assertEq(b, 101112);
    }

    function testPackedGasComparison() public {
        uint256 gasBefore = gasleft();
        yul.setPackedSolidity(100, 200);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        yul.setPackedYul(300, 400);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== setPacked Gas Comparison ===");
        console.log("Solidity (shift + or):", gasSolidity);
        console.log("Yul (shl + or + sstore):", gasYul);

        uint256 gasBefore3 = gasleft();
        yul.getPackedSolidity();
        uint256 gasGetSolidity = gasBefore3 - gasleft();

        uint256 gasBefore4 = gasleft();
        yul.getPackedYul();
        uint256 gasGetYul = gasBefore4 - gasleft();

        console.log("=== getPacked Gas Comparison ===");
        console.log("Solidity (shift + cast):", gasGetSolidity);
        console.log("Yul (sload + shr + and):", gasGetYul);
    }

    // ═══════════════════════════════════════════════════════
    // 综合报告
    // ═══════════════════════════════════════════════════════

    function testFullYulComparisonReport() public {
        console.log("");
        console.log("============================================");
        console.log("  Week 11 Yul vs Solidity Gas Comparison   ");
        console.log("============================================");
        console.log("");

        // getValue
        yul.setValueSolidity(42);
        uint256 g1 = gasleft();
        yul.getValueSolidity();
        uint256 gs1 = g1 - gasleft();
        uint256 g2 = gasleft();
        yul.getValueYul();
        uint256 gy2 = g2 - gasleft();
        _printRow("getValue", gs1, gy2);

        // setValue (no event)
        g1 = gasleft();
        yul.setValueSolidity(100);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.setValueYul(200);
        gy2 = g2 - gasleft();
        _printRow("setValue", gs1, gy2);

        // max
        g1 = gasleft();
        yul.maxSolidity(50, 60);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.maxYul(50, 60);
        gy2 = g2 - gasleft();
        _printRow("max", gs1, gy2);

        // sum(100)
        g1 = gasleft();
        yul.sumSolidity(100);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.sumYul(100);
        gy2 = g2 - gasleft();
        _printRow("sum(100)", gs1, gy2);

        // hash
        bytes memory data = "Hello World!";
        g1 = gasleft();
        yul.hashSolidity(data);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.hashYul(data);
        gy2 = g2 - gasleft();
        _printRow("hash", gs1, gy2);

        // balanceOf
        address alice = makeAddr("alice_report");
        yul.setBalanceSolidity(alice, 500);
        g1 = gasleft();
        yul.getBalanceSolidity(alice);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.getBalanceYul(alice);
        gy2 = g2 - gasleft();
        _printRow("balanceOf", gs1, gy2);

        // packed get
        yul.setPackedSolidity(111, 222);
        g1 = gasleft();
        yul.getPackedSolidity();
        gs1 = g1 - gasleft();
        g2 = gasleft();
        yul.getPackedYul();
        gy2 = g2 - gasleft();
        _printRow("getPacked", gs1, gy2);

        console.log("");
        console.log("============================================");
    }

    function _printRow(string memory name, uint256 solGas, uint256 yulGas) internal view {
        int256 diff = int256(solGas) - int256(yulGas);
        console.log("Function:", name);
        console.log("  Solidity:", solGas);
        console.log("  Yul:     ", yulGas);
        console.log("  Diff:    ", diff);
    }
}
