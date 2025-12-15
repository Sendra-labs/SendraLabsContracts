//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolStorage } from "./ProtocolStorage.sol";
import { ProtocolLib } from "../lib/Protocol.lib.sol";
import { AddressProvider } from "./config/AddressProvider.sol";
import { GMXMarketsRegistry } from "./config/gmxMarkets.sol";
import { GMXPrices } from "../periphery/utilsGMX/GMXPrices.sol";
import { MarketNeutralReader } from "./bundles/readers/marketNeutralReader.sol";
import { MarketNeutralProxy } from "./bundles/executors/proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainReader {

    ProtocolStorage public immutable protocolStorage;
    AddressProvider public immutable addressProvider;
    MarketNeutralReader public immutable marketNeutralReader;
    GMXPrices public immutable gmxPrices;
    GMXMarketsRegistry public immutable gmxMarkets;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        marketNeutralReader = MarketNeutralReader(addressProvider.getAddress("MarketNeutralReader"));
        gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
    }

    struct GlobalUserData {
        int256 totalPnl;
        uint256 totalVolume;
        uint256 totalTransactions;
        uint256 totalPositions;
        uint256 totalActivePositions;
        uint256 totalValueLocked;
        uint256 averagePositionSize;
    }

    function getGlobalUserData(address _user) public view returns (GlobalUserData memory) {
        ProtocolLib.UserInfoRead memory user = protocolStorage.getUser(_user);
        
        uint256 totalVolume = 0;
        uint256 totalValueLocked = 0;
        
        for(uint256 i = 1; i <= user.totalPositions; i++) {
            ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, i);
            if(position.positionType == 0) { // MarketNeutral = 0
                bytes[] memory positionData = position.positionData;
                uint256 initialUsdValue = abi.decode(positionData[8], (uint256));
                totalVolume += initialUsdValue;
                
                uint256 closeDate = abi.decode(positionData[10], (uint256));
                if(closeDate == 0) {
                    totalValueLocked += initialUsdValue;
                }
            }
        }
        
        uint256 averagePositionSize = 0;
        if(user.totalPositions > 0) {
            averagePositionSize = totalVolume / user.totalPositions;
        }
        
        return GlobalUserData(
            user.globalPnl,
            totalVolume,
            user.transactionCount,
            user.totalPositions,
            user.activePositions,
            totalValueLocked,
            averagePositionSize
        );
    }
    
    struct MarketNeutralPosition {
        uint256 positionId;
        int256 pnlRealTime;
        uint256 sizeRealTime;
        uint256 investedInitialValue;
        uint256 initialToken;
        uint256 initialUsdValue;
        uint256 initialPriceTokenLong;
        uint256 initialPriceTokenShort;
        uint256 openDate;
        uint256 sizeDeltaUsdLong;
        uint256 sizeDeltaUsdShort;
        int256 longPnl;
        int256 shortPnl;
        address marketLong;
        address marketShort;
        address proxy;
        bool isActive;
    }
/*
    5, //positionId
    0, //pnlRealTime
    100000000000000000000000000000000, //sizeRealTime
    100000000, //investedInitialValue
    0, //initialToken
    100000000, //initialUsdValue
    15620400000, //initialPriceTokenLong
    36182417, //initialPriceTokenShort
    1762461082, //openDate
    50000000000000000000000000000000, sizeDeltaUsdShort
    50000000000000000000000000000000, //sizeDeltaUsdLong        
    0, //longPnl
    0, //shortPnl
    0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9, //marketLong
    0x4fDd333FF9cA409df583f306B6F5a7fFdE790739, //marketShort
    0x83a2db03363a1e2d791506Ee26BeCE9c671C0AA8, //proxy
    true //isActive 

    
*/
    function getMarketNeutralPositionsData(address _user) public view returns (MarketNeutralPosition[] memory) {
        ProtocolLib.UserInfoRead memory user = protocolStorage.getUser(_user);
        
        // First pass: count MarketNeutral positions
        uint256 marketNeutralCount = 0;
        for(uint256 i = 1; i <= user.totalPositions; i++) {
            ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, i);
            if(position.positionType == 0) { // MarketNeutral = 0
                marketNeutralCount++;
            }
        }
        
        // Create array with correct size
        MarketNeutralPosition[] memory marketNeutralPosition = new MarketNeutralPosition[](marketNeutralCount);
        uint256 index = 0;
        
        // Second pass: populate array
        for(uint256 i = 1; i <= user.totalPositions; i++) {
            ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, i);
            if(position.positionType == 0) { // MarketNeutral = 0
                bytes[] memory positionData = position.positionData;
                uint256 closeDate = abi.decode(positionData[10], (uint256));
                bool isActive = closeDate == 0;
                
                int256 longPnl;
                int256 shortPnl;
                int256 totalPnl;
                uint256 sizeRealTime;
                
                // For active positions, calculate real-time PNL
                // For closed positions, use stored PNL and size = 0
                if (isActive) {
                    (longPnl, shortPnl, totalPnl) = marketNeutralReader.getMarketNeutralRealTimePnL(_user, position.id);
                    sizeRealTime = marketNeutralReader.getMarketNeutralTotalSize(_user, position.id);
                } else {
                    // For closed positions, use stored PNL and size = 0
                    totalPnl = position.pnl;
                    longPnl = 0; // Can't determine individual PNL for closed positions
                    shortPnl = 0;
                    sizeRealTime = 0;
                }
                
                marketNeutralPosition[index] = MarketNeutralPosition(
                    position.id,
                    totalPnl,
                    sizeRealTime,
                    abi.decode(positionData[0], (uint256)),
                    abi.decode(positionData[1], (uint256)),
                    abi.decode(positionData[8], (uint256)),
                    abi.decode(positionData[6], (uint256)),
                    abi.decode(positionData[7], (uint256)),
                    abi.decode(positionData[9], (uint256)),
                    abi.decode(positionData[4], (uint256)),
                    abi.decode(positionData[5], (uint256)),
                    longPnl,
                    shortPnl,
                    abi.decode(positionData[2], (address)),
                    abi.decode(positionData[3], (address)),
                    abi.decode(positionData[17], (address)),
                    isActive
                );
                index++;
            }
        }
        return marketNeutralPosition;
    }

    function getMarketNeutralPositionDataById(address _user, uint256 _positionId) public view returns (MarketNeutralPosition memory) {
        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, _positionId);
        (int256 longPnl, int256 shortPnl, int256 totalPnl) = marketNeutralReader.getMarketNeutralRealTimePnL(_user, _positionId);
        uint256 closeDate = abi.decode(position.positionData[10], (uint256));
        bool isActive = closeDate == 0;
        return MarketNeutralPosition(
            position.id,
            totalPnl,
            marketNeutralReader.getMarketNeutralTotalSize(_user, _positionId),
            abi.decode(position.positionData[0], (uint256)),
            abi.decode(position.positionData[1], (uint256)),
            abi.decode(position.positionData[8], (uint256)),
            abi.decode(position.positionData[6], (uint256)),
            abi.decode(position.positionData[7], (uint256)),
            abi.decode(position.positionData[9], (uint256)),
            abi.decode(position.positionData[4], (uint256)),
            abi.decode(position.positionData[5], (uint256)),
            longPnl,
            shortPnl,
            abi.decode(position.positionData[2], (address)),
            abi.decode(position.positionData[3], (address)),
            abi.decode(position.positionData[17], (address)),
            isActive
        );
    }

    function getPositions(address _user, uint256 _from, uint256 _to) public view returns (ProtocolLib.Position[] memory) {
        ProtocolLib.Position[] memory positions = new ProtocolLib.Position[](_to - _from + 1);
        for(uint256 i = _from; i <= _to; i++) {
            positions[i - _from] = protocolStorage.getUserPositionById(_user, i);
        }
        return positions;
    }

    function getProtocolStats() public view returns (ProtocolLib.ProtocolStats memory) {
        return protocolStorage.getProtocolStats();
    }

    function getPrices(string memory _marketLong, string memory _marketShort) public view returns (uint256, uint256) {
        return (gmxPrices.getPrice(gmxMarkets.getMarket(_marketLong)), gmxPrices.getPrice(gmxMarkets.getMarket(_marketShort)));
    }

    function getEtherPrice() public view returns (uint256) {
        return gmxPrices.getPrice(gmxMarkets.getMarket("ETHUSDC"));
    }

    function getUserUsdcBalance(address _user) public view returns (uint256) {
        return IERC20(addressProvider.getAddress("USDC")).balanceOf(_user);
    }

    function getMarketNeutralPositionsDataSimple(address _user) public view returns (MarketNeutralPosition[] memory) {
        ProtocolLib.UserInfoRead memory user = protocolStorage.getUser(_user);
        
        uint256 marketNeutralCount = 0;
        for(uint256 i = 1; i <= user.totalPositions; i++) {
            ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, i);
            if(position.positionType == 0) { // MarketNeutral = 0
                marketNeutralCount++;
            }
        }
        
        MarketNeutralPosition[] memory marketNeutralPosition = new MarketNeutralPosition[](marketNeutralCount);
        uint256 index = 0;
        
        for(uint256 i = 1; i <= user.totalPositions; i++) {
            ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, i);
            if(position.positionType == 0) { // MarketNeutral = 0
                bytes[] memory positionData = position.positionData;
                uint256 closeDate = abi.decode(positionData[10], (uint256));
                bool isActive = closeDate == 0;
                
                int256 longPnl;
                int256 shortPnl;
                int256 totalPnl;
                uint256 sizeRealTime;
                
                // For active positions, calculate real-time PNL
                // For closed positions, use stored PNL and size = 0
                if (isActive) {
                    (longPnl, shortPnl, totalPnl) = (0, 0, 0);
                    sizeRealTime = 0;
                } else {
                    // For closed positions, use stored PNL and size = 0
                    totalPnl = position.pnl;
                    longPnl = 0; // Can't determine individual PNL for closed positions
                    shortPnl = 0;
                    sizeRealTime = 0;
                }
                
                marketNeutralPosition[index] = MarketNeutralPosition(
                    position.id,
                    totalPnl,
                    sizeRealTime,
                    abi.decode(positionData[0], (uint256)),
                    abi.decode(positionData[1], (uint256)),
                    abi.decode(positionData[8], (uint256)),
                    abi.decode(positionData[6], (uint256)),
                    abi.decode(positionData[7], (uint256)),
                    abi.decode(positionData[9], (uint256)),
                    abi.decode(positionData[4], (uint256)),
                    abi.decode(positionData[5], (uint256)),
                    longPnl,
                    shortPnl,
                    abi.decode(positionData[2], (address)),
                    abi.decode(positionData[3], (address)),
                    abi.decode(positionData[17], (address)),
                    isActive
                );
                index++;
            }
        }
        return marketNeutralPosition;
    }

    function isProxyNeeded(address _user, string calldata _marketLong, string calldata _marketShort) public view returns (bool, address) {
        MarketNeutralPosition[] memory marketNeutralPositions = getMarketNeutralPositionsDataSimple(_user);
        for(uint256 i = 0; i < marketNeutralPositions.length; i++) {
            if(marketNeutralPositions[i].isActive) {
                address proxy = marketNeutralPositions[i].proxy;
                // Skip if proxy is address(0) (shouldn't happen, but safety check)
                if(proxy == address(0)) continue;
                
                bool isMarketBeingUsed = MarketNeutralProxy(proxy).isMarketBeingUsed(_marketLong, _marketShort);
                if(!isMarketBeingUsed) {
                    return (false, marketNeutralPositions[i].proxy); // user is owner of a proxy that is not being used for this markets
                    // retunrs "false, proxy is not needed, user is owner and can use this adress"
                }
            }
        }
        return (true, address(0)); // user needs to claim or deploy a new proxy
    }
}

/*
front end calls isProxyNeeded
if false, front end calls proxy to open marketNeutral position
if true, front end calls proxyManager initializeProxy 
*/