// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// External imports
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { Fee } from "@layerzerolabs/oft-evm/contracts/Fee.sol";

// Local imports
import { DoubleSidedRateLimiter } from "./DoubleSidedRateLimiter.sol";
import { IMintableBurnableVoidReturn } from "./interfaces/IMintableBurnableVoidReturn.sol";

/**
 * @title MABAOFTDSRLFee
 * Full name: Mint And Burn OFT Adapter With Fee And Double Sided Rate Limiter
 * @notice A variant of the standard OFT Adapter that uses an existing ERC20's mint and burn mechanisms for cross-chain transfers.
 * @dev This contract needs mint permissions on the token.
 * @dev This contract burns the tokens from its own balance after transferring from the sender.
 * 
 * @dev This contract extends the DoubleSidedRateLimiter contract to provide double-sided rate limiting functionality.
 * @dev It allows for the configuration of rate limits for both outbound and inbound directions.
 * @dev It also allows for the setting of the rate limit accounting type to be net or gross.
 *
 * @dev Inherits from OFTCore and provides implementations for _debit and _credit functions using a mintable and burnable token.
 */
abstract contract MABAOFTDSRLFee is OFTCore, DoubleSidedRateLimiter, Fee, Pausable {
    using SafeERC20 for IERC20;

    /// @dev The underlying ERC20 token.
    IERC20 internal immutable innerToken;
    mapping(address => bool) public pausers;

    uint256 public feeBalance;

    event FeeWithdrawn(address indexed to, uint256 amountLD);
    event PauserStatusChange(address pauserAddress, bool newStatus);

    error NoFeesToWithdraw();
    error NotPauser();

    /**
     * @notice Initializes the MintBurnOFTAdapter contract.
     *
     * @param _token The address of the underlying ERC20 token.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The address of the delegate.
     *
     * @dev Calls the OFTCore constructor with the token's decimals, the endpoint, and the delegate.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTCore(IERC20Metadata(_token).decimals(), _lzEndpoint, _delegate) {
        innerToken = IERC20(_token);
    }

    /**
     * @notice Sets the cross-chain tx rate limits for specific endpoints based on provided configurations.
     * It allows configuration of rate limits either for outbound or inbound directions.
     * This method is designed to be called by contract admins for updating the system's rate limiting behavior.
     * 
     * @param _rateLimitConfigs An array of `RateLimitConfig` structs that specify the new rate limit settings.
     * Each struct includes an endpoint ID, the limit value, and the window duration.
     * @param _direction The direction (inbound or outbound) specifies whether the endpoint ID passed should be considered a srcEid or dstEid.
     * This parameter determines which set of rate limits (inbound or outbound) will be updated for each endpoint.
     */
    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs, RateLimitDirection _direction) external onlyOwner {
        _setRateLimits(_rateLimitConfigs, _direction);
    }

    /**
     * @notice Resets the rate limits for the given endpoint ids.
     * @param _eids The endpoint ids to reset the rate limits for.
     * @param _direction The direction of the rate limits to reset.
     */
    function resetRateLimits(uint32[] calldata _eids, RateLimitDirection _direction) external onlyOwner {
        _resetRateLimits(_eids, _direction);
    }

    /**
     * @notice Sets the rate limit accounting type.
     * @dev You may want to call `resetRateLimits` after changing the rate limit accounting type.
     * @param _rateLimitAccountingType The new rate limit accounting type.
     */
    function setRateLimitAccountingType(RateLimitAccountingType _rateLimitAccountingType) external onlyOwner {
        _setRateLimitAccountingType(_rateLimitAccountingType);
    }

    /**
     * @notice Sets the pauser status for a given address.
     * @param _pauser The address to set the pauser status for.
     * @param _status The new pauser status.
     */
    function setPauser(address _pauser, bool _status) public onlyOwner {
        pausers[_pauser] = _status;

        emit PauserStatusChange(_pauser, _status);
    }

    /**
     * @notice Pauses the contract if the caller is a pauser.
     * @dev Only pausers can pause the contract.
     */
    function pause() external {
        if (!pausers[msg.sender]) revert NotPauser();
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only the owner can unpause the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Retrieves the address of the underlying ERC20 token.
     *
     * @return The address of the adapted ERC20 token.
     *
     * @dev In the case of MintBurnOFTAdapter, address(this) and erc20 are NOT the same contract.
     */
    function token() public view returns (address) {
        return address(innerToken);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the underlying token to send.
     *
     * @return requiresApproval True if approval is required, false otherwise.
     *
     * @dev In this adapter, approval is REQUIRED because it uses allowance
     * from the sender to transfer tokens from the sender to the adapter before burning.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return true;
    }

    /**
     * @notice Withdraws accumulated fees to a specified address.
     * @param _to The address to which the fees will be withdrawn.
     */
    function withdrawFees(address _to) external onlyOwner {
        uint256 balance = feeBalance;
        if (balance == 0) revert NoFeesToWithdraw();

        feeBalance = 0;
        innerToken.safeTransfer(_to, balance);
        emit FeeWithdrawn(_to, balance);
    }

    function _debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal view virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        amountSentLD = _amountLD;

        // @dev Apply the fee, then de-dust the amount afterwards.
        // This means the fee is taken from the amount before the dust is removed.
        uint256 fee = getFee(_dstEid, _amountLD);
        amountReceivedLD = _removeDust(_amountLD - fee);

        // @dev Check for slippage.
        if (amountReceivedLD < _minAmountLD) {
            revert SlippageExceeded(amountReceivedLD, _minAmountLD);
        }
    }

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
        _checkAndUpdateRateLimit(_dstEid, amountSentLD, RateLimitDirection.Outbound);

        if (amountSentLD > amountReceivedLD) {
            // @dev increment the total fees that can be withdrawn
            feeBalance += (amountSentLD - amountReceivedLD);

            innerToken.safeTransferFrom(_from, address(this), amountSentLD);
        }

        IMintableBurnableVoidReturn(address(innerToken)).burn(amountSentLD > amountReceivedLD ? address(this) : _from, amountReceivedLD);
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
        if (_to == address(0x0)) _to = address(0xdead); // _mint(...) does not support address(0x0)

        // Check and update the rate limit based on the source endpoint ID (srcEid) and the amount in local decimals from the message.
        _checkAndUpdateRateLimit(_srcEid, _amountLD, RateLimitDirection.Inbound);

        // Mints the tokens and transfers to the recipient.
        IMintableBurnableVoidReturn(address(innerToken)).mint(_to, _amountLD);
        
        // In the case of NON-default OFTAdapter, the amountLD MIGHT not be equal to amountReceivedLD.
        return _amountLD;
    }
}
