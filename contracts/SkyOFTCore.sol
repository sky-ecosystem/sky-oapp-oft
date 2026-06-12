// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { FeeUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/FeeUpgradeable.sol";
import { OFTCoreUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import { SendParam, OFTLimit, OFTFeeDetail, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { ISkyOFT } from "./interfaces/ISkyOFT.sol";
import {
    RateLimitConfig,
    RateLimitDirection,
    RateLimitAccountingType,
    SkyRateLimiter
} from "./SkyRateLimiter.sol";

/**
 * @title SkyOFTCore
 * @notice The SkyOFTCore contract, which manages cross-chain transfer rate limits and fees.
 * @dev This contracts defines the core functionalities of the SkyOFT system, including rate limit management,
 * pauser management, and fee withdrawal.
 *
 * @dev All mutable state in this contract and its ancestors lives in ERC-7201 namespaced storage,
 *      so new state can safely be added to any layer of the inheritance graph without shifting
 *      slot positions in deployed proxies.
 */
abstract contract SkyOFTCore is
    ISkyOFT,
    OFTCoreUpgradeable,
    SkyRateLimiter,
    FeeUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{

    struct SkyOFTCoreStorage {
        mapping(address pauser => bool canPause) pausers;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.storage.SkyOFTCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SKY_OFT_CORE_STORAGE_LOCATION = 0xf9dea648e4f31f4a8d1fbdc7eeca2b36f48d9310e4a268bd28dd82005c1b7900;

    function _getSkyOFTCoreStorage() internal pure returns (SkyOFTCoreStorage storage $) {
        assembly {
            $.slot := SKY_OFT_CORE_STORAGE_LOCATION
        }
    }

    function pausers(address _pauser) external view returns (bool) {
        return _getSkyOFTCoreStorage().pausers[_pauser];
    }

    IERC20 internal immutable innerToken;

    /**
     * @notice Sets immutables on the implementation contract.
     *
     * @param _token The address of the underlying ERC20 token.
     * @param _lzEndpoint The LayerZero endpoint address.
     *
     * @dev State (owner, peers, pause flag, etc.) is set via `__SkyOFTCore_init` from the child's `initialize`.
     */
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTCoreUpgradeable(IERC20Metadata(_token).decimals(), _lzEndpoint) {
        innerToken = IERC20(_token);
    }

    /**
     * @dev Initializes the inherited upgradeable contracts. Must be called from the child's `initialize`.
     * @param _delegate The address of the delegate.
     */
    function __SkyOFTCore_init(address _delegate) internal onlyInitializing {
        __OFTCore_init(_delegate);
        __Ownable_init(_delegate);
        __Fee_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Restricts proxy upgrades to the owner.
     * @dev Required hook for UUPS proxies.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Returns the address of the current implementation behind the proxy.
     */
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
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
    function approvalRequired() external pure virtual override returns (bool requiresApproval) {
        return true;
    }

    /**
     * @notice Provides the fee breakdown and settings data for an OFT. Unused in the default implementation.
     * @param _sendParam The parameters for the send operation.
     * @return oftLimit The OFT limit information.
     * @return oftFeeDetails The details of OFT fees.
     * @return oftReceipt The OFT receipt information.
     */
    function quoteOFT(
        SendParam calldata _sendParam
    )
        external
        view
        virtual
        override
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        uint256 minAmountLD = 0;
        (/*uint256 currentAmountInFlight*/, uint256 maxAmountLD) = getAmountCanBeSent(_sendParam.dstEid);
        oftLimit = OFTLimit(minAmountLD, maxAmountLD);

        // @dev This is the same as the send() operation, but without the actual send.
        // - amountSentLD is the amount in local decimals that would be sent from the sender.
        // - amountReceivedLD is the amount in local decimals that will be credited to the recipient on the remote OFT.
        // @dev The amountSentLD MIGHT not equal the amount the user actually receives. HOWEVER, the default does.
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debitView(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        // Return empty array if no fee is charged, otherwise include fee details.
        if (amountSentLD == amountReceivedLD) {
            oftFeeDetails = new OFTFeeDetail[](0);
        } else {
            oftFeeDetails = new OFTFeeDetail[](1);
            oftFeeDetails[0] = OFTFeeDetail(
                int256(amountSentLD - amountReceivedLD), // The fee amount in local decimals.
                'SkyOFT: cross-chain transfer fee' // Fee description.
            );
        }
    }

    /**
     * @notice Sets the cross-chain tx rate limits for specific endpoints based on provided configurations.
     * It allows configuration of rate limits either for outbound and inbound directions.
     * This method is designed to be called by contract admins for updating the system's rate limiting behavior.
     *
     * @notice WARNING: Changing rate limits without first calling resetRateLimits() MIGHT result in unexpected behavior.
     * DYOR on Rate Limits across every VM to ensure compatibility.
     * Especially consider inflight decay rates when reducing limits.
     *
     * @param _rateLimitConfigsInbound Array of INBOUND `RateLimitConfig` structs that specify new rate limit settings.
     * @param _rateLimitConfigsOutbound Array of OUTBOUND `RateLimitConfig` structs that specify new rate limit settings.
     *
     * @dev Each struct includes an endpoint ID, the limit value, and the window duration.
     * @dev The direction (inbound or outbound) specifies whether the eid passed should be considered a srcEid or dstEid.
     */
    function setRateLimits(
        RateLimitConfig[] calldata _rateLimitConfigsInbound,
        RateLimitConfig[] calldata _rateLimitConfigsOutbound
    ) external onlyOwner {
        _setRateLimits(_rateLimitConfigsInbound, RateLimitDirection.Inbound);
        _setRateLimits(_rateLimitConfigsOutbound, RateLimitDirection.Outbound);
    }

    /**
     * @notice Resets the rate limits for the given endpoint ids.
     * @param _eidsInbound The endpoint ids to reset the rate limits for inbound.
     * @param _eidsOutbound The endpoint ids to reset the rate limits for outbound.
     */
    function resetRateLimits(uint32[] calldata _eidsInbound, uint32[] calldata _eidsOutbound) external onlyOwner {
        _resetRateLimits(_eidsInbound, RateLimitDirection.Inbound);
        _resetRateLimits(_eidsOutbound, RateLimitDirection.Outbound);
    }

    /**
     * @notice Sets the rate limit accounting type.
     * @param _rateLimitAccountingType The new rate limit accounting type.
     * @dev You may want to call `resetRateLimits` after changing the rate limit accounting type.
     */
    function setRateLimitAccountingType(RateLimitAccountingType _rateLimitAccountingType) external onlyOwner {
        _setRateLimitAccountingType(_rateLimitAccountingType);
    }

    /**
     * @notice Sets the pauser status for a given address.
     * @param _pauser The address to set the pauser status for.
     * @param _canPause Boolean indicating ability to pause cross-chain transfers.
     */
    function setPauser(address _pauser, bool _canPause) public onlyOwner {
        SkyOFTCoreStorage storage $ = _getSkyOFTCoreStorage();
        // @dev Perform an idempotency check to prevent unnecessary state changes.
        // @dev Also prevents redundant event emissions.
        if ($.pausers[_pauser] == _canPause) revert PauserIdempotent(_pauser);

        $.pausers[_pauser] = _canPause;
        emit PauserSet(_pauser, _canPause);
    }

    /**
     * @notice Pauses the contract if the caller is a pauser.
     * @dev Only pausers can pause the contract.
     */
    function pause() external {
        if (!_getSkyOFTCoreStorage().pausers[msg.sender]) revert OnlyPauser(msg.sender);
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
     * @dev Internal function to mock the amount mutation from a OFT debit() operation.
     * @param _amountLD The amount to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination endpoint ID.
     * @return amountSentLD The amount sent, in local decimals.
     * @return amountReceivedLD The amount to be received on the remote chain, in local decimals.
     *
     * @dev This function applies the fee to the amount, removes dust, and checks for slippage.
     * @dev This view function will revert if cross-chain transfers are paused.
     */
    function _debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal view virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        amountSentLD = _amountLD;

        // @dev Apply the fee, then de-dust the amount afterwards.
        // This means the fee is taken from the amount before the dust is removed.
        uint256 fee = getFee(_dstEid, _amountLD);
        // @dev The fee technically also includes the dust.
        amountReceivedLD = _removeDust(_amountLD - fee);

        // @dev Check for slippage.
        if (amountReceivedLD < _minAmountLD) {
            revert SlippageExceeded(amountReceivedLD, _minAmountLD);
        }
    }
}
