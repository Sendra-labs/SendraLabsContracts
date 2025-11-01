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
        ProtocolLib.User memory user = protocolStorage.getUser(_user);
        ProtocolLib.Position[] memory positions = user.globalPosition.positions;
        
        uint256 totalVolume = 0;
        uint256 totalValueLocked = 0;
        
        for(uint256 i = 0; i < positions.length; i++) {
            if(positions[i].positionType == 0) { // MarketNeutral = 0
                bytes[] memory positionData = positions[i].positionData;
                uint256 initialUsdValue = abi.decode(positionData[8], (uint256));
                totalVolume += initialUsdValue;
                
                // Verificar si la posición está activa (closeDate == 0)
                uint256 closeDate = abi.decode(positionData[10], (uint256));
                if(closeDate == 0) {
                    totalValueLocked += initialUsdValue;
                }
            }
        }
        
        uint256 averagePositionSize = 0;
        if(user.globalPosition.totalPositions > 0) {
            averagePositionSize = totalVolume / user.globalPosition.totalPositions;
        }
        
        return GlobalUserData(
            user.globalPnl,
            totalVolume,
            user.transactionCount,
            user.globalPosition.totalPositions,
            user.globalPosition.activePositions,
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

    function getMarketNeutralPositionsData(address _user) public view returns (MarketNeutralPosition[] memory) {
        ProtocolLib.User memory user = protocolStorage.getUser(_user);
        ProtocolLib.Position[] memory positions = user.globalPosition.positions;
        MarketNeutralPosition[] memory marketNeutralPosition = new MarketNeutralPosition[](positions.length);
        for(uint256 i = 0; i < positions.length; i++) {
            if(positions[i].positionType == 0) { // MarketNeutral = 0
                (int256 longPnl, int256 shortPnl, int256 totalPnl) = marketNeutralReader.getMarketNeutralRealTimePnL(_user, positions[i].id);
                bytes[] memory positionData = positions[i].positionData;
                uint256 closeDate = abi.decode(positionData[10], (uint256));
                bool isActive = closeDate == 0;
                marketNeutralPosition[i] = MarketNeutralPosition(
                    positions[i].id,
                    totalPnl,
                    marketNeutralReader.getMarketNeutralTotalSize(_user, positions[i].id),
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

    function getProtocolStats() public view returns (ProtocolLib.ProtocolStats memory) {
        return protocolStorage.getProtocolStats();
    }

    function getPrices(string memory _marketLong, string memory _marketShort) public view returns (uint256, uint256) {
        return (gmxPrices.getPrice(gmxMarkets.getMarket(_marketLong)), gmxPrices.getPrice(gmxMarkets.getMarket(_marketShort)));
    }

    function getEtherPrice() public view returns (uint256) {
        return gmxPrices.getPrice(gmxMarkets.getMarket("WETH"));
    }

    function getUserUsdcBalance(address _user) public view returns (uint256) {
        return IERC20(addressProvider.getAddress("USDC")).balanceOf(_user);
    }

    function isProxyNeeded(address _user, string calldata _marketLong, string calldata _marketShort) public view returns (bool, address) {
        MarketNeutralPosition[] memory marketNeutralPositions = getMarketNeutralPositionsData(_user);
        for(uint256 i = 0; i < marketNeutralPositions.length; i++) {
            if(marketNeutralPositions[i].isActive) {
                address proxy = marketNeutralPositions[i].proxy;
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