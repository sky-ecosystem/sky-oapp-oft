// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Usds } from "../mocks/Usds.sol";
import { MABAOFTTest } from "./MABAOFT.t.sol";

contract MABAOFTUSDSTest is MABAOFTTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
        bToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
        cToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
    }

    function assignMintingRights() public override {
        Usds(address(aToken)).rely(address(aOFT));
        Usds(address(bToken)).rely(address(bOFT));
        Usds(address(cToken)).rely(address(cOFT));
    }
}