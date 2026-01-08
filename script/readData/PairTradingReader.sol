//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { PairTradingReader } from "../../src/core/bundles/readers/pairTradingReader.sol";
import { AddressProvider } from "../../src/core/config/AddressProvider.sol";
import { IReader } from "../../src/interfaces/GMX/IReader.sol";

contract PairTradingReaderTest is Script {
    AddressProvider public immutable addressProvider = AddressProvider(0x73836d093005Dafeb3446c6DB10f325a52ea6f0E);

    function run() public view {
        PairTradingReader pairTradingReader = PairTradingReader(addressProvider.getAddress("PairTradingReader"));
        console.log("PairTradingReader: ", address(pairTradingReader));
        console.log("ReaderGMX: ", addressProvider.getAddress("ReaderGMX"));
        address dataStore = addressProvider.getAddress("GMXDataStore");
        address referralStorage = addressProvider.getAddress("ReferralStorageGMX");
        console.log("Data Store: ", dataStore);
        console.log("Referral Storage: ", referralStorage);
        bytes32 positionKey = 0xa995a4bdb5964c8fe16c1ad684be8eee1c1c016c6ed16681a279b2aacbd615e8;
        address market = 0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B;
        
        console.log("Position Key: ", uint256(positionKey));
        console.log("Market: ", market);
        
        // Try to get basic position info first
        IReader.Position memory position;
        bool positionExists = false;
        
        try pairTradingReader.getPositionFromGMX(positionKey) returns (IReader.Position memory pos) {
            position = pos;
            positionExists = true;
            console.log("=== Basic Position Info ===");
            console.log("Account: ", position.account);
            console.log("Market: ", position.market);
            console.log("Collateral Token: ", position.collateralToken);
            console.log("Size in USD: ", position.sizeInUsd);
            console.log("Size in Tokens: ", position.sizeInTokens);
            console.log("Collateral Amount: ", position.collateralAmount);
            console.log("Is Long: ", position.isLong);
        } catch {
            console.log("ERROR: Could not get basic position info (position may not exist)");
            return;
        }
        
        // Try to get full PositionInfo
        try pairTradingReader.getPositionInfoFromGMX(positionKey, market) returns (IReader.PositionInfo memory positionInfo) {
            console.log("=== Full Position Info ===");
            console.log("Position Key: ", uint256(positionInfo.positionKey));
            
            console.log("=== PNL ===");
            console.log("Base PNL USD: ", uint256(positionInfo.basePnlUsd));
            console.log("Uncapped Base PNL USD: ", uint256(positionInfo.uncappedBasePnlUsd));
            console.log("PNL After Price Impact USD: ", uint256(positionInfo.pnlAfterPriceImpactUsd));
            
            console.log("=== Fees ===");
            console.log("Position Fee Amount: ", positionInfo.fees.positionFeeAmount);
            console.log("Total Cost Amount: ", positionInfo.fees.totalCostAmount);
            console.log("Borrowing Fee USD: ", positionInfo.fees.borrowing.borrowingFeeUsd);
            console.log("Borrowing Fee Amount: ", positionInfo.fees.borrowing.borrowingFeeAmount);
            console.log("Funding Fee Amount: ", positionInfo.fees.funding.fundingFeeAmount);
        } catch Error(string memory reason) {
            console.log("ERROR getting PositionInfo: ", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR getting PositionInfo: Low-level revert");
            console.logBytes(lowLevelData);
        }
    }
    // command to run the script:
    // forge script script/readData/PairTradingReader.sol:PairTradingReaderTest --rpc-url https://1rpc.io/arb -vvvv
}