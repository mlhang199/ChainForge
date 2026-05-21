// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IAMMCalleeOpt {
    function ammCall(address sender, address tokenOut, uint256 amountOut, bytes calldata data) external;
}

/**
 * @title SimpleAMM_Optimized
 * @dev Week 10 Gas 优化版 SimpleAMM
 *
 * 优化项：
 *   1. 存储槽打包：feeTo + blockTimestampLast 共享 slot（省 1 slot）
 *   2. 消除 _update() 中冗余的 _reserveA/_reserveB 写入
 *   3. 缓存 storage 读取到 memory
 *   4. immutable 常量（tokenA/tokenB 已在原版中 immutable）
 */
contract SimpleAMM_Optimized is ERC20, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    address public immutable tokenA;
    address public immutable tokenB;

    uint256 private _reserveA;
    uint256 private _reserveB;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    // ─── 优化1: 存储槽打包 ──────────────────────────────
    // 优化前: feeTo(slot9) + feeToSetter(slot10) + pendingFeeToSetter(slot11) = 3 slots
    // 优化后: feeTo + blockTimestampLast 共享 slot，省 1 slot
    // 当 _update() 读取 blockTimestampLast 时，feeTo 也在同一 slot 中，
    // 如果后续 _mintFee() 读取 feeTo，就是热访问（100 gas vs 2100 gas）
    address public feeTo;                // slot 9, offset 0 (20 bytes)
    uint32  public blockTimestampLast;   // slot 9, offset 20 (4 bytes)
    // slot 9: 24 bytes used, 8 bytes padding — 节省了原来的 slot 15

    address public feeToSetter;          // slot 10
    address public pendingFeeToSetter;   // slot 11

    uint256 private _kLast;              // slot 12
    uint256 public price0CumulativeLast; // slot 13
    uint256 public price1CumulativeLast; // slot 14
    // 原 slot 15 (blockTimestampLast) 已打包到 slot 9，总 slot 数从 16 减到 15

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event Swap(address indexed sender, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event FeeToChanged(address indexed oldFeeTo, address indexed newFeeTo);
    event FeeToSetterChanged(address indexed oldSetter, address indexed newSetter);
    event Sync(uint256 reserveA, uint256 reserveB);

    constructor(address tokenA_, address tokenB_)
        ERC20("SimpleAMM LP Token", "SALP")
        Ownable(msg.sender)
    {
        require(tokenA_ != address(0) && tokenB_ != address(0), "Zero address");
        require(tokenA_ != tokenB_, "Identical addresses");
        tokenA = tokenA_;
        tokenB = tokenB_;
        feeToSetter = msg.sender;
    }

    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction expired");
        _;
    }

    modifier onlyFeeToSetter() {
        require(msg.sender == feeToSetter, "Forbidden: not feeToSetter");
        _;
    }

    function reserveA() external view returns (uint256) {
        return _reserveA;
    }

    function reserveB() external view returns (uint256) {
        return _reserveB;
    }

    function kLast() external view returns (uint256) {
        return _kLast;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        require(amountIn > 0, "Insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR / FEE_DENOMINATOR;
        return (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
    }

    function consult(address token, uint256 secondsAgo) external view returns (uint256 priceAverage) {
        require(secondsAgo > 0, "Seconds must be > 0");
        require(token == tokenA || token == tokenB, "Invalid token");

        uint32 currentTime = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = currentTime - blockTimestampLast;
        require(timeElapsed >= secondsAgo, "Not enough data");

        if (token == tokenA) {
            uint256 currentCumulative = price0CumulativeLast +
                _uq112x112(_reserveB, _reserveA) * (currentTime - blockTimestampLast);
            priceAverage = currentCumulative / secondsAgo;
        } else {
            uint256 currentCumulative = price1CumulativeLast +
                _uq112x112(_reserveA, _reserveB) * (currentTime - blockTimestampLast);
            priceAverage = currentCumulative / secondsAgo;
        }
    }

    function setFeeTo(address feeTo_) external onlyFeeToSetter {
        address oldFeeTo = feeTo;
        feeTo = feeTo_;
        emit FeeToChanged(oldFeeTo, feeTo_);
    }

    function proposeFeeToSetter(address newSetter) external onlyFeeToSetter {
        require(newSetter != address(0), "Zero address");
        pendingFeeToSetter = newSetter;
    }

    function acceptFeeToSetter() external {
        require(msg.sender == pendingFeeToSetter, "Forbidden: not pending feeToSetter");
        address oldSetter = feeToSetter;
        feeToSetter = pendingFeeToSetter;
        pendingFeeToSetter = address(0);
        emit FeeToSetterChanged(oldSetter, feeToSetter);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function sync() external nonReentrant {
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        _reserveA = balanceA;
        _reserveB = balanceB;
        emit Sync(balanceA, balanceB);
    }

    function skim(address to) external nonReentrant {
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        uint256 excessA = balanceA > _reserveA ? balanceA - _reserveA : 0;
        uint256 excessB = balanceB > _reserveB ? balanceB - _reserveB : 0;
        if (excessA > 0) IERC20(tokenA).safeTransfer(to, excessA);
        if (excessB > 0) IERC20(tokenB).safeTransfer(to, excessB);
    }

    function addLiquidity(uint256 amountA, uint256 amountB, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        ensure(deadline)
        returns (uint256 liquidity)
    {
        return _addLiquidity(amountA, amountB);
    }

    function addLiquidityWithPermit(
        uint256 amountA, uint256 amountB, uint256 deadline,
        uint8 v, bytes32 r, bytes32 s, uint256 permitDeadline
    )
        external
        nonReentrant
        whenNotPaused
        ensure(deadline)
        returns (uint256 liquidity)
    {
        IERC20Permit(tokenA).permit(msg.sender, address(this), amountA, permitDeadline, v, r, s);
        return _addLiquidity(amountA, amountB);
    }

    function _addLiquidity(uint256 amountA, uint256 amountB)
        private
        returns (uint256 liquidity)
    {
        require(amountA > 0 && amountB > 0, "Zero amount");

        _mintFee();

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        uint256 totalSupply_ = totalSupply();

        if (totalSupply_ == 0) {
            liquidity = _sqrt(amountA * amountB);
            require(liquidity > MINIMUM_LIQUIDITY, "Insufficient initial liquidity");
            liquidity -= MINIMUM_LIQUIDITY;
            _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_LIQUIDITY);
        } else {
            uint256 liquidityA = (amountA * totalSupply_) / _reserveA;
            uint256 liquidityB = (amountB * totalSupply_) / _reserveB;
            liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
            require(liquidity > 0, "Insufficient liquidity minted");
        }

        _mint(msg.sender, liquidity);

        // ─── 优化2: 消除冗余写入 ──────────────────────────────
        // 优化前: 先写 _reserveA/_reserveB，再传给 _update 又写一次（相同值）
        // 优化后: 直接用局部变量，只通过 _update 写一次
        uint256 newReserveA = _reserveA + amountA;
        uint256 newReserveB = _reserveB + amountB;
        _update(newReserveA, newReserveB, true);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity, uint256 deadline)
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        require(liquidity > 0, "Zero liquidity");

        _mintFee();

        uint256 totalSupply_ = totalSupply();

        amountA = (_reserveA * liquidity) / totalSupply_;
        amountB = (_reserveB * liquidity) / totalSupply_;

        require(amountA > 0 && amountB > 0, "Insufficient liquidity burned");

        _burn(msg.sender, liquidity);

        // ─── 优化2: 同上，消除冗余写入 ──────────────────────────
        uint256 newReserveA = _reserveA - amountA;
        uint256 newReserveB = _reserveB - amountB;
        _update(newReserveA, newReserveB, true);

        IERC20(tokenA).safeTransfer(msg.sender, amountA);
        IERC20(tokenB).safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidity);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        ensure(deadline)
        returns (uint256 amountOut)
    {
        return _swap(tokenIn, amountIn, amountOutMin);
    }

    function swapWithPermit(
        address tokenIn, uint256 amountIn, uint256 amountOutMin, uint256 deadline,
        uint8 v, bytes32 r, bytes32 s, uint256 permitDeadline
    )
        external
        nonReentrant
        whenNotPaused
        ensure(deadline)
        returns (uint256 amountOut)
    {
        IERC20Permit(tokenIn).permit(msg.sender, address(this), amountIn, permitDeadline, v, r, s);
        return _swap(tokenIn, amountIn, amountOutMin);
    }

    function _swap(address tokenIn, uint256 amountIn, uint256 amountOutMin)
        private
        returns (uint256 amountOut)
    {
        require(tokenIn == tokenA || tokenIn == tokenB, "Invalid token");
        require(amountIn > 0, "Zero input");

        bool isAToB = tokenIn == tokenA;
        (uint256 reserveIn, uint256 reserveOut, address tokenOut) =
            isAToB ? (_reserveA, _reserveB, tokenB) : (_reserveB, _reserveA, tokenA);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage exceeded");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        // ─── 优化2: 消除冗余写入 ──────────────────────────────
        uint256 newReserveA;
        uint256 newReserveB;
        if (isAToB) {
            newReserveA = _reserveA + amountIn;
            newReserveB = _reserveB - amountOut;
        } else {
            newReserveB = _reserveB + amountIn;
            newReserveA = _reserveA - amountOut;
        }
        _update(newReserveA, newReserveB, false);

        emit Swap(msg.sender, tokenIn, amountIn, tokenOut, amountOut);
    }

    function flashSwap(address tokenOut, uint256 amountOut, bytes calldata data, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        ensure(deadline)
    {
        require(tokenOut == tokenA || tokenOut == tokenB, "Invalid token");
        require(amountOut > 0, "Zero output");

        bool isOutA = tokenOut == tokenA;
        (uint256 reserveOut, uint256 reserveIn, address tokenIn) =
            isOutA ? (_reserveA, _reserveB, tokenB) : (_reserveB, _reserveA, tokenA);

        require(amountOut < reserveOut, "Insufficient liquidity");

        uint256 amountIn = (reserveIn * amountOut) / (reserveOut - amountOut);
        uint256 amountInWithFee = (amountIn * FEE_DENOMINATOR) / FEE_NUMERATOR;

        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        if (data.length > 0) {
            IAMMCalleeOpt(msg.sender).ammCall(msg.sender, tokenOut, amountOut, data);
        }

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountInWithFee);
        uint256 received = IERC20(tokenIn).balanceOf(address(this)) - balanceBefore;

        require(received >= amountInWithFee, "Insufficient repayment");

        uint256 newReserveA;
        uint256 newReserveB;
        if (isOutA) {
            newReserveA = _reserveA - amountOut;
            newReserveB = _reserveB + received;
        } else {
            newReserveB = _reserveB - amountOut;
            newReserveA = _reserveA + received;
        }
        _update(newReserveA, newReserveB, false);

        emit Swap(msg.sender, tokenIn, amountInWithFee, tokenOut, amountOut);
    }

    // ─── Internal ──────────────────────────────────────────

    // ─── 优化2: _update 不再冗余写入 reserveA/reserveB ───
    // 优化前: _update 写入 _reserveA = balanceA, _reserveB = balanceB
    //         调用方已经修改了 _reserveA/_reserveB，_update 再写一次 = 冗余
    // 优化后: _update 只负责 TWAP 和 kLast，reserve 写入由调用方在 _update 后完成
    function _update(uint256 newReserveA, uint256 newReserveB, bool updateKLast) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        if (timeElapsed > 0 && _reserveA > 0 && _reserveB > 0) {
            price0CumulativeLast += _uq112x112(_reserveB, _reserveA) * timeElapsed;
            price1CumulativeLast += _uq112x112(_reserveA, _reserveB) * timeElapsed;
        }

        _reserveA = newReserveA;
        _reserveB = newReserveB;
        blockTimestampLast = blockTimestamp;
        if (updateKLast) {
            _kLast = newReserveA * newReserveB;
        }
        emit Sync(newReserveA, newReserveB);
    }

    function _uq112x112(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return (numerator << 112) / denominator;
    }

    function _mintFee() private {
        if (feeTo == address(0)) {
            return;
        }

        uint256 kLast_ = _kLast;
        if (kLast_ == 0) {
            return;
        }

        uint256 rootK = _sqrt(_reserveA * _reserveB);
        uint256 rootKLast = _sqrt(kLast_);

        if (rootK > rootKLast) {
            uint256 totalSupply_ = totalSupply();
            uint256 numerator = totalSupply_ * (rootK - rootKLast);
            uint256 denominator = 5 * rootK + rootKLast;
            uint256 feeLiquidity = numerator / denominator;

            if (feeLiquidity > 0) {
                _mint(feeTo, feeLiquidity);
            }
        }
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
