//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RolesLib } from "../lib/security/Roles.lib.sol";

/**
 * @title Roles
 * @author @Diego-AVZ
 * @notice Advanced role-based access control with democratic consensus
 * @dev Implements multi-admin governance with contract whitelisting and admin management
 * @dev Features: 3-initial admin setup, democratic contract approval, admin penalization system
 * @custom:security Designed to prevent single points of failure and admin compromise
 */
contract Roles {

    /// @notice Cold administrators recorded at deployment. Removable like any other admin.
    address public immutable mainAdmin;
    address public immutable admin2;
    address public immutable admin3;

    uint8 public constant REQUIRED_APPROVALS = 3;

    /**
     * @notice Cold wallets plus the hot wallets that sign the deploy.
     * @dev The cold addresses are not keys. The hot wallets are admins in the same transaction,
     *      so the deploy can reach quorum without a signature from the hardware wallets.
     */
    constructor(
        address _mainAdmin,
        address _admin2,
        address _admin3,
        address _hot1,
        address _hot2,
        address _hot3
    ) {
        mainAdmin = _mainAdmin;
        admin2 = _admin2;
        admin3 = _admin3;
        _initAdmin(_mainAdmin);
        _initAdmin(_admin2);
        _initAdmin(_admin3);
        _initAdmin(_hot1);
        _initAdmin(_hot2);
        _initAdmin(_hot3);
    }

    function _initAdmin(address account) private {
        if (account == address(0) || isAdmin[account].isAdmin) revert InvalidSigner();
        isAdmin[account].isAdmin = true;
        admins.push(account);
    }
    
    /// @notice Thrown when an unauthorized address attempts to perform an admin action
    error InvalidSigner();
    
    /// @notice Thrown when an invalid contract address is provided
    error InvalidContract();
    
    error AdminAlreadyExists();
    error AdminNotFound();
    error AdminAlreadyPenalized();
    error InvalidApproval();
    error AlreadyProtocol();
    error NameMismatch();
    /**
     * @notice Modifier that restricts access to admin addresses only
     * @dev Reverts with InvalidSigner if the caller is not an admin
    */
    modifier onlyAdmin() {
        if (!isAdmin[msg.sender].isAdmin) revert InvalidSigner();
        _;
    }

    address[] public admins;

    /// @notice Mapping of contract addresses to their protocol status and metadata
    mapping(address => RolesLib.Contract) isProtocol;
    
    /// @notice Mapping of addresses to their admin status
    mapping(address => RolesLib.Admin) isAdmin; 

    /**
     * @notice Approves a contract for the protocol whitelist.
     * @dev The contract stays inactive until REQUIRED_APPROVALS distinct admins have called this.
     *      The name is fixed by the first approval. A later call with a different name reverts.
     */
    function allowContract(address _contract, string calldata _name) public onlyAdmin {
        if (_contract == address(0) || !isContractAddress(_contract)) revert InvalidContract();
        if (isProtocol[_contract].isProtocol) revert AlreadyProtocol();
        if (checkApprovals(isProtocol[_contract].approvedBy)) revert InvalidApproval();

        if (bytes(isProtocol[_contract].name).length == 0) {
            isProtocol[_contract].name = _name;
        } else if (keccak256(bytes(isProtocol[_contract].name)) != keccak256(bytes(_name))) {
            revert NameMismatch();
        }

        isProtocol[_contract].approvals++;
        isProtocol[_contract].approvedBy.push(msg.sender);

        if (isProtocol[_contract].approvals >= REQUIRED_APPROVALS) {
            isProtocol[_contract].isProtocol = true;
        }
    }

    /**
     * @notice Approves removal of a protocol contract.
     * @dev Removal happens only after REQUIRED_APPROVALS distinct admins. The allow-list is cleared,
     *      so putting the same contract back also takes REQUIRED_APPROVALS fresh approvals.
     */
    function deleteContract(address _contract) public onlyAdmin {
        if (!isProtocol[_contract].isProtocol) revert InvalidContract();
        if (checkApprovals(isProtocol[_contract].removalApprovedBy)) revert InvalidApproval();

        isProtocol[_contract].removalApprovals++;
        isProtocol[_contract].removalApprovedBy.push(msg.sender);

        if (isProtocol[_contract].removalApprovals >= REQUIRED_APPROVALS) {
            isProtocol[_contract].isProtocol = false;
            isProtocol[_contract].approvals = 0;
            isProtocol[_contract].removalApprovals = 0;
            delete isProtocol[_contract].approvedBy;
            delete isProtocol[_contract].removalApprovedBy;
        }
    }

    /**
     * @notice Proposes a new admin for consensus approval
     * @dev Uses the same approval system as contracts. Activation takes REQUIRED_APPROVALS admins.
     * @param _admin The address of the new admin to propose
     * @custom:security Prevents single compromised admin from adding unlimited admins
     * @custom:security Requires REQUIRED_APPROVALS distinct admins to add a new admin
     */
    function proposeAdmin(address _admin) public onlyAdmin() {
        if (_admin == address(0)) revert InvalidSigner();
        if (isAdmin[_admin].isAdmin) revert AdminAlreadyExists();
        
        // Check if this admin has already approved this pending admin
        if(checkAdminApprovals(isAdmin[_admin].approvedBy)) revert InvalidApproval();
        
        // Add approval
        isAdmin[_admin].approvals++;
        isAdmin[_admin].approvedBy.push(msg.sender);
        
        if (isAdmin[_admin].approvals >= REQUIRED_APPROVALS) {
            isAdmin[_admin].isAdmin = true;
            admins.push(_admin);
        }
    }

    /**
     * @notice Internal function to remove an admin from the system
     * @dev Removes admin from both mapping and array. Used by penalization system
     * @param _admin The address of the admin to remove
     * @custom:security This function is internal and can only be called by penalization logic
     */
    function removeAdmin(address _admin) internal {
        if (!isAdmin[_admin].isAdmin) revert AdminNotFound();
        isAdmin[_admin].isAdmin = false;
        isAdmin[_admin].approvals = 0;
        isAdmin[_admin].penalties = 0;
        delete isAdmin[_admin].approvedBy;
        delete isAdmin[_admin].penalizedBy;
        for (uint i = 0; i < admins.length; i++) {
            if (admins[i] == _admin) {
                admins[i] = admins[admins.length - 1];
                admins.pop();
                break;
            }
        }
    }

    /**
     * @notice Penalizes an admin for misconduct or compromise
     * @dev Implements democratic consensus - admin is removed when majority agrees
     * @param _admin The address of the admin to penalize
     * @custom:security Prevents self-penalization and duplicate penalties from same admin.
     *                 The constructor admins can be removed too. Removal takes REQUIRED_APPROVALS
     *                 distinct admins, so a replacement has to be added before one of three can leave.
     */
    function penalizeAdmin(address _admin) public onlyAdmin {
        if (_admin == msg.sender) revert InvalidSigner();
        if (!isAdmin[_admin].isAdmin) revert AdminNotFound();

        address[] storage penalizers = isAdmin[_admin].penalizedBy;
        for (uint i = 0; i < penalizers.length; i++) {
            if (penalizers[i] == msg.sender) revert AdminAlreadyPenalized();
        }

        isAdmin[_admin].penalizedBy.push(msg.sender);
        isAdmin[_admin].penalties++;
        if (isAdmin[_admin].penalties >= REQUIRED_APPROVALS) {
            removeAdmin(_admin);
        }
    }

    /**
     * @notice Returns all admin addresses
     * @return Array of all admin addresses in the system
     */
    function getAdmins() public view returns(address[] memory) {
        return admins;
    }

    /**
     * @notice Returns detailed information about a specific admin
     * @param _admin The address of the admin to query
     * @return Admin struct containing status, penalties, and who penalized them
     */
    function getAdmin(address _admin) public view returns(RolesLib.Admin memory) {
        return isAdmin[_admin];
    }

    function checkAdmin(address _admin) public view returns(bool) {
        return isAdmin[_admin].isAdmin;
    }
    
    
    /**
     * @notice Internal function to verify if an address contains contract code
     * @dev Uses assembly to check the extcodehash of the address
     * @param account The address to check for contract code
     * @return True if the address contains contract code, false otherwise
    */
    function isContractAddress(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 emptyHash = keccak256("");
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != emptyHash);
    }

    /**
     * @notice Checks if an address is a whitelisted protocol contract
     * @param _contract The address to check
     * @return True if the address is a protocol contract, false otherwise
    */
    function isProtocolContract(address _contract) public view returns(bool) {
        return isProtocol[_contract].isProtocol;
    }

    /**
     * @notice Internal function to check if current admin has already approved a contract
     * @dev Prevents duplicate approvals from the same admin
     * @param _approvedBy Array of addresses who have approved the contract
     * @return True if current admin has already approved, false otherwise
     */
    function checkApprovals(address[] memory _approvedBy) internal view returns(bool) {
        for(uint i = 0; i < _approvedBy.length; i++){
            if(_approvedBy[i] == msg.sender) return true;
        }
        return false;
    }
    
    /**
     * @notice Internal function to check if current admin has already approved a pending admin
     * @dev Prevents duplicate approvals from the same admin
     * @param _approvedBy Array of addresses who have approved the pending admin
     * @return True if current admin has already approved, false otherwise
     */
    function checkAdminApprovals(address[] memory _approvedBy) internal view returns(bool) {
        for(uint i = 0; i < _approvedBy.length; i++){
            if(_approvedBy[i] == msg.sender) return true;
        }
        return false;
    }
}