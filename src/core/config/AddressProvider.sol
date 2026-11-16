/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒                                                                                                                                                    
________________________________________________________________
*/

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Roles } from "../../security/Roles.sol";

/**
 * @title AddressProvider
 * @dev Centralized contract to manage addresses of all protocols
 * 
 * Scalable solution that allows:
 * - Adding new protocols without touching proxies
 * - Changing implementations without redeploying
 * - Fixed known storage in all proxies
 */
contract AddressProvider {

    Roles public immutable roles;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    uint8 public constant REQUIRED_APPROVALS = 3;

    modifier onlyAdmin() {
        if (!roles.checkAdmin(msg.sender)) revert NotAdmin();
        _;
    }

    mapping(string => address) public addressMap;

    struct AddressVote {
        uint8 approvals;
        address[] approvedBy;
    }

    /// @dev One ballot per name and address. A different address is a different ballot.
    mapping(bytes32 => AddressVote) private addressVotes;

    function getAddress(string calldata contractName) public view returns (address) {
        address contractAddress = addressMap[contractName];
        if (contractAddress == address(0)) revert AddressNotFound(contractName);
        return contractAddress;
    }

    /**
     * @notice Votes to register `contractName` as `_address`.
     * @dev The registry changes only after REQUIRED_APPROVALS distinct admins vote for the same pair.
     *      Overwriting an existing entry takes the same quorum.
     */
    function proposeAddress(string calldata contractName, address _address) public onlyAdmin {
        if (_address == address(0) || bytes(contractName).length == 0) revert ZeroAddress();
        bytes32 id = keccak256(abi.encode(contractName, _address));
        AddressVote storage vote = addressVotes[id];
        uint256 n = vote.approvedBy.length;
        for (uint256 i = 0; i < n; i++) {
            if (vote.approvedBy[i] == msg.sender) revert AlreadyApproved();
        }
        vote.approvals++;
        vote.approvedBy.push(msg.sender);
        if (vote.approvals >= REQUIRED_APPROVALS) {
            addressMap[contractName] = _address;
            delete addressVotes[id];
            emit ContractAddressUpdated(contractName, _address);
        }
    }

    event ContractAddressUpdated(string indexed contractName, address indexed _address);

    error AddressNotFound(string contractName);
    error NotAdmin();
    error ZeroAddress();
    error AlreadyApproved();
}