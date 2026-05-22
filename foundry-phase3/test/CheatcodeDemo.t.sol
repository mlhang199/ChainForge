// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "forge-std/Test.sol";

// 辅助合约：用来测试 vm.prank 的效果
contract Greeter {
    address public lastCaller;

    function greet() external returns (address) {
        lastCaller = msg.sender;
        return msg.sender;
    }
}

contract CheatcodeDemo is Test {
    // ── 1. vm.prank: 伪装身份（影响外部调用） ──
    function testPrank() public {
        address alice = makeAddr("alice");
        Greeter greeter = new Greeter();

        vm.prank(alice);
        address caller = greeter.greet();  // 外部调用，msg.sender 是 alice
        assertEq(caller, alice);
        assertEq(greeter.lastCaller(), alice);
    }

    // ── 2. vm.deal: 无中生有给 ETH ──
    function testDeal() public {
        address bob = makeAddr("bob");
        assertEq(bob.balance, 0);           // 刚创建，0 ETH

        vm.deal(bob, 100 ether);            // 直接给 100 ETH
        assertEq(bob.balance, 100 ether);   // 现在有 100 ETH 了！
    }

    // ── 3. vm.warp: 时间旅行 ──
    function testWarp() public {
        vm.warp(1_000_000);                 // 设置 timestamp = 1,000,000
        assertEq(block.timestamp, 1_000_000);

        vm.warp(1_000_000 + 1 days);        // 快进 1 天
        assertEq(block.timestamp, 1_000_000 + 1 days);
    }

    // ── 4. vm.expectRevert: 预期 revert ──
    function testExpectRevert() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert();                  // 下一个调用应该 revert
        payable(address(0)).transfer(1);    // alice 没有 ETH，转账必然失败
    }

    // ── 5. vm.startPrank / stopPrank: 持续伪装（影响外部调用） ──
    function testStartPrank() public {
        address alice = makeAddr("alice");
        Greeter greeter = new Greeter();

        vm.startPrank(alice);
        address caller1 = greeter.greet();  // 第一次调用：alice
        address caller2 = greeter.greet();  // 第二次调用：还是 alice
        vm.stopPrank();

        assertEq(caller1, alice);
        assertEq(caller2, alice);
    }

    // ── 6. vm.expectEmit: 验证事件 ──
    function testExpectEmit() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(1), 100);
        emit Transfer(address(0), address(1), 100); // 匹配成功
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
}
