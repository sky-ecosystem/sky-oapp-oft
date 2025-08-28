// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { OFTAdapterDSRLFee } from "./oft-dsrl/OFTAdapterDSRLFee.sol";

contract OFTAdapter is OFTAdapterDSRLFee {
    using SafeERC20 for IERC20;

    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapterDSRLFee(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}

    event LockedTokensMigrated(address indexed to, uint256 amountLD);

    function migrateLockedTokens(address _to) external onlyOwner {
        uint256 balance = innerToken.balanceOf(address(this));
        innerToken.safeTransfer(_to, balance);
        emit LockedTokensMigrated(_to, balance);
    }
}