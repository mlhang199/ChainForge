# Week 9 Gas 分析 — Top 5 最贵函数

基于 `forge test --gas-report` 的基线数据。

## Top 5 最昂贵函数（按 Avg Gas）

| 排名 | 合约 | 函数 | Avg Gas | 分析 |
|------|------|------|---------|------|
| 1 | SimpleAMM | addLiquidity | 296,198 | 首次添加需 mint LP + 锁定 MINIMUM_LIQUIDITY，transferFrom 两次，_mintFee 计算 |
| 2 | ChainForgeRouter | addPool | 141,392 | 创建新 Pool struct 并存入数组 + mapping 双向写入 |
| 3 | ChainForgeRouter | swapExactTokensForTokens | 140,884 | 多跳 swap 循环，每跳 approve + swap |
| 4 | MyNFT | batchMint | 99,906 | 循环 _safeMint，每次循环读写 _nextTokenId (storage) |
| 5 | SimpleAMM | swap | 57,047 | 含 0.3% 手续费计算、储备量更新、TWAP 累积 |

## 关键发现

1. **SimpleAMM.addLiquidity 最贵** — 因为涉及 LP token mint、transferFrom 两次、_mintFee + _update
2. **batchMint 的循环 storage 读写** — `_nextTokenId++` 每次循环都 SLOAD + SSTORE，quantity=5 时约 99,906 gas
3. **Router 的 swap** — 每跳都要 forceApprove + swap，跨合约调用开销大
4. **Storage 操作是 Gas 主因** — SLOAD/SSTORE 占了 swap/addLiquidity 大部分开销

## 优化方向（Week 10 目标）

1. batchMint: 缓存 _nextTokenId，unchecked ++i → 预计节省 20-30%
2. Router swap: 移除循环内 forceApprove，改用一次 approve → 预计节省 10-15%
3. SimpleAMM: 存储槽打包 feeTo/feeToSetter/pendingFeeToSetter → 预计节省 5-10%
