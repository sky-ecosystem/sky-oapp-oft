// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { RateLimitAccountingType } from "./ISkyRateLimiter.sol";

interface ISkyOFTAdapter {
    // Events
    event LockedTokensMigrated(address indexed to, uint256 amountLD);

    // Errors
    error InvalidAddressZero();

    /**
     * @notice Migrates all locked tokens to a specified address, less the accumulated fees.
     * @param _to The address to which the locked tokens will be migrated.
     *
     * @dev This function is intended to be called by the owner to migrate all locked tokens
     * from this contract to another address, effectively allowing for a migration of the contract's state.
     * @dev The migration EXCLUDES accumulated fees.
     */
    function migrateLockedTokens(address _to) external;

    /**
     * @notice Sets the accounting type for the reserved aggregate eid.
     * @param aggregateRateLimitAccountingType The new aggregate-slot accounting type.
     * @dev You may want to call `resetRateLimits` for `SENTINEL_EID` after changing this.
     */
    function setAggregateRateLimitAccountingType(RateLimitAccountingType aggregateRateLimitAccountingType) external;
}
