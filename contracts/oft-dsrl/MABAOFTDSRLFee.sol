// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { OFTAdapterDSRLFeeBase } from "./OFTAdapterDSRLFeeBase.sol";
import { IMintableBurnableVoidReturn } from "./interfaces/IMintableBurnableVoidReturn.sol";

/**
 * @title MABAOFTDSRLFee
 * Full name: Mint And Burn OFT Adapter With Fee And Double Sided Rate Limiter
 * @notice A variant of the standard OFT Adapter that uses an existing ERC20's mint and burn mechanisms for cross-chain transfers.
 * @dev This contract needs mint permissions on the token.
 * @dev This contract burns the tokens from the sender's balance.
 *
 * @dev This contract extends the DoubleSidedRateLimiter contract to provide double-sided rate limiting functionality.
 * @dev It allows for the configuration of rate limits for both outbound and inbound directions.
 * @dev It also allows for the setting of the rate limit accounting type to be net or gross.
 */
abstract contract MABAOFTDSRLFee is OFTAdapterDSRLFeeBase {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the MintBurnOFTAdapter contract.
     *
     * @param _token The address of the underlying ERC20 token.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The address of the delegate.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapterDSRLFeeBase(_token, _lzEndpoint, _delegate) {}

    /**
     * @notice Burns tokens from the sender's balance to prepare for sending.
     *
     * @param _from The address to debit the tokens from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     *
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     *
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, i.e., 1 token in, 1 token out.
     *      If the 'innerToken' applies something like a transfer fee, the default will NOT work.
     *      A pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev we are using amountReceivedLD because we care about the amount of tokens leaving the chain
        // @dev fee doesn't leave the chain, so we don't care about it here
        _checkAndUpdateRateLimit(_dstEid, amountReceivedLD, RateLimitDirection.Outbound);

        uint256 fee = amountSentLD - amountReceivedLD;

        if (fee > 0) {
            // @dev increment the total fees that can be withdrawn
            feeBalance += fee;

            innerToken.safeTransferFrom(_from, address(this), fee);
        }

        IMintableBurnableVoidReturn(address(innerToken)).burn(_from, amountReceivedLD);
    }

    /**
     * @notice Mints tokens to the specified address upon receiving them.
     *
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     *
     * @return amountReceivedLD The amount of tokens actually received in local decimals.
     *
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, i.e., 1 token in, 1 token out.
     *      If the 'innerToken' applies something like a transfer fee, the default will NOT work.
     *      A pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
        if (_to == address(0x0) || _to == address(innerToken)) _to = address(0xdead); // mint fn has restrictions

        // Check and update the rate limit based on the source endpoint ID (srcEid) and the amount in local decimals from the message.
        _checkAndUpdateRateLimit(_srcEid, _amountLD, RateLimitDirection.Inbound);

        // Mints the tokens and transfers to the recipient.
        IMintableBurnableVoidReturn(address(innerToken)).mint(_to, _amountLD);
        
        // In the case of NON-default OFTAdapter, the amountLD MIGHT not be equal to amountReceivedLD.
        return _amountLD;
    }
}
