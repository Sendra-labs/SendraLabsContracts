// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Roles } from "../src/security/Roles.sol";
import { SendraStorage } from "../src/core/SendraStorage.sol";
import { SendraLib } from "../src/lib/Sendra.lib.sol";

contract SigningWallet is IERC1271 {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (ECDSA.recover(hash, signature) == owner) return IERC1271.isValidSignature.selector;
        return bytes4(0);
    }
}

contract MultichainPulseTest is Test {
    Roles internal roles;
    SendraStorage internal arbitrum;
    SendraStorage internal base;

    address internal admin1 = address(0xA11);
    address internal admin2 = address(0xA12);
    address internal admin3 = address(0xA13);

    uint256 internal constant PK_A = 0xA11CE;
    uint256 internal constant PK_B = 0xB0B;
    uint256 internal constant PK_C = 0xC0C;

    function setUp() public {
        roles = new Roles(admin1, admin2, admin3);
        vm.prank(admin1);
        roles.allowContract(address(this), "MultichainTest");
        arbitrum = new SendraStorage(address(roles));
        base = new SendraStorage(address(roles));
        vm.startPrank(admin1);
        arbitrum.setPulseSyncer(address(this));
        base.setPulseSyncer(address(this));
        vm.stopPrank();
    }

    function testTemporalIsPendingUntilCommit() public {
        address user = address(0xBEEF);
        _apply(arbitrum, user, 0, 100);
        _apply(arbitrum, user, 3, 25);
        _apply(arbitrum, user, 2, 400);

        SendraLib.PulseSnapshot memory snap = arbitrum.getPulseSnapshot(user);
        assertEq(snap.syncVersion, 0);
        assertEq(snap.globalPulse.totalCapitalIn, 0);
        assertEq(snap.temporalPulse.totalCapitalIn, 100);
        assertEq(snap.temporalPulse.currentExposure, 25);
        assertEq(snap.globalPulse.peakSimultaneousExposure, 400);
        assertEq(arbitrum.getUniqueGlobalAccumulator(0, user), 100);
        assertEq(arbitrum.getUniqueGlobalAccumulator(3, user), 25);
        assertEq(arbitrum.getUniqueGlobalAccumulator(2, user), 400);
        assertGt(snap.globalPulse.firstActivityTimestamp, 0);

        arbitrum.sealTemporalPulse(user);
        snap = arbitrum.getPulseSnapshot(user);
        assertTrue(snap.hasSeal);
        assertEq(snap.sealedPulse.totalCapitalIn, 100);
        assertEq(snap.temporalPulse.totalCapitalIn, 0);
        assertEq(arbitrum.getUniqueGlobalAccumulator(0, user), 100);

        _apply(arbitrum, user, 0, 7);
        arbitrum.sealTemporalPulse(user);
        snap = arbitrum.getPulseSnapshot(user);
        assertEq(snap.sealedPulse.totalCapitalIn, 100, "open seal is not replaced");
        assertEq(snap.temporalPulse.totalCapitalIn, 7);

        SendraLib.GlobalAccumulators memory next;
        next.totalCapitalIn = 100;
        next.currentExposure = 25;
        _commit(arbitrum, user, 0, 1, true, snap.sealHash, 42161, next);

        snap = arbitrum.getPulseSnapshot(user);
        assertEq(snap.syncVersion, 1);
        assertFalse(snap.hasSeal);
        assertEq(snap.globalPulse.totalCapitalIn, 100);
        assertEq(snap.temporalPulse.totalCapitalIn, 7);
        assertEq(snap.globalPulse.peakSimultaneousExposure, 400);
        assertEq(arbitrum.getUniqueGlobalAccumulator(0, user), 107);
    }

    function testStaleCommitCannotOverwriteANewerGlobal() public {
        address user = address(0xBEEF);
        _apply(arbitrum, user, 0, 10);
        arbitrum.sealTemporalPulse(user);
        bytes32 sealHash = arbitrum.getPulseSnapshot(user).sealHash;

        SendraLib.GlobalAccumulators memory next;
        next.totalCapitalIn = 10;
        _commit(arbitrum, user, 0, 1, true, sealHash, 42161, next);

        next.totalCapitalIn = 1;
        vm.expectRevert(abi.encodeWithSelector(SendraStorage.StalePulseVersion.selector, uint64(1), uint64(0)));
        _commit(arbitrum, user, 0, 2, false, bytes32(0), 42161, next);

        _commit(arbitrum, user, 0, 1, true, sealHash, 42161, next);
        assertEq(arbitrum.getPulseSnapshot(user).syncVersion, 1);
        assertEq(arbitrum.getPulseSnapshot(user).globalPulse.totalCapitalIn, 10);
    }

    function testCatchUpUsesTheNewerGlobalAndKeepsUnsealedActivity() public {
        address user = address(0xBEEF);
        _apply(arbitrum, user, 0, 20);
        _apply(base, user, 0, 8);
        arbitrum.sealTemporalPulse(user);
        base.sealTemporalPulse(user);

        bytes32 baseSeal = base.getPulseSnapshot(user).sealHash;
        SendraLib.GlobalAccumulators memory next;
        next.totalCapitalIn = 28;
        _commit(arbitrum, user, 0, 1, true, arbitrum.getPulseSnapshot(user).sealHash, 42161, next);

        _apply(base, user, 0, 3);
        assertEq(base.getPulseSnapshot(user).syncVersion, 0);
        assertEq(base.getPulseSnapshot(user).globalPulse.totalCapitalIn, 0);
        assertEq(base.getPulseSnapshot(user).sealedPulse.totalCapitalIn, 8);
        assertEq(base.getPulseSnapshot(user).temporalPulse.totalCapitalIn, 3);

        uint64 canonicalVersion = arbitrum.getPulseSnapshot(user).syncVersion;
        assertEq(canonicalVersion, 1);
        next = arbitrum.getPulseSnapshot(user).globalPulse;
        _commit(base, user, 0, canonicalVersion, true, baseSeal, 8453, next);

        SendraLib.PulseSnapshot memory caughtUp = base.getPulseSnapshot(user);
        assertEq(caughtUp.syncVersion, 1);
        assertFalse(caughtUp.hasSeal);
        assertEq(caughtUp.globalPulse.totalCapitalIn, 28);
        assertEq(caughtUp.temporalPulse.totalCapitalIn, 3);
        assertEq(base.getUniqueGlobalAccumulator(0, user), 31);

        base.sealTemporalPulse(user);
        bytes32 freshSeal = base.getPulseSnapshot(user).sealHash;
        next.totalCapitalIn = 31;
        _commit(arbitrum, user, 1, 2, false, bytes32(0), 42161, next);
        _commit(base, user, 1, 2, true, freshSeal, 8453, next);
        assertEq(arbitrum.getPulseSnapshot(user).globalPulse.totalCapitalIn, 31);
        assertEq(base.getPulseSnapshot(user).globalPulse.totalCapitalIn, 31);
        assertEq(base.getPulseSnapshot(user).syncVersion, 2);
        assertEq(base.getUniqueGlobalAccumulator(0, user), 31);
    }

    function testTimestampsTakeMinAndMaxWithoutGoingBackwards() public {
        address user = address(0xBEEF);
        vm.warp(1_000);
        _apply(arbitrum, user, 0, 1);
        vm.warp(2_500);
        _apply(arbitrum, user, 15, 2_500);

        SendraLib.GlobalAccumulators memory next;
        next.totalCapitalIn = 1;
        next.firstActivityTimestamp = 4_000;
        next.lastActivityTimestamp = 1_000;
        arbitrum.sealTemporalPulse(user);
        _commit(arbitrum, user, 0, 1, true, arbitrum.getPulseSnapshot(user).sealHash, 42161, next);

        SendraLib.PulseSnapshot memory snap = arbitrum.getPulseSnapshot(user);
        assertEq(snap.globalPulse.firstActivityTimestamp, 1_000);
        assertEq(snap.globalPulse.lastActivityTimestamp, 2_500);

        next.firstActivityTimestamp = 100;
        next.lastActivityTimestamp = 9_000;
        _commit(arbitrum, user, 1, 2, false, bytes32(0), 42161, next);
        snap = arbitrum.getPulseSnapshot(user);
        assertEq(snap.globalPulse.firstActivityTimestamp, 100);
        assertEq(snap.globalPulse.lastActivityTimestamp, 9_000);
    }

    function testLinkRequiresBothSignaturesAndSharesAccounting() public {
        address a = vm.addr(PK_A);
        address b = vm.addr(PK_B);
        address c = vm.addr(PK_C);

        _apply(arbitrum, a, 0, 100);
        _apply(arbitrum, b, 0, 40);
        _apply(arbitrum, a, 2, 10);
        _apply(arbitrum, b, 2, 80);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(uint256(1));
        arbitrum.addPositionToUser(a, SendraLib.Position({ positionType: 1, id: 1, pnl: 0, isActive: true, positionData: data }));
        arbitrum.addPositionToUser(b, SendraLib.Position({ positionType: 2, id: 1, pnl: 5, isActive: true, positionData: data }));

        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = arbitrum.linkDigest(a, b, deadline);
        vm.expectRevert(SendraStorage.InvalidLinkSignature.selector);
        arbitrum.linkWallets(a, b, deadline, _sign(PK_A, digest), _sign(PK_C, digest));

        arbitrum.linkWallets(a, b, deadline, _sign(PK_A, digest), _sign(PK_B, digest));

        address root = arbitrum.accountingRootOf(a);
        assertEq(arbitrum.accountingRootOf(b), root);
        assertEq(arbitrum.getUserIdByAddress(a), arbitrum.getUserIdByAddress(b));
        assertEq(arbitrum.getUniqueGlobalAccumulator(0, b), 140);
        assertEq(arbitrum.getUniqueGlobalAccumulator(2, a), 80);
        assertEq(arbitrum.getAccountingPositionCount(b), 2);

        (address wallet0,, SendraLib.Position memory first) = arbitrum.getAccountingPosition(a, 0);
        (address wallet1,, SendraLib.Position memory second) = arbitrum.getAccountingPosition(b, 1);
        assertEq(wallet0, a);
        assertEq(first.positionType, 1);
        assertEq(wallet1, b);
        assertEq(second.pnl, 5);
        assertEq(arbitrum.getUserPositionById(b, 1).positionType, 2);

        SendraLib.AccountingOverview memory overview = arbitrum.getAccountingOverview(b);
        assertEq(overview.root, root);
        assertEq(overview.walletCount, 2);
        assertEq(overview.totalPositions, 2);
        assertEq(overview.activePositions, 2);

        vm.expectRevert(SendraStorage.InvalidLinkSignature.selector);
        arbitrum.linkWallets(a, b, deadline, _sign(PK_A, digest), _sign(PK_B, digest));

        _apply(arbitrum, c, 0, 10);
        arbitrum.addPositionToUser(c, SendraLib.Position({ positionType: 3, id: 1, pnl: 0, isActive: true, positionData: data }));
        uint256 deadlineC = block.timestamp + 1 days;
        bytes32 digestC = arbitrum.linkDigest(b, c, deadlineC);
        arbitrum.linkWallets(b, c, deadlineC, _sign(PK_B, digestC), _sign(PK_C, digestC));

        assertEq(arbitrum.accountingRootOf(c), root);
        assertEq(arbitrum.getAccountingWallets(c).length, 3);
        assertEq(arbitrum.getUniqueGlobalAccumulator(0, c), 150);
        assertEq(arbitrum.getAccountingPositionCount(a), 3);
        assertEq(arbitrum.getUserIdByAddress(c), arbitrum.getUserIdByAddress(a));
    }

    function testContractWalletCanLink() public {
        uint256 ownerPk = 0xD00D;
        SigningWallet wallet = new SigningWallet(vm.addr(ownerPk));
        address other = vm.addr(PK_B);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = arbitrum.linkDigest(address(wallet), other, deadline);
        arbitrum.linkWallets(address(wallet), other, deadline, _sign(ownerPk, digest), _sign(PK_B, digest));
        assertEq(arbitrum.accountingRootOf(other), arbitrum.accountingRootOf(address(wallet)));
    }

    function testLinkedWalletCap() public {
        uint256 rootPk = 1;
        address root = vm.addr(rootPk);
        for (uint256 i = 0; i < 16; i++) {
            uint256 extraPk = 100 + i;
            address extra = vm.addr(extraPk);
            uint256 deadline = block.timestamp + 1 days;
            bytes32 digest = arbitrum.linkDigest(root, extra, deadline);
            if (i < 15) {
                arbitrum.linkWallets(root, extra, deadline, _sign(rootPk, digest), _sign(extraPk, digest));
            } else {
                vm.expectRevert(SendraStorage.LinkWalletLimit.selector);
                arbitrum.linkWallets(root, extra, deadline, _sign(rootPk, digest), _sign(extraPk, digest));
            }
        }
        assertEq(arbitrum.getAccountingWallets(root).length, 16);
    }

    function testOnlySyncerCommits() public {
        vm.expectRevert(SendraStorage.InvalidSyncer.selector);
        vm.prank(address(0x1234));
        arbitrum.sealTemporalPulse(address(0xBEEF));
    }

    function _apply(SendraStorage store, address user, uint8 fieldId, int256 delta) internal {
        uint8[] memory ids = new uint8[](1);
        int256[] memory deltas = new int256[](1);
        ids[0] = fieldId;
        deltas[0] = delta;
        store.applyGlobalPulseDeltas(user, ids, deltas);
    }

    function _commit(
        SendraStorage store,
        address user,
        uint64 expectedVersion,
        uint64 newVersion,
        bool clearSeal,
        bytes32 sealHash,
        uint256 chainId,
        SendraLib.GlobalAccumulators memory next
    ) internal {
        uint256[] memory chainIds = new uint256[](1);
        bytes32[] memory sealHashes = new bytes32[](1);
        chainIds[0] = chainId;
        sealHashes[0] = sealHash;
        store.commitGlobalPulse(
            user, expectedVersion, newVersion, clearSeal, clearSeal ? sealHash : bytes32(0), chainIds, sealHashes, next
        );
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
