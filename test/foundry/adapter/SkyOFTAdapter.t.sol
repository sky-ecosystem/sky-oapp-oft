// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Mock imports
import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { OFTComposerMock } from "@layerzerolabs/oft-evm/test/mocks/OFTComposerMock.sol";
import { MintBurnERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/MintBurnERC20Mock.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import { SkyOFTAdapter } from "../../../contracts/SkyOFTAdapter.sol";
import { SkyRateLimiter, RateLimit, RateLimitConfig, RateLimitDirection, RateLimitAccountingType } from "../../../contracts/SkyRateLimiter.sol";
import { ISkyRateLimiter } from "../../../contracts/interfaces/ISkyRateLimiter.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt, Origin, OFTLimit, OFTFeeDetail } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import { SkyOFTCore } from "../../../contracts/SkyOFTCore.sol";
import { ISkyOFT } from "../../../contracts/interfaces/ISkyOFT.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// DevTools imports
import { TestHelperOz5WithRevertAssertions } from "../helpers/TestHelperOz5WithRevertAssertions.sol";

contract SkyOFTAdapterTest is TestHelperOz5WithRevertAssertions {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    IERC20 aToken;
    IERC20 bToken;
    IERC20 cToken;

    SkyOFTAdapter aOFT;
    SkyOFTAdapter bOFT;
    SkyOFTAdapter cOFT;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    uint256 public initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(userC, 1000 ether);
        
        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aOutboundConfigs = new RateLimitConfig[](1);
        aOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 10 ether, window: 60 seconds});

        // The inbound (receive) rate limits for OFT A.
        RateLimitConfig[] memory aInboundConfigs = new RateLimitConfig[](1);
        aInboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 10 ether, window: 60 seconds});

        // The outbound (send) rate limits for OFT B.
        RateLimitConfig[] memory bOutboundConfigs = new RateLimitConfig[](1);
        bOutboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        // The inbound (receive) rate limits for OFT B.
        RateLimitConfig[] memory bInboundConfigs = new RateLimitConfig[](1);
        bInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        // The outbound (send) rate limits for OFT C (only limits to A).
        RateLimitConfig[] memory cOutboundConfigs = new RateLimitConfig[](1);
        cOutboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});
        
        // The inbound (receive) rate limits for OFT C (only limits from A).
        RateLimitConfig[] memory cInboundConfigs = new RateLimitConfig[](1);
        cInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);
        setUpTokens();
        
        aOFT = SkyOFTAdapter(_deployAdapterProxy(address(aToken), address(endpoints[aEid]), address(this)));
        aOFT.setRateLimits(aInboundConfigs, aOutboundConfigs);
        _enableSentinelUnbounded(aOFT);

        bOFT = SkyOFTAdapter(_deployAdapterProxy(address(bToken), address(endpoints[bEid]), address(this)));
        bOFT.setRateLimits(bInboundConfigs, bOutboundConfigs);
        _enableSentinelUnbounded(bOFT);

        cOFT = SkyOFTAdapter(_deployAdapterProxy(address(cToken), address(endpoints[cEid]), address(this)));
        cOFT.setRateLimits(cInboundConfigs, cOutboundConfigs);
        _enableSentinelUnbounded(cOFT);

        // config and wire the ofts
        address[] memory ofts = new address[](3);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        ofts[2] = address(cOFT);
        this.wireOApps(ofts);

        // mint tokens
        deal(address(aToken), userA, initialBalance);
        deal(address(bToken), userB, initialBalance);
        deal(address(cToken), userC, initialBalance);

        // mint tokens to the B and C adapter lockboxes
        // this is not needed in production, only for testing
        // because there is more than one lockbox in the testing mesh
        deal(address(bToken), address(bOFT), initialBalance);
        deal(address(cToken), address(cOFT), initialBalance);
    }

    function setUpTokens() public virtual {
        aToken = new MintBurnERC20Mock("aToken", "aToken");
        bToken = new MintBurnERC20Mock("bToken", "bToken");
        cToken = new MintBurnERC20Mock("cToken", "cToken");
    }

    function _deployAdapterProxy(address _token, address _endpoint, address _delegate) internal returns (address) {
        address impl = _deployOApp(type(SkyOFTAdapter).creationCode, abi.encode(_token, _endpoint));
        return _deployOApp(
            type(ERC1967Proxy).creationCode,
            abi.encode(impl, abi.encodeCall(SkyOFTAdapter.initialize, (_delegate)))
        );
    }

    // @dev Configures the SENTINEL_EID buckets with effectively-unbounded limits so the global
    // cap is inert; per-eid behavior remains the binding constraint for the existing test scenarios.
    function _enableSentinelUnbounded(SkyOFTAdapter _oft) internal {
        RateLimitConfig[] memory s = new RateLimitConfig[](1);
        s[0] = RateLimitConfig({eid: _oft.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        _oft.setRateLimits(s, s);
    }

    function test_constructor() public view {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));
        assertEq(cOFT.owner(), address(this));

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);

        assertEq(aOFT.token(), address(aToken));
        assertEq(bOFT.token(), address(bToken));
        assertEq(cOFT.token(), address(cToken));
    }

    function test_set_rates() public {
        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        uint256 tokensToSend = 2 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send two times within the allowed outbound window.
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    function test_set_rates_only_apply_per_direction() public {
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);
        
        // The outbound (send) rate limits for OFT A only allows to send 2.5 tokens every 60 seconds.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 2.5 ether, window: 60 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        // The inbound (receive) rate limits for OFT B allows for 5 tokens to be received every 60 seconds..
        RateLimitConfig[] memory bNewInboundConfigs = new RateLimitConfig[](1);
        bNewInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 5 ether, window: 60 seconds});
        RateLimitConfig[] memory bEmptyOutboundConfigs = new RateLimitConfig[](0);
        bOFT.setRateLimits(bNewInboundConfigs, bEmptyOutboundConfigs);

        uint256 tokensToSend = 2.5 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory _sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(_sendParam, false);

        // User A calls send twice which loads two packets with a total of 5 tokens inside.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(_sendParam, fee, payable(address(this)));
        skip(60 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(_sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify and execute those packets all at once to test if the inbound rate limit applies.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend * 2);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend * 2);
    }

    function test_set_rates_only_apply_per_pathway() public {
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);

        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](2);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        aNewOutboundConfigs[1] = RateLimitConfig({eid: cEid, limit: 2 ether, window: 60 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        uint256 tokensToSend = 2 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParamToEndpointC = SendParam(
            cEid,
            addressToBytes32(userC),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory feeC = aOFT.quoteSend(sendParamToEndpointC, false);

        // User A call send within the allowed outbound window and limit.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: feeC.nativeFee }(sendParamToEndpointC, feeC, payable(address(this)));
        vm.stopPrank();

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);

        SendParam memory sendParamToEndpointB = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory feeB = aOFT.quoteSend(sendParamToEndpointB, false);

        // User A call send within the allowed outbound window and limit.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: feeB.nativeFee }(sendParamToEndpointB, feeB, payable(address(this)));
        vm.stopPrank();
    }

    function test_only_owner_can_set_rates() public {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);

        vm.prank(userB);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB)
        );
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);
    }

    function test_send_oft() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_fails_outside_outbound_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
    }

    function test_send_oft_succeeds_after_waiting_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send first time
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);

        uint256 tokensToSendAfter = 1 ether;
        SendParam memory nextSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfter,
            tokensToSendAfter,
            options,
            "",
            ""
        );
        MessagingFee memory nextFee = aOFT.quoteSend(nextSendParam, false);

        // User A waits 61 seconds and calls send a second time
        skip(61 seconds);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSendAfter);
        aOFT.send{ value: nextFee.nativeFee }(nextSendParam, nextFee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfter);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend + tokensToSendAfter);
    }

    function test_receive_oft_fails_outside_inbound_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send two times within the allowed outbound window.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 fails and must wait at least 60 seconds.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");
    }

    function test_send_oft_fails_global_outbound_cap_aggregate() public {
        // Precondition: aOFT's per-eid outbound to bEid is the looser cap, so the sentinel binds first.
        assertEq(aOFT.outboundRateLimits(bEid).limit, 10 ether);

        // Tighten aOFT's global outbound cap below the per-eid cap so the global one binds first.
        // Inbound sentinel stays effectively unbounded — required so Net-mode offset on `_debit`
        // doesn't revert touching the global inbound bucket.
        RateLimitConfig[] memory sIn = new RateLimitConfig[](1);
        sIn[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        RateLimitConfig[] memory sOut = new RateLimitConfig[](1);
        sOut[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: 4 ether, window: 60 seconds});
        aOFT.setRateLimits(sIn, sOut);

        uint256 tokensToSend = 3 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        vm.startPrank(userA);
        // Send 1: 3 ether, within per-eid (10) and global (4). Succeeds.
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(userA));

        // Send 2: aggregate 6 > global 4. Per-eid still has headroom — the global cap binds.
        aToken.approve(address(aOFT), tokensToSend);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(userA));
        vm.stopPrank();
    }

    function test_gross_mode_receive_does_not_offset_sentinel_outbound() public {
        // In Gross mode, an inbound receive must NOT decrement the sentinel outbound bucket
        // (the way it would under Net). This test distinguishes Gross's no-offset semantics
        // from Net's mutual-offset semantics, specifically for the sentinel.
        aOFT.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        // Tighten aOFT's sentinel outbound to 4 ether (inbound sentinel stays unbounded).
        RateLimitConfig[] memory sIn = new RateLimitConfig[](1);
        sIn[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        RateLimitConfig[] memory sOut = new RateLimitConfig[](1);
        sOut[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: 4 ether, window: 60 seconds});
        aOFT.setRateLimits(sIn, sOut);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Send 3 ether a→b. Sentinel outbound in-flight = 3.
        SendParam memory aToB = SendParam(bEid, addressToBytes32(userB), 3 ether, 3 ether, options, "", "");
        MessagingFee memory aFee = aOFT.quoteSend(aToB, false);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), 3 ether);
        aOFT.send{ value: aFee.nativeFee }(aToB, aFee, payable(userA));
        vm.stopPrank();
        assertEq(aOFT.outboundRateLimits(aOFT.SENTINEL_EID()).amountInFlight, 3 ether);

        // Deliver to b, then have b send 3 ether back to a. This triggers aOFT._credit, which
        // would decrement sentinel outbound under Net but must leave it untouched under Gross.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        SendParam memory bToA = SendParam(aEid, addressToBytes32(userA), 3 ether, 3 ether, options, "", "");
        MessagingFee memory bFee = bOFT.quoteSend(bToA, false);
        vm.startPrank(userB);
        bToken.approve(address(bOFT), 3 ether);
        bOFT.send{ value: bFee.nativeFee }(bToA, bFee, payable(userB));
        vm.stopPrank();
        verifyAndExecutePackets(aEid, addressToBytes32(address(aOFT)));

        // Under Gross, sentinel outbound in-flight is still 3 (unchanged by the receive).
        // (Under Net, this would be 0 after the offset.)
        assertEq(aOFT.outboundRateLimits(aOFT.SENTINEL_EID()).amountInFlight, 3 ether);

        // The sentinel outbound cap (4) still binds: a 2-ether send would push aggregate to 5 → revert.
        SendParam memory nextSend = SendParam(bEid, addressToBytes32(userB), 2 ether, 2 ether, options, "", "");
        MessagingFee memory nextFee = aOFT.quoteSend(nextSend, false);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), 2 ether);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: nextFee.nativeFee }(nextSend, nextFee, payable(userA));
        vm.stopPrank();
    }

    function test_receive_oft_fails_global_inbound_cap_aggregate() public {
        // Precondition: bOFT's per-eid inbound from aEid is the looser cap, so the sentinel binds first.
        assertEq(bOFT.inboundRateLimits(aEid).limit, 10 ether);

        // Tighten bOFT's global inbound cap below the per-chain limit so the global one binds first.
        // Outbound sentinel stays effectively unbounded — required so `_debit` (called when receiving
        // in Net mode) doesn't revert offsetting the global inbound bucket.
        RateLimitConfig[] memory sIn = new RateLimitConfig[](1);
        sIn[0] = RateLimitConfig({eid: bOFT.SENTINEL_EID(), limit: 4 ether, window: 60 seconds});
        RateLimitConfig[] memory sOut = new RateLimitConfig[](1);
        sOut[0] = RateLimitConfig({eid: bOFT.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        bOFT.setRateLimits(sIn, sOut);

        uint256 tokensToSend = 3 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        // Two consecutive sends from A → B; aggregate (6) exceeds bOFT's global inbound cap (4).
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(userA));
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(userA));
        vm.stopPrank();

        // Packet 1: 3 ether, within per-chain (10) and global (4). Succeeds.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2: aggregate 6 > global 4. Per-chain still has headroom — the global cap binds.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");
    }

    function test_outbound_views_reflect_global_cap() public {
        // Precondition: aOFT's per-eid outbound to bEid is the looser cap, so the sentinel binds.
        assertEq(aOFT.outboundRateLimits(bEid).limit, 10 ether);

        // Tighten aOFT's global outbound cap below the per-eid cap so the global binds.
        RateLimitConfig[] memory sIn = new RateLimitConfig[](1);
        sIn[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        RateLimitConfig[] memory sOut = new RateLimitConfig[](1);
        sOut[0] = RateLimitConfig({eid: aOFT.SENTINEL_EID(), limit: 3 ether, window: 60 seconds});
        aOFT.setRateLimits(sIn, sOut);

        // Cold state: per-eid (10) > sentinel (3), sentinel binds at 3.
        (uint256 currentAmountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentAmountInFlight, 0);
        assertEq(amountCanBeSent, 3 ether);

        // Send 1 ether — bumps both per-eid and sentinel outbound buckets by 1.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(userB), 1 ether, 1 ether, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), 1 ether);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
        vm.stopPrank();

        // After send: currentAmountInFlight reflects per-eid (1 ether), amountCanBeSent = min(10-1, 3-1) = 2.
        (currentAmountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentAmountInFlight, 1 ether);
        assertEq(amountCanBeSent, 2 ether);

        // quoteOFT.maxAmountLD reflects the same binding sentinel cap.
        (OFTLimit memory oftLimit,,) = aOFT.quoteOFT(sendParam);
        assertEq(oftLimit.maxAmountLD, 2 ether);
    }

    function test_inbound_views_reflect_global_cap() public {
        // Tighten bOFT's global inbound cap below per-eid; outbound stays unbounded.
        RateLimitConfig[] memory sIn = new RateLimitConfig[](1);
        sIn[0] = RateLimitConfig({eid: bOFT.SENTINEL_EID(), limit: 2 ether, window: 60 seconds});
        RateLimitConfig[] memory sOut = new RateLimitConfig[](1);
        sOut[0] = RateLimitConfig({eid: bOFT.SENTINEL_EID(), limit: type(uint128).max, window: 1});
        bOFT.setRateLimits(sIn, sOut);

        // Cold state: per-eid (10) > sentinel (2), sentinel binds at 2.
        (uint256 currentAmountInFlight, uint256 amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentAmountInFlight, 0);
        assertEq(amountCanBeReceived, 2 ether);

        // Send 1 ether a→b and deliver — bumps bOFT's inbound aEid bucket and its sentinel by 1.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(userB), 1 ether, 1 ether, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), 1 ether);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
        vm.stopPrank();
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        // After delivery: currentAmountInFlight reflects per-eid (1 ether), amountCanBeReceived = min(10-1, 2-1) = 1.
        (currentAmountInFlight, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentAmountInFlight, 1 ether);
        assertEq(amountCanBeReceived, 1 ether);
    }

    function test_views_use_per_eid_when_sentinel_unbounded() public view {
        // Precondition: setUp left both sentinel buckets effectively unbounded.
        assertEq(aOFT.outboundRateLimits(aOFT.SENTINEL_EID()).limit, type(uint128).max);
        assertEq(aOFT.inboundRateLimits(aOFT.SENTINEL_EID()).limit, type(uint128).max);

        // With the sentinel unbounded, the per-eid limit binds.
        (, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 10 ether);
        (, uint256 amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);
    }


    function test_receive_oft_succeeds_after_waiting_limit() public {

        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 waits at least 60 seconds and is executed.
        skip(61 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend * 2);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend * 2);
    }

    function test_receive_oft_succeeds_with_amount_allowed_after_decay() public {
        uint256 tokensToSend = 10 ether;
        uint256 tokensToSendAfterDecay = 5 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        SendParam memory sendParamAfterDecay = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfterDecay,
            tokensToSendAfterDecay,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        MessagingFee memory feeAfterDecay = aOFT.quoteSend(sendParamAfterDecay, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSendAfterDecay);
        aOFT.send{ value: fee.nativeFee }(sendParamAfterDecay, feeAfterDecay, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 waits at least 30 seconds.
        // Because the decay is 60 seconds, with a limit of 10 tokens, 5 tokens should be free to send after 30 seconds of decay.
        skip(30 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfterDecay);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend + tokensToSendAfterDecay);
    }

    function test_receive_oft_fails_with_amount_greater_than_decay() public {
        uint256 tokensToSend = 10 ether;
        uint256 tokensToSendAfterDecay = 5.1 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        SendParam memory sendParamAfterDecay = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfterDecay,
            tokensToSendAfterDecay,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        MessagingFee memory feeAfterDecay = aOFT.quoteSend(sendParamAfterDecay, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));
        aToken.approve(address(aOFT), tokensToSendAfterDecay);
        aOFT.send{ value: fee.nativeFee }(sendParamAfterDecay, feeAfterDecay, payable(address(this)));
        vm.stopPrank();
        // Packet 2 waits at least 30 seconds.
        // Because the decay is 60 seconds, with a limit of 10 tokens, only 5 tokens should be free to send after 30 seconds of decay.
        skip(30 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfterDecay);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_compose_msg() public {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(220000, 0)
            .addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(composer)),
            tokensToSend,
            tokensToSend,
            options,
            composeMsg,
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(composer)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = aOFT.send{ value: fee.nativeFee }(
            sendParam,
            fee,
            payable(address(this))
        );
        vm.stopPrank();

        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            aEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    function _createSendParam(uint256 _tokensToSend, uint32 _dstEid, address _to) internal pure returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        return SendParam(
            _dstEid,
            addressToBytes32(_to),
            _tokensToSend,
            _tokensToSend * 9_000 / 10_000,
            options,
            "",
            ""
        );
    }

    function test_net_rate_limiting() public {
        // 1. Set the ORL on aEid to bEid to 20 eth/min.  The inbound rate limit on bEid from
        // aEid remains the same (10 eth/min).
        RateLimitConfig[] memory aOutboundConfigs = new RateLimitConfig[](1);
        aOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 20 ether, window: 60 seconds});
        RateLimitConfig[] memory aInboundConfigs = new RateLimitConfig[](1);
        aInboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 20 ether, window: 60 seconds});
        aOFT.setRateLimits(aInboundConfigs, aOutboundConfigs);
        
        uint256 amountCanBeSent;
        uint256 amountCanBeReceived;

        // 2. tokensToSend is meant to exhaust bEid's IRL from aEid.
        uint256 tokensToSend = 10 ether;
        SendParam memory aToBSendParam = _createSendParam(tokensToSend, bEid, userB);
        MessagingFee memory fee = aOFT.quoteSend(aToBSendParam, false);

        // 3. userA exhausts the IRL of bEid from aEid.
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(aToBSendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 10 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0);

        // 4. Assert bEid IRL from aEID is exhausted.
        RateLimit memory rl = bOFT.inboundRateLimits(aEid);

        assertEq(rl.amountInFlight, tokensToSend);
        assertEq(rl.lastUpdated, block.timestamp);
        assertEq(rl.limit, 10 ether);
        assertEq(rl.window, 60 seconds);

        // 5. Send 10 ether from aEid to bEid again.  This should not fail because ORL of aEID to bEid is 20 ether.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(aToBSendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0); // should not have changed

        // 6. Expect the packet delivery to revert, as the IRL is exhausted.  This packet is now in flight until the IRL
        // allows another 10 ether to be received.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");

        // 7. userB sends back the 10 ether to userA on aEid, resetting the amountCanBeReceived on bEid from aEID to 10
        // ether.  The packet from #6 can now be delivered without violating the IRL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);
        SendParam memory bToASendParam = _createSendParam(tokensToSend, aEid, userA);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 20 ether);
        verifyAndExecutePackets(aEid, addressToBytes32(address(aOFT)), 1, address(0));
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);
        rl = bOFT.inboundRateLimits(aEid);
        assertEq(rl.amountInFlight, 0);
        assertEq(rl.lastUpdated, block.timestamp);
        assertEq(rl.limit, 10 ether);
        assertEq(rl.window, 60 seconds);

        // 8. try to send 10 ether from bEid to aEid again, violating the ORL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        // 9. The packet from #6 can be delivered through a permission-less retry without violating the IRL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 10 ether);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0);

        // 10. Similar to #8, send 10 ether from bEid to aEid again, but this time successfully as the ORL has reset.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
    }

    function test_reset_rate_limits_and_apply_new_limits() public {
        // Initial setup - send tokens to hit the rate limit
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        // Send tokens to hit the rate limit
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify we've hit the rate limit
        (uint256 amountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, tokensToSend);
        assertEq(amountCanBeSent, 0);

        // Reset the rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = bEid;
        aOFT.resetRateLimits(new uint32[](0), eids);

        (amountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, 0 ether);
        assertEq(amountCanBeSent, 10 ether);

        // Verify the rate limits are reset
        RateLimitConfig[] memory newOutboundConfigs = new RateLimitConfig[](1);
        newOutboundConfigs[0] = RateLimitConfig({
            eid: bEid,
            limit: 20 ether,  // Double the previous limit
            window: 30 seconds // Half the previous window
        });
        aOFT.setRateLimits(new RateLimitConfig[](0), newOutboundConfigs);

        // Verify the new limits are in effect
        (amountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, 0 ether);
        assertEq(amountCanBeSent, 20 ether);

        // Test we can send with the new higher limit
        uint256 newTokensToSend = 15 ether;
        SendParam memory newSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            newTokensToSend,
            newTokensToSend,
            options,
            "",
            ""
        );
        fee = aOFT.quoteSend(newSendParam, false);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), newTokensToSend);
        aOFT.send{ value: fee.nativeFee }(newSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify the new amount that can be sent
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // 20 ether limit - 15 ether sent = 5 ether remaining

        // Test the shorter window
        skip(31 seconds); // Just over the new 30 second window
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether); // Should be fully reset after the window
    }

    function test_reset_rate_limits_and_change_to_gross_accounting() public {
        // override B rate limits
        RateLimitConfig[] memory newBOutboundConfigs = new RateLimitConfig[](1);
        newBOutboundConfigs[0] = RateLimitConfig({
            eid: aEid,
            limit: 30 ether,
            window: 60 seconds
        });
        RateLimitConfig[] memory newBInboundConfigs = new RateLimitConfig[](1);
        newBInboundConfigs[0] = RateLimitConfig({
            eid: aEid,
            limit: 60 ether,
            window: 60 seconds
        });
        bOFT.setRateLimits(newBInboundConfigs, newBOutboundConfigs);

        // Initial setup - send tokens to hit the rate limit
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        // Send tokens to hit the rate limit
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify we've hit the rate limit
        (uint256 amountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, tokensToSend);
        assertEq(amountCanBeSent, 0);

        // Change accounting type
        aOFT.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        // Reset the rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = bEid;
        aOFT.resetRateLimits(new uint32[](0), eids);

        // Set new rate limits with Gross accounting
        RateLimitConfig[] memory newOutboundConfigs = new RateLimitConfig[](1);
        newOutboundConfigs[0] = RateLimitConfig({
            eid: bEid,
            limit: 20 ether,  // Double the previous limit
            window: 30 seconds // Half the previous window
        });
        aOFT.setRateLimits(new RateLimitConfig[](0), newOutboundConfigs);

        // Send tokens in one direction
        uint256 firstSend = 15 ether;
        SendParam memory firstSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            firstSend,
            firstSend,
            options,
            "",
            ""
        );
        fee = aOFT.quoteSend(firstSendParam, false);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), firstSend);
        aOFT.send{ value: fee.nativeFee }(firstSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify first send amount
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // 20 ether limit - 15 ether sent = 5 ether remaining

        // Execute the packet
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        // Get amount can be received from bEid to aEid
        (, uint256 amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);

        // Now send tokens back from B to A - with Gross accounting, this should not affect the rate limit
        vm.startPrank(userB);
        bToken.approve(address(bOFT), firstSend);
        SendParam memory returnSendParam = SendParam(
            aEid,
            addressToBytes32(userA),
            5 ether,
            5 ether,
            options,
            "",
            ""
        );
        fee = bOFT.quoteSend(returnSendParam, false);
        bOFT.send{ value: fee.nativeFee }(returnSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Execute the return packet
        verifyAndExecutePackets(aEid, addressToBytes32(address(aOFT)));

        // Verify that sending tokens back did not affect the outbound rate limit
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // Should still be 5 ether, unchanged by the return transfer

        // Wait for window to expire and verify reset
        skip(31 seconds);
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether); // Should be fully reset after the window
    }

    function test_send_with_fee() public {
        uint16 feeBps = 100;
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 tokenFee = tokensToSend * feeBps / 10000;
        uint256 minAmountToCreditLD = tokensToSend - tokenFee;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            minAmountToCreditLD,
            options,
            "",
            ""
        );
        MessagingFee memory protocolFee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(address(aOFT)), 0);
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: protocolFee.nativeFee }(sendParam, protocolFee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(aToken.balanceOf(address(aOFT)), tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + minAmountToCreditLD);
        assertEq(bToken.balanceOf(address(bOFT)), initialBalance - minAmountToCreditLD);
        assertEq(aOFT.feeBalance(), tokenFee);
        assertEq(bOFT.feeBalance(), 0);
    }

    function test_migrate_locked_tokens() public {
        vm.prank(userA);
        aToken.transfer(address(aOFT), initialBalance);

        assertEq(aToken.balanceOf(address(this)), 0);
        assertEq(aToken.balanceOf(address(aOFT)), initialBalance);

        // not owner
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.migrateLockedTokens(address(this));

        // migrate locked tokens
        aOFT.migrateLockedTokens(address(this));

        assertEq(aToken.balanceOf(address(this)), initialBalance);
        assertEq(aToken.balanceOf(address(aOFT)), 0);
    }

    function test_setPauser() public {
        assertFalse(aOFT.pausers(userA));
        
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.setPauser(userA, true);
        
        aOFT.setPauser(userA, true);
        assertTrue(aOFT.pausers(userA));
        
        aOFT.setPauser(userA, false);
        assertFalse(aOFT.pausers(userA));
        
        vm.expectEmit(true, true, true, true);
        emit ISkyOFT.PauserSet(userA, true);
        aOFT.setPauser(userA, true);
    }

    function test_pause() public {
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(ISkyOFT.OnlyPauser.selector, userB));
        aOFT.pause();
        
        aOFT.setPauser(userA, true);
        
        vm.prank(userA);
        aOFT.pause();
        
        // Verify contract is paused by attempting a transfer
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        uint256 dummyNativeFee = 1 ether;
        MessagingFee memory fee = MessagingFee({
            nativeFee: dummyNativeFee,
            lzTokenFee: 0
        });
        
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        aOFT.send{ value: dummyNativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
    }

    function test_unpause() public {
        aOFT.setPauser(userA, true);
        vm.prank(userA);
        aOFT.pause();
        
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.unpause();
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        aOFT.unpause();
        
        // Owner can unpause
        aOFT.unpause();
        
        // Verify contract is unpaused by performing a transfer
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
        
        // Verify the transfer was successful
        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
    }

    function test_multiple_pausers() public {
        aOFT.setPauser(userA, true);
        aOFT.setPauser(userB, true);
        
        assertTrue(aOFT.pausers(userA));
        assertTrue(aOFT.pausers(userB));
        
        vm.prank(userB);
        aOFT.pause();
        
        aOFT.unpause();
        
        vm.prank(userA);
        aOFT.pause();
        
        aOFT.setPauser(userA, false);
        aOFT.setPauser(userB, false);
        
        assertFalse(aOFT.pausers(userA));
        assertFalse(aOFT.pausers(userB));
    }

    function test_send_oft_to_null_address() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(0)),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(0xdead)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(0xdead)), tokensToSend);
    }

    function test_send_oft_to_inner_token_address() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(bToken)),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(0xdead)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(0xdead)), tokensToSend);
    }

    function test_rate_limit_send_with_fee() public {
        uint16 feeBps = 100;
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 tokenFee = tokensToSend * feeBps / 10000;
        uint256 minAmountToCreditLD = tokensToSend - tokenFee;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            minAmountToCreditLD,
            options,
            "",
            ""
        );
        MessagingFee memory protocolFee = aOFT.quoteSend(sendParam, false);

        (uint256 currentSendAmountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (uint256 currentReceiveAmountInFlight, uint256 amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        (currentSendAmountInFlight, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (currentReceiveAmountInFlight, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userA);

        aToken.approve(address(aOFT), tokensToSend);

        aOFT.send{ value: protocolFee.nativeFee }(sendParam, protocolFee, payable(address(this)));

        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        (currentSendAmountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentSendAmountInFlight, minAmountToCreditLD);
        assertEq(amountCanBeSent, 10 ether - minAmountToCreditLD);

        (currentReceiveAmountInFlight, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        (currentSendAmountInFlight, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (currentReceiveAmountInFlight, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentReceiveAmountInFlight, minAmountToCreditLD);
        assertEq(amountCanBeReceived, 10 ether - minAmountToCreditLD);
    }

    function test_quoteOFT_no_fee_returns_empty_array() public view {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        // Test with no fee set (default is 0)
        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return empty fee details array when no fee is charged
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no fee is charged");
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, tokensToSend, "Amount received should equal tokens to send when no fee");
    }

    function test_quoteOFT_with_fee_returns_populated_array() public {
        // Set a fee
        uint16 feeBps = 100; // 1%
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 expectedFee = tokensToSend * feeBps / 10000;
        uint256 expectedAmountReceived = tokensToSend - expectedFee;
        
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            expectedAmountReceived, // min amount after fee
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return populated fee details array when fee is charged
        assertEq(oftFeeDetails.length, 1, "Fee details array should have 1 element when fee is charged");
        assertEq(oftFeeDetails[0].feeAmountLD, int256(expectedFee), "Fee amount should match expected fee");
        assertEq(oftFeeDetails[0].description, "SkyOFT: cross-chain transfer fee", "Fee description should match");
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, expectedAmountReceived, "Amount received should be after fee deduction");
    }

    function test_quoteOFT_with_dust_removal_and_fee() public {
        // Set a fee
        uint16 feeBps = 50; // 0.5%
        aOFT.setDefaultFeeBps(feeBps);

        // Use an amount that will result in dust after fee calculation
        uint256 tokensToSend = 1000001; // This should create some dust after fee and dust removal
        
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            0, // min amount (we'll accept any amount for this test)
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // The dust removal happens in _removeDust, which should remove any remainder
        // If there's a difference between sent and received, should have fee details
        if (oftReceipt.amountSentLD != oftReceipt.amountReceivedLD) {
            assertEq(oftFeeDetails.length, 1, "Fee details array should have 1 element when fee is charged");
            assertEq(oftFeeDetails[0].feeAmountLD, int256(oftReceipt.amountSentLD) - int256(oftReceipt.amountReceivedLD), "Fee amount should match difference");
            assertEq(oftFeeDetails[0].description, "SkyOFT: cross-chain transfer fee", "Fee description should match");
        } else {
            assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no effective fee");
        }
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
    }

    function test_quoteOFT_zero_fee_edge_case() public {
        // Explicitly set fee to 0
        aOFT.setDefaultFeeBps(0);

        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        (, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return empty fee details array when fee is explicitly 0
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when fee is 0");
        
        // Verify amounts are equal
        assertEq(oftReceipt.amountSentLD, oftReceipt.amountReceivedLD, "Sent and received amounts should be equal with 0 fee");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
    }

    function test_quoteOFT_rate_limit_integration() public view {
        uint256 tokensToSend = 5 ether; // Within rate limit
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Verify rate limit is properly reflected
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertGt(oftLimit.maxAmountLD, tokensToSend, "Max amount should be greater than tokens to send");
        
        // Should work without fee
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no fee is charged");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, tokensToSend, "Amount received should equal tokens to send");
    }

    // @dev Each test below verifies that the ERC-7201 storage-slot constant in the contract matches the
    //      formula documented in its preceding comment. The strategy: compute the slot from the documented
    //      formula, write a sentinel value to that slot via `vm.store`, and assert the contract's read path
    //      sees the written value. If the constant in the file drifted from the formula, the contract would
    //      read a different slot and the assertion would fail.

    function test_SkyRateLimiter_storage_slot_matches_derivation() public {
        bytes32 expectedSlot = keccak256(abi.encode(uint256(keccak256("sky.storage.SkyRateLimiter")) - 1)) & ~bytes32(uint256(0xff));
        // Direct check against the hardcoded constant in SkyRateLimiter.sol.
        assertEq(expectedSlot, bytes32(uint256(0x868cf2e95349a11bfef6fbb57b8a2d9f17221bd478f74444896b781776317b00)));
        // Behavioral check: rateLimitAccountingType is at offset 0 of the namespaced struct.
        vm.store(address(aOFT), expectedSlot, bytes32(uint256(uint8(RateLimitAccountingType.Gross))));
        assertEq(uint256(aOFT.rateLimitAccountingType()), uint256(RateLimitAccountingType.Gross));
    }

    function test_SkyOFTCore_storage_slot_matches_derivation() public {
        bytes32 expectedBase = keccak256(abi.encode(uint256(keccak256("sky.storage.SkyOFTCore")) - 1)) & ~bytes32(uint256(0xff));
        // Direct check against the hardcoded constant in SkyOFTCore.sol.
        assertEq(expectedBase, bytes32(uint256(0xf9dea648e4f31f4a8d1fbdc7eeca2b36f48d9310e4a268bd28dd82005c1b7900)));
        // Behavioral check: pausers is a mapping at offset 0 of the namespaced struct.
        // Mapping value slot for key `k` at base slot `b`: keccak256(abi.encode(k, b)).
        address probe = address(0xBEEF);
        bytes32 valueSlot = keccak256(abi.encode(probe, expectedBase));
        vm.store(address(aOFT), valueSlot, bytes32(uint256(1)));
        assertTrue(aOFT.pausers(probe));
    }

    function test_SkyOFTAdapter_storage_slot_matches_derivation() public {
        bytes32 expectedSlot = keccak256(abi.encode(uint256(keccak256("sky.storage.SkyOFTAdapter")) - 1)) & ~bytes32(uint256(0xff));
        // Direct check against the hardcoded constant in SkyOFTAdapter.sol.
        assertEq(expectedSlot, bytes32(uint256(0xa212a9105d34110ec7b56ba95a22a00c83c40de826beea9f21530155344fbd00)));
        // Behavioral check: feeBalance (uint256) is at offset 0 of the namespaced struct.
        uint256 sentinel = 123456 ether;
        vm.store(address(aOFT), expectedSlot, bytes32(sentinel));
        assertEq(aOFT.feeBalance(), sentinel);
    }
}