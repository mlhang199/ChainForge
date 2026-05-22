// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MyNFT.sol";

contract MyNFTTest is Test {
    MyNFT nft;
    address minter = makeAddr("minter");
    address alice = makeAddr("alice");
    string constant BASE_URI = "ipfs://QmTest/";

    function setUp() public {
        // name, symbol, baseURI, maxSupply (0 = unlimited)
        nft = new MyNFT("ChainForge NFT", "CFNFT", BASE_URI, 0);
    }

    // ── 基本属性 ──

    function testNameAndSymbol() public view {
        assertEq(nft.name(), "ChainForge NFT");
        assertEq(nft.symbol(), "CFNFT");
    }

    function testMaxSupplyUnlimited() public view {
        assertEq(nft.maxSupply(), 0);
    }

    function testMaxSupplyLimited() public {
        MyNFT limited = new MyNFT("Limited", "LNFT", BASE_URI, 100);
        assertEq(limited.maxSupply(), 100);
    }

    // ── Mint ──

    function testMint() public {
        uint256 tokenId = nft.mint(alice);
        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.totalMinted(), 1);
    }

    function testMintSequentialIds() public {
        nft.mint(alice);
        uint256 secondId = nft.mint(minter);
        assertEq(secondId, 1);
        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(1), minter);
    }

    function testMintOnlyOwner() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter));
        nft.mint(minter);
    }

    function testMintExceedsMaxSupply() public {
        MyNFT limited = new MyNFT("Limited", "LNFT", BASE_URI, 2);
        limited.mint(alice);
        limited.mint(alice);
        vm.expectRevert("Max supply reached");
        limited.mint(alice);
    }

    // ── BatchMint ──

    function testBatchMint() public {
        nft.batchMint(alice, 5);
        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.totalMinted(), 5);
        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(4), alice);
    }

    function testBatchMintOnlyOwner() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter));
        nft.batchMint(minter, 3);
    }

    function testBatchMintExceedsMaxSupply() public {
        MyNFT limited = new MyNFT("Limited", "LNFT", BASE_URI, 5);
        limited.batchMint(alice, 3);
        vm.expectRevert("Max supply reached");
        limited.batchMint(alice, 3); // 3 + 3 > 5
    }

    // ── TokenURI ──

    function testTokenURI() public {
        nft.mint(alice);
        assertEq(nft.tokenURI(0), string(abi.encodePacked(BASE_URI, "0")));
    }

    function testSetBaseURI() public {
        nft.mint(alice);
        nft.setBaseURI("https://api.new.com/");
        assertEq(nft.tokenURI(0), "https://api.new.com/0");
    }

    function testSetBaseURIOnlyOwner() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter));
        nft.setBaseURI("https://hack.com/");
    }

    // ── Transfer ──

    function testTransferNFT() public {
        nft.mint(alice);
        vm.prank(alice);
        nft.transferFrom(alice, minter, 0);
        assertEq(nft.ownerOf(0), minter);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(minter), 1);
    }
}
