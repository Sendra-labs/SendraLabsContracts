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

    /// @notice The main administrator addresses, immutable after deployment
    address immutable mainAdmin;
    address immutable admin2;
    address immutable admin3;

    /**
     * @notice Initializes the Roles contract with main administrators
     * @param _mainAdmin The address of the main administrator
     * @param _admin2 The address of the second administrator
     * @param _admin3 The address of the third administrator
    */
    constructor(address _mainAdmin, address _admin2, address _admin3) {
        if (_mainAdmin == address(0) || _admin2 == address(0) || _admin3 == address(0)) revert InvalidSigner();
        if (_mainAdmin == _admin2 || _mainAdmin == _admin3 || _admin2 == _admin3) revert InvalidSigner();
        
        mainAdmin = _mainAdmin;
        admin2 = _admin2;
        admin3 = _admin3;
        
        isAdmin[_mainAdmin].isAdmin = true;
        isAdmin[_admin2].isAdmin = true;
        isAdmin[_admin3].isAdmin = true;
        
        admins.push(_mainAdmin);
        admins.push(_admin2);
        admins.push(_admin3);
    }
    
    /// @notice Thrown when an unauthorized address attempts to perform an admin action
    error InvalidSigner();
    
    /// @notice Thrown when an invalid contract address is provided
    error InvalidContract();
    
    error AdminAlreadyExists();
    error AdminNotFound();
    error AdminAlreadyPenalized();
    error InvalidApproval();
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
     * @notice Allows a contract to be recognized as part of the protocol
     * @dev Implements democratic consensus - requires 2 admin approvals to activate contract
     * @dev Prevents duplicate approvals from same admin. Contract activates when approvals >= 2
     * @param _contract The address of the contract to whitelist
     * @param _name The name/identifier of the contract
     * @custom:security Only admin addresses can whitelist contracts
     * @custom:security Requires 2 admin approvals for activation (prevents single admin compromise)
     */
    function allowContract(address _contract, string calldata _name) public onlyAdmin(){
        if (
            _contract == address(0) ||
            !isContractAddress(_contract)
        ) 
        revert InvalidContract();

        if(checkApprovals(isProtocol[_contract].approvedBy)) revert InvalidApproval();

        if(isProtocol[_contract].approvals >= 2){
            isProtocol[_contract] = RolesLib.Contract(true,_name, isProtocol[_contract].approvals, isProtocol[_contract].approvedBy);
        } else {
            isProtocol[_contract].approvals++;
            isProtocol[_contract].approvedBy.push(msg.sender);
        }
    }
    
    /**
     * @notice Removes a contract from the protocol whitelist
     * @dev Only callable by admin addresses. Sets the contract's protocol status to false
     * @param _contract The address of the contract to remove from the protocol
     * @custom:security Only admin addresses can remove contracts from the protocol
    */
    function deleteContract(address _contract) public onlyAdmin() {
        if (!isProtocol[_contract].isProtocol) revert InvalidContract();
        isProtocol[_contract].isProtocol = false;
    }

    /**
     * @notice Proposes a new admin for consensus approval
     * @dev Uses same approval system as contracts - requires 2 admin approvals
     * @param _admin The address of the new admin to propose
     * @custom:security Prevents single compromised admin from adding unlimited admins
     * @custom:security Requires democratic consensus (2 approvals) to add new admin
     */
    function proposeAdmin(address _admin) public onlyAdmin() {
        if (_admin == address(0)) revert InvalidSigner();
        if (isAdmin[_admin].isAdmin) revert AdminAlreadyExists();
        
        // Check if this admin has already approved this pending admin
        if(checkAdminApprovals(isAdmin[_admin].approvedBy)) revert InvalidApproval();
        
        // Add approval
        isAdmin[_admin].approvals++;
        isAdmin[_admin].approvedBy.push(msg.sender);
        
        // If we have enough approvals (2), activate the admin
        if (isAdmin[_admin].approvals >= 2) {
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
     * @custom:security Prevents self-penalization and duplicate penalties from same admin
     * @custom:security Admin is removed when penalties >= 2 (majority consensus)
     */
    function penalizeAdmin(address _admin) public onlyAdmin() {
        if (_admin == msg.sender) revert InvalidSigner();
        
        address[] storage penalizers = isAdmin[_admin].penalizedBy;
        for (uint i = 0; i < penalizers.length; i++) {
            if (penalizers[i] == msg.sender) revert AdminAlreadyPenalized();
        }
        
        isAdmin[_admin].penalizedBy.push(msg.sender);
        isAdmin[_admin].penalties++;
        if (isAdmin[_admin].penalties >= 2) {
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