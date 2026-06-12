// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ISkyOFTAdapter } from "./interfaces/ISkyOFTAdapter.sol";
import { SkyOFTCore, RateLimitDirection } from "./SkyOFTCore.sol";

/**
 * @title SkyOFTAdapter Contract
 * @dev OFTAdapter is a contract that adapts an ERC-20 token to the OFT functionality.
 * @dev This contract extends the SkyOFTCore, which extends the SkyRateLimiter containing rate limiting functionality.
 * @dev It allows for the configuration of rate limits for both outbound and inbound directions.
 * @dev It also allows for the setting of the rate limit accounting type to be net or gross.
 *
 * @dev For existing ERC20 tokens, this can be used to convert the token to cross-chain compatibility.
 * @dev WARNING: ONLY 1 of these should exist for a given global mesh.
 */
contract SkyOFTAdapter is ISkyOFTAdapter, SkyOFTCore {
    using SafeERC20 for IERC20;

    // @dev Reserved eid for aggregate cross-chain caps. Unset sentinel limits brick every transfer.
    // @dev Both inbound and outbound must be configured; setting only one side bricks every transfer
    //      in the unconfigured direction across all peers.
    // @dev NOT included implicitly in `setRateLimits` / `resetRateLimits`: operators rotating limits or
    //      flipping `RateLimitAccountingType` must pass `SENTINEL_EID` in those arrays explicitly to
    //      affect the global cap alongside per-eid buckets.
    uint32 public constant SENTINEL_EID = type(uint32).max;

    struct SkyOFTAdapterStorage {
        uint256 feeBalance;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.storage.SkyOFTAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SKY_OFT_ADAPTER_STORAGE_LOCATION = 0xa212a9105d34110ec7b56ba95a22a00c83c40de826beea9f21530155344fbd00;

    function _getSkyOFTAdapterStorage() internal pure returns (SkyOFTAdapterStorage storage $) {
        assembly {
            $.slot := SKY_OFT_ADAPTER_STORAGE_LOCATION
        }
    }

    function feeBalance() external view returns (uint256) {
        return _getSkyOFTAdapterStorage().feeBalance;
    }

    /**
     * @notice Constructor sets immutables on the implementation; state is set via `initialize` on the proxy.
     *
     * @param _token The address of the underlying ERC20 token.
     * @param _lzEndpoint The LayerZero endpoint address.
     */
    constructor(address _token, address _lzEndpoint) SkyOFTCore(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the proxy.
     * @param _delegate The address of the delegate.
     */
    function initialize(address _delegate) external initializer {
        __SkyOFTCore_init(_delegate);
    }

    /**
     * @notice Outbound capacity to `_dstEid`, accounting for both the per-eid and the global (sentinel) caps.
     * @dev Overridden so `quoteOFT` and external callers see the true binding constraint.
     * @dev `currentAmountInFlight` is the per-eid bucket only; `amountCanBeSent` is `min(per-eid, sentinel)`.
     */
    function getAmountCanBeSent(
        uint32 _dstEid
    ) public view override returns (uint256 currentAmountInFlight, uint256 amountCanBeSent) {
        (currentAmountInFlight, amountCanBeSent) = super.getAmountCanBeSent(_dstEid);
        (, uint256 sentinelCap) = super.getAmountCanBeSent(SENTINEL_EID);
        if (sentinelCap < amountCanBeSent) amountCanBeSent = sentinelCap;
    }

    /**
     * @notice Inbound capacity from `_srcEid`, accounting for both the per-eid and the global (sentinel) caps.
     * @dev `currentAmountInFlight` is the per-eid bucket only; `amountCanBeReceived` is `min(per-eid, sentinel)`.
     */
    function getAmountCanBeReceived(
        uint32 _srcEid
    ) public view override returns (uint256 currentAmountInFlight, uint256 amountCanBeReceived) {
        (currentAmountInFlight, amountCanBeReceived) = super.getAmountCanBeReceived(_srcEid);
        (, uint256 sentinelCap) = super.getAmountCanBeReceived(SENTINEL_EID);
        if (sentinelCap < amountCanBeReceived) amountCanBeReceived = sentinelCap;
    }

    /**
     * @notice Withdraws accumulated fees to a specified address.
     * @param _to The address to which the fees will be withdrawn.
     * @param _amountLD The amount of tokens to withdraw in local decimals.
     *
     * @dev Doesn't allow owner to pull from the locked assets of the contract, only from accumulated fees.
     */
    function withdrawFees(address _to, uint256 _amountLD) external onlyOwner {
        SkyOFTAdapterStorage storage $ = _getSkyOFTAdapterStorage();
        uint256 balance = $.feeBalance;
        if (_amountLD > balance) revert InsufficientFeeBalance(_amountLD, balance);

        // @dev Deduct the amount from the fee balance before transferring.
        $.feeBalance -= _amountLD;

        innerToken.safeTransfer(_to, _amountLD);
        emit FeesWithdrawn(_to, _amountLD);
    }

    /**
     * @notice Migrates all locked tokens to a specified address, less the accumulated fees.
     * @param _to The address to which the locked tokens will be migrated.
     *
     * @dev This function is intended to be called by the owner to migrate all locked tokens
     * from this contract to another address, effectively allowing for a migration of the contract's state.
     * @dev The migration EXCLUDES accumulated fees.
     */
    function migrateLockedTokens(address _to) external onlyOwner {
        // @dev Block sending directly to the zero address.
        if (_to == address(0)) revert InvalidAddressZero();

        // @dev Do not include the fee balance in the migration.
        uint256 balance = innerToken.balanceOf(address(this)) - _getSkyOFTAdapterStorage().feeBalance;

        innerToken.safeTransfer(_to, balance);
        emit LockedTokensMigrated(_to, balance);
    }

    /**
     * @dev Locks tokens from the sender's specified balance in this contract.
     * @param _from The address to debit from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     *
     * @dev msg.sender will need to approve this _amountLD of tokens to be locked inside of the contract.
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
     * IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
     * a pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev We are using amountReceivedLD because that is the amount of tokens leaving the chain.
        // @dev The fee remains on this chain, thus it is not included in the rate limit check.
        _checkAndUpdateRateLimit(_dstEid, amountReceivedLD, RateLimitDirection.Outbound);

        // @dev Apply the global outbound cap (Net-mode mutual offset propagates to inbound sentinel).
        _checkAndUpdateRateLimit(SENTINEL_EID, amountReceivedLD, RateLimitDirection.Outbound);

        // @dev Lock tokens by moving them into this contract from the caller.
        innerToken.safeTransferFrom(_from, address(this), amountSentLD);

        // @dev Conditionally handle the fee.
        uint256 fee = amountSentLD - amountReceivedLD;
        if (fee > 0) _getSkyOFTAdapterStorage().feeBalance += fee;
    }

    /**
     * @notice Transfers tokens to the recipient.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @param _srcEid The source Endpoint ID.
     *
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
        // @dev Check and update the rate limit based on the source endpoint ID (srcEid).
        _checkAndUpdateRateLimit(_srcEid, _amountLD, RateLimitDirection.Inbound);

        // @dev Apply the global inbound cap (Net-mode mutual offset propagates to outbound sentinel).
        _checkAndUpdateRateLimit(SENTINEL_EID, _amountLD, RateLimitDirection.Inbound);

        // @dev If recipient is the zero address or the inner token, reroute to the dead address.
        if (_to == address(0) || _to == token()) _to = address(0xdead);

        // @dev Unlock the tokens and transfer to the recipient.
        innerToken.safeTransfer(_to, _amountLD);

        return _amountLD;
    }
}