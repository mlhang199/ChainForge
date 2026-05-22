// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/CommitRevealAuction.sol";

contract CommitRevealAuctionTest is Test {
    CommitRevealAuction auction;

    address owner;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    bytes32 constant ALICE_SECRET = keccak256("alice_secret");
    bytes32 constant BOB_SECRET = keccak256("alice_secret"); // different bid, same word is fine
    bytes32 constant CAROL_SECRET = keccak256("carol_secret");

    function setUp() public {
        owner = address(this);
        auction = new CommitRevealAuction();
    }

    function _commit(address user, uint256 bid, bytes32 secret) internal {
        bytes32 hash = keccak256(abi.encodePacked(bid, secret));
        vm.prank(user);
        auction.commit(hash);
    }

    // ── Commit Phase ──

    function testCommitSuccess() public {
        bytes32 hash = keccak256(abi.encodePacked(uint256(100), ALICE_SECRET));
        vm.prank(alice);
        auction.commit(hash);

        (bytes32 storedHash, uint256 blockNum) = auction.commits(alice);
        assertEq(storedHash, hash);
        assertGt(blockNum, 0);
    }

    function testCommitEmitsEvent() public {
        bytes32 hash = keccak256(abi.encodePacked(uint256(100), ALICE_SECRET));
        vm.expectEmit(true, false, false, false);
        emit CommitRevealAuction.Committed(alice, block.number);
        vm.prank(alice);
        auction.commit(hash);
    }

    function testCommitRejectsDuplicate() public {
        _commit(alice, 100, ALICE_SECRET);

        bytes32 newHash = keccak256(abi.encodePacked(uint256(200), ALICE_SECRET));
        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.AlreadyCommitted.selector);
        auction.commit(newHash);
    }

    function testCommitRejectsAfterRevealPhase() public {
        auction.startRevealPhase();

        bytes32 hash = keccak256(abi.encodePacked(uint256(100), ALICE_SECRET));
        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.NotInCommitPhase.selector);
        auction.commit(hash);
    }

    function testCommitterCount() public {
        _commit(alice, 100, ALICE_SECRET);
        _commit(bob, 200, BOB_SECRET);
        assertEq(auction.committerCount(), 2);
    }

    // ── Reveal Phase ──

    function testFullCommitRevealFlow() public {
        _commit(alice, 100, ALICE_SECRET);
        _commit(bob, 200, BOB_SECRET);

        auction.startRevealPhase();

        vm.prank(alice);
        auction.reveal(100, ALICE_SECRET);

        vm.prank(bob);
        auction.reveal(200, BOB_SECRET);

        assertEq(auction.highestBidder(), bob);
        assertEq(auction.highestBid(), 200);
    }

    function testAliceWinsHigherBid() public {
        _commit(alice, 500, ALICE_SECRET);
        _commit(bob, 200, BOB_SECRET);

        auction.startRevealPhase();

        vm.prank(alice);
        auction.reveal(500, ALICE_SECRET);

        vm.prank(bob);
        auction.reveal(200, BOB_SECRET);

        assertEq(auction.highestBidder(), alice);
        assertEq(auction.highestBid(), 500);
    }

    function testRevealEmitsEvent() public {
        _commit(alice, 100, ALICE_SECRET);
        auction.startRevealPhase();

        vm.expectEmit(true, false, false, false);
        emit CommitRevealAuction.Revealed(alice, 100);
        vm.prank(alice);
        auction.reveal(100, ALICE_SECRET);
    }

    function testRevealRejectsBeforeRevealPhase() public {
        _commit(alice, 100, ALICE_SECRET);

        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.NotInRevealPhase.selector);
        auction.reveal(100, ALICE_SECRET);
    }

    function testRevealRejectsWrongSecret() public {
        _commit(alice, 100, ALICE_SECRET);
        auction.startRevealPhase();

        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.HashMismatch.selector);
        auction.reveal(100, keccak256("wrong_secret"));
    }

    function testRevealRejectsWrongBid() public {
        _commit(alice, 100, ALICE_SECRET);
        auction.startRevealPhase();

        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.HashMismatch.selector);
        auction.reveal(999, ALICE_SECRET);
    }

    function testRevealRejectsNoCommit() public {
        auction.startRevealPhase();

        vm.prank(carol);
        vm.expectRevert(CommitRevealAuction.NotInCommitPhase.selector);
        auction.reveal(100, CAROL_SECRET);
    }

    function testRevealPreventsDoubleReveal() public {
        _commit(alice, 100, ALICE_SECRET);
        auction.startRevealPhase();

        vm.prank(alice);
        auction.reveal(100, ALICE_SECRET);

        // second reveal: hash was zeroed
        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.NotInCommitPhase.selector);
        auction.reveal(100, ALICE_SECRET);
    }

    // ── Settlement ──

    function testSettle() public {
        _commit(alice, 300, ALICE_SECRET);
        auction.startRevealPhase();

        vm.prank(alice);
        auction.reveal(300, ALICE_SECRET);

        vm.expectEmit(true, false, false, false);
        emit CommitRevealAuction.AuctionSettled(alice, 300);
        auction.settle();

        assertTrue(auction.ended());
    }

    function testSettleRejectsDoubleSettle() public {
        auction.settle();
        vm.expectRevert(CommitRevealAuction.AuctionEnded.selector);
        auction.settle();
    }

    function testSettleOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        auction.settle();
    }

    function testCommitRejectsAfterEnd() public {
        auction.settle();
        bytes32 hash = keccak256(abi.encodePacked(uint256(100), ALICE_SECRET));
        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.AuctionEnded.selector);
        auction.commit(hash);
    }

    function testRevealRejectsAfterEnd() public {
        _commit(alice, 100, ALICE_SECRET);
        auction.startRevealPhase();
        auction.settle();

        vm.prank(alice);
        vm.expectRevert(CommitRevealAuction.AuctionEnded.selector);
        auction.reveal(100, ALICE_SECRET);
    }

    // ── Helper ──

    function testMakeHash() public {
        bytes32 expected = keccak256(abi.encodePacked(uint256(42), keccak256("test")));
        assertEq(auction.makeHash(42, keccak256("test")), expected);
    }

    // ── StartRevealPhase ──

    function testStartRevealPhaseOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        auction.startRevealPhase();
    }

    function testStartRevealPhaseRejectsDouble() public {
        auction.startRevealPhase();
        vm.expectRevert(CommitRevealAuction.NotInCommitPhase.selector);
        auction.startRevealPhase();
    }

    // ── Three-way auction ──

    function testThreeWayAuctionHighestWins() public {
        _commit(alice, 100, ALICE_SECRET);
        _commit(bob, 300, BOB_SECRET);
        _commit(carol, 200, CAROL_SECRET);

        auction.startRevealPhase();

        vm.prank(alice);
        auction.reveal(100, ALICE_SECRET);
        vm.prank(bob);
        auction.reveal(300, BOB_SECRET);
        vm.prank(carol);
        auction.reveal(200, CAROL_SECRET);

        assertEq(auction.highestBidder(), bob);
        assertEq(auction.highestBid(), 300);

        auction.settle();
        assertTrue(auction.ended());
    }
}
