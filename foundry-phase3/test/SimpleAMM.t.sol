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
    address feeRecipient = makeAddr("feeRecipient");

    uint256 constant AMOUNT = 10_000 * 1e18;

    function setUp() public {
        tokenA = new MyToken("Token A", "TKA", 1_000_000, 0);
        tokenB = new MyToken("Token B", "TKB", 1_000_000, 0);
        amm = new SimpleAMM(address(tokenA), address(tokenB));

        tokenA.transfer(alice, 100_000 * 1e18);
        tokenB.transfer(alice, 100_000 * 1e18);
        tokenA.transfer(bob, 100_000 * 1e18);
        tokenB.transfer(bob, 100_000 * 1e18);
    }

    // ── Helpers ──

    function _addLiquidity(address user, uint256 amountA, uint256 amountB) internal {
        vm.startPrank(user);
        tokenA.approve(address(amm), amountA);
        tokenB.approve(address(amm), amountB);
        amm.addLiquidity(amountA, amountB, block.timestamp + 300);
        vm.stopPrank();
    }

    // ── Constructor ──

    function testConstructorSetsTokens() public view {
        assertEq(amm.tokenA(), address(tokenA));
        assertEq(amm.tokenB(), address(tokenB));
    }

    function testConstructorRejectsZeroAddress() public {
        vm.expectRevert("Zero address");
        new SimpleAMM(address(0), address(tokenB));
    }

    function testConstructorRejectsIdenticalAddresses() public {
        vm.expectRevert("Identical addresses");
        new SimpleAMM(address(tokenA), address(tokenA));
    }

    // ── AddLiquidity ──

    function testAddLiquidityInitial() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        assertGt(amm.balanceOf(alice), 0);
        assertEq(amm.reserveA(), AMOUNT);
        assertEq(amm.reserveB(), AMOUNT);
    }

    function testAddLiquidityEmitsEvent() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), AMOUNT);
        tokenB.approve(address(amm), AMOUNT);

        // Don't check liquidity value precisely, just verify event is emitted with correct indexed provider
        vm.expectEmit(true, false, false, false);
        emit SimpleAMM.LiquidityAdded(alice, AMOUNT, AMOUNT, 0);
        amm.addLiquidity(AMOUNT, AMOUNT, block.timestamp + 300);
        vm.stopPrank();
    }

    function testAddLiquiditySubsequent() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);
        _addLiquidity(bob, 5_000 * 1e18, 5_000 * 1e18);

        uint256 aliceLP = amm.balanceOf(alice);
        uint256 bobLP = amm.balanceOf(bob);
        assertGt(bobLP, 0);
        // Bob added half the amount, so roughly half the LP tokens
        assertApproxEqRel(bobLP, aliceLP / 2, 0.05e18); // 5% tolerance
    }

    function testAddLiquidityRejectsZeroAmount() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), AMOUNT);
        vm.expectRevert("Zero amount");
        amm.addLiquidity(0, AMOUNT, block.timestamp + 300);
        vm.stopPrank();
    }

    function testAddLiquidityExpiredDeadline() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), AMOUNT);
        tokenB.approve(address(amm), AMOUNT);
        vm.expectRevert("Transaction expired");
        amm.addLiquidity(AMOUNT, AMOUNT, block.timestamp - 1);
        vm.stopPrank();
    }

    // ── RemoveLiquidity ──

    function testRemoveLiquidity() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        uint256 lpBalance = amm.balanceOf(alice);
        vm.startPrank(alice);
        amm.removeLiquidity(lpBalance, block.timestamp + 300);
        vm.stopPrank();

        assertEq(amm.balanceOf(alice), 0);
        assertGt(tokenA.balanceOf(alice), 0);
        assertGt(tokenB.balanceOf(alice), 0);
    }

    function testRemoveLiquidityEmitsEvent() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);
        uint256 lpBalance = amm.balanceOf(alice);

        vm.startPrank(alice);
        vm.expectEmit(true, false, false, false);
        emit SimpleAMM.LiquidityRemoved(alice, 0, 0, lpBalance);
        amm.removeLiquidity(lpBalance, block.timestamp + 300);
        vm.stopPrank();
    }

    function testRemoveLiquidityZeroFails() public {
        vm.prank(alice);
        vm.expectRevert("Zero liquidity");
        amm.removeLiquidity(0, block.timestamp + 300);
    }

    // ── Swap ──

    function testSwapAForB() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        uint256 amountIn = 100 * 1e18;
        uint256 bobBBefore = tokenB.balanceOf(bob);

        vm.startPrank(bob);
        tokenA.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(tokenA), amountIn, 0, block.timestamp + 300);
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertGt(tokenB.balanceOf(bob), bobBBefore);
    }

    function testSwapBForA() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        uint256 amountIn = 100 * 1e18;

        vm.startPrank(bob);
        tokenB.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(tokenB), amountIn, 0, block.timestamp + 300);
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertGt(tokenA.balanceOf(bob), 0);
    }

    function testSwapUpdatesReserves() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 * 1e18);
        amm.swap(address(tokenA), 100 * 1e18, 0, block.timestamp + 300);
        vm.stopPrank();

        assertGt(amm.reserveA(), AMOUNT);
        assertLt(amm.reserveB(), AMOUNT);
    }

    function testSwapEmitsEvent() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 * 1e18);
        vm.expectEmit(true, true, false, false);
        emit SimpleAMM.Swap(bob, address(tokenA), 100 * 1e18, address(tokenB), 0);
        amm.swap(address(tokenA), 100 * 1e18, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function testSwapSlippageProtection() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 * 1e18);
        vm.expectRevert("Slippage exceeded");
        amm.swap(address(tokenA), 100 * 1e18, type(uint256).max, block.timestamp + 300);
        vm.stopPrank();
    }

    function testSwapInvalidToken() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        vm.prank(bob);
        vm.expectRevert("Invalid token");
        amm.swap(address(0x1234), 100 * 1e18, 0, block.timestamp + 300);
    }

    function testSwapZeroInput() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        vm.prank(bob);
        vm.expectRevert("Zero input");
        amm.swap(address(tokenA), 0, 0, block.timestamp + 300);
    }

    // ── K Value ──

    function testKValueIncreasesWithFee() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);
        uint256 kBefore = amm.reserveA() * amm.reserveB();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 1_000 * 1e18);
        amm.swap(address(tokenA), 1_000 * 1e18, 0, block.timestamp + 300);
        vm.stopPrank();

        uint256 kAfter = amm.reserveA() * amm.reserveB();
        assertGe(kAfter, kBefore, "K should increase due to fee");
    }

    // ── getAmountOut ──

    function testGetAmountOut() public view {
        uint256 out = amm.getAmountOut(1_000, 10_000, 10_000);
        assertGt(out, 0);
        assertLt(out, 1_000); // output must be less than input due to fee
    }

    function testGetAmountOutZeroInputFails() public {
        vm.expectRevert("Insufficient input");
        amm.getAmountOut(0, 10_000, 10_000);
    }

    // ── Pause ──

    function testPauseBlocksAddLiquidity() public {
        amm.pause();
        vm.prank(alice);
        vm.expectRevert();
        amm.addLiquidity(AMOUNT, AMOUNT, block.timestamp + 300);
    }

    function testPauseBlocksSwap() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);
        amm.pause();

        vm.prank(bob);
        vm.expectRevert();
        amm.swap(address(tokenA), 100 * 1e18, 0, block.timestamp + 300);
    }

    function testUnpauseRestoresFunctionality() public {
        amm.pause();
        amm.unpause();
        _addLiquidity(alice, AMOUNT, AMOUNT);
        assertGt(amm.balanceOf(alice), 0);
    }

    // ── FeeTo ──

    function testSetFeeTo() public {
        amm.setFeeTo(feeRecipient);
        assertEq(amm.feeTo(), feeRecipient);
    }

    function testSetFeeToOnlyFeeToSetter() public {
        vm.prank(alice);
        vm.expectRevert("Forbidden: not feeToSetter");
        amm.setFeeTo(feeRecipient);
    }

    function testFeeToSetterTwoStep() public {
        amm.proposeFeeToSetter(alice);

        vm.prank(alice);
        amm.acceptFeeToSetter();
        assertEq(amm.feeToSetter(), alice);
    }

    function testAcceptFeeToSetterOnlyPending() public {
        amm.proposeFeeToSetter(alice);

        vm.prank(bob);
        vm.expectRevert("Forbidden: not pending feeToSetter");
        amm.acceptFeeToSetter();
    }

    // ── Sync / Skim ──

    function testSync() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        // Directly transfer extra tokens to AMM (bypassing addLiquidity)
        tokenA.transfer(address(amm), 1_000 * 1e18);
        amm.sync();

        assertEq(amm.reserveA(), AMOUNT + 1_000 * 1e18);
    }

    function testSkim() public {
        _addLiquidity(alice, AMOUNT, AMOUNT);

        // Directly transfer extra tokens
        uint256 excess = 500 * 1e18;
        tokenA.transfer(address(amm), excess);

        uint256 bobABefore = tokenA.balanceOf(bob);
        amm.skim(bob);
        assertGt(tokenA.balanceOf(bob), bobABefore);
    }
}
