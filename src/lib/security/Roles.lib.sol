//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library RolesLib {

    struct Contract {
        bool isProtocol;
        string name;
        uint8 approvals;
        address[] approvedBy;
        uint8 removalApprovals;
        address[] removalApprovedBy;
    }

    struct Admin {
        bool isAdmin;
        uint8 penalties;
        address[] penalizedBy;
        uint8 approvals;
        address[] approvedBy;
    }

}