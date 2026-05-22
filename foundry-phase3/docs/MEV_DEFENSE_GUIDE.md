# MEV 防御指南

> ChainForge 项目 MEV 防御策略文档 — Week 12 产出

---

## 1. 威胁模型

### 操作风险分级

| 风险等级 | 操作类型 | MEV 暴露 | 典型损失 |
|----------|----------|----------|----------|
| **高** | DEX 大额 Swap | 三明治攻击 | 0.5%-5% 本金 |
| **高** | NFT 铸造/拍卖 | Front-run | 错失机会或溢价 |
| **中** | 流动性添加 | Just-in-time 流动性 | 手续费收入被稀释 |
| **中** | 清算 | 清算竞争 | 清算奖金被抢 |
| **低** | ERC-20 转账 | 无直接暴露 | — |
| **低** | 授权 (approve) | 无直接暴露 | — |

### 攻击者视角

MEV 搜索者的利润公式：

```
利润 = 价格滑点利润 - Gas 成本 - 交易费
     ≈ victimAmount × (actualSlippage - toleratedSlippage) - gasCost
```

只要利润 > 0，攻击就会发生。

---

## 2. 防御策略矩阵

| 策略 | 适用场景 | 防御强度 | 实现复杂度 | 用户体验影响 |
|------|----------|----------|------------|------------|
| 收紧滑点保护 | 所有 Swap | 中 | 低 | 需要理解滑点 |
| Flashbots Protect RPC | 所有交易 | 高 | 低 | 无感知 |
| Commit-Reveal | 拍卖/竞价 | 高 | 中 | 两步操作 |
| 私有内存池 | 所有交易 | 高 | 中 | 依赖第三方 |
| 交易拆分 | 大额 Swap | 中 | 中 | 多笔确认 |
| 时间锁 | 治理/管理操作 | 低 | 低 | 延迟执行 |

---

## 3. 技术实现

### 3.1 SlippageProtection 库

已在 `src/SlippageProtection.sol` 实现：

```solidity
library SlippageProtection {
    uint256 public constant BPS = 10000;

    function checkSlippage(
        uint256 expectedAmountOut,
        uint256 actualAmountOut,
        uint256 maxSlippageBps  // 50 = 0.5%
    ) internal pure {
        uint256 minAmountOut = expectedAmountOut * (BPS - maxSlippageBps) / BPS;
        if (actualAmountOut < minAmountOut) {
            revert SlippageExceeded(expectedAmountOut, actualAmountOut, maxSlippageBps);
        }
    }
}
```

集成到 Router：

```solidity
function swapWithSlippageProtection(
    uint256 amountIn,
    uint256 expectedAmountOut,
    uint256 maxSlippageBps,
    address[] calldata path,
    address to,
    uint256 deadline
) external ensure(deadline) returns (uint256[] memory amounts) {
    // ... swap logic ...
    SlippageProtection.checkSlippage(expectedAmountOut, amounts[path.length - 1], maxSlippageBps);
    // ...
}
```

### 3.2 Commit-Reveal 拍卖

已在 `src/CommitRevealAuction.sol` 实现：

```solidity
contract CommitRevealAuction {
    // Phase 1: 用户提交 keccak256(bid, secret)
    function commit(bytes32 hash) external { ... }

    // Phase 2: 所有提交完成后，开启揭示阶段
    function startRevealPhase() external onlyOwner { ... }

    // Phase 3: 用户揭示出价
    function reveal(uint256 bid, bytes32 secret) external { ... }
}
```

攻击者无法 front-run，因为在 commit 阶段看不到实际出价。

### 3.3 Flashbots Protect RPC

已在 `scripts/secure_swap.js` 实现：

```javascript
const FLASHBOTS_PROTECT_RPC = "https://rpc.flashbots.net";
const provider = new ethers.JsonRpcProvider(FLASHBOTS_PROTECT_RPC);
```

关键：交易不进入公开 mempool，直接发送给 Flashbots 区块构建者。

---

## 4. 监控建议

### 链上监控

| 监控项 | 方法 | 触发条件 |
|--------|------|----------|
| 异常 gas 价格 | 比较 pending 交易 gas | 超出 2x 平均值 |
| 连续同地址交易 | 追踪同一地址连续 tx | 3 笔以内同 block |
| 价格偏移 | 对比预期 vs 实际输出 | 超过设定阈值 |
| Mempool 监控 | 订阅 pending 交易 | 大额 swap 出现 |

### 事后分析

```bash
# 使用 Foundry cast 检查交易
cast tx <TX_HASH> --rpc-url $RPC_URL

# 检查同一区块内的相关交易
cast block <BLOCK_NUMBER> --rpc-url $RPC_URL
```

### 推荐工具

| 工具 | 用途 |
|------|------|
| eigenphi.io | MEV 交易分析 |
| Zeromev | MEV 数据 API |
| Flashbots Dashboard | Flashbots 生态监控 |
| cast | 命令行链上查询 |

---

## 5. 最佳实践清单

### 合约开发者

- [ ] 所有 swap 函数必须包含 `amountOutMin` 参数
- [ ] 使用自定义 error（如 `SlippageExceeded`）而非字符串 revert
- [ ] 拍卖/竞价使用 Commit-Reveal 模式
- [ ] 管理操作加时间锁
- [ ] 外部调用使用 checks-effects-interactions 模式

### 前端/SDK 开发者

- [ ] 默认使用 Flashbots Protect RPC
- [ ] 根据代币类型自动设置合理滑点
- [ ] 显示预期输出和最小输出（slippage adjusted）
- [ ] 大额交易提示拆分建议
- [ ] 交易提交后显示 pending 状态和 explorer 链接

### 用户

- [ ] 了解滑点含义，不盲目调高
- [ ] 大额交易先小额测试
- [ ] 使用支持私有交易的 RPC
- [ ] 关注交易确认时间，异常延迟可能意味着竞争
