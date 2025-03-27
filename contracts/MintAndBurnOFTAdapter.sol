// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { MABAOFTDSRLFee } from "./oft-dsrl/MABAOFTDSRLFee.sol";

contract MintAndBurnOFTAdapter is MABAOFTDSRLFee {
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) MABAOFTDSRLFee(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}
}