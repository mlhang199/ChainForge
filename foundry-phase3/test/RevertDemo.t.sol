// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/RevertDemo.sol";

/**
 * @title RevertDemoTest
 * @dev Week 11 — Opcode 调试实战：观察各种 revert 场景的 trace 输出
 *
 * 使用 `forge test --match-test testXXX -vvvv` 查看完整 Opcode trace。
 */
contract RevertDemoTest is Test {
    RevertDemo demo;
    address alice = makeAddr("alice");

    function setUp() public {
        demo = new RevertDemo();
        vm.deal(alice, 10 ether);
    }

    // ═══════════════════════════════════════════════════════
    // 场景 1: require 带消息
    // ═══════════════════════════════════════════════════════

    function testWithdrawRevertWithMessage() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        demo.withdraw(1 ether);
    }

    function testWithdrawSuccess() public {
        vm.prank(alice);
        demo.deposit{value: 1 ether}();

        vm.prank(alice);
        demo.withdraw(0.5 ether);

        assertEq(demo.balance(), 0.5 ether);
    }

    // ═══════════════════════════════════════════════════════
    // 场景 2: require 无消息
    // ═══════════════════════════════════════════════════════

    function testWithdrawSilentRevert() public {
        vm.prank(alice);
        vm.expectRevert();
        demo.withdrawSilent(1 ether);
    }

    // ═══════════════════════════════════════════════════════
    // 场景 3: 自定义错误
    // ═══════════════════════════════════════════════════════

    function testWithdrawCustomError() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RevertDemo.InsufficientBalance.selector, 1 ether, 0)
        );
        demo.withdrawCustom(1 ether);
    }

    // ═══════════════════════════════════════════════════════
    // 场景 4: 除零
    // ═══════════════════════════════════════════════════════

    function testDivideByZero() public {
        vm.expectRevert();
        demo.divide(10, 0);
    }

    function testDivideSuccess() public {
        assertEq(demo.divide(10, 2), 5);
    }

    // ═══════════════════════════════════════════════════════
    // 场景 5: 数组越界
    // ═══════════════════════════════════════════════════════

    function testArrayOutOfBounds() public {
        demo.addItem(42);
        assertEq(demo.getItem(0), 42);

        vm.expectRevert();
        demo.getItem(1); // 越界
    }

    // ═══════════════════════════════════════════════════════
    // 场景 6: 嵌套调用链
    // ═══════════════════════════════════════════════════════

    function testNestedCallRevert() public {
        vm.expectRevert("Amount must be positive");
        demo.outerCall(0);
    }

    function testNestedCallSuccess() public {
        demo.outerCall(1);
    }

    // ═══════════════════════════════════════════════════════
    // Gas 分析：成功 vs 失败
    // ═══════════════════════════════════════════════════════

    function testRevertGasCost() public {
        // 成功路径
        vm.prank(alice);
        demo.deposit{value: 10 ether}();

        uint256 gasSuccess = gasleft();
        vm.prank(alice);
        demo.withdraw(1 ether);
        uint256 gasUsedSuccess = gasSuccess - gasleft();

        // 失败路径 — 捕获 revert 的 gas
        uint256 gasBeforeRevert = gasleft();
        vm.prank(alice);
        try demo.withdraw(100 ether) {
            fail("Should have reverted");
        } catch {
            // 成功捕获
        }
        uint256 gasUsedRevert = gasBeforeRevert - gasleft();

        console.log("=== Revert Gas Analysis ===");
        console.log("Successful withdraw:", gasUsedSuccess);
        console.log("Failed withdraw:    ", gasUsedRevert);
        console.log("Revert overhead:    ", gasUsedRevert > gasUsedSuccess ? gasUsedRevert - gasUsedSuccess : 0);
    }
}
