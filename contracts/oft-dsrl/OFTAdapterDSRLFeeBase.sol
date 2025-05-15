// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Fee } from "@layerzerolabs/oft-evm/contracts/Fee.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

import { DoubleSidedRateLimiter } from "./DoubleSidedRateLimiter.sol";

/**
 * @title OFTAdapterDSRLFeeBase
 * @dev Base contract for Omnichain Fungible Token Adapter with Double Sided Rate Limiter and Fee
 * @dev It extracts common fee, rate limiting, pauser logic, and debitView implementation.
 */
abstract contract OFTAdapterDSRLFeeBase is OFTCore, DoubleSidedRateLimiter, Fee, Pausable {
    using SafeERC20 for IERC20;

    uint256 public feeBalance;
    mapping(address => bool) public pausers;

    IERC20 internal immutable innerToken;

    event FeeWithdrawn(address indexed to, uint256 amountLD);
    event PauserStatusChange(address pauserAddress, bool newStatus);

    error NoFeesToWithdraw();
    error NotPauser();

    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTCore(IERC20Metadata(_token).decimals(), _lzEndpoint, _delegate) {
        innerToken = IERC20(_token);
    }

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the adapted ERC20 token.
     *
     * @dev In the case of OFTAdapter, address(this) and ERC20 are NOT the same contract.
     */
    function token() public view returns (address) {
        return address(innerToken);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return true;
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
     * @notice Withdraws accumulated fees to a specified address.
     * @param _to The address to which the fees will be withdrawn.
     */
    function withdrawFees(address _to) external onlyOwner {
        // @dev doesn't allow owner to pull from the locked assets of the contract,
        // only from accumulated fees
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
} 