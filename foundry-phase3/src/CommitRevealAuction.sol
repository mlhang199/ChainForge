// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title CommitRevealAuction
/// @dev Commit-Reveal 拍卖 — 防止出价被 front-run
///
/// 流程: commit(keccak256(bid, secret)) → startRevealPhase → reveal(bid, secret) → 确定最高出价者
contract CommitRevealAuction is Ownable {
    error NotInCommitPhase();
    error NotInRevealPhase();
    error AlreadyCommitted();
    error HashMismatch();
    error BidTooLow(uint256 bid, uint256 highestBid);
    error AuctionEnded();

    struct Commit {
        bytes32 hash;
        uint256 blockNumber;
    }

    mapping(address => Commit) public commits;
    mapping(address => uint256) public revealedBids;

    address[] public committers;

    address public highestBidder;
    uint256 public highestBid;

    bool public revealPhase;
    bool public ended;

    event Committed(address indexed bidder, uint256 blockNumber);
    event Revealed(address indexed bidder, uint256 bid);
    event AuctionSettled(address indexed winner, uint256 winningBid);

    constructor() Ownable(msg.sender) {}

    // ─── Commit Phase ─────────────────────────────────────

    function commit(bytes32 _hash) external {
        if (revealPhase) revert NotInCommitPhase();
        if (ended) revert AuctionEnded();
        if (commits[msg.sender].hash != bytes32(0)) revert AlreadyCommitted();

        commits[msg.sender] = Commit({hash: _hash, blockNumber: block.number});
        committers.push(msg.sender);

        emit Committed(msg.sender, block.number);
    }

    // ─── Reveal Phase ─────────────────────────────────────

    function startRevealPhase() external onlyOwner {
        if (revealPhase) revert NotInCommitPhase();
        if (ended) revert AuctionEnded();
        revealPhase = true;
    }

    function reveal(uint256 _bid, bytes32 _secret) external {
        if (!revealPhase) revert NotInRevealPhase();
        if (ended) revert AuctionEnded();

        bytes32 expectedHash = commits[msg.sender].hash;
        if (expectedHash == bytes32(0)) revert NotInCommitPhase();
        if (keccak256(abi.encodePacked(_bid, _secret)) != expectedHash) revert HashMismatch();

        // 防止重复 reveal
        commits[msg.sender].hash = bytes32(0);

        revealedBids[msg.sender] = _bid;

        if (_bid > highestBid) {
            highestBid = _bid;
            highestBidder = msg.sender;
        }

        emit Revealed(msg.sender, _bid);
    }

    // ─── Settlement ───────────────────────────────────────

    function settle() external onlyOwner {
        if (ended) revert AuctionEnded();
        ended = true;
        emit AuctionSettled(highestBidder, highestBid);
    }

    // ─── View ─────────────────────────────────────────────

    function committerCount() external view returns (uint256) {
        return committers.length;
    }

    /// @dev 生成 commit hash 的辅助函数
    function makeHash(uint256 _bid, bytes32 _secret) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_bid, _secret));
    }
}
