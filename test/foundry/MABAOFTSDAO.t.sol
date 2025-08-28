// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SDAO } from "../mocks/SDAO.sol";
import { MABAOFTTest } from "./MABAOFT.t.sol";

contract MABAOFTSDAOTest is MABAOFTTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new SDAO("SDAO", "SDAO")));
        bToken = IERC20(address(new SDAO("SDAO", "SDAO")));
        cToken = IERC20(address(new SDAO("SDAO", "SDAO")));
    }
    function assignMintingRights() public override {
        SDAO(address(aToken)).rely(address(aOFT));
        SDAO(address(bToken)).rely(address(bOFT));
        SDAO(address(cToken)).rely(address(cOFT));
    }
}