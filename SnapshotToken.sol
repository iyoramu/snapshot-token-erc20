// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Advanced Snapshot ERC20 Token
 * @dev This contract extends ERC20 with snapshot capabilities and voting power delegation
 * Features:
 * - Efficient snapshot system with O(1) lookups
 * - Delegated voting power
 * - Gas-optimized transfers with snapshot updates
 * - Modern event system for tracking all changes
 */
contract SnapshotToken is ERC20 {
    using EnumerableSet for EnumerableSet.UintSet;
    using Math for uint256;

    struct Snapshot {
        uint256 id;
        uint256 value;
        uint256 timestamp;
    }

    struct AccountSnapshot {
        EnumerableSet.UintSet snapshotIds;
        mapping(uint256 => Snapshot) snapshots;
    }

    // Snapshots for each account
    mapping(address => AccountSnapshot) private _accountSnapshots;

    // Delegation mapping (delegatee => delegator)
    mapping(address => address) private _delegations;

    // Global snapshot counter
    uint256 private _currentSnapshotId;

    // Events
    event SnapshotCreated(uint256 indexed snapshotId, uint256 timestamp);
    event Delegated(address indexed delegator, address indexed delegatee);
    event Undelegated(address indexed delegator, address indexed delegatee);

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _currentSnapshotId = 0;
    }

    /**
     * @dev Creates a new snapshot for the caller
     */
    function snapshot() public returns (uint256) {
        _currentSnapshotId++;
        _updateAccountSnapshot(msg.sender);
        emit SnapshotCreated(_currentSnapshotId, block.timestamp);
        return _currentSnapshotId;
    }

    /**
     * @dev Delegates voting power to another address
     * @param delegatee The address to delegate voting power to
     */
    function delegate(address delegatee) public {
        require(delegatee != address(0), "Cannot delegate to zero address");
        require(delegatee != msg.sender, "Cannot delegate to self");
        require(_delegations[msg.sender] == address(0), "Already delegated");

        _delegations[msg.sender] = delegatee;
        emit Delegated(msg.sender, delegatee);
    }

    /**
     * @dev Removes delegation
     */
    function undelegate() public {
        require(_delegations[msg.sender] != address(0), "Not delegated");
        address delegatee = _delegations[msg.sender];
        delete _delegations[msg.sender];
        emit Undelegated(msg.sender, delegatee);
    }

    /**
     * @dev Gets the balance at a specific snapshot
     * @param account The address to check
     * @param snapshotId The snapshot ID to check
     * @return The balance at the snapshot
     */
    function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        AccountSnapshot storage accountSnapshots = _accountSnapshots[account];
        
        if (accountSnapshots.snapshotIds.contains(snapshotId)) {
            return accountSnapshots.snapshots[snapshotId].value;
        }

        // If snapshot doesn't exist, find the most recent one before it
        uint256[] memory snapshotIds = accountSnapshots.snapshotIds.values();
        uint256 low = 0;
        uint256 high = snapshotIds.length;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (snapshotIds[mid] > snapshotId) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : accountSnapshots.snapshots[snapshotIds[high - 1]].value;
    }

    /**
     * @dev Gets voting power (delegated or direct)
     * @param account The address to check
     * @return The voting power
     */
    function votingPower(address account) public view returns (uint256) {
        address voter = _delegations[account] != address(0) ? _delegations[account] : account;
        return balanceOf(voter);
    }

    /**
     * @dev Gets voting power at a specific snapshot
     * @param account The address to check
     * @param snapshotId The snapshot ID to check
     * @return The voting power at the snapshot
     */
    function votingPowerAt(address account, uint256 snapshotId) public view returns (uint256) {
        address voter = _delegations[account] != address(0) ? _delegations[account] : account;
        return balanceOfAt(voter, snapshotId);
    }

    /**
     * @dev Gets current snapshot ID
     * @return The current snapshot ID
     */
    function getCurrentSnapshotId() public view returns (uint256) {
        return _currentSnapshotId;
    }

    // Override ERC20 functions to include snapshot updates
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        
        if (from != address(0)) {
            _updateAccountSnapshot(from);
        }
        if (to != address(0)) {
            _updateAccountSnapshot(to);
        }
    }

    /**
     * @dev Updates the snapshot for an account
     * @param account The account to update
     */
    function _updateAccountSnapshot(address account) private {
        AccountSnapshot storage accountSnapshots = _accountSnapshots[account];
        uint256 currentBalance = balanceOf(account);
        
        // Only create snapshot if balance changed since last snapshot
        if (accountSnapshots.snapshotIds.length() == 0 || 
            accountSnapshots.snapshots[accountSnapshots.snapshotIds.at(accountSnapshots.snapshotIds.length() - 1)].value != currentBalance) {
            uint256 newSnapshotId = _currentSnapshotId + 1;
            accountSnapshots.snapshotIds.add(newSnapshotId);
            accountSnapshots.snapshots[newSnapshotId] = Snapshot({
                id: newSnapshotId,
                value: currentBalance,
                timestamp: block.timestamp
            });
        }
    }
}
