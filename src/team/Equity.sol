//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolLib } from "../lib/Protocol.lib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Roles } from "../security/Roles.sol";
import { PartnerManager } from "./PartnerManager.sol";

contract Equity is ReentrancyGuard {

    constructor(ProtocolLib.Partner[] memory _partners, address _usdcAddress, address _rolesAddress) {
        totalEquity = 10000;
        availableEquity = totalEquity;
        initializePartnersEquity(_partners);
        USDC = IERC20(_usdcAddress);
        roles = Roles(_rolesAddress);
    }

    IERC20 public immutable USDC;
    Roles public immutable roles;

    /**
     * @notice Modifier that restricts access to authorized protocol contracts only
     * @dev Uses Roles contract to verify that caller is a registered protocol contract
     */
    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    // Total equity of the protocol 
    // 10000 = 100%  ... 100 = 1%
    // 1 = 0.01% => minimum value to be used
    uint256 public immutable totalEquity;
    uint256 public availableEquity;
    uint256 public availableEtherRevenue;
    uint256 public totalEtherRevenue;
    uint256 public availableUsdRevenue;
    uint256 public totalUsdRevenue;
    uint256 public partnersCount;
    uint256 public totalEquitySold;

    mapping(address => ProtocolLib.Partner) public partners;
    address[] public partnersContracts;

    function factory(ProtocolLib.Partner memory _partner) internal returns (address) {
        PartnerManager _newPartnerManager = new PartnerManager(_partner, address(roles));
        partnersContracts.push(address(_newPartnerManager));
        return address(_newPartnerManager);
    }

    function initializePartnersEquity(ProtocolLib.Partner[] memory _partners) internal {
        if(_partners.length == 0) revert InvalidPartner();
        if(availableEquity == 0) revert InvalidEquity();

        for(uint256 i = 0; i < _partners.length; i++) {
            for(uint256 j = i + 1; j < _partners.length; j++) {
                if(_partners[i].member == _partners[j].member) revert InvalidPartner();
            }
        }
        
        for(uint256 i = 0; i < _partners.length; i++) {
            if(_partners[i].member == address(0)) revert InvalidPartner();
            if(_partners[i].equity == 0) revert InvalidEquity();
            if(_partners[i].equity > availableEquity) revert InvalidEquity();
            address _newPartnerManager = factory(_partners[i]);
            availableEquity -= _partners[i].equity;
            partners[_newPartnerManager] = _partners[i];
        }
        partnersCount = _partners.length;
        if(availableEquity != 0) revert InvalidEquity();
    }

    receive() external payable {
        if(msg.value == 0) revert InvalidValue();
        availableEtherRevenue += msg.value;
        totalEtherRevenue += msg.value;
    }

    function receiveUsd(uint256 _amount) external nonReentrant  onlyProtocol {
        if(_amount == 0) revert InvalidValue();

        uint256 newAvailableUsdRevenue = availableUsdRevenue + _amount;
        uint256 newTotalUsdRevenue = totalUsdRevenue + _amount;

        bool success = USDC.transferFrom(msg.sender, address(this), _amount);
        if(!success) revert InvalidValue();

        availableUsdRevenue = newAvailableUsdRevenue;
        totalUsdRevenue = newTotalUsdRevenue;
    }

    function distributeRevenue() public nonReentrant onlyProtocol{
        uint256 batchRevenueEth = availableEtherRevenue;
        uint256 batchRevenueUsd = availableUsdRevenue;
        for(uint256 i = 0; i < partnersContracts.length; i++) {
            address partnerAddr = partnersContracts[i];
            uint256 amountEth = (batchRevenueEth/totalEquity)*partners[partnerAddr].equity;
            uint256 amountUsd = (batchRevenueUsd/totalEquity)*partners[partnerAddr].equity;
            availableUsdRevenue -= amountUsd;
            availableEtherRevenue -= amountEth;
            Address.sendValue(payable(partnerAddr), amountEth);
            USDC.transfer(partnerAddr, amountUsd);
        }
        if(availableEtherRevenue != 0 || availableUsdRevenue != 0) revert InvalidRevenue();
    }

    function claimRevenue(address _to) public nonReentrant {
        if(partners[_to].equity == 0) revert InvalidPartner();
        (uint256 _amountEth, uint256 _amountUsd) = checkPartnerRevenue(_to);
        if(_amountEth == 0 && _amountUsd == 0) revert InvalidRevenue();
        if(_amountEth > availableEtherRevenue) revert InvalidRevenue();
        if(_amountUsd > availableUsdRevenue) revert InvalidRevenue();
        availableEtherRevenue -= _amountEth;
        availableUsdRevenue -= _amountUsd;
        partners[_to].etherRevenue += _amountEth;
        partners[_to].usdRevenue += _amountUsd;
        Address.sendValue(payable(_to), _amountEth);
        USDC.transfer(_to, _amountUsd);
    }

    function sellEquity(address _from, address _to, uint256 _equity, uint256 _priceUsd) public nonReentrant {
        if(_equity < 1 || _equity > partners[_from].equity) revert InvalidEquity();
        if(_priceUsd == 0) revert InvalidPrice();
        if(_from == _to || _from == address(0) || _to == address(0)) revert InvalidPartner();
        if(partners[_from].equity == 0) partnersCount--;
        //partners[_from].equity -= _equity;
        partners[_to].equity += _equity;
        partnersCount++;
        partners[_from].equitySold += _equity;
        totalEquitySold += _equity;
    }

    function checkPartnerRevenue(address _to) public view returns (uint256 _amountEth, uint256 _amountUsd) {
        if(partners[_to].equitySold == 0) {
            _amountEth = (totalEtherRevenue/partners[_to].equity) - partners[_to].etherRevenue;
            _amountUsd = (totalUsdRevenue/partners[_to].equity) - partners[_to].usdRevenue;
        } else {
            _amountEth = ((((totalEtherRevenue/partners[_to].equity) - partners[_to].etherRevenue) * partners[_to].equitySold) / 100) - partners[_to].etherRevenue;
            _amountUsd = ((((totalUsdRevenue/partners[_to].equity) - partners[_to].usdRevenue) * partners[_to].equitySold) / 100) - partners[_to].usdRevenue;
        }
        return (_amountEth, _amountUsd);
    }

    error InvalidEquity();
    error InvalidPartner();
    error InvalidValue();
    error SenderNotAllowed();
    error InvalidRevenue();
    error InvalidPrice();
    
}