// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyToken.sol";
import "../src/MyTokenWithYul.sol";

/**
 * @title MyTokenWithYulTest
 * @dev Week 11 — Yul 重写 balanceOf 正确性验证 + Gas 对比
 */
contract MyTokenWithYulTest is Test {
    MyToken token;
    MyTokenWithYul tokenYul;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MyToken("ChainForge Token", "CFT", 1_000_000, 0);
        tokenYul = new MyTokenWithYul("ChainForge Token Yul", "CFTY", 1_000_000, 0);

        token.transfer(alice, 10_000 * 1e18);
        token.transfer(bob, 5_000 * 1e18);

        tokenYul.transfer(alice, 10_000 * 1e18);
        tokenYul.transfer(bob, 5_000 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    // balanceOf 正确性
    // ═══════════════════════════════════════════════════════

    function testBalanceOfMatches() public {
        assertEq(
            tokenYul.balanceOf(alice),
            tokenYul.balanceOfYul(alice),
            "Yul balanceOf should match Solidity balanceOf"
        );
        assertEq(
            tokenYul.balanceOf(bob),
            tokenYul.balanceOfYul(bob),
            "Yul balanceOf for bob should match"
        );
    }

    function testBalanceOfZeroAddress() public {
        assertEq(tokenYul.balanceOfYul(address(0)), 0, "Zero address balance should be 0");
    }

    function testBalanceOfAfterTransfer() public {
        vm.prank(alice);
        tokenYul.transfer(bob, 1000 * 1e18);

        assertEq(tokenYul.balanceOf(alice), tokenYul.balanceOfYul(alice));
        assertEq(tokenYul.balanceOf(bob), tokenYul.balanceOfYul(bob));
    }

    // ═══════════════════════════════════════════════════════
    // totalSupply 正确性
    // ═══════════════════════════════════════════════════════

    function testTotalSupplyMatches() public {
        assertEq(
            tokenYul.totalSupply(),
            tokenYul.totalSupplyYul(),
            "Yul totalSupply should match Solidity totalSupply"
        );
    }

    function testTotalSupplyAfterMint() public {
        uint256 supplyBefore = tokenYul.totalSupplyYul();
        tokenYul.mint(alice, 1000);
        uint256 supplyAfter = tokenYul.totalSupplyYul();
        assertEq(supplyAfter - supplyBefore, 1000 * 1e18);
        assertEq(tokenYul.totalSupply(), tokenYul.totalSupplyYul());
    }

    // ═══════════════════════════════════════════════════════
    // allowance 正确性
    // ═══════════════════════════════════════════════════════

    function testAllowanceMatches() public {
        vm.prank(alice);
        tokenYul.approve(bob, 500 * 1e18);

        assertEq(
            tokenYul.allowance(alice, bob),
            tokenYul.allowanceYul(alice, bob),
            "Yul allowance should match Solidity allowance"
        );
    }

    function testAllowanceZeroBeforeApprove() public {
        assertEq(tokenYul.allowanceYul(alice, bob), 0);
    }

    // ═══════════════════════════════════════════════════════
    // maxSupply 正确性
    // ═══════════════════════════════════════════════════════

    function testMaxSupplyMatches() public {
        assertEq(tokenYul.maxSupply(), tokenYul.maxSupplyYul());
    }

    function testMaxSupplyWithLimit() public {
        MyTokenWithYul limited = new MyTokenWithYul("Limited", "LMT", 100, 1_000_000);
        assertEq(limited.maxSupply(), limited.maxSupplyYul());
    }

    // ═══════════════════════════════════════════════════════
    // Gas 对比
    // ═══════════════════════════════════════════════════════

    function testBalanceOfGasComparison() public {
        uint256 gasBefore = gasleft();
        tokenYul.balanceOf(alice);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        tokenYul.balanceOfYul(alice);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== balanceOf Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
        console.log("Saved:   ", gasSolidity > gasYul ? gasSolidity - gasYul : 0);
    }

    function testTotalSupplyGasComparison() public {
        uint256 gasBefore = gasleft();
        tokenYul.totalSupply();
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        tokenYul.totalSupplyYul();
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== totalSupply Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
        console.log("Saved:   ", gasSolidity > gasYul ? gasSolidity - gasYul : 0);
    }

    function testAllowanceGasComparison() public {
        vm.prank(alice);
        tokenYul.approve(bob, 500 * 1e18);

        uint256 gasBefore = gasleft();
        tokenYul.allowance(alice, bob);
        uint256 gasSolidity = gasBefore - gasleft();

        uint256 gasBefore2 = gasleft();
        tokenYul.allowanceYul(alice, bob);
        uint256 gasYul = gasBefore2 - gasleft();

        console.log("=== allowance Gas Comparison ===");
        console.log("Solidity:", gasSolidity);
        console.log("Yul:     ", gasYul);
        console.log("Saved:   ", gasSolidity > gasYul ? gasSolidity - gasYul : 0);
    }

    // ═══════════════════════════════════════════════════════
    // 综合报告
    // ═══════════════════════════════════════════════════════

    function testFullYulRewriteReport() public {
        console.log("");
        console.log("==============================================");
        console.log("  MyTokenWithYul Rewrite Gas Comparison       ");
        console.log("==============================================");
        console.log("");

        // balanceOf
        uint256 g1 = gasleft();
        tokenYul.balanceOf(alice);
        uint256 gs1 = g1 - gasleft();
        uint256 g2 = gasleft();
        tokenYul.balanceOfYul(alice);
        uint256 gy2 = g2 - gasleft();
        _printRow("balanceOf", gs1, gy2);

        // totalSupply
        g1 = gasleft();
        tokenYul.totalSupply();
        gs1 = g1 - gasleft();
        g2 = gasleft();
        tokenYul.totalSupplyYul();
        gy2 = g2 - gasleft();
        _printRow("totalSupply", gs1, gy2);

        // allowance (nested mapping)
        vm.prank(alice);
        tokenYul.approve(bob, 500 * 1e18);
        g1 = gasleft();
        tokenYul.allowance(alice, bob);
        gs1 = g1 - gasleft();
        g2 = gasleft();
        tokenYul.allowanceYul(alice, bob);
        gy2 = g2 - gasleft();
        _printRow("allowance", gs1, gy2);

        // maxSupply
        g1 = gasleft();
        tokenYul.maxSupply();
        gs1 = g1 - gasleft();
        g2 = gasleft();
        tokenYul.maxSupplyYul();
        gy2 = g2 - gasleft();
        _printRow("maxSupply", gs1, gy2);

        console.log("");
        console.log("==============================================");
    }

    function _printRow(string memory name, uint256 solGas, uint256 yulGas) internal view {
        int256 diff = int256(solGas) - int256(yulGas);
        console.log("Function:", name);
        console.log("  Solidity:", solGas);
        console.log("  Yul:     ", yulGas);
        console.log("  Diff:    ", diff);
    }
}
