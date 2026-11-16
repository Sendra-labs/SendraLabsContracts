// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Roles } from "../src/security/Roles.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";

contract QuorumTarget {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract RolesQuorumTest is Test {
    address internal admin1 = address(0xA11);
    address internal admin2 = address(0xA12);
    address internal admin3 = address(0xA13);
    address internal hot = address(0xB07);

    Roles internal roles;
    AddressProvider internal provider;
    QuorumTarget internal target;

    function setUp() public {
        roles = new Roles(admin1, admin2, admin3, address(0xB01), address(0xB02), address(0xB03));
        provider = new AddressProvider(address(roles));
        target = new QuorumTarget();
    }

    function testAllowNeedsThreeAdmins() public {
        vm.prank(admin1);
        roles.allowContract(address(target), "Target");
        vm.prank(admin2);
        roles.allowContract(address(target), "Target");
        assertFalse(roles.isProtocolContract(address(target)));

        vm.prank(admin3);
        roles.allowContract(address(target), "Target");
        assertTrue(roles.isProtocolContract(address(target)));
    }

    function testSameAdminCannotApproveTwice() public {
        vm.prank(admin1);
        roles.allowContract(address(target), "Target");
        vm.prank(admin1);
        vm.expectRevert(Roles.InvalidApproval.selector);
        roles.allowContract(address(target), "Target");
    }

    function testDeleteNeedsThreeAdminsAndClearsApprovals() public {
        _allow(address(target), "Target");

        vm.prank(admin1);
        roles.deleteContract(address(target));
        vm.prank(admin2);
        roles.deleteContract(address(target));
        assertTrue(roles.isProtocolContract(address(target)));

        vm.prank(admin3);
        roles.deleteContract(address(target));
        assertFalse(roles.isProtocolContract(address(target)));

        vm.prank(admin1);
        roles.allowContract(address(target), "Target");
        assertFalse(roles.isProtocolContract(address(target)));
    }

    function testProposeAndPenalizeNeedThreeIncludingGenesis() public {
        vm.prank(admin1);
        roles.proposeAdmin(hot);
        vm.prank(admin2);
        roles.proposeAdmin(hot);
        assertFalse(roles.checkAdmin(hot));
        vm.prank(admin3);
        roles.proposeAdmin(hot);
        assertTrue(roles.checkAdmin(hot));

        vm.prank(admin1);
        roles.penalizeAdmin(hot);
        vm.prank(admin2);
        roles.penalizeAdmin(hot);
        assertTrue(roles.checkAdmin(hot));
        vm.prank(admin3);
        roles.penalizeAdmin(hot);
        assertFalse(roles.checkAdmin(hot));

        vm.prank(admin1);
        roles.proposeAdmin(hot);
        vm.prank(admin2);
        roles.proposeAdmin(hot);
        vm.prank(admin3);
        roles.proposeAdmin(hot);

        vm.prank(admin2);
        roles.penalizeAdmin(admin1);
        vm.prank(admin3);
        roles.penalizeAdmin(admin1);
        assertTrue(roles.checkAdmin(admin1));
        vm.prank(hot);
        roles.penalizeAdmin(admin1);
        assertFalse(roles.checkAdmin(admin1));
    }

    function testAddressNeedsThreeVotes() public {
        address listed = address(0x1234);
        vm.prank(admin1);
        provider.proposeAddress("SendraStorage", listed);
        vm.prank(admin2);
        provider.proposeAddress("SendraStorage", listed);
        vm.expectRevert(abi.encodeWithSelector(AddressProvider.AddressNotFound.selector, "SendraStorage"));
        provider.getAddress("SendraStorage");

        vm.prank(admin3);
        provider.proposeAddress("SendraStorage", listed);
        assertEq(provider.getAddress("SendraStorage"), listed);
    }

    function _allow(address account, string memory name) internal {
        vm.prank(admin1);
        roles.allowContract(account, name);
        vm.prank(admin2);
        roles.allowContract(account, name);
        vm.prank(admin3);
        roles.allowContract(account, name);
    }
}
