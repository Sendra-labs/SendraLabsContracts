//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { BundlesRouter } from "./bundles/BundlesRouter.sol";
import { MarketNeutral } from "./bundles/executors/MarketNeutral.sol";
import { ProtocolLib } from "../lib/Protocol.lib.sol";
import { ProtocolStorage } from "./ProtocolStorage.sol";
import { GMXMarketsRegistry } from "./config/gmxMarkets.sol";
import { GMXPrices } from "../periphery/utilsGMX/GMXPrices.sol";

/**
 * @title Main
 * @author @Diego-AVZ
 * @notice Main contract for the protocol
 * @dev This contract is the main entry point for the protocol`s frontend
 */
contract Main is ReentrancyGuard {
    
    BundlesRouter public immutable bundlesRouter;
    MarketNeutral public immutable marketNeutral;
    ProtocolStorage public immutable protocolStorage;
    GMXMarketsRegistry public immutable gmxMarkets;
    GMXPrices public immutable gmxPrices;

    constructor(address _bundlesRouter, address payable _marketNeutral, address _protocolStorage, address _gmxMarkets, address _gmxPrices) {
        bundlesRouter = BundlesRouter(_bundlesRouter);
        marketNeutral = MarketNeutral(_marketNeutral);
        protocolStorage = ProtocolStorage(_protocolStorage);
        gmxMarkets = GMXMarketsRegistry(_gmxMarkets);
        gmxPrices = GMXPrices(_gmxPrices);
    }

    function openMarketNeutral(
        string calldata _marketLong,
        string calldata _marketShort,
        uint256 _totalEthAmount,
        uint256 _sizeDeltaUsdLong,
        uint256 _sizeDeltaUsdShort,
        uint256 _executionFee,
        uint256 _slippageBps
    ) public payable nonReentrant {

        (uint256 aceptablePriceLong, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_marketLong), true, true, _slippageBps);
        (uint256 aceptablePriceShort, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_marketShort), false, true, _slippageBps);
        
        bytes[] memory newPositionData = new bytes[](10);
        newPositionData[0] = abi.encode(_totalEthAmount);
        newPositionData[1] = abi.encode(true); // isNativeToken
        newPositionData[2] = abi.encode(gmxMarkets.getMarket(_marketLong));
        newPositionData[3] = abi.encode(gmxMarkets.getMarket(_marketShort));
        newPositionData[4] = abi.encode(_sizeDeltaUsdLong); 
        newPositionData[5] = abi.encode(_sizeDeltaUsdShort); 
        newPositionData[6] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_marketLong)));
        newPositionData[7] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_marketShort)));
        newPositionData[8] = abi.encode(_totalEthAmount * gmxPrices.getPrice(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336)); //checkThisLine Decimals
        newPositionData[9] = abi.encode(block.timestamp);
        newPositionData[10] = abi.encode(uint256(0));  // closeDate
        newPositionData[11] = abi.encode(uint256(0));  // finalUsdValue
        newPositionData[12] = abi.encode(uint256(0));  // finalPriceTokenLong
        newPositionData[13] = abi.encode(uint256(0));  // finalPriceTokenShort
        newPositionData[14] = abi.encode(int256(0));  // PNL
 
        /*__  market neutral positionParams  __*/
        //0  {0, totalEthAmount}
        //1  {2, isNativeToken}
        //2  {1, market Long}
        //3  {1, market Short}
        //4  {0, sizeDeltaUsdLong}
        //5  {0, sizeDeltaUsdShort}
        //6  {0, initialPriceTokenLong}
        //7  {0, initialPriceTokenShort}
        //8  {0, initialUsdValue}
        //9  {0, openDate}
        //10 {0, closeDate}
        //11 {0, finalUsdValue}
        //12 {0, finalPriceTokenLong}
        //13 {0, finalPriceTokenShort}
        //14 {0, PNL}

        uint256 _value = msg.value / 2;
        initializePosition(newPositionData, 0);
        openPositionSimpleParams(_totalEthAmount/2, _sizeDeltaUsdLong, aceptablePriceLong, _executionFee, _value, _marketLong, true);
        openPositionSimpleParams(_totalEthAmount/2, _sizeDeltaUsdShort, aceptablePriceShort, _executionFee, _value, _marketShort, false);

    }

    function closeMarketNeutral(
        uint256 positionId, 
        uint256 _executionFee, 
        uint256 _slippageBps
    ) public payable nonReentrant {
        uint256 _value = msg.value / 2;
        closeSideMarketNeutral(positionId, _executionFee, _slippageBps, _value, true);
        closeSideMarketNeutral(positionId, _executionFee, _slippageBps, _value, false);
    }

    function openPositionSimpleParams(
        uint256 _ethAmount,
        uint256 _sizeDeltaUsd,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        uint256 _value,
        string calldata _market,
        bool _isLong
    ) public payable {
        
        uint256[] memory _types = new uint256[](7); // [0, 0, 0, 0, 1, 1, 2]
        _types[0] = 0; // uint256
        _types[1] = 0; // uint256
        _types[2] = 0; // uint256
        _types[3] = 0; // uint256
        _types[4] = 1; // address
        _types[5] = 1; // address
        _types[6] = 2; // bool

        bytes[] memory _values = new bytes[](7); 
        _values[0] = abi.encode(_ethAmount);
        _values[1] = abi.encode(_sizeDeltaUsd);
        _values[2] = abi.encode(_acceptablePrice);
        _values[3] = abi.encode(_executionFee);
        _values[4] = abi.encode(gmxMarkets.getMarket(_market));
        _values[5] = abi.encode(msg.sender);
        _values[6] = abi.encode(_isLong);

        bundlesRouter.route{
            value: _value
        }(
            address(marketNeutral),
            0, 
            createParams(
                _types,
                _values
            )
        );
    }

    function createPositions(
        ProtocolLib.Position[] memory _positions, 
        bytes[] memory _newPositionData, 
        uint128 _positionType,
        uint256 _positionId
    ) public pure returns (
        ProtocolLib.Position[] memory
    ) {

        ProtocolLib.Position[] memory newPositions = new ProtocolLib.Position[](_positions.length + 1);
        
        ProtocolLib.Position memory newPosition = ProtocolLib.Position(_positionType, _positionId, 0, true, _newPositionData);
        
        for(uint256 i = 0; i < _positions.length; i++) {
            newPositions[i] = _positions[i];
        }
        
        newPositions[newPositions.length - 1] = newPosition;

        return newPositions;
    
    }

    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType) internal {

        protocolStorage.updateUserTransactionCount(msg.sender, 1);
        ProtocolLib.GlobalPosition memory userGlobalPosition = protocolStorage.getUser(msg.sender).globalPosition;
        
        uint256 positionId = userGlobalPosition.totalPositions + 1;

        protocolStorage.updateUserGlobalPosition(
            msg.sender, 
            ProtocolLib.GlobalPosition(
                positionId, // == totalPositions + 1
                userGlobalPosition.activePositions + 1,
                createPositions(userGlobalPosition.positions, _newPositionData, _positionType, positionId)
            )
        );

    }

    function createParams(uint256[] memory _types, bytes[] memory _values) public pure returns (bytes[] memory) {
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(_types);
        params[1] = abi.encode(_values);
        return params;
    }

    function getUserPosition(ProtocolLib.Position[] memory _positions, uint256 _positionId) public pure returns (ProtocolLib.Position memory, uint256 index) {
        for(uint256 i = 0; i < _positions.length; i++) {
            if(_positions[i].id == _positionId) {
                return (_positions[i], i);
            }
        }
        revert("Position not found");
    }

    function closeSideMarketNeutral(
        uint256 _positionId,
        uint256 _executionFee,
        uint256 _slippageBps,
        uint256 _value,
        bool _isLongSide
    ) public payable {
        ProtocolLib.User memory userData = protocolStorage.getUser(msg.sender);
        (ProtocolLib.Position memory position, ) = getUserPosition(userData.globalPosition.positions, _positionId);
        bytes[] memory positionData = position.positionData;
        /*__  market neutral positionParams  __*/
        //0 {0, totalEthAmount}
        //1 {2, isNativeToken}
        //2 {1, market Long}
        //3 {1, market Short}
        //4 {0, sizeDeltaUsdLong}
        //5 {0, sizeDeltaUsdShort}
        //6 {0, initialPriceTokenLong}
        //7 {0, initialPriceTokenShort}
        //8 {0, initialUsdValue
        //9 {0, openDate}
       
        uint256[] memory _types = new uint256[](7);
        _types[0] = 0; // uint256
        _types[1] = 0; // uint256
        _types[2] = 0; // uint256
        _types[3] = 1; // address
        _types[4] = 1; // address
        _types[5] = 2; // bool
        _types[6] = 0; // uint256 positionId
        address _market = abi.decode(_isLongSide ? positionData[2] : positionData[3], (address));
        
        (uint256 _acceptablePrice, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(
            _market,
            _isLongSide, 
            false, 
            _slippageBps
        );

        bytes[] memory _values = new bytes[](7);
        _values[0] = _isLongSide ? positionData[4] : positionData[5]; // sizeDeltaUsd
        _values[1] = abi.encode(_acceptablePrice);
        _values[2] = abi.encode(_executionFee);
        _values[3] = abi.encode(_market);
        _values[4] = abi.encode(msg.sender); // receier
        _values[5] = abi.encode(_isLongSide); // isLong
        _values[6] = abi.encode(_positionId); // positionId

        bundlesRouter.route{
            value: _value
        }(
            address(marketNeutral),
            1, 
            createParams(
                _types,
                _values
            )
        );

    } 

    function closePositionSimpleParams(
        uint256 _positionId,
        uint256 _executionFee,
        uint256 _slippageBps
    ) public payable nonReentrant{
        ProtocolLib.User memory userData = protocolStorage.getUser(msg.sender);
        (ProtocolLib.Position memory position, ) = getUserPosition(userData.globalPosition.positions, _positionId);
        bytes[] memory positionData = position.positionData;

        uint256[] memory _types = new uint256[](6);
        _types[0] = 0; // uint256
        _types[1] = 0; // uint256
        _types[2] = 0; // uint256
        _types[3] = 1; // address
        _types[4] = 1; // address
        _types[5] = 2; // bool

        address marketAddress = abi.decode(positionData[4], (address));
        bool isLong = abi.decode(positionData[3], (bool));

        bytes[] memory _values = new bytes[](6);
        _values[0] = positionData[2]; // sizeDeltaUsd
        // cuando registremos el positionType en upgradeableLib el positionData[2] debe ser el sizeDeltaUsd
        // el elemento 2 de la lista de PositionParam sera algo asi {paramType: 0, paramValue: sizeDeltaUsd} // uint256
        // ctrl + f en main y en marketNeutral "ref0001" para ver el sizeDeltaUsd donde se guarda
        (uint256 _acceptablePrice, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(marketAddress, isLong, false, _slippageBps);
        _values[1] = abi.encode(_acceptablePrice);
        _values[2] = abi.encode(_executionFee); 
        _values[3] = positionData[4]; // market
        _values[4] = abi.encode(msg.sender); // receier
        _values[5] = positionData[3]; // isLong

        bundlesRouter.route{
            value: msg.value
        }(
            address(marketNeutral),
            1, 
            createParams(
                _types,
                _values
            )
        );
    }
/*
    function createDeFiParam(bytes memory _value, uint8 _type) public pure returns (ProtocolLib.DeFiParam memory) {
        if(_type == 1) return abi.decode(_value, (uint256));
        else if(_type == 2) return abi.decode(_value, (int256));
        else if(_type == 3) return abi.decode(_value, (bool));
        else if(_type == 4) return abi.decode(_value, (bytes));
        else if(_type == 5) return abi.decode(_value, (address));
        else if(_type == 6) abi.decode(_value, (bytes32));
        else revert InvalidType();
    }
*/
    error InvalidType();

}