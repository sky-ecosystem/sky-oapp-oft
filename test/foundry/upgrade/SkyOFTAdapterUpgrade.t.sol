// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Mocks
import { MintBurnERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/MintBurnERC20Mock.sol";

// Sky contracts under test
import { SkyOFTAdapter } from "../../../contracts/SkyOFTAdapter.sol";
import { RateLimitConfig, RateLimit } from "../../../contracts/interfaces/ISkyRateLimiter.sol";

// OZ
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// LZ test harness — only used to spin up a single EndpointV2 mock that `OFTCoreUpgradeable`
// needs at construction time. The upgrade tests themselves don't exercise messaging.
import { TestHelperOz5WithRevertAssertions } from "../helpers/TestHelperOz5WithRevertAssertions.sol";

/**
 * @notice V2 implementation used to verify the UUPS upgrade path swaps logic correctly.
 * @dev Same constructor + storage as v1; adds a `version()` marker and a `reinitialize`
 *      step that exercises the upgrade-with-calldata path.
 */
contract SkyOFTAdapterV2Mock is SkyOFTAdapter {
    event Reinitialized(uint256 v);

    constructor(address _token, address _lzEndpoint) SkyOFTAdapter(_token, _lzEndpoint) {}

    function version() external pure returns (uint256) {
        return 2;
    }

    // @dev Marked `reinitializer(2)` so it can only run once during the v1→v2 upgrade.
    function reinitialize() external reinitializer(2) {
        emit Reinitialized(2);
    }
}

/**
 * @notice A contract that does NOT inherit UUPSUpgradeable — used to verify the
 *         ERC-1822 `proxiableUUID` check rejects non-UUPS implementations.
 */
contract NonUUPSContract {
    function notUUPS() external pure returns (bool) {
        return true;
    }
}

/**
 * @notice A contract that inherits UUPSUpgradeable but returns the WRONG proxiable slot.
 *         Verifies `UUPSUpgradeable._upgradeToAndCallUUPS` rejects impls whose
 *         proxiableUUID() doesn't match the canonical ERC-1967 implementation slot.
 */
contract WrongUUIDContract is UUPSUpgradeable {
    bytes32 public constant BAD_SLOT = bytes32(uint256(0xDEAD));

    function proxiableUUID() external pure override returns (bytes32) {
        return BAD_SLOT;
    }

    function _authorizeUpgrade(address) internal override {}
}

/**
 * @notice Tests focused exclusively on the UUPS upgrade path: who can upgrade,
 *         what state survives, and the proxy/impl init invariants.
 */
contract SkyOFTAdapterUpgradeTest is TestHelperOz5WithRevertAssertions {
    uint32 internal constant aEid = 1;
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal owner = address(this);
    address internal attacker = address(0xBAD);

    MintBurnERC20Mock internal aToken;
    SkyOFTAdapter internal aOFTImpl;
    SkyOFTAdapter internal aOFT; // proxy

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        aToken = new MintBurnERC20Mock("aToken", "aToken");
        aOFTImpl = new SkyOFTAdapter(address(aToken), address(endpoints[aEid]));
        aOFT = SkyOFTAdapter(
            address(
                new ERC1967Proxy(
                    address(aOFTImpl),
                    abi.encodeCall(SkyOFTAdapter.initialize, (owner))
                )
            )
        );
    }

    // --- access control on the upgrade entrypoint --------------------------

    function test_upgrade_by_owner_succeeds() public {
        SkyOFTAdapterV2Mock newImpl = new SkyOFTAdapterV2Mock(address(aToken), address(endpoints[aEid]));

        // Exercise the realistic upgrade-with-calldata path: swap impl AND run the v2 reinitializer atomically.
        vm.expectEmit(true, true, true, true);
        emit SkyOFTAdapterV2Mock.Reinitialized(2);
        aOFT.upgradeToAndCall(address(newImpl), abi.encodeCall(SkyOFTAdapterV2Mock.reinitialize, ()));

        assertEq(aOFT.getImplementation(), address(newImpl));
        assertEq(SkyOFTAdapterV2Mock(address(aOFT)).version(), 2);
    }

    function test_upgrade_by_non_owner_reverts() public {
        SkyOFTAdapterV2Mock newImpl = new SkyOFTAdapterV2Mock(address(aToken), address(endpoints[aEid]));

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        aOFT.upgradeToAndCall(address(newImpl), "");
    }

    // --- state preservation across upgrade ---------------------------------

    function test_state_persists_across_upgrade() public {
        // Snapshot some state on v1
        RateLimitConfig[] memory outbound = new RateLimitConfig[](1);
        outbound[0] = RateLimitConfig({eid: 99, limit: 1 ether, window: 60 seconds});
        RateLimitConfig[] memory empty = new RateLimitConfig[](0);
        aOFT.setRateLimits(empty, outbound);
        aOFT.setPauser(attacker, true);

        RateLimit memory rlBefore = aOFT.outboundRateLimits(99);
        bool pauserBefore = aOFT.pausers(attacker);
        address ownerBefore = aOFT.owner();

        // Upgrade
        SkyOFTAdapterV2Mock newImpl = new SkyOFTAdapterV2Mock(address(aToken), address(endpoints[aEid]));
        aOFT.upgradeToAndCall(address(newImpl), "");

        // Verify state preserved through the proxy
        RateLimit memory rlAfter = aOFT.outboundRateLimits(99);
        assertEq(rlAfter.lastUpdated, rlBefore.lastUpdated);
        assertEq(rlAfter.window, rlBefore.window);
        assertEq(rlAfter.amountInFlight, rlBefore.amountInFlight);
        assertEq(rlAfter.limit, rlBefore.limit);
        assertEq(aOFT.pausers(attacker), pauserBefore);
        assertEq(aOFT.owner(), ownerBefore);

        // ...and v2 logic is live
        assertEq(SkyOFTAdapterV2Mock(address(aOFT)).version(), 2);
    }

    // --- initializer invariants --------------------------------------------

    function test_implementation_cannot_be_initialized_directly() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        aOFTImpl.initialize(owner);
    }

    function test_proxy_cannot_be_reinitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        aOFT.initialize(owner);
    }

    // --- implementation slot exposure --------------------------------------

    function test_getImplementation_matches_eip1967_slot() public view {
        assertEq(aOFT.getImplementation(), address(aOFTImpl));

        bytes32 raw = vm.load(address(aOFT), IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(raw))), address(aOFTImpl));
    }

    // --- proxiableUUID guard rejects non-UUPS impls ------------------------

    function test_upgrade_to_non_uups_reverts() public {
        NonUUPSContract bad = new NonUUPSContract();
        // UUPSUpgradeable._upgradeToAndCallUUPS catches a failing proxiableUUID() call and reverts with ERC1967InvalidImplementation(newImplementation).
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(bad)));
        aOFT.upgradeToAndCall(address(bad), "");
    }

    function test_upgrade_to_impl_with_wrong_proxiable_uuid_reverts() public {
        // The impl is UUPS but reports a non-canonical proxiable slot. UUPSUpgradeable
        // must reject it with `UUPSUnsupportedProxiableUUID(slot)` directly (not via the catch).
        WrongUUIDContract bad = new WrongUUIDContract();
        vm.expectRevert(abi.encodeWithSelector(UUPSUpgradeable.UUPSUnsupportedProxiableUUID.selector, bad.BAD_SLOT()));
        aOFT.upgradeToAndCall(address(bad), "");
    }

    // --- onlyProxy guard on the implementation -----------------------------

    function test_upgrade_called_on_implementation_reverts() public {
        // `upgradeToAndCall` has the `onlyProxy` modifier, which reverts when invoked
        // directly on the implementation (i.e. not through a proxy delegatecall).
        SkyOFTAdapterV2Mock newImpl = new SkyOFTAdapterV2Mock(address(aToken), address(endpoints[aEid]));
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        aOFTImpl.upgradeToAndCall(address(newImpl), "");
    }
}
