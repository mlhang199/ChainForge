// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/ChainForgeRouter.sol";
import "../src/SimpleAMM.sol";
import "../src/MyToken.sol";

contract ChainForgeRouterTest is Test {
    ChainForgeRouter router;
    SimpleAMM amm1; // CFT / WETH
    SimpleAMM amm2; // WETH / USDC
    MyToken cft;
    MyToken weth;
    MyToken usdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant LIQUIDITY_AMOUNT = 10_000 * 1e18;

    function setUp() public {
        cft = new MyToken("CFT", "CFT", 1_000_000, 0);
        weth = new MyToken("WETH", "WETH", 1_000_000, 0);
        usdc = new MyToken("USDC", "USDC", 1_000_000, 0);

        amm1 = new SimpleAMM(address(cft), address(weth));
        amm2 = new SimpleAMM(address(weth), address(usdc));

        router = new ChainForgeRouter();
        router.addPool(address(cft), address(weth), address(amm1));
        router.addPool(address(weth), address(usdc), address(amm2));

        // Distribute tokens
        cft.transfer(alice, 100_000 * 1e18);
        weth.transfer(alice, 100_000 * 1e18);
        usdc.transfer(alice, 100_000 * 1e18);
        cft.transfer(bob, 100_000 * 1e18);
        weth.transfer(bob, 100_000 * 1e18);
        usdc.transfer(bob, 100_000 * 1e18);

        // Add initial liquidity to both pools
        _addLiquidity(alice, address(cft), address(weth), address(amm1), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _addLiquidity(alice, address(weth), address(usdc), address(amm2), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    }

    function _addLiquidity(address user, address, address, address amm, uint256 amountA, uint256 amountB) internal {
        SimpleAMM pool = SimpleAMM(amm);
        vm.startPrank(user);
        IERC20(pool.tokenA()).approve(amm, amountA);
        IERC20(pool.tokenB()).approve(amm, amountB);
        pool.addLiquidity(amountA, amountB, block.timestamp + 300);
        vm.stopPrank();
    }

    // ── Pool Management ──

    function testPoolCount() public view {
        assertEq(router.poolCount(), 2);
    }

    function testPairFor() public view {
        assertEq(router.pairFor(address(cft), address(weth)), address(amm1));
        assertEq(router.pairFor(address(weth), address(cft)), address(amm1)); // bidirectional
        assertEq(router.pairFor(address(weth), address(usdc)), address(amm2));
    }

    function testAddPoolRejectsDuplicate() public {
        vm.expectRevert("Pool already exists");
        router.addPool(address(cft), address(weth), address(amm1));
    }

    function testAddPoolRejectsZeroAddress() public {
        vm.expectRevert("Zero address");
        router.addPool(address(0), address(weth), address(amm1));
    }

    function testAddPoolEmitsEvent() public {
        MyToken newToken = new MyToken("NEW", "NEW", 1_000_000, 0);
        SimpleAMM newAmm = new SimpleAMM(address(usdc), address(newToken));

        vm.expectEmit(true, true, true, false);
        emit ChainForgeRouter.PoolAdded(address(usdc), address(newToken), address(newAmm));
        router.addPool(address(usdc), address(newToken), address(newAmm));
    }

    // ── getAmountsOut ──

    function testGetAmountsOutSingleHop() public view {
        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(weth);

        uint256[] memory amounts = router.getAmountsOut(100 * 1e18, path);
        assertEq(amounts[0], 100 * 1e18);
        assertGt(amounts[1], 0);
        assertLt(amounts[1], 100 * 1e18); // fee deducted
    }

    function testGetAmountsOutMultiHop() public view {
        address[] memory path = new address[](3);
        path[0] = address(cft);
        path[1] = address(weth);
        path[2] = address(usdc);

        uint256[] memory amounts = router.getAmountsOut(100 * 1e18, path);
        assertEq(amounts[0], 100 * 1e18);
        assertGt(amounts[1], 0);
        assertGt(amounts[2], 0);
        assertLt(amounts[2], amounts[1]); // each hop loses value to fee
    }

    function testGetAmountsOutInvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(cft);

        vm.expectRevert("Invalid path");
        router.getAmountsOut(100 * 1e18, path);
    }

    function testGetAmountsOutPoolNotFound() public {
        MyToken newToken = new MyToken("NEW", "NEW", 1_000_000, 0);
        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(newToken);

        vm.expectRevert("Pool not found");
        router.getAmountsOut(100 * 1e18, path);
    }

    // ── swapExactTokensForTokens ──

    function testSwapSingleHop() public {
        uint256 amountIn = 100 * 1e18;

        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(weth);

        uint256 bobWethBefore = weth.balanceOf(bob);

        vm.startPrank(bob);
        cft.approve(address(router), amountIn);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn, 0, path, bob, block.timestamp + 300
        );
        vm.stopPrank();

        assertGt(amounts[1], 0);
        assertGt(weth.balanceOf(bob), bobWethBefore);
    }

    function testSwapMultiHop() public {
        uint256 amountIn = 100 * 1e18;

        address[] memory path = new address[](3);
        path[0] = address(cft);
        path[1] = address(weth);
        path[2] = address(usdc);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.startPrank(bob);
        cft.approve(address(router), amountIn);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn, 0, path, bob, block.timestamp + 300
        );
        vm.stopPrank();

        assertGt(amounts[2], 0);
        assertGt(usdc.balanceOf(bob), bobUsdcBefore);
    }

    function testSwapSlippageProtection() public {
        uint256 amountIn = 100 * 1e18;

        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(weth);

        vm.startPrank(bob);
        cft.approve(address(router), amountIn);
        vm.expectRevert("Slippage exceeded");
        router.swapExactTokensForTokens(
            amountIn, type(uint256).max, path, bob, block.timestamp + 300
        );
        vm.stopPrank();
    }

    function testSwapExpiredDeadline() public {
        uint256 amountIn = 100 * 1e18;

        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(weth);

        vm.startPrank(bob);
        cft.approve(address(router), amountIn);
        vm.expectRevert("Transaction expired");
        router.swapExactTokensForTokens(
            amountIn, 0, path, bob, block.timestamp - 1
        );
        vm.stopPrank();
    }

    function testSwapEmitsEvent() public {
        uint256 amountIn = 100 * 1e18;

        address[] memory path = new address[](2);
        path[0] = address(cft);
        path[1] = address(weth);

        vm.startPrank(bob);
        cft.approve(address(router), amountIn);
        vm.expectEmit(true, false, false, false);
        emit ChainForgeRouter.SwapExecuted(bob, amountIn, 0, path);
        router.swapExactTokensForTokens(
            amountIn, 0, path, bob, block.timestamp + 300
        );
        vm.stopPrank();
    }
}
