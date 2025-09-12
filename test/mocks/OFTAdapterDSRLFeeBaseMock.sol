// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterDSRLFeeBase } from "../../contracts/oft-dsrl/OFTAdapterDSRLFeeBase.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OFTAdapterDSRLFeeBaseMock
/// @dev Mock implementation of abstract OFTAdapterDSRLFeeBase for testing only
contract OFTAdapterDSRLFeeBaseMock is OFTAdapterDSRLFeeBase {
    constructor(address _token, address _lzEndpoint, address _delegate)
        OFTAdapterDSRLFeeBase(_token, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}

    /// @dev Implements abstract _debit by deferring to _debitView
    function _debit(
        address,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal view override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
    }

    /// @dev Implements abstract _credit by returning the same amount
    function _credit(
        address,
        uint256 _amountLD,
        uint32
    ) internal pure override returns (uint256 amountReceivedLD) {
        amountReceivedLD = _amountLD;
    }

    /// @notice Set the internal feeBalance for testing
    function setFeeBalance(uint256 _amount) external {
        feeBalance = _amount;
    }

    /// @notice Expose the _debitView function for testing
    function debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid) external view returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return _debitView(_amountLD, _minAmountLD, _dstEid);
    }
} 