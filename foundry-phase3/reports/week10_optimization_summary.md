# Week 10 Gas 优化总结

## 优化前 vs 优化后

| 合约 | 函数 | 优化前 Gas | 优化后 Gas | 节省 | 节省率 |
|------|------|-----------|-----------|------|--------|
| SimpleAMM | addLiquidity | 297,917 | 241,065 | 56,852 | **19%** |
| SimpleAMM | swap | 28,822 | 18,774 | 10,048 | **34%** |
| SimpleAMM | removeLiquidity | 20,537 | 20,083 | 454 | 2% |
| MyNFT | batchMint(10) | 306,045 | 304,323 | 1,722 | 0.6% |
| MyNFT | batchMint(20) | 527,787 | 524,044 | 3,743 | 0.7% |
| Router | swap(2-hop) | 184,127 | 174,479 | 9,648 | 5% |
| MyNFT | setBaseURI (calldata) | 13,386 | 13,106 | 280 | 2% |

## 应用的优化技巧

### 1. 存储槽打包（Slot Packing）

**优化**: 将 `feeTo`(20B) + `blockTimestampLast`(4B) 打包到同一 slot

**原版存储布局**:
```
Slot 9:  feeTo (address, 20B) — 12B 浪费
Slot 10: feeToSetter (address, 20B)
Slot 11: pendingFeeToSetter (address, 20B)
...
Slot 15: blockTimestampLast (uint32, 4B) — 28B 浪费
```

**优化版存储布局**:
```
Slot 9:  feeTo (address, 20B) + blockTimestampLast (uint32, 4B) — 节省 1 slot
Slot 10: feeToSetter (address, 20B)
Slot 11: pendingFeeToSetter (address, 20B)
...
Slot 14: price1CumulativeLast (uint256)
// slot 15 不再需要
```

**效果**: 总 slot 数从 16 减到 15。当 `_mintFee()` 读取 `feeTo` 后，同 slot 的 `blockTimestampLast` 在 `_update()` 中变为热访问（100 gas vs 2100 gas）。

### 2. 消除冗余存储写入

**优化**: `_update()` 不再重复写入 `_reserveA`/`_reserveB`

**原版**:
```solidity
_reserveA += amountA;  // SSTORE
_reserveB += amountB;  // SSTORE
_update(_reserveA, _reserveB, true);  // 内部又写一次 _reserveA, _reserveB
```

**优化版**:
```solidity
uint256 newReserveA = _reserveA + amountA;  // 读一次
uint256 newReserveB = _reserveB + amountB;  // 读一次
_update(newReserveA, newReserveB, true);    // _update 内只写一次
```

**效果**: swap 优化 34%（10,048 gas），addLiquidity 优化 19%（56,852 gas）。这是最有效的优化。

### 3. unchecked + 缓存循环变量

**优化**: MyNFT `batchMint` 缓存 `_nextTokenId` + `unchecked { ++i }`

**原版**:
```solidity
for (uint256 i = 0; i < quantity; i++) {
    uint256 tokenId = _nextTokenId++;  // 每次循环 SLOAD + SSTORE
    _safeMint(to, tokenId);
}
```

**优化版**:
```solidity
uint256 startId = _nextTokenId;    // 1 SLOAD
_nextTokenId = startId + quantity;  // 1 SSTORE
for (uint256 i; i < quantity;) {
    _safeMint(to, startId + i);
    unchecked { ++i; }              // 跳过溢出检查
}
```

**效果**: batchMint(10) 节省 1,722 gas（0.6%），batchMint(20) 节省 3,743 gas（0.7%）。

**注意**: 优化幅度比预期小，因为 Solidity 编译器（via_ir=true, optimizer_runs=200）已经在编译期做了部分缓存优化。真正的收益在禁用优化器或低 optimizer_runs 时会更显著。

### 4. 事件替代存储分析

**结论**: 所有 storage 变量都在链上被读取，没有"只写不读"的 mapping 可以用事件替代。现有设计已经合理。

- `_kLast`: 被 `_mintFee()` 读取计算协议费
- `price0/1CumulativeLast`: 被 `consult()` 读取计算 TWAP
- `pairFor` mapping: 被 Router 的 swap 路径查找读取

### 5. Calldata 替代 Memory

**优化**: `setBaseURI` 参数从 `string memory` 改为 `string calldata`

**效果**: 节省 280 gas（2%）。calldata 避免了从 calldata 复制到 memory 的开销。

## 整体效果

| 指标 | 值 |
|------|------|
| 测试套件 | 86 tests, 全部通过 |
| Top1 优化 | swap -34% gas |
| Top2 优化 | addLiquidity -19% gas |
| Top3 优化 | Router swap -5% gas |
| 涉及优化技巧 | 5 项全部覆盖 |

## 教训

1. **冗余写入是最大的 Gas 杀手** — `_update()` 中重复写入 reserve 变量浪费了 ~34% 的 swap gas
2. **Solidity 优化器很强大** — via_ir + optimizer_runs=200 已经做了很多缓存优化，手动缓存效果被削弱
3. **Slot Packing 的价值** — 不只是省 slot 数，更重要的是让同 slot 变量成为热访问
4. **Calldata 优化** — 对大数组/string 参数有效果，但对短字符串提升有限
5. **事件 vs 存储** — 不是所有场景都适合用事件替代，AMM 的 TWAP 就必须用存储

## 优化文件清单

| 文件 | 说明 |
|------|------|
| `src/SimpleAMM_Optimized.sol` | Slot packing + 消除冗余写入 |
| `src/MyNFT_Optimized.sol` | batchMint 缓存 + unchecked |
| `src/ChainForgeRouter_Optimized.sol` | 循环缓存 + unchecked + calldata |
| `test/GasComparison.t.sol` | Gas 对比测试（9 个测试） |
| `reports/week10_optimized_gas_report.md` | 完整 Gas 报告 |
| `.gas-snapshot-week10-optimized` | Gas 快照基线 |
