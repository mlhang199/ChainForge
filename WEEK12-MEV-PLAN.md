# Week 12 MEV 分析与防御

> 目标：理解 MEV 如何影响链上交易，掌握防御手段，编写安全的交易提交脚本。
>
> 前置：Week 9-11 已完成（Foundry 测试 129 个、Gas 优化、EVM/Opcode/Yul 实验）
> 分支：`phase3-evm-mev`

---

## 12.1 周一：MEV 理论学习

### 上午：MEV 基础复习

5 种 MEV 类型：
1. **Front-running**：抢跑，监测 mempool 后提前下单
2. **Back-running**：尾随套利，在目标交易后立即套利
3. **Sandwich Attack**：三明治攻击（对用户伤害最大），front-run + back-run 夹击
4. **Arbitrage**：跨 DEX 套利（中性/正面）
5. **Liquidation**：清算（协议正常运作）

### 下午：分析真实 MEV 交易

访问 https://eigenphi.io/ 找一笔三明治攻击，记录：
- 受害者交易哈希
- 攻击者 front-run / back-run 交易哈希
- 受害代币对、滑点设置
- 攻击者利润

输出：`notes/week12_mev_case_study.md`

---

## 12.2 周二：SlippageProtection 库

### 全天：编写 + 集成 + 测试

创建 `src/SlippageProtection.sol`：

```solidity
library SlippageProtection {
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxSlippageBps);
    uint256 constant BPS = 10000;

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

集成到 ChainForgeRouter 新函数 `swapWithSlippageProtection()`。

测试场景：
- 正常滑点内通过
- 超出滑点 revert
- 边界值测试（0% / 100% 滑点）
- 模拟价格变动

输出：`src/SlippageProtection.sol` + `test/SlippageProtection.t.sol`

---

## 12.3 周三：Commit-Reveal 模式

### 全天：实现 + 测试

创建 `src/CommitRevealAuction.sol`：

```solidity
contract CommitRevealAuction {
    struct Commit { bytes32 hash; uint256 blockNumber; }
    mapping(address => Commit) public commits;
    mapping(address => uint256) public revealedBids;
    bool public revealPhase;

    function commit(bytes32 hash) external { ... }
    function reveal(uint256 bid, bytes32 secret) external { ... }
    function startRevealPhase() external onlyOwner { ... }
}
```

测试场景：
- commit → reveal 完整流程
- 提前 reveal 失败
- 错误 secret reveal 失败
- 同一用户多次 commit 覆盖
- 最高出价者获胜

输出：`src/CommitRevealAuction.sol` + `test/CommitRevealAuction.t.sol`

---

## 12.4 周四：Flashbots Protect RPC 脚本

### 上午：JavaScript 版安全交易脚本

创建 `scripts/secure_swap.js`：
- Flashbots Protect RPC（`https://rpc.flashbots.net`）
- 自动计算 slippage 保护
- Deadline 检查
- 交易结果分析

### 下午：Java 版安全交易服务

创建 `backend/src/main/java/.../mev/SecureSwapService.java`：
- Web3j 连接 Flashbots Protect RPC
- Slippage 计算
- EIP-1559 交易参数

输出：`foundry-phase3/scripts/secure_swap.js` + `backend/.../mev/SecureSwapService.java`

---

## 12.5 周五：MEV 防御指南 + 第三阶段总结

### 上午：撰写防御方案文档

`docs/MEV_DEFENSE_GUIDE.md`：
- 威胁模型（高风险 vs 低风险操作）
- 防御策略矩阵
- 技术实现代码片段
- 监控建议

### 下午：第三阶段完成报告

`PHASE-3-COMPLETION-REPORT.md`：
- 核心产出统计（测试数、Gas 节省、合约数）
- Week 9-12 关键数据
- 学到的核心概念
- 未完成/待深入

---

## 产出文件清单

| 文件 | 说明 |
|------|------|
| `src/SlippageProtection.sol` | 滑点保护库 |
| `src/CommitRevealAuction.sol` | Commit-Reveal 拍卖合约 |
| `test/SlippageProtection.t.sol` | 滑点保护测试 |
| `test/CommitRevealAuction.t.sol` | Commit-Reveal 测试 |
| `scripts/secure_swap.js` | 安全交易脚本（JS） |
| `backend/.../mev/SecureSwapService.java` | 安全交易服务（Java） |
| `notes/week12_mev_case_study.md` | MEV 案例分析 |
| `docs/MEV_DEFENSE_GUIDE.md` | MEV 防御指南 |
| `PHASE-3-COMPLETION-REPORT.md` | 第三阶段完成报告 |

## 检查点

- [ ] SlippageProtection 库 + 测试通过
- [ ] Commit-Reveal 合约 + 测试通过
- [ ] 安全交易脚本可运行
- [ ] MEV 防御指南完成
- [ ] 第三阶段完成报告完成
- [ ] 所有测试 ≥ 140 个（当前 129）
