// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { OFTAdapterDSRLFeeBase } from "../../contracts/oft-dsrl/OFTAdapterDSRLFeeBase.sol";
import { OFTAdapterDSRLFeeBaseMock } from "../mocks/OFTAdapterDSRLFeeBaseMock.sol";
import { TestHelperOz5WithRevertAssertions } from "./helpers/TestHelperOz5WithRevertAssertions.sol";

contract OFTAdapterDSRLFeeBaseTest is TestHelperOz5WithRevertAssertions {
    event FeeWithdrawn(address indexed to, uint256 amountLD);

    ERC20Mock private token;
    OFTAdapterDSRLFeeBaseMock private adapter;

    uint32 private aEid = 1;

    address private nonOwner = makeAddr("nonOwner");
    address private recipient = makeAddr("recipient");

    function setUp() public override {
        setUpEndpoints(1, LibraryType.UltraLightNode);

        token = new ERC20Mock("Token", "TK");
        adapter = new OFTAdapterDSRLFeeBaseMock(address(token), address(endpoints[aEid]), address(this));
    }

    function testConstructorProperties() public view {
        assertEq(address(adapter.token()), address(token));
        assertEq(address(adapter.owner()), address(this));
        assertEq(adapter.approvalRequired(), true);
    }

    function testWithdrawFeesSuccess() public {
        uint256 amount = 100 ether;
        token.mint(address(adapter), amount);
        adapter.setFeeBalance(amount);
        assertEq(adapter.feeBalance(), amount);

        vm.expectEmit();
        emit FeeWithdrawn(recipient, amount);
        adapter.withdrawFees(recipient);

        assertEq(adapter.feeBalance(), 0);
        assertEq(token.balanceOf(recipient), amount);
    }

    function testWithdrawFeesRevertsWhenNoFees() public {
        vm.expectRevert(OFTAdapterDSRLFeeBase.NoFeesToWithdraw.selector);
        adapter.withdrawFees(recipient);
    }

    function testWithdrawFeesRevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        adapter.withdrawFees(recipient);
    }

    function testDebitView() public {
        (uint256 amountSentLD, uint256 amountReceivedLD) = adapter.debitView(0.5 ether, 0.5 ether, aEid);
        assertEq(amountSentLD, 0.5 ether);
        assertEq(amountReceivedLD, 0.5 ether);

        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, 1e12, 1.3 * 1e12));
        (amountSentLD, amountReceivedLD) = adapter.debitView(1.3 * 1e12, 1.3 * 1e12, aEid);
    }
} 