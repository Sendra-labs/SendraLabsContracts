//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MarketNeutralLib } from "../../../lib/MarketNeutral/MarketNeutralLib.sol";
import { GMXMarketsRegistry } from "../../config/gmxMarkets.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProxyManager } from "../storage/ProxyManager.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";

contract MarketNeutralProxy is ReentrancyGuard {

    AddressProvider public immutable addressProvider;
    address public marketNeutral;
    uint256 public immutable id;

    constructor(address _addressProvider, uint256 _id) {
        addressProvider = AddressProvider(_addressProvider);
        id = _id;
        marketNeutral = addressProvider.getAddress("MarketNeutral");
    }

    modifier onlyOwner() {
        address owner = ProxyManager(addressProvider.getAddress("ProxyManager")).getOwner(id);
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    address[] internal markets;

    function initialize() public onlyOwner {
        marketNeutral = addressProvider.getAddress("MarketNeutral");
    }

    function openEtherMarketNeutralDelegatecall(MarketNeutralLib.EtherMarketNeutralInput calldata _input) public payable onlyOwner nonReentrant {
        manageMarkets(_input.marketLong, _input.marketShort);
        (bool success,) = marketNeutral.delegatecall(
            abi.encodeWithSignature(
                "openEtherMarketNeutral((string,string,uint256,uint256,uint256,uint256,uint256))",
                _input
            )
        );
        require(success, "Delegatecall failed");
    }

    function openUSDCMarketNeutralDelegatecall(MarketNeutralLib.UsdcMarketNeutralInput calldata _input) public payable onlyOwner nonReentrant {
        manageMarkets(_input.marketLong, _input.marketShort);
        (bool success,) = marketNeutral.delegatecall(
            abi.encodeWithSignature(
                "openUSDCMarketNeutral((string,string,uint256,uint256,uint256,uint256,uint256))",
                _input
            )
        );
        require(success, "Delegatecall failed");
    }

    //closeMarketNeutral
    function closeMarketNeutralDelegatecall(MarketNeutralLib.CloseMarketNeutralInput calldata _input) public payable onlyOwner nonReentrant {
        deleteMarket(_input.positionId);
        (bool success,) = marketNeutral.delegatecall(
            abi.encodeWithSignature(
                "closeMarketNeutral((uint256,uint256,uint256))",
                _input
            )
        );
        require(success, "Delegatecall failed");
    }

    function manageMarkets(string calldata _marketLong, string calldata _marketShort) internal {
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < markets.length; i++) {
            if (
                markets[i] == marketLong || 
                markets[i] == marketShort
            ) {
                revert MarketAlreadyExists();
            }
        }
        markets.push(marketLong);
        markets.push(marketShort);
    }

    function deleteMarket(uint256 _positionId) internal {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address owner = ProxyManager(addressProvider.getAddress("ProxyManager")).getOwner(id);
        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(owner, _positionId);
        address marketLong = abi.decode(position.positionData[2], (address));
        address marketShort = abi.decode(position.positionData[3], (address));
        for(uint256 i = 0; i < markets.length; i++) {
        if (markets[i] == marketLong || markets[i] == marketShort) {
                markets[i] = markets[markets.length - 1];
                markets.pop();
                break;
            }
        }
        if (markets.length == 0) {
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(id); // ESTO DEBE HACERSE EN AFTER ORDER EXECUTION
        }
    }

    function isMarketBeingUsed(string calldata _marketLong, string calldata _marketShort) public view returns (bool) {
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < markets.length; i++) {
            if (markets[i] == marketLong || markets[i] == marketShort) {
                return true; // market is being used
            }
        }
        return false; // market is not being used
    }

    function getId() public view returns (uint256) {
        return id;
    }
    
    error NotOwner();
    error MarketAlreadyExists();

}