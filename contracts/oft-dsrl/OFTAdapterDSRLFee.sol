// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { OFTAdapterDSRLFeeBase } from "./OFTAdapterDSRLFeeBase.sol";

/**
 * @title OFTAdapterDSRLFee Contract
 * @dev OFTAdapter is a contract that adapts an ERC-20 token to the OFT functionality.
 * @dev This contract extends the DoubleSidedRateLimiter contract to provide double-sided rate limiting functionality.
 * @dev It allows for the configuration of rate limits for both outbound and inbound directions.
 * @dev It also allows for the setting of the rate limit accounting type to be net or gross.
 *
 * @dev For existing ERC20 tokens, this can be used to convert the token to crosschain compatibility.
 * @dev WARNING: ONLY 1 of these should exist for a given global mesh,
 * unless you make a NON-default implementation of OFT and needs to be done very carefully.
 * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
 * IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
 * a pre/post balance check will need to be done to calculate the amountSentLD/amountReceivedLD.
 */
abstract contract OFTAdapterDSRLFee is OFTAdapterDSRLFeeBase {
    using SafeERC20 for IERC20;

    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapterDSRLFeeBase(_token, _lzEndpoint, _delegate) {}

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
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev we are using amountReceivedLD because we care about the amount of tokens leaving the chain
        // @dev fee doesn't leave the chain, so we don't care about it here
        _checkAndUpdateRateLimit(_dstEid, amountReceivedLD, RateLimitDirection.Outbound);

        if (amountSentLD > amountReceivedLD) {
            // @dev increment the total fees that can be withdrawn
            feeBalance += (amountSentLD - amountReceivedLD);
        }

        // @dev Lock tokens by moving them into this contract from the caller.
        innerToken.safeTransferFrom(_from, address(this), amountSentLD);
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     *
     * @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
     * IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
     * a pre/post balance check will need to be done to calculate the amountReceivedLD.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
        if (_to == address(0x0) || _to == address(innerToken)) _to = address(0xdead); // transfer fn has restrictions

        // Check and update the rate limit based on the source endpoint ID (srcEid) and the amount in local decimals from the message.
        _checkAndUpdateRateLimit(_srcEid, _amountLD, RateLimitDirection.Inbound);
        
        // @dev Unlock the tokens and transfer to the recipient.
        innerToken.safeTransfer(_to, _amountLD);

        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }
}