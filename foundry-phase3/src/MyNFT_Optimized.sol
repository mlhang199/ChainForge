// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyNFT_Optimized
 * @dev Week 10 Gas 优化版 MyNFT
 *
 * 优化项：
 *   1. batchMint: 缓存 _nextTokenId（1 SLOAD + 1 SSTORE 替代 N 次 SLOAD+SSTORE）
 *   2. batchMint: unchecked { ++i } 消除循环溢出检查
 *   3. batchMint: 预计算 tokenId = startId + i，避免每次递增
 */
contract MyNFT_Optimized is ERC721, Ownable {
    uint256 private _nextTokenId;
    string private _baseTokenURI;
    uint256 private _maxSupply;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {
        _baseTokenURI = baseURI_;
        _maxSupply = maxSupply_;
    }

    function mint(address to) external onlyOwner returns (uint256) {
        require(_maxSupply == 0 || _nextTokenId < _maxSupply, "Max supply reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    // ─── 优化: 缓存 + unchecked ──────────────────────────────
    // 优化前: 每次循环 _nextTokenId++ (1 SLOAD + 1 SSTORE) × quantity 次
    //         + i++ 溢出检查 × quantity 次
    // 优化后: 1 SLOAD + 1 SSTORE + unchecked 循环
    // Gas 节省: ~2,600 per iteration (SLOAD) + ~2,900 per iteration (SSTORE) + ~80 per iteration (unchecked)
    function batchMint(address to, uint256 quantity) external onlyOwner {
        require(_maxSupply == 0 || _nextTokenId + quantity <= _maxSupply, "Max supply reached");

        uint256 startId = _nextTokenId;    // 1 SLOAD（替代 quantity 次）
        _nextTokenId = startId + quantity;  // 1 SSTORE（替代 quantity 次）

        for (uint256 i; i < quantity;) {
            _safeMint(to, startId + i);     // 预计算 tokenId
            unchecked { ++i; }              // 跳过溢出检查
        }
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    function maxSupply() external view returns (uint256) {
        return _maxSupply;
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
