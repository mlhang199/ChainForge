# 第三阶段学习计划：EVM 底层与 MEV（第 9-12 周）

> 目标：从"能写合约"跨越到"精通合约"——理解 EVM 执行模型、掌握 Gas 优化技巧、建立 MEV 防御意识。
>
> 前置条件：已完成 ChainForge 项目（ERC-20 + ERC-721 + SimpleAMM + Router）。
> 技术栈：Foundry + Solidity + Web3j + Java。

---

## 目录

- [全局准备](#全局准备)
- [第 9 周：Foundry 工具链与 Gas 分析](#第-9-周foundry-工具链与-gas-分析)
- [第 10 周：Gas 优化实战](#第-10-周gas-优化实战)
- [第 11 周：EVM 深入与 Opcode](#第-11-周evm-深入与-opcode)
- [第 12 周：MEV 分析与防御](#第-12-周mev-分析与防御)
- [附录](#附录)

---

## 全局准备

### 环境要求

```bash
# 1. 安装 Foundry（如果还没有）
curl -L https://foundry.paradigm.xyz | bash
source ~/.zshrc
foundryup

# 验证安装
forge --version   # 应输出 >= 0.2.0
cast --version
anvil --version
```

### 项目初始化

```bash
# 在项目根目录下新建 foundry 子项目，复用现有合约
cd /Users/zhuzhou/lihang/web3/nft-test
mkdir -p foundry-phase3/src foundry-phase3/test foundry-phase3/script
cd foundry-phase3

# 初始化 foundry（不使用模板）
forge init --force --no-commit

# 安装 OpenZeppelin（与 Hardhat 项目版本对齐）
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2

# 将现有合约链接/复制到 foundry/src
ln -s ../contracts/src/SimpleAMM.sol src/SimpleAMM.sol
ln -s ../contracts/src/ChainForgeRouter.sol src/ChainForgeRouter.sol
ln -s ../contracts/src/MyToken.sol src/MyToken.sol
ln -s ../contracts/src/MyNFT.sol src/MyNFT.sol
ln -s ../contracts/src/FlashSwapReceiver.sol src/FlashSwapReceiver.sol
```

### `foundry.toml` 配置

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.28"
optimizer = true
optimizer_runs = 200

# Gas 报告配置
[profile.default.gas_reports]
* = ["SimpleAMM", "ChainForgeRouter", "MyToken", "MyNFT"]

[fmt]
line_length = 100
tab_width = 4
bracket_spacing = false
```

### 本周产出物总览

| 周次 | 核心产出 | 形式 |
|------|---------|------|
| 第 9 周 | Gas 分析报告 + Foundry 测试套件 | `.md` + `.sol` + 命令输出 |
| 第 10 周 | 优化后合约 + Gas 快照对比 | `.sol` + `.gas-snapshot` |
| 第 11 周 | EVM 调试笔记 + 手写 Yul 实验 | `.md` + `.sol` |
| 第 12 周 | MEV 防御脚本 + 安全交易指南 | `.js`/`.java` + `.md` |

---

## 第 9 周：Foundry 工具链与 Gas 分析

> **目标**：在现有 ChainForge 合约上建立 Foundry 测试基线，输出首份 Gas 报告，识别 Top 5 最昂贵的操作。

### 9.1 周一：Foundry 入门与迁移

#### 上午任务：理解 Foundry 核心命令

```bash
# 编译合约
forge build

# 运行所有测试
forge test

# 带详细输出的测试
forge test -vvv

# 仅运行匹配名称的测试
forge test --match-test testSwap

# Gas 报告（核心命令）
forge test --gas-report

# 生成 Gas 快照（用于后续对比）
forge snapshot
```

#### 下午任务：为 MyToken 写第一个 Foundry 测试

新建 `test/MyToken.t.sol`：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MyToken("ChainForge Token", "CFT", 1000000);
        token.transfer(alice, 10_000 * 1e18);
    }

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1_000_000 * 1e18);
        assertEq(token.decimals(), 18);
    }

    function testTransfer() public {
        vm.prank(alice);
        token.transfer(bob, 100 * 1e18);
        assertEq(token.balanceOf(bob), 100 * 1e18);
    }

    function testTransferEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(alice, bob, 100 * 1e18);
        token.transfer(bob, 100 * 1e18);
    }

    function testFailTransferExceedsBalance() public {
        vm.prank(alice);
        token.transfer(bob, 1_000_000 * 1e18); // 应该 revert
    }
}
```

运行：
```bash
forge test --match-contract MyTokenTest -vvv
```

**今日检查点：**
- [ ] `forge build` 成功编译所有合约
- [ ] `MyTokenTest` 全部通过
- [ ] 理解 `setUp()` / `vm.prank()` / `makeAddr()` 的用法

### 9.2 周二：MyNFT 测试 + Gas 报告初探

#### 上午任务：为 MyNFT 写 Foundry 测试

新建 `test/MyNFT.t.sol`：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyNFT.sol";

contract MyNFTTest is Test {
    MyNFT nft;
    address owner = address(this);
    address minter = makeAddr("minter");
    string constant BASE_URI = "ipfs://QmTest/";

    function setUp() public {
        nft = new MyNFT("ChainForge NFT", "CFNFT", BASE_URI);
    }

    function testMint() public {
        uint256 tokenId = nft.mint(minter);
        assertEq(nft.ownerOf(tokenId), minter);
        assertEq(nft.tokenURI(tokenId), string(abi.encodePacked(BASE_URI, "0")));
    }

    function testBatchMint() public {
        nft.batchMint(minter, 5);
        assertEq(nft.balanceOf(minter), 5);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(minter);
        vm.expectRevert();
        nft.mint(minter);
    }

    function testSetBaseURI() public {
        nft.setBaseURI("https://api.new.com/");
        nft.mint(minter);
        assertEq(nft.tokenURI(0), "https://api.new.com/0");
    }
}
```

#### 下午任务：生成首份 Gas 报告

```bash
# 生成 MyToken 和 MyNFT 的 Gas 报告
forge test --match-contract "MyTokenTest|MyNFTTest" --gas-report > reports/week9_nft_token_gas.md

# 查看结果
cat reports/week9_nft_token_gas.md
```

**Gas 报告解读示例：**

```
| MyToken contract          |                 |        |        |        |         |
|---------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost           | Deployment Size |        |        |        |         |
| 1234567                   | 4567            |        |        |        |         |
| Function Name             | min             | avg    | median | max    | # calls |
| transfer                  | 2852            | 2852   | 2852   | 2852   | 3       |
| mint                      | 34567           | 34567  | 34567  | 34567  | 1       |
| balanceOf                 | 456             | 456    | 456    | 456    | 5       |
```

**今日检查点：**
- [ ] MyNFT 测试全部通过
- [ ] 生成首份 Gas 报告并理解其结构
- [ ] 记录 `transfer` / `mint` / `balanceOf` 的基准 Gas

### 9.3 周三：SimpleAMM 测试（上）—— 流动性操作

#### 全天任务：为 SimpleAMM 的 addLiquidity / removeLiquidity 写测试

新建 `test/SimpleAMM.t.sol`（骨架）：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/SimpleAMM.sol";
import "../src/MyToken.sol";

contract SimpleAMMTest is Test {
    SimpleAMM amm;
    MyToken tokenA;
    MyToken tokenB;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        tokenA = new MyToken("Token A", "TKA", 1000000);
        tokenB = new MyToken("Token B", "TKB", 1000000);

        amm = new SimpleAMM(address(tokenA), address(tokenB));

        // 给测试账号准备代币
        tokenA.transfer(alice, 100_000 * 1e18);
        tokenB.transfer(alice, 100_000 * 1e18);
        tokenA.transfer(bob, 100_000 * 1e18);
        tokenB.transfer(bob, 100_000 * 1e18);
    }

    // ── 辅助函数：添加流动性 ──
    function _addLiquidity(address user, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(user);
        tokenA.approve(address(amm), amountA);
        tokenB.approve(address(amm), amountB);
        amm.addLiquidity(amountA, amountB);
        vm.stopPrank();
    }

    function testAddLiquidityInitial() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 20_000 * 1e18;

        _addLiquidity(alice, amountA, amountB);

        assertEq(amm.balanceOf(alice), Math.sqrt(amountA * amountB)); // 首次 LP = sqrt
    }

    function testAddLiquiditySubsequent() public {
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);
        _addLiquidity(bob, 5_000 * 1e18, 5_000 * 1e18);

        // Bob 应该获得约 50% 的 LP Token（因为池子 doubled）
        uint256 aliceLP = amm.balanceOf(alice);
        uint256 bobLP = amm.balanceOf(bob);
        assertApproxEqRel(bobLP, aliceLP / 2, 0.01e18); // 1% 误差
    }

    function testRemoveLiquidity() public {
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);

        uint256 lpBalance = amm.balanceOf(alice);
        vm.startPrank(alice);
        amm.approve(address(amm), lpBalance);
        amm.removeLiquidity(lpBalance);
        vm.stopPrank();

        assertEq(amm.balanceOf(alice), 0);
    }
}
```

> 注意：如果 SimpleAMM 的 `addLiquidity` 返回值或签名不同，需要根据实际合约调整。

**今日检查点：**
- [ ] `testAddLiquidityInitial` 通过
- [ ] `testAddLiquiditySubsequent` 通过
- [ ] `testRemoveLiquidity` 通过

### 9.4 周四：SimpleAMM 测试（下）—— Swap + 事件

#### 上午任务：Swap 测试

```solidity
    function testSwapAForB() public {
        // 先添加流动性
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);

        uint256 amountIn = 100 * 1e18;
        uint256 bobBalanceBefore = tokenB.balanceOf(bob);

        // Bob swap A for B
        vm.startPrank(bob);
        tokenA.approve(address(amm), amountIn);
        amm.swap(address(tokenA), amountIn);
        vm.stopPrank();

        uint256 bobBalanceAfter = tokenB.balanceOf(bob);
        assertGt(bobBalanceAfter, bobBalanceBefore);
    }

    function testSwapUpdatesReserves() public {
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 * 1e18);
        amm.swap(address(tokenA), 100 * 1e18);
        vm.stopPrank();

        (uint256 reserveA, uint256 reserveB) = amm.getReserves();
        assertGt(reserveA, 10_000 * 1e18);
        assertLt(reserveB, 10_000 * 1e18);
    }
```

#### 下午任务：事件测试 + K 值验证

```solidity
    function testSwapEmitsEvent() public {
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 * 1e18);

        vm.expectEmit(true, true, false, false);
        emit SimpleAMM.Swap(bob, address(tokenA), 100 * 1e18, address(tokenB), 0); // amountOut 不检查
        amm.swap(address(tokenA), 100 * 1e18);
        vm.stopPrank();
    }

    function testKValueIncreasesWithFee() public {
        _addLiquidity(alice, 10_000 * 1e18, 10_000 * 1e18);
        uint256 kBefore = amm.reserveA() * amm.reserveB();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 1000 * 1e18);
        amm.swap(address(tokenA), 1000 * 1e18);
        vm.stopPrank();

        uint256 kAfter = amm.reserveA() * amm.reserveB();
        assertGe(kAfter, kBefore, "K should increase due to fee");
    }
```

**今日检查点：**
- [ ] Swap 测试通过
- [ ] 事件测试通过
- [ ] K 值验证通过

### 9.5 周五：ChainForgeRouter 测试 + 首份完整 Gas 报告

#### 全天任务：Router 多跳测试 + 生成全量 Gas 报告

```solidity
// test/ChainForgeRouter.t.sol（骨架）
contract ChainForgeRouterTest is Test {
    ChainForgeRouter router;
    SimpleAMM amm1; // CFT / WETH
    SimpleAMM amm2; // WETH / USDC
    MyToken cft;
    MyToken weth;
    MyToken usdc;

    function setUp() public {
        cft = new MyToken("CFT", "CFT", 1000000);
        weth = new MyToken("WETH", "WETH", 1000000);
        usdc = new MyToken("USDC", "USDC", 1000000);

        amm1 = new SimpleAMM(address(cft), address(weth));
        amm2 = new SimpleAMM(address(weth), address(usdc));

        router = new ChainForgeRouter();
        router.addPool(address(cft), address(weth), address(amm1));
        router.addPool(address(weth), address(usdc), address(amm2));

        // 添加初始流动性（此处省略具体数值）
    }

    function testGetAmountsOut() public view {
        address[] memory path = new address[](3);
        path[0] = address(cft);
        path[1] = address(weth);
        path[2] = address(usdc);

        uint256[] memory amounts = router.getAmountsOut(100 * 1e18, path);
        assertEq(amounts[0], 100 * 1e18);
        assertGt(amounts[2], 0);
    }
}
```

生成完整 Gas 报告：

```bash
# 创建报告目录
mkdir -p reports

# 运行全部测试并生成 Gas 报告
forge test --gas-report > reports/week9_full_gas_report.md

# 同时生成快照
forge snapshot --snap .gas-snapshot-week9-baseline

# 统计每个合约的平均函数 Gas
forge test --gas-report | grep -E "(contract|Function|Deployment)" > reports/week9_gas_summary.md
```

**今日检查点：**
- [ ] Router 基础测试通过
- [ ] 生成 `reports/week9_full_gas_report.md`
- [ ] 生成 `.gas-snapshot-week9-baseline`
- [ ] **识别并记录 Top 5 最贵函数**（写到 `reports/week9_top5_expensive.md`）

### 9.6 周末：回顾与文档整理

#### 任务：撰写第 9 周学习笔记

新建 `notes/week9_foundry_basics.md`：

```markdown
# Week 9 学习笔记

## Foundry vs Hardhat 感受
- Foundry 编译速度：____秒 vs Hardhat ____秒
- 测试写法：Solidity 内置 vs JavaScript 外部
- Gas 报告：内置 vs 需插件

## Top 5 最昂贵函数
| 排名 | 合约 | 函数 | 平均 Gas | 分析 |
|------|------|------|---------|------|
| 1 | | | | |
| 2 | | | | |
...

## 遇到的问题
1. ...

## 下周优化目标
- 目标：将 SimpleAMM.swap 的 Gas 降低 ____%
```

**周末检查点：**
- [ ] 学习笔记完成
- [ ] 所有测试文件已提交到 Git

---

## 第 10 周：Gas 优化实战

> **目标**：对 ChainForge 合约应用 5 大 Gas 优化技巧，生成优化前后对比报告，目标整体 Gas 降低 20%+。

### 10.1 周一：优化技巧 1 —— 存储槽打包（Slot Packing）

#### 上午：学习存储布局

```bash
# 查看 SimpleAMM 的存储布局
forge inspect SimpleAMM storage-layout
```

输出示例：
```
| Name                  | Type    | Slot | Offset | Bytes | Contract    |
|-----------------------|---------|------|--------|-------|-------------|
| tokenA                | address | 0    | 0      | 20    | SimpleAMM   |
| tokenB                | address | 1    | 0      | 20    | SimpleAMM   |
| _reserveA             | uint256 | 2    | 0      | 32    | SimpleAMM   |
| _reserveB             | uint256 | 3    | 0      | 32    | SimpleAMM   |
| feeTo                 | address | 4    | 0      | 20    | SimpleAMM   |
| feeToSetter           | address | 5    | 0      | 20    | SimpleAMM   |
| pendingFeeToSetter    | address | 6    | 0      | 20    | SimpleAMM   |
```

**问题发现：** `feeTo`, `feeToSetter`, `pendingFeeToSetter` 都是 `address`（20 bytes），却各占一个 slot！

#### 下午：动手打包

新建 `src/SimpleAMM_Optimized_V1.sol`，复制原合约并修改：

```solidity
// ❌ 优化前：3 个 address 各占 1 slot
    address public feeTo;
    address public feeToSetter;
    address public pendingFeeToSetter;

// ✅ 优化后：3 个 address 打包到 1 个 slot
// 注意：这需要调整访问方式，使用 struct 或内联汇编
    struct FeeConfig {
        address feeTo;
        address feeToSetter;
        address pendingFeeToSetter;
    }
    FeeConfig public feeConfig;
```

> ⚠️ **注意：** 由于 SimpleAMM 已经部署，直接改存储布局会破坏兼容性。第 10 周的优化是**练习性质**，创建 `SimpleAMM_Optimized.sol` 作为对比版本。

运行对比测试：

```bash
# 测试原始版本
forge test --match-contract SimpleAMMTest --gas-report > reports/week10_before_slot_packing.md

# 测试优化版本（需要写一个新的测试文件指向优化合约）
# forge test --match-contract SimpleAMM_Optimized_Test --gas-report > reports/week10_after_slot_packing.md
```

**今日检查点：**
- [ ] 用 `forge inspect` 导出至少 2 个合约的存储布局
- [ ] 发现至少 1 个可打包的存储浪费
- [ ] 创建优化版本合约并编译通过

### 10.2 周二：优化技巧 2 —— 缓存存储变量到内存

#### 全天：在循环和重复读取中应用缓存

**示例场景：** `batchMint` 中的 `_nextTokenId`

查看原 MyNFT：
```solidity
// src/MyNFT.sol
function batchMint(address to, uint256 quantity) external onlyOwner {
    for (uint256 i = 0; i < quantity; i++) {
        uint256 tokenId = _nextTokenId++; // 每次循环都读/写 storage！
        _safeMint(to, tokenId);
    }
}
```

> 实际上 `_nextTokenId++` 是 storage 读写，但这个例子中它本身就是递增的，不太好缓存。我们看 SimpleAMM。

在 SimpleAMM 中找循环：
```bash
grep -n "for (" src/SimpleAMM.sol
```

如果 Router 中有循环遍历 pools，优化如下：

```solidity
// ❌ 优化前
function someFunction() external view {
    for (uint256 i = 0; i < pools.length; i++) { // 每次读 pools.length (storage)
        ...
    }
}

// ✅ 优化后
function someFunction() external view {
    uint256 poolCount = pools.length; // 1 次 SLOAD
    for (uint256 i = 0; i < poolCount; i++) {
        ...
    }
}
```

**今日检查点：**
- [ ] 在至少 2 个合约中找到循环里的 storage 重复读取
- [ ] 应用缓存优化
- [ ] 测试通过，Gas 有下降

### 10.3 周三：优化技巧 3 —— unchecked + ++i

#### 全天：在确定不会溢出的循环中应用

```solidity
// ❌ 优化前
function batchMint(address to, uint256 quantity) external onlyOwner {
    for (uint256 i = 0; i < quantity; i++) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
}

// ✅ 优化后
function batchMint_Optimized(address to, uint256 quantity) external onlyOwner {
    uint256 startId = _nextTokenId; // 1 次 SLOAD
    _nextTokenId += quantity;       // 1 次 SSTORE
    
    for (uint256 i = 0; i < quantity;) {
        _safeMint(to, startId + i);
        unchecked { ++i; }          // 跳过溢出检查
    }
}
```

> 这个优化版本同时应用了**缓存**和**unchecked**！`_nextTokenId` 从 `quantity` 次读写变成了 2 次。

写对比测试：

```solidity
function testBatchMintGasComparison() public {
    uint256 gasBefore = gasleft();
    nft.batchMint(alice, 10);
    uint256 gasOriginal = gasBefore - gasleft();

    uint256 gasBefore2 = gasleft();
    nftOptimized.batchMint_Optimized(bob, 10);
    uint256 gasOptimized = gasBefore2 - gasleft();

    console.log("Original gas:", gasOriginal);
    console.log("Optimized gas:", gasOptimized);
    console.log("Saved:", gasOriginal - gasOptimized);
    assertLt(gasOptimized, gasOriginal);
}
```

**今日检查点：**
- [ ] 至少 2 个循环应用了 `unchecked { ++i; }`
- [ ] 写对比测试验证 Gas 节省
- [ ] 记录节省的 Gas 数量

### 10.4 周四：优化技巧 4 —— 用事件替代存储

#### 上午：理论 + 适用场景分析

不是所有存储都能换成事件。适合换事件的场景：
- 历史记录类数据（交易历史、操作日志）
- 只在链下展示、合约内部从不读取的数据
- 大量写入、极少读取的数据

ChainForge 中的候选：
- `Swap` 事件已经用了，很好
- `LiquidityAdded` / `LiquidityRemoved` 也是事件，很好
- 检查是否有 `mapping` 只被写入但从不在合约内读取

```bash
# 查找所有 mapping
grep -n "mapping" src/*.sol
```

#### 下午：实践（如适用）

如果发现有可替换的 mapping，写优化版本。如果没有，写一份分析报告说明为什么现有设计已经合理。

**今日检查点：**
- [ ] 审计所有 mapping 的使用模式
- [ ] 识别至少 1 个"可事件化"的候选（或证明没有）
- [ ] 如实施优化，写对比测试

### 10.5 周五：优化技巧 5 —— Calldata 替代 Memory

#### 全天：外部函数参数优化

```solidity
// ❌ 优化前
function getAmountsOut(uint256 amountIn, address[] memory path)
    external view returns (uint256[] memory amounts);

// ✅ 优化后
function getAmountsOut(uint256 amountIn, address[] calldata path)
    external view returns (uint256[] memory amounts);
```

在 Router 合约中检查所有 `external` 函数：

```bash
grep -n "external" src/ChainForgeRouter.sol
```

将只读数组参数从 `memory` 改为 `calldata`。

**今日检查点：**
- [ ] 所有只读的 `external` 函数参数已审计
- [ ] 适用的已从 `memory` 改为 `calldata`
- [ ] 测试通过

### 10.6 周六：生成 Gas 快照对比报告

#### 全天：最终对比

```bash
# 1. 生成优化后的快照
forge snapshot --snap .gas-snapshot-week10-optimized

# 2. 对比基线和优化版（需要 diff 工具）
diff .gas-snapshot-week9-baseline .gas-snapshot-week10-optimized > reports/week10_gas_diff.md

# 3. 生成完整对比报告
forge test --gas-report > reports/week10_optimized_gas_report.md
```

撰写报告 `reports/week10_optimization_summary.md`：

```markdown
# Week 10 Gas 优化总结

## 优化前 vs 优化后

| 合约 | 函数 | 优化前 Gas | 优化后 Gas | 节省 | 节省率 |
|------|------|-----------|-----------|------|--------|
| MyNFT | batchMint(10) | X | Y | Z | W% |
| SimpleAMM | swap | X | Y | Z | W% |
| ChainForgeRouter | getAmountsOut | X | Y | Z | W% |

## 应用的优化技巧
1. **存储槽打包**：____
2. **缓存存储变量**：____
3. **unchecked 循环**：____
4. **事件替代存储**：____
5. **calldata 替代 memory**：____

## 未达到预期的原因
（如某些优化无效，分析原因）

## 教训
- ...
```

**今日检查点：**
- [ ] `.gas-snapshot-week10-optimized` 已生成
- [ ] 对比报告完成
- [ ] **整体 Gas 节省 >= 20%**（如未达标，分析原因）

### 10.7 周日：回顾与复习

**今日检查点：**
- [ ] 所有修改已提交 Git
- [ ] 优化报告完成
- [ ] 准备进入 Opcode 学习

---

## 第 11 周：EVM 深入与 Opcode

> **目标**：理解 Solidity 代码如何被编译成字节码，能在 evm.codes 上调试简单合约，手写简单 Yul 代码。

### 11.1 周一：从 Solidity 到字节码

#### 上午：编译并查看字节码

```bash
# 查看 MyToken 的字节码
forge inspect MyToken bytecode

# 查看 MyToken 的 Opcode（人类可读版）
forge inspect MyToken opcodes > notes/week11_mytoken_opcodes.txt

# 只看部署字节码（creation bytecode）
forge inspect MyToken deployedBytecode
```

#### 下午：理解编译输出结构

新建 `notes/week11_bytecode_anatomy.md`：

```markdown
# 字节码解剖

## MyToken 编译输出分析

### 创建字节码（Creation Bytecode）
- 长度：____ 字节
- 作用：部署时执行，运行构造函数，返回 runtime bytecode

### 运行时字节码（Runtime Bytecode）
- 长度：____ 字节
- 作用：部署后实际执行的逻辑

### 关键 Opcode 片段
（从 opcodes 输出中截取transfer函数的片段）

```
PUSH1 0x04
CALLDATALOAD
PUSH1 0x24
CALLDATALOAD
...
```

解释：
- `CALLDATALOAD 0x04`：读取第 4 字节的 calldata（函数选择器之后第一个参数）
- ...
```

**今日检查点：**
- [ ] 导出至少 1 个合约的完整 Opcode 列表
- [ ] 能指出函数选择器（PUSH4 0x____）的位置
- [ ] 理解创建字节码和运行时字节码的区别

### 11.2 周二：evm.codes 交互学习

#### 全天：在 evm.codes Playground 上手调

访问 https://www.evm.codes/playground

**练习 1：简单加法**
```
PUSH1 0x05    // 栈: [5]
PUSH1 0x03    // 栈: [5, 3]
ADD           // 栈: [8]
STOP
```

在 Playground 中执行，观察：
- Stack 的变化
- Gas 的消耗（PUSH1 = 3, ADD = 3, STOP = 0）

**练习 2：读取 Storage**
```
PUSH1 0x00    // slot 0
SLOAD         // 读取 slot 0
STOP
```

观察：
- SLOAD 的 Gas = 2100（冷访问）或 100（热访问）
- 为什么差这么多？

**练习 3：写入 Storage**
```
PUSH1 0x01    // value
PUSH1 0x00    // slot
SSTORE        // 写入
STOP
```

观察：
- SSTORE 的 Gas 取决于当前值（EIP-2200）
- 从 0 到非 0：20100 Gas
- 从非 0 到非 0：2900 Gas
- 从非 0 到 0：退款！

**今日检查点：**
- [ ] 完成 3 个 Playground 练习
- [ ] 记录每个 Opcode 的 Gas 消耗
- [ ] 理解 SSTORE 的 Gas 退款机制

### 11.3 周三：Solidity 内联汇编（Yul）

#### 上午：学习 Yul 语法

Yul 是 Solidity 支持的内联汇编语言，让你直接写 EVM 级别的代码。

```solidity
contract YulExamples {
    uint256 public value;

    // 示例 1：用 Yul 读取 storage
    function getValueViaYul() external view returns (uint256 v) {
        assembly {
            v := sload(value.slot)
        }
    }

    // 示例 2：用 Yul 写入 storage（更省 Gas？测试一下）
    function setValueViaYul(uint256 newValue) external {
        assembly {
            sstore(value.slot, newValue)
        }
    }

    // 示例 3：用 Yul 做条件判断
    function max(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            // if a >= b, result = a, else result = b
            if iszero(lt(a, b)) {
                result := a
            }
            if lt(a, b) {
                result := b
            }
        }
    }
}
```

#### 下午：写对比测试

```solidity
contract YulGasTest is Test {
    YulExamples yul;

    function setUp() public {
        yul = new YulExamples();
    }

    function testStorageWriteGas() public {
        uint256 gasSolidity = gasleft();
        yul.setValueViaYul(42);
        uint256 gasUsedYul = gasSolidity - gasleft();

        // 对比纯 Solidity 写法
        // ...

        console.log("Yul SSTORE gas:", gasUsedYul);
    }
}
```

**今日检查点：**
- [ ] 创建 `YulExamples.sol` 并编译通过
- [ ] 至少 3 个 Yul 函数（读 storage、写 storage、条件判断）
- [ ] 对比测试通过

### 11.4 周四：用 Yul 重写一个简单函数

#### 全天：挑战任务

选择 MyToken 或 MyNFT 中的一个**简单函数**，用纯 Yul 重写。

示例：重写 `balanceOf` 的读取逻辑

```solidity
contract MyTokenWithYul is ERC20 {
    // ... 构造函数等不变

    function balanceOfYul(address account) external view returns (uint256 b) {
        // ERC20 的 balances mapping 在 slot 0
        // balanceOf[account] 的存储位置 = keccak256(account . slot)
        assembly {
            mstore(0x00, account)
            mstore(0x20, 0x00) // balances mapping 的 slot
            let slot := keccak256(0x00, 0x40)
            b := sload(slot)
        }
    }
}
```

写测试验证结果和 Solidity 版本一致：

```solidity
function testBalanceOfMatchesYul() public {
    assertEq(token.balanceOf(alice), token.balanceOfYul(alice));
}
```

**今日检查点：**
- [ ] 至少 1 个函数用 Yul 重写
- [ ] 测试证明结果与 Solidity 版本一致
- [ ] 记录 Gas 差异（Yul 通常不会更省，因为 Solidity 优化器已经很强，但理解底层很有价值）

### 11.5 周五：Opcode 调试实战

#### 全天：调试一个 revert 场景

创建一个故意会 revert 的合约，用 trace 查看执行过程：

```solidity
contract RevertDemo {
    uint256 public balance;

    function withdraw(uint256 amount) external {
        require(balance >= amount, "Insufficient balance"); // 会 revert
        balance -= amount;
    }
}
```

```bash
# 用 forge 运行并查看详细 trace
forge test --match-test testWithdrawRevert -vvvv
```

观察：
- `REVERT` Opcode 在哪里触发
- 错误消息是如何编码在 revert data 中的
- Gas 在 revert 时是否全部消耗

**今日检查点：**
- [ ] 能读懂 forge 的 trace 输出
- [ ] 理解 revert 的 Gas 行为
- [ ] 笔记记录 Opcode 级别的执行流程

### 11.6 周末：Opcode 笔记整理

撰写 `notes/week11_evm_deep_dive.md`：

```markdown
# EVM 深入学习笔记

## 核心理解
- EVM 是基于栈的虚拟机
- 所有数据通过 Stack / Memory / Storage / Calldata 传递
- Gas 成本：Storage >> Memory > Stack > Calldata

## 关键 Opcode
| Opcode | Gas | 作用 | 使用场景 |
|--------|-----|------|---------|
| SLOAD | 2100/100 | 读存储 | 尽量少用 |
| SSTORE | 5000-22100 | 写存储 | 尽量少用 |
| CALL | 2600+ | 外部调用 | 注意重入风险 |
| DELEGATECALL | 2600+ | 委托调用 | 代理合约核心 |
| LOG0-LOG4 | 375+ | 事件日志 | 比 Storage 便宜 |
| RETURN | 0 | 返回数据 | |
| REVERT | 0 | 回滚 | 不消耗剩余 Gas |

## Yul 体验
- Yul 让你直接操控 EVM
- Solidity 0.8+ 的优化器已经很强大，Yul 优化空间有限
- Yul 的真正价值：理解底层、写极度优化的库（如 Solady）

## 推荐资源
- evm.codes
- Ethereum Yellow Paper（选读）
- Solidity 文档 Inline Assembly 章节
```

**周末检查点：**
- [ ] 完整笔记完成
- [ ] 所有实验代码提交 Git

---

## 第 12 周：MEV 分析与防御

> **目标**：理解 MEV 如何影响链上交易，掌握防御手段，编写安全的交易提交脚本。

### 12.1 周一：MEV 理论学习

#### 上午：复习 MEV 基础

回顾指南中的 MEV 章节，重点理解：
1. **Front-running**：抢跑
2. **Back-running**：尾随套利
3. **Sandwich Attack**：三明治攻击（对用户伤害最大）
4. **Arbitrage**：跨 DEX 套利（中性/正面）
5. **Liquidation**：清算（协议正常运作）

#### 下午：分析真实 MEV 交易

访问 https://explore.flashbots.net/ 或 https://eigenphi.io/

找一笔三明治攻击交易：
1. 记录受害者的交易哈希
2. 记录攻击者的 Front-run 交易哈希
3. 记录攻击者的 Back-run 交易哈希
4. 计算攻击者利润

笔记模板：
```markdown
# MEV 案例分析

## 案例 1：三明治攻击
- 区块：____
- 受害者交易：0x...
- 攻击者 Front-run：0x...
- 攻击者 Back-run：0x...
- 受害代币对：____
- 受害者滑点设置：____%
- 攻击者利润：____ ETH

## 攻击模式
（描述交易在区块中的顺序）
```

**今日检查点：**
- [ ] 在 Flashbots Explorer 上找到至少 1 笔三明治攻击
- [ ] 记录攻击的三笔交易哈希
- [ ] 理解交易排序与利润的关系

### 12.2 周二：Flashbots Protect RPC 实操

#### 上午：配置 Protect RPC

Flashbots Protect 是一个隐私 RPC，交易不进入公开 mempool，直接提交给验证者，从而防止 Front-running。

**MetaMask 配置：**
1. 打开 MetaMask → 设置 → 网络 → 添加网络
2. 网络名称：`Flashbots Protect`
3. RPC URL：`https://rpc.flashbots.net`
4. 链 ID：`1`（主网）或 `11155111`（Sepolia）
5. 货币符号：`ETH`
6. 区块浏览器：`https://etherscan.io`

#### 下午：用代码提交交易

**JavaScript 版本（ethers.js）：**

```javascript
// scripts/flashbots_send.js
const { ethers } = require("ethers");

const FLASHBOTS_RPC = "https://rpc.flashbots.net";
const PRIVATE_KEY = process.env.PRIVATE_KEY;

async function main() {
    const provider = new ethers.JsonRpcProvider(FLASHBOTS_RPC);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    const tx = {
        to: "0x...",
        value: ethers.parseEther("0.001"),
        maxFeePerGas: ethers.parseUnits("50", "gwei"),
        maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
    };

    const response = await wallet.sendTransaction(tx);
    console.log("Transaction hash:", response.hash);
    await response.wait();
    console.log("Confirmed!");
}

main().catch(console.error);
```

**Java 版本（Web3j）：**

```java
// FlashbotsProtectService.java
@Service
public class FlashbotsProtectService {

    private static final String FLASHBOTS_RPC = "https://rpc.flashbots.net";

    private final Web3j web3j;
    private final Credentials credentials;

    public FlashbotsProtectService(@Value("${private.key}") String privateKey) {
        this.web3j = Web3j.build(new HttpService(FLASHBOTS_RPC));
        this.credentials = Credentials.create(privateKey);
    }

    public String sendProtectedTransaction(String to, BigInteger valueWei) throws Exception {
        EthGasPrice gasPrice = web3j.ethGasPrice().send();

        RawTransaction rawTx = RawTransaction.createEtherTransaction(
            BigInteger.valueOf(System.currentTimeMillis() / 1000 + 300), // nonce 需要正确获取
            gasPrice.getGasPrice(),
            BigInteger.valueOf(21000), // gas limit
            to,
            valueWei
        );

        byte[] signedTx = TransactionEncoder.signMessage(rawTx, credentials);
        String hexTx = Numeric.toHexString(signedTx);

        EthSendTransaction response = web3j.ethSendRawTransaction(hexTx).send();
        return response.getTransactionHash();
    }
}
```

**今日检查点：**
- [ ] Flashbots Protect RPC 已添加到 MetaMask
- [ ] 用脚本（JS 或 Java）成功发送至少 1 笔测试交易到 Flashbots RPC
- [ ] 交易在 Etherscan 上显示（注意 Flashbots 交易可能延迟几秒）

### 12.3 周三：Slippage 机制与防御

#### 上午：理解 Slippage

在 AMM 中，**Slippage（滑点）** 是实际成交价与预期价的偏差。

```solidity
// Uniswap Router 中的 slippage 保护
function swapExactTokensForTokens(
    uint256 amountIn,           // 精确输入
    uint256 amountOutMin,       // 最小输出（slippage 保护）
    address[] calldata path,
    address to,
    uint256 deadline
) external;
```

如果设置 `amountOutMin = expectedAmount * 0.95`，表示接受 5% 的滑点。
**问题：** 这 5% 就是三明治攻击者的利润空间！

#### 下午：实现严格的 Slippage 检查

```solidity
library SlippageProtection {
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxSlippageBps);

    uint256 constant BPS = 10000; // 100% = 10000 bps

    function checkSlippage(
        uint256 expectedAmountOut,
        uint256 actualAmountOut,
        uint256 maxSlippageBps // 例如 50 = 0.5%
    ) internal pure {
        uint256 minAmountOut = expectedAmountOut * (BPS - maxSlippageBps) / BPS;
        if (actualAmountOut < minAmountOut) {
            revert SlippageExceeded(expectedAmountOut, actualAmountOut, maxSlippageBps);
        }
    }
}
```

在 ChainForgeRouter 中集成：

```solidity
contract ChainForgeRouter {
    using SlippageProtection for uint256;

    function swapWithSlippageProtection(
        uint256 amountIn,
        uint256 expectedAmountOut,
        uint256 maxSlippageBps,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        uint256[] memory amounts = getAmountsOut(amountIn, path);
        uint256 actualAmountOut = amounts[amounts.length - 1];

        actualAmountOut.checkSlippage(expectedAmountOut, maxSlippageBps);

        // ... 执行 swap
    }
}
```

**今日检查点：**
- [ ] `SlippageProtection` 库编写完成
- [ ] 集成到 Router 或新合约中
- [ ] 测试：模拟价格变动时 revert 是否正确触发

### 12.4 周四：Commit-Reveal 模式

#### 全天：学习并实现 Commit-Reveal

**场景：** 拍卖、投票、随机数生成等需要隐藏意图的场景。

**原理：**
1. **Commit 阶段**：提交 `keccak256(choice + secret)`
2. **Reveal 阶段**：公开 `choice` 和 `secret`，合约验证哈希匹配

```solidity
contract CommitRevealAuction {
    struct Commit {
        bytes32 hash;
        uint256 blockNumber;
    }

    mapping(address => Commit) public commits;
    mapping(address => uint256) public revealedBids;
    bool public revealPhase;

    function commit(bytes32 hash) external {
        require(!revealPhase, "Reveal phase started");
        commits[msg.sender] = Commit(hash, block.number);
    }

    function reveal(uint256 bid, bytes32 secret) external {
        require(revealPhase, "Not reveal phase");
        Commit memory c = commits[msg.sender];
        require(c.hash == keccak256(abi.encodePacked(bid, secret)), "Invalid reveal");
        revealedBids[msg.sender] = bid;
    }

    function startRevealPhase() external onlyOwner {
        revealPhase = true;
    }
}
```

**今日检查点：**
- [ ] Commit-Reveal 合约编写完成
- [ ] 测试完整流程（commit → 尝试提前 reveal → 正常 reveal）
- [ ] 理解为什么这能防御 Front-running

### 12.5 周五：MEV 防御方案总结 + 脚本完善

#### 上午：撰写防御方案文档

新建 `docs/MEV_DEFENSE_GUIDE.md`：

```markdown
# ChainForge MEV 防御指南

## 威胁模型

### 高风险操作
1. 大额 Swap（> $1000 等值）
2. 首次添加流动性（价格发现阶段）
3. 公开 mempool 中的敏感交易

### 低风险操作
1. 小额转账
2. 仅与已知合约交互的读取操作
3. 通过私有池提交的交易

## 防御策略矩阵

| 场景 | 推荐策略 | 实现方式 |
|------|---------|---------|
| 日常小额交易 | 低 Slippage | amountOutMin 设 0.5% |
| 大额 Swap | Flashbots Protect | 切换 RPC endpoint |
| 批量操作 | 私有交易池 | MEV Blocker / MEV Share |
| 拍卖/投票 | Commit-Reveal | 两阶段提交 |
| 生产系统 | 批量拍卖 | 集成 CoW Swap API |

## 技术实现

### 1. Flashbots Protect RPC（推荐）
```java
// Java 后端配置
private static final String PROTECT_RPC = "https://rpc.flashbots.net";
this.web3j = Web3j.build(new HttpService(PROTECT_RPC));
```

### 2. 严格 Slippage
```java
BigDecimal minAmountOut = expectedAmountOut
    .multiply(BigDecimal.valueOf(9950))
    .divide(BigDecimal.valueOf(10000));
```

### 3. 交易截止时间
```java
long deadline = System.currentTimeMillis() / 1000 + 300; // 5 分钟
```

## 监控
- 定期检查交易是否被三明治攻击
- 使用 EigenPhi API 分析交易模式
```

#### 下午：完善交易脚本

完善 `scripts/secure_swap.js` 或 `SecureSwapService.java`，集成：
1. Flashbots Protect RPC
2. 自动计算 slippage
3. Deadline 检查
4. 交易结果分析

**今日检查点：**
- [ ] MEV 防御指南文档完成
- [ ] 安全交易脚本可运行
- [ ] 脚本集成 Slippage + Deadline + Protect RPC

### 12.6 周六：端到端测试

#### 全天：完整流程测试

在 Sepolia 测试网上走完整流程：

```
1. 获取测试 ETH
2. 通过 Flashbots Protect RPC 发送交易
3. 通过普通 RPC 发送交易
4. 对比两笔交易的：
   - 确认时间
   - Gas 费用
   - 是否被抢跑（测试网 MEV 较少，主要验证流程）
```

记录到 `notes/week12_testnet_experiment.md`。

**今日检查点：**
- [ ] Sepolia 测试网交易成功
- [ ] Protect RPC 和普通 RPC 的对比记录
- [ ] 实验笔记完成

### 12.7 周日：第三阶段总结

撰写 `PHASE-3-COMPLETION-REPORT.md`：

```markdown
# 第三阶段完成报告

## 时间：第 9-12 周

## 核心产出
1. Foundry 测试套件（____ 个测试文件，____ 个测试用例）
2. Gas 优化报告（整体节省 ____%）
3. EVM/Opcode 学习笔记
4. Yul 实验合约
5. MEV 防御指南 + 安全交易脚本

## 关键数据
| 指标 | 优化前 | 优化后 | 变化 |
|------|--------|--------|------|
| SimpleAMM.swap 平均 Gas | ____ | ____ | ____% |
| MyNFT.batchMint(10) Gas | ____ | ____ | ____% |
| Router.getAmountsOut Gas | ____ | ____ | ____% |

## 学到的核心概念
1. EVM 四大件：Stack / Memory / Storage / Calldata
2. Storage 是最贵的，优化优先级最高
3. MEV 是区块排序权的经济变现
4. Flashbots Protect 是最简单的 MEV 防御

## 未完成/待深入
- [ ] 代理合约（UUPS/Transparent Proxy）
- [ ] 高级 Yul 优化（如 Solady 库级别的优化）
- [ ] 主网级别的 MEV 监控 bot

## 下一步建议
1. 将 Foundry 测试集成到 CI（GitHub Actions）
2. 对 SimpleAMM 做更激进的 Gas 优化
3. 学习 ERC-4337 Account Abstraction
```

**今日检查点：**
- [ ] 完成报告撰写
- [ ] 所有产出物已整理并提交 Git
- [ ] 准备汇报/展示

---

## 附录

### A. 每日时间建议

| 时间段 | 任务类型 | 说明 |
|--------|---------|------|
| 上午 2h | 理论学习/阅读 | 看文档、白皮书、evm.codes |
| 下午 3h | 编码/实验 | 写合约、写测试、跑命令 |
| 晚上 1h | 笔记/复盘 | 记录当天所学、整理输出 |

### B. 常用 Foundry 命令速查

```bash
# 基础
forge build                    # 编译
forge test                     # 运行测试
forge test -vvv                # 详细输出
forge test --gas-report        # Gas 报告
forge test --match-test testX  # 仅运行匹配测试

# Gas
forge snapshot                 # 生成 .gas-snapshot
forge snapshot --check         # 对比快照
forge test --gas-report        # 完整 Gas 报告

# 检查
forge inspect <Contract> opcodes         # Opcode 列表
forge inspect <Contract> storage-layout  # 存储布局
forge inspect <Contract> bytecode        # 字节码
forge inspect <Contract> abi             # ABI

# 本地链
anvil                          # 启动本地节点
anvil --fork-url <RPC>         # Fork 主网

# 格式化
forge fmt                      # 格式化代码
```

### C. 推荐资源

| 资源 | 链接 | 用途 |
|------|------|------|
| evm.codes | https://www.evm.codes | Opcode 参考 + Playground |
| Foundry Book | https://book.getfoundry.sh | Foundry 完整文档 |
| Flashbots Protect | https://protect.flashbots.net | 私有交易 RPC |
| EigenPhi | https://eigenphi.io | MEV 交易分析 |
| Ethereum Yellow Paper | https://ethereum.github.io/yellowpaper | EVM 规范 |
| Solidity Inline Assembly | https://docs.soliditylang.org/en/latest/assembly.html | Yul 文档 |

### D. Git 提交规范

第三阶段使用以下提交前缀：

```
foundry: add MyToken tests
gas-opt: cache storage reads in batchMint
evm: add Yul balanceOf experiment
mev: integrate Flashbots Protect RPC
docs: add week 9 gas analysis report
```
