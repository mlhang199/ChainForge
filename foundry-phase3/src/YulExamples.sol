// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title YulExamples
 * @dev Week 11 EVM 深入 — Yul 内联汇编实验
 *
 * 实验项：
 *   1. Yul 读取 storage（sload）
 *   2. Yul 写入 storage（sstore）
 *   3. Yul 条件判断（if/switch）
 *   4. Yul 循环（for）
 *   5. Yul 内存操作（mload/mstore）
 *   6. Yul 计算 keccak256
 *   7. 纯 Solidity 对照版本
 */
contract YulExamples {
    uint256 public value;
    uint256 public count;
    mapping(address => uint256) public balances;

    event ValueChanged(uint256 oldValue, uint256 newValue);
    event Counted(uint256 result);

    // ═══════════════════════════════════════════════════════
    // 1. Yul 读取 storage
    // ═══════════════════════════════════════════════════════

    function getValueSolidity() external view returns (uint256) {
        return value;
    }

    function getValueYul() external view returns (uint256 v) {
        assembly {
            v := sload(value.slot)
        }
    }

    function getValueYulOffset() external view returns (uint256 v) {
        // 展示 .slot 和 .offset 的区别
        assembly {
            v := sload(value.slot) // value 在 slot 0，offset 0
        }
    }

    // ═══════════════════════════════════════════════════════
    // 2. Yul 写入 storage
    // ═══════════════════════════════════════════════════════

    function setValueSolidity(uint256 newValue) external {
        uint256 old = value;
        value = newValue;
        emit ValueChanged(old, newValue);
    }

    function setValueYul(uint256 newValue) external {
        assembly {
            sstore(value.slot, newValue)
        }
        // 注意：Yul 版本不触发 event，因为 event 需要额外处理
    }

    function setValueYulWithEvent(uint256 newValue) external {
        uint256 old;
        assembly {
            old := sload(value.slot)
            sstore(value.slot, newValue)
        }
        emit ValueChanged(old, newValue);
    }

    // ═══════════════════════════════════════════════════════
    // 3. Yul 条件判断
    // ═══════════════════════════════════════════════════════

    function maxSolidity(uint256 a, uint256 b) external pure returns (uint256) {
        return a >= b ? a : b;
    }

    function maxYul(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            if iszero(lt(a, b)) { result := a }
            if lt(a, b) { result := b }
        }
    }

    function maxYulSwitch(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            switch lt(a, b)
            case 1 { result := b }
            default { result := a }
        }
    }

    // ═══════════════════════════════════════════════════════
    // 4. Yul 循环
    // ═══════════════════════════════════════════════════════

    function sumSolidity(uint256 n) external pure returns (uint256) {
        uint256 s;
        for (uint256 i = 1; i <= n; i++) {
            s += i;
        }
        return s;
    }

    function sumYul(uint256 n) external pure returns (uint256 result) {
        assembly {
            for { let i := 1 } lt(i, add(n, 1)) { i := add(i, 1) } {
                result := add(result, i)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // 5. Yul 内存操作
    // ═══════════════════════════════════════════════════════

    function hashSolidity(bytes memory data) external pure returns (bytes32) {
        return keccak256(data);
    }

    function hashYul(bytes memory data) external view returns (bytes32 h) {
        assembly {
            let len := mload(data)        // bytes 长度在 data 前面 32 字节
            let ptr := add(data, 0x20)    // 实际数据起始位置
            h := keccak256(ptr, len)      // keccak256(ptr, len)
        }
    }

    // ═══════════════════════════════════════════════════════
    // 6. Yul 读取 mapping
    // ═══════════════════════════════════════════════════════

    function getBalanceSolidity(address account) external view returns (uint256) {
        return balances[account];
    }

    function getBalanceYul(address account) external view returns (uint256 b) {
        // balances mapping 在 slot 2
        // balances[account] 的存储位置 = keccak256(abi.encode(account, 2))
        assembly {
            mstore(0x00, account)
            mstore(0x20, balances.slot)
            let slot := keccak256(0x00, 0x40)
            b := sload(slot)
        }
    }

    // ═══════════════════════════════════════════════════════
    // 7. Yul 写入 mapping
    // ═══════════════════════════════════════════════════════

    function setBalanceSolidity(address account, uint256 amount) external {
        balances[account] = amount;
    }

    function setBalanceYul(address account, uint256 amount) external {
        assembly {
            mstore(0x00, account)
            mstore(0x20, balances.slot)
            let slot := keccak256(0x00, 0x40)
            sstore(slot, amount)
        }
    }

    // ═══════════════════════════════════════════════════════
    // 8. Yul 优化：存储多个值到同一 slot
    // ═══════════════════════════════════════════════════════

    // 假设我们要在一个 slot 中存储两个 uint128
    uint256 private _packedData; // slot 3: high 128 bits = valueA, low 128 bits = valueB

    function setPackedSolidity(uint128 a, uint128 b) external {
        _packedData = (uint256(a) << 128) | uint256(b);
    }

    function getPackedSolidity() external view returns (uint128 a, uint128 b) {
        a = uint128(_packedData >> 128);
        b = uint128(_packedData);
    }

    function setPackedYul(uint128 a, uint128 b) external {
        assembly {
            let packed := or(shl(128, a), b)
            sstore(_packedData.slot, packed)
        }
    }

    function getPackedYul() external view returns (uint128 a, uint128 b) {
        assembly {
            let packed := sload(_packedData.slot)
            a := shr(128, packed)
            b := and(packed, 0xffffffffffffffffffffffffffffffff) // 低 128 位
        }
    }
}
