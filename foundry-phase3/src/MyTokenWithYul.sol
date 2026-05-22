// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyTokenWithYul
 * @dev Week 11 — 用 Yul 重写关键读取函数的 MyToken
 *
 * ERC20 存储布局（OZ v5）：
 *   Slot 0: _balances (mapping(address => uint256))
 *   Slot 1: _allowances (mapping(address => mapping(address => uint256)))
 *   Slot 2: _totalSupply (uint256)
 *   Slot 3: _name (string)
 *   Slot 4: _symbol (string)
 *   ...
 *
 * 用 Yul 直接读取这些 slot，绕过 Solidity 的开销。
 */
contract MyTokenWithYul is ERC20Permit, Ownable {
    uint256 private _maxSupply;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        uint256 maxSupply_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(msg.sender) {
        require(maxSupply_ == 0 || initialSupply_ <= maxSupply_, "Initial supply exceeds max");
        _maxSupply = maxSupply_ * 10 ** decimals();

        if (initialSupply_ > 0) {
            _mint(msg.sender, initialSupply_ * 10 ** decimals());
        }
    }

    function mint(address to, uint256 amount) external onlyOwner {
        uint256 amountWithDecimals = amount * 10 ** decimals();
        if (_maxSupply > 0) {
            require(totalSupply() + amountWithDecimals <= _maxSupply, "Exceeds max supply");
        }
        _mint(to, amountWithDecimals);
    }

    function maxSupply() external view returns (uint256) {
        return _maxSupply;
    }

    // ═══════════════════════════════════════════════════════
    // Yul 重写版本
    // ═══════════════════════════════════════════════════════

    /// @notice 用 Yul 重写 balanceOf — 直接 sload mapping
    function balanceOfYul(address account) external view returns (uint256 b) {
        // _balances 在 slot 0
        // balances[account] 的存储位置 = keccak256(abi.encode(account, 0))
        assembly {
            mstore(0x00, account)
            mstore(0x20, 0x00) // _balances.slot = 0
            let slot := keccak256(0x00, 0x40)
            b := sload(slot)
        }
    }

    /// @notice 用 Yul 重写 totalSupply — 直接 sload slot 2
    function totalSupplyYul() external view returns (uint256 ts) {
        assembly {
            ts := sload(2) // _totalSupply 在 slot 2
        }
    }

    /// @notice 用 Yul 重写 allowance 读取
    function allowanceYul(address owner, address spender) external view returns (uint256 a) {
        // _allowances 在 slot 1
        // allowances[owner][spender] = keccak256(abi.encode(spender, keccak256(abi.encode(owner, 1))))
        assembly {
            // 第一层：keccak256(owner . 1) → allowances[owner] 的 slot
            mstore(0x00, owner)
            mstore(0x20, 0x01) // _allowances.slot = 1
            let innerSlot := keccak256(0x00, 0x40)

            // 第二层：keccak256(spender . innerSlot) → allowances[owner][spender] 的值
            mstore(0x00, spender)
            mstore(0x20, innerSlot)
            let outerSlot := keccak256(0x00, 0x40)
            a := sload(outerSlot)
        }
    }

    /// @notice 用 Yul 读取 _maxSupply（slot 9，因为 OZ ERC20Permit 增加了额外 slot）
    function maxSupplyYul() external view returns (uint256 ms) {
        assembly {
            ms := sload(_maxSupply.slot)
        }
    }
}
