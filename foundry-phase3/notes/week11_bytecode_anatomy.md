# Week 11 字节码解剖笔记

## 1. 合约字节码概览

| 合约 | Runtime Bytecode (字节) | Creation Bytecode (字节) |
|------|------------------------|------------------------|
| MyToken | 3,759 | 5,987 |
| MyNFT | 5,025 | - |
| SimpleAMM | 10,130 | 11,474 |
| ChainForgeRouter | 4,497 | - |

## 2. 创建字节码 vs 运行时字节码

### 创建字节码（Creation Bytecode）
- **作用**：部署时执行，运行构造函数，返回 runtime bytecode
- **结构**：`init code` + `runtime bytecode` + `auxdata（CBOR 编码的元数据）`
- **执行流程**：
  1. EVM 执行 init code
  2. init code 运行构造函数逻辑
  3. `CODECOPY` 将 runtime bytecode 复制到内存
  4. `RETURN` 返回 runtime bytecode
  5. Runtime bytecode 被存储到链上

### 运行时字节码（Runtime Bytecode）
- **作用**：部署后实际执行的逻辑，存储在链上
- **结构**：函数分派器 + 函数体 + 元数据
- **不可变**：部署后无法修改（除非使用代理模式）

## 3. MyToken 函数选择器

从 `forge inspect MyToken methodIdentifiers` 获取的关键选择器：

| 函数 | 选择器 (4 bytes) | 说明 |
|------|-----------------|------|
| `transfer(address,uint256)` | `0xa9059cbb` | 最常用的 ERC20 函数 |
| `balanceOf(address)` | `0x70a08231` | 查询余额 |
| `approve(address,uint256)` | `0x095ea7b3` | 授权 |
| `transferFrom(address,address,uint256)` | `0x23b872dd` | 代理转账 |
| `totalSupply()` | `0x18160ddd` | 总供应量 |
| `name()` | `0x06fdde03` | 代币名称 |
| `symbol()` | `0x95d89b41` | 代币符号 |
| `decimals()` | `0x313ce567` | 精度 |
| `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)` | `0xd505accf` | EIP-2612 签名授权 |
| `mint(address,uint256)` | `0x40c10f19` | 铸造代币 |

### 函数分派机制

当调用合约时，EVM 执行流程：
1. `CALLDATALOAD 0x00` 读取前 4 字节（函数选择器）
2. 与已知选择器比较（`DUP1` + `EQ` + `JUMPI`）
3. 匹配后跳转到对应函数体
4. 不匹配则 fallback 或 revert

## 4. MyToken 存储布局

| Slot | 变量 | 类型 | 大小 |
|------|------|------|------|
| 0 | `_balances` | mapping(address => uint256) | 32B |
| 1 | `_allowances` | mapping(address => mapping(address => uint256)) | 32B |
| 2 | `_totalSupply` | uint256 | 32B |
| 3 | `_name` | string | 32B |
| 4 | `_symbol` | string | 32B |
| 5 | `_nameFallback` | string | 32B |
| 6 | `_versionFallback` | string | 32B |
| 7 | `_nonces` | mapping(address => uint256) | 32B |
| 8 | `_owner` | address | 20B（剩余 12B 空闲）|
| 9 | `_maxSupply` | uint256 | 32B |

**发现**：`_owner`(slot 8) 只有 20 字节，剩余 12 字节空闲。但 `_maxSupply` 是 uint256 无法打包。

## 5. SimpleAMM 存储布局

| Slot | 变量 | 类型 | 大小 |
|------|------|------|------|
| 0-5 | ERC20 + ReentrancyGuard | - | - |
| 6 | `_paused`(1B) + `_owner`(20B) | bool + address | 21B 打包 |
| 7 | `_reserveA` | uint256 | 32B |
| 8 | `_reserveB` | uint256 | 32B |
| 9 | `feeTo` | address | 20B（12B 空闲）|
| 10 | `feeToSetter` | address | 20B（12B 空闲）|
| 11 | `pendingFeeToSetter` | address | 20B（12B 空闲）|
| 12 | `_kLast` | uint256 | 32B |
| 13 | `price0CumulativeLast` | uint256 | 32B |
| 14 | `price1CumulativeLast` | uint256 | 32B |
| 15 | `blockTimestampLast` | uint32 | 4B（28B 空闲）|

**优化机会（已在 Week 10 实施）**：
- `feeTo`(20B) + `blockTimestampLast`(4B) 可打包到 slot 9
- `feeToSetter`(20B) + `pendingFeeToSetter`(20B) 理论上可打包但需要手动管理偏移

## 6. 关键 Assembly 片段分析

### 函数分派器（MyToken）

```asm
/* transfer(address,uint256) */
  0xa9059cbb    // PUSH4 函数选择器
  dup2          // 复制 calldata 前 4 字节
  eq            // 比较
  tag_XX        // 匹配后跳转目标
  jumpi         // 条件跳转
```

### SLOAD 读取存储（balanceOf）

```asm
  0x00          // slot 0 (_balances mapping)
  mstore        // 写入内存
  <address>     // 账户地址
  mstore        // 写入内存
  0x40          // 64 字节
  keccak256     // 计算 mapping 存储位置 = keccak256(key . slot)
  sload         // 读取该 slot
```

### SSTORE 写入存储（transfer）

```asm
  <value>       // 新余额
  <slot>        // 计算出的 mapping slot
  sstore        // 写入
```

## 7. 核心概念总结

1. **字节码分层**：Creation bytecode → Runtime bytecode（前者包含后者）
2. **函数选择器**：`keccak256(funcSig)[:4]`，4 字节精确匹配
3. **Mapping 存储**：`slot = keccak256(key . mappingSlot)`，不连续
4. **Solidity 编译器**：via-ir 模式下 assembly 输出可能为 null（使用优化 IR 中间表示）
5. **字节码大小**：与 Gas 无直接关系，但影响部署成本（每字节 200 gas）
