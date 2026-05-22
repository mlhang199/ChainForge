# Week 11 EVM 深入学习笔记

## 1. EVM 核心概念

### 1.1 EVM 架构

EVM 是基于**栈**的虚拟机，数据通过四种存储区域传递：

| 区域 | Gas 成本 | 大小限制 | 生命周期 | 用途 |
|------|---------|---------|---------|------|
| **Stack** | 几乎免费 | 1024 层，每层 32B | 函数调用内 | 局部变量、计算 |
| **Memory** | 按字节付费 | 动态扩展 | 交易内 | 临时数据、返回值 |
| **Storage** | 极贵（SLOAD 2100, SSTORE 5000-22100） | 2^256 slots | 永久 | 合约状态 |
| **Calldata** | 便宜（3 gas/byte） | = 交易输入 | 交易内 | 函数参数 |

### 1.2 执行流程

```
用户发送交易 → EVM 创建执行环境
  → 从 calldata 读取函数选择器（前 4 字节）
  → 与合约的函数分派器匹配
  → 跳转到对应函数体
  → 执行 Opcode 序列
  → RETURN（成功）或 REVERT（失败）
```

## 2. 关键 Opcode 详解

| Opcode | Gas | 作用 | 使用场景 |
|--------|-----|------|---------|
| `PUSH1-PUSH32` | 3 | 压入常量到栈 | 所有操作 |
| `DUP1-DUP16` | 3 | 复制栈上第 n 个元素 | 变量复用 |
| `SWAP1-SWAP16` | 3 | 交换栈顶和第 n 个元素 | 参数传递 |
| `POP` | 2 | 丢弃栈顶元素 | 清理 |
| `ADD/SUB/MUL` | 3 | 算术运算 | 计算逻辑 |
| `DIV/SDIV` | 5 | 除法 | 计算逻辑 |
| `MULMOD/ADDMOD` | 8 | 模运算 | 精确计算 |
| `EXP` | 10+50*byte | 指数运算 | 大数计算 |
| `LT/GT/EQ` | 3 | 比较操作 | 条件判断 |
| `ISZERO` | 3 | 取反 | 条件判断 |
| `AND/OR/XOR/NOT` | 3 | 位运算 | 打包/解包 |
| `SHL/SHR` | 3 | 移位 | 打包/解包 |
| `MLOAD` | 3+内存扩展 | 读内存 | 临时数据 |
| `MSTORE` | 3+内存扩展 | 写内存 | 临时数据 |
| `SLOAD` | 2100(冷)/100(热) | 读存储 | 状态读取 |
| `SSTORE` | 22100/2900/退款 | 写存储 | 状态修改 |
| `CALLDATALOAD` | 3 | 读 calldata | 读取参数 |
| `CALLDATASIZE` | 2 | calldata 长度 | 检查 |
| `JUMP/JUMPI` | 8 | 跳转 | 控制流 |
| `JUMPDEST` | 1 | 跳转目标标记 | 控制流 |
| `KECCAK256` | 30+6*word | 哈希 | mapping 计算 |
| `LOG0-LOG4` | 375+375*topic+8*byte | 事件日志 | 链下通知 |
| `CALL` | 2600+ | 外部调用 | 合约交互 |
| `STATICCALL` | 2600+ | 只读外部调用 | view 函数 |
| `RETURN` | 0+内存 | 返回数据 | 函数返回 |
| `REVERT` | 0+内存 | 回滚 | 错误处理 |
| `SELFDESTRUCT` | 5000 | 自毁 | 不推荐使用 |

### 2.1 SSTORE Gas 详解（EIP-2200）

| 场景 | Gas | 退款 | 说明 |
|------|-----|------|------|
| 0 → 非零 | 22,100 | - | 首次写入 |
| 非零 → 非零（相同值） | 2,900 | - | 脏写入 |
| 非零 → 非零（不同值） | 2,900 | - | 修改 |
| 非零 → 0 | 2,900 | +4,800 | 删除（净收益 -1,900） |
| 0 → 0（冷） | 2,100 | - | 脏读取 |
| 0 → 0（热） | 100 | - | 已读取过 |

### 2.2 KECCAK256 在 Mapping 中的作用

Solidity 的 `mapping(key => value)` 存储位置计算：

```
slot = keccak256(abi.encode(key, mappingSlot))
```

- 单层 mapping：`keccak256(key . slot)`
- 嵌套 mapping：`keccak256(innerKey . keccak256(outerKey . slot))`

**实测**：Yul 直接计算 `keccak256` 读取 mapping 比通过 Solidity 的 `balanceOf()` 节省 ~90% Gas（9,766 → 965），因为绕过了 Solidity 的函数分派器、边界检查等开销。

## 3. 字节码分析

### 3.1 合约字节码大小

| 合约 | Runtime Bytecode | 说明 |
|------|-----------------|------|
| MyToken | 3,759 字节 | ERC20 + Permit + Ownable |
| MyNFT | 5,025 字节 | ERC721 + Ownable |
| SimpleAMM | 10,130 字节 | 最大合约 |
| ChainForgeRouter | 4,497 字节 | 路由器 |

部署成本 = 字节大小 × 200 gas（data cost）+ 基础部署成本（32,000）

### 3.2 函数选择器

函数选择器 = `keccak256(funcSig)[:4]`

| 函数 | 选择器 |
|------|--------|
| `transfer(address,uint256)` | `0xa9059cbb` |
| `balanceOf(address)` | `0x70a08231` |
| `approve(address,uint256)` | `0x095ea7b3` |

EVM 分派流程：
1. `CALLDATALOAD 0x00` → 读取前 4 字节
2. `DUP1` + `EQ 0xa9059cbb` + `JUMPI` → 匹配 `transfer`
3. 不匹配继续检查下一个选择器
4. 全不匹配 → fallback 函数或 revert

## 4. Yul 内联汇编实验结果

### 4.1 Gas 对比汇总

| 操作 | Solidity Gas | Yul Gas | 节省 | 节省率 |
|------|-------------|---------|------|--------|
| **setValue（纯写入）** | 2,403 | 1,302 | 1,101 | **46%** |
| **max（条件判断）** | 1,055 | 788 | 267 | **25%** |
| **sum(100)（循环）** | 11,344 | 6,832 | 4,512 | **40%** |
| **balanceOf（mapping读）** | 1,227 | 809 | 418 | **34%** |
| **setPacked（打包写入）** | 28,047 | 1,412 | 26,635 | **95%** |
| **getPacked（打包读取）** | 1,138 | 931 | 207 | **18%** |
| **getValue（简单读取）** | 1,085 | 1,103 | -18 | -2% |
| **hash（keccak256）** | 1,423 | 1,447 | -24 | -2% |

### 4.2 MyTokenWithYul 重写结果

| 函数 | Solidity Gas | Yul Gas | 节省 | 节省率 |
|------|-------------|---------|------|--------|
| **balanceOf** | 9,766 | 965 | 8,801 | **90%** |
| **totalSupply** | 2,675 | 992 | 1,683 | **63%** |
| **allowance** | 1,809 | 1,134 | 675 | **37%** |
| **maxSupply** | 3,042 | 818 | 2,224 | **73%** |

### 4.3 关键发现

1. **简单读取无优势**：`getValue`（直接读 slot）Yul 反而多 18 gas，因为 Solidity 优化器已经足够好
2. **Mapping 读取大幅优化**：直接计算 `keccak256` 读取 mapping 绕过了函数分派器，节省 90%
3. **循环优化显著**：Yul 的 `for` 循环比 Solidity 的 `for` 循环节省 40%，因为无溢出检查
4. **Packed Storage 最优**：Yul 直接 `shl + or + sstore` 比先计算再写入节省 95%
5. **Solidity 0.8+ 优化器很强**：在简单场景下，手动 Yul 无法超越编译器

### 4.4 Yul 适用场景

**值得用 Yul**：
- Mapping 读取优化（尤其是频繁调用的 `balanceOf`）
- Packed storage 读写（一次 SSTORE 写入多个值）
- 循环密集型操作
- 绕过 Solidity 的安全检查（在确定安全的前提下）

**不值得用 Yul**：
- 简单的存储读写（Solidity 优化器已经很好）
- 涉及复杂类型（string、bytes 操作）
- 需要安全检查的运算（除法、溢出）

## 5. Revert 和错误处理

### 5.1 Revert 类型分析

| 类型 | 编码方式 | Gas 影响 | 示例 |
|------|---------|---------|------|
| `require("msg")` | 选择器 + string ABI 编码 | 较高（消息字符串占用空间）| `require(x > 0, "Invalid")` |
| `require` 无消息 | 空 revert data | 最低 | `require(x > 0)` |
| 自定义 error | 选择器 + 参数 ABI 编码 | 中等（比 string 紧凑）| `revert InsufficientBalance(x, y)` |
| Panic（内建） | `0x4e487b71` + 错误码 | 较低 | 除零 `0x12`，溢出 `0x11` |
| 数组越界 | Panic `0x32` | 较低 | `arr[i]` 越界 |

### 5.2 Revert Gas 行为

- Revert **不消耗剩余 Gas**（与早期 EVM 不同）
- 只消耗已执行的 Opcode Gas + revert data 编码 Gas
- `try/catch` 可以捕获 revert 并测量 Gas 消耗

### 5.3 Forge Trace 解读

```
[2376] RevertDemo::withdraw(1e18)
  └─ ← [Revert] Insufficient balance
```

- `[2376]` = 该调用消耗的 Gas
- `[Revert]` = 执行到 REVERT opcode
- `Insufficient balance` = 解码后的 revert 原因

```
[401] RevertDemo::divide(10, 0) [staticcall]
  └─ ← [Revert] panic: division or modulo by zero (0x12)
```

- `[staticcall]` = view 函数使用 STATICCALL
- `panic: ... (0x12)` = Solidity Panic 错误，0x12 = 除零

## 6. 学习资源

| 资源 | 链接 | 用途 |
|------|------|------|
| evm.codes | https://www.evm.codes | Opcode 参考 + Playground |
| Foundry Book | https://book.getfoundry.sh | forge inspect 等命令 |
| Solidity Assembly | https://docs.soliditylang.org/en/latest/assembly.html | Yul 文档 |
| Ethereum Yellow Paper | https://ethereum.github.io/yellowpaper | EVM 规范 |
| Solady | https://github.com/Vectorized/solady | Yul 优化库实战参考 |

## 7. Week 11 产出文件

| 文件 | 说明 |
|------|------|
| `src/YulExamples.sol` | Yul 内联汇编实验（8 组对比） |
| `src/MyTokenWithYul.sol` | 用 Yul 重写 balanceOf/totalSupply/allowance |
| `src/RevertDemo.sol` | 6 种 revert 场景 |
| `test/YulExamples.t.sol` | Yul 对比测试（20 个） |
| `test/MyTokenWithYul.t.sol` | Yul 重写正确性验证（13 个） |
| `test/RevertDemo.t.sol` | Revert 调试测试（10 个） |
| `notes/week11_bytecode_anatomy.md` | 字节码解剖笔记 |
| `notes/week11_mytoken_assembly.txt` | MyToken 完整汇编输出 |
| `notes/week11_evm_deep_dive.md` | 本文档 |
