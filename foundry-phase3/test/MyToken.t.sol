// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // name, symbol, initialSupply, maxSupply (0 = unlimited)
        token = new MyToken("ChainForge Token", "CFT", 1_000_000, 0);
        token.transfer(alice, 10_000 * 1e18);
    }

    // ── 基本属性 ──

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1_000_000 * 1e18);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "ChainForge Token");
        assertEq(token.symbol(), "CFT");
    }

    function testMaxSupplyUnlimited() public view {
        assertEq(token.maxSupply(), 0);
    }

    function testMaxSupplyLimited() public {
        MyToken limited = new MyToken("Limited", "LTD", 500_000, 1_000_000);
        assertEq(limited.maxSupply(), 1_000_000 * 1e18);
    }

    // ── Transfer ──

    function testTransfer() public {
        vm.prank(alice);
        token.transfer(bob, 100 * 1e18);
        assertEq(token.balanceOf(bob), 100 * 1e18);
        assertEq(token.balanceOf(alice), 10_000 * 1e18 - 100 * 1e18);
    }

    function testTransferEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(alice, bob, 100 * 1e18);
        token.transfer(bob, 100 * 1e18);
    }

    function testTransferFailsExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1_000_000 * 1e18);
    }

    // ── Mint ──

    function testMint() public {
        token.mint(bob, 5_000);
        assertEq(token.balanceOf(bob), 5_000 * 1e18);
    }

    function testMintOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.mint(alice, 100);
    }

    function testMintExceedsMaxSupply() public {
        MyToken limited = new MyToken("Limited", "LTD", 900_000, 1_000_000);
        vm.expectRevert("Exceeds max supply");
        limited.mint(bob, 200_000);
    }

    function testInitialSupplyExceedsMax() public {
        vm.expectRevert("Initial supply exceeds max");
        new MyToken("Bad", "BAD", 2_000_000, 1_000_000);
    }

    // ── Approve / Allowance ──

    function testApprove() public {
        vm.prank(alice);
        token.approve(bob, 500 * 1e18);
        assertEq(token.allowance(alice, bob), 500 * 1e18);
    }

    function testApproveEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(alice, bob, 500 * 1e18);
        token.approve(bob, 500 * 1e18);
    }

    // ── Permit (EIP-2612) ──

    function testPermit() public {
        // 使用已知私钥，确保签名和地址匹配
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        token.transfer(owner, 1_000 * 1e18);

        uint256 amount = 500 * 1e18;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPk, owner, bob, amount);

        vm.prank(bob);
        token.permit(owner, bob, amount, type(uint256).max, v, r, s);
        assertEq(token.allowance(owner, bob), amount);
    }

    // ── Helpers ──

    function _signPermit(uint256 ownerPk, address owner, address spender, uint256 value)
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                token.nonces(owner),
                type(uint256).max
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(ownerPk, digest);
    }
}
