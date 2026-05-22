// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title RevertDemo
 * @dev Week 11 — 故意 revert 场景，用于 forge -vvvv trace 调试
 *
 * 场景：
 *   1. require 失败（带消息）
 *   2. require 失败（无消息）
 *   3. revert 自定义错误
 *   4. 除零错误
 *   5. 数组越界
 *   6. 重入攻击被 ReentrancyGuard 拦截
 */
contract RevertDemo {
    uint256 public balance;
    bool private _locked;
    uint256[] public items;

    error InsufficientBalance(uint256 requested, uint256 available);
    error Unauthorized();
    error ReentrantCall();

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // 场景 1: require 带消息
    function withdraw(uint256 amount) external {
        require(balance >= amount, "Insufficient balance");
        balance -= amount;
    }

    // 场景 2: require 无消息
    function withdrawSilent(uint256 amount) external {
        require(balance >= amount);
        balance -= amount;
    }

    // 场景 3: 自定义错误
    function withdrawCustom(uint256 amount) external {
        if (balance < amount) {
            revert InsufficientBalance(amount, balance);
        }
        balance -= amount;
    }

    // 场景 4: 除零（Solidity 自动检查）
    function divide(uint256 a, uint256 b) external pure returns (uint256) {
        return a / b;
    }

    // 场景 5: 数组越界
    function getItem(uint256 index) external view returns (uint256) {
        return items[index]; // 越界时自动 revert
    }

    // 场景 6: 模拟重入
    function protectedAction() external nonReentrant {
        // 做一些操作
        balance = balance + 1;
    }

    // 辅助函数
    function deposit() external payable {
        balance += msg.value;
    }

    function addItem(uint256 item) external {
        items.push(item);
    }

    // 嵌套调用链 — 追踪 revert 传播
    function outerCall(uint256 amount) external {
        _innerCall(amount);
    }

    function _innerCall(uint256 amount) internal {
        _deepestCall(amount);
    }

    function _deepestCall(uint256 amount) internal pure {
        require(amount > 0, "Amount must be positive");
    }
}
