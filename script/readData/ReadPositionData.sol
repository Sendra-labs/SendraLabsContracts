//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { IReader } from "../../src/interfaces/GMX/IReader.sol";
import { GMXPrices } from "../../src/periphery/utilsGMX/GMXPrices.sol";
import { AddressProvider } from "../../src/core/config/AddressProvider.sol";

/**
 * @title ReadPositionData
 * @notice Script para leer datos completos de una posición de GMX usando el Reader directamente
 * @dev Muestra PNL, fees, price impact y toda la información relevante
 * 
 * USO:
 * 1. Abre una posición en GMX
 * 2. Obtén el positionKey (puedes calcularlo o leerlo de los eventos)
 * 3. Ejecuta: forge script script/readData/ReadPositionData.sol:ReadPositionData --rpc-url <RPC_URL> -vvvv
 * 
 * Para calcular el positionKey:
 * positionKey = keccak256(abi.encode(account, market, collateralToken, isLong))
 */
contract ReadPositionData is Script {
    // Direcciones de GMX (Arbitrum)
    IReader public constant READER_GMX = IReader(0x470fbC46bcC0f16532691Df360A07d8Bf5ee0789);
    address public constant DATASTORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    address public constant REFERRAL_STORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
    
    // AddressProvider para obtener GMXPrices
    AddressProvider public constant ADDRESS_PROVIDER = AddressProvider(0x73836d093005Dafeb3446c6DB10f325a52ea6f0E);

    function run() public view {
        // ========== CONFIGURACIÓN ==========
        // OPCIÓN 1: Pasa el positionKey directamente
        bytes32 positionKey = 0x3a2f596025ad55af54e9b8cccbf8e12a9f8a55b20f9d065b203889fa5591bf15; // ← CAMBIA ESTO
        
        // OPCIÓN 2: Calcula el positionKey desde los datos de la posición
        // Descomenta y completa estos valores:
        // address account = 0xaD2215Ceb5e1371a5e9f1BaBd56eDb6052e9307D; // ← Dirección de la cuenta
        // address market = 0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B; // ← Dirección del market
        // address collateralToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // ← Token de colateral
        // bool isLong = true; // ← true para LONG, false para SHORT
        // positionKey = calculatePositionKey(account, market, collateralToken, isLong);
        
        // ====================================
        
        console.log("\n==========================================");
        console.log("LECTURA DE POSICION GMX");
        console.log("==========================================\n");
        console.log("Reader GMX: ", address(READER_GMX));
        console.log("DataStore: ", DATASTORE);
        console.log("Position Key (input): ", uint256(positionKey));
        console.log("\n");
        
        // ========== 1. INFORMACIÓN BÁSICA DE LA POSICIÓN ==========
        console.log("info basica");
        IReader.Position memory position;
        bool positionExists = false;
        bytes32 calculatedPositionKey;
        
        try READER_GMX.getPosition(DATASTORE, positionKey) returns (IReader.Position memory pos) {
            position = pos;
            
            console.log("\n=== RESULTADO DE getPosition() ===");
            console.log("Account: ", pos.account);
            console.log("Market: ", pos.market);
            console.log("Collateral Token: ", pos.collateralToken);
            console.log("Size in USD (raw, 30 decimals): ", pos.sizeInUsd);
            console.log("Size in Tokens (raw): ", pos.sizeInTokens);
            console.log("Collateral Amount (raw): ", pos.collateralAmount);
            console.log("Pending Impact Amount (raw): ", uint256(pos.pendingImpactAmount > 0 ? pos.pendingImpactAmount : -pos.pendingImpactAmount));
            console.log("Borrowing Factor (raw): ", pos.borrowingFactor);
            console.log("Funding Fee Amount Per Size (raw): ", pos.fundingFeeAmountPerSize);
            console.log("Long Token Claimable Funding Amount Per Size (raw): ", pos.longTokenClaimableFundingAmountPerSize);
            console.log("Short Token Claimable Funding Amount Per Size (raw): ", pos.shortTokenClaimableFundingAmountPerSize);
            console.log("Increased At Time: ", pos.increasedAtTime);
            console.log("Decreased At Time: ", pos.decreasedAtTime);
            console.log("Is Long: ", pos.isLong);
            console.log("\n");
            
            // Verificar si la posición es válida
            if (pos.account == address(0) || pos.sizeInUsd == 0) {
                console.log("La posicion esta vacia o cerrada");
                console.log("El positionKey usado: ", uint256(positionKey));
                console.log("Intenta calcular el positionKey correcto desde:");
                console.log("  - Account");
                console.log("  - Market");
                console.log("  - Collateral Token");
                console.log("  - Is Long");
                console.log("\nO usa getAccountPositions() para listar todas las posiciones de una cuenta.");
                return;
            }
            
            positionExists = true;
            
            // Calcular el positionKey correcto desde los datos de la posición
            calculatedPositionKey = calculatePositionKey(pos.account, pos.market, pos.collateralToken, pos.isLong);
            console.log("Position Key usado: ", uint256(positionKey));
            console.log("Position Key calculado desde datos: ", uint256(calculatedPositionKey));
            
            // Si el positionKey de entrada no coincide, usar el calculado
            if (calculatedPositionKey != positionKey) {
                console.log("El positionKey de entrada no coincide. Usando el calculado.");
                positionKey = calculatedPositionKey;
            }
            
            console.log("\n=== DATOS CONVERTIDOS A FORMATO LEGIBLE ===");
            
            // Convertir sizeInUsd a formato legible
            // sizeInUsd está en 30 decimals, necesitamos convertirlo a USD normal
            // Dividir por 1e30 para convertir de 30 decimals a USD (sin decimals)
            uint256 sizeInUsdReadable = position.sizeInUsd / 1e30;
            console.log("Size in USD: ", sizeInUsdReadable, " USD");
            
            // Collateral amount está en token decimals (6 para USDC, 18 para WETH)
            // Necesitamos saber los decimals del token para convertir correctamente
            uint256 collateralReadable;
            if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC
                collateralReadable = position.collateralAmount / 1e6; // USDC tiene 6 decimals
                console.log("Collateral Amount: ", collateralReadable, " USDC");
            } else {
                // Asumimos WETH (18 decimals)
                collateralReadable = position.collateralAmount / 1e18;
                console.log("Collateral Amount: ", collateralReadable, " tokens (assuming 18 decimals)");
            }
            
            // Convertir pendingImpactAmount (está en 30 decimals)
            int256 pendingImpactUsd = position.pendingImpactAmount;
            uint256 pendingImpactReadable = uint256(pendingImpactUsd > 0 ? pendingImpactUsd : -pendingImpactUsd) / 1e30;
            console.log("Pending Impact Amount: ", pendingImpactReadable, pendingImpactUsd >= 0 ? " USD" : " USD (negativo)");
            
            // Tiempo que lleva abierta la posición
            if (position.increasedAtTime > 0) {
                uint256 currentTime = block.timestamp;
                uint256 timeOpen = currentTime - position.increasedAtTime;
                uint256 hoursOpen = timeOpen / 3600;
                uint256 daysOpen = hoursOpen / 24;
                uint256 minutesOpen = (timeOpen % 3600) / 60;
                console.log("Tiempo abierta: ", daysOpen, " dias");
                console.log("Horas: ", hoursOpen % 24);
                console.log("Minutos: ", minutesOpen);
            }
            
        } catch Error(string memory reason) {
            console.log("ERROR getting basic position: ", reason);
            return;
        } catch {
                console.log("ERROR: Position does not exist or cannot be read");
                console.log("Verifica que:");
                console.log("  1. La posicion este abierta (GMX elimina posiciones cerradas)");
                console.log("  2. El positionKey sea correcto");
            return;
        }
        
        if (!positionExists || position.sizeInUsd == 0) {
            console.log("\nERROR: La posicion no existe o esta cerrada");
            console.log("GMX elimina las posiciones del DataStore cuando se cierran completamente.");
            return;
        }
        
        // Usar el market de la posición
        address market = position.market;
        console.log("\nUsando market de la posicion: ", market);
        console.log("\n");
        
        // ========== 2. OBTENER PRECIOS DEL MERCADO ==========
        console.log("=== 2. OBTENIENDO PRECIOS DEL MERCADO ===");
        IReader.MarketPrices memory prices;
        
        try this.getMarketPrices(market) returns (IReader.MarketPrices memory marketPrices) {
            prices = marketPrices;
            console.log("Index Token Price (30 decimals): ", prices.indexTokenPrice.min);
            console.log("Long Token Price (30 decimals): ", prices.longTokenPrice.min);
            console.log("Short Token Price (30 decimals): ", prices.shortTokenPrice.min);
        } catch {
            console.log("ERROR obteniendo precios. Usando precios por defecto (puede fallar getPositionInfo)");
            // Crear precios por defecto (no recomendado, pero intentamos)
            prices = IReader.MarketPrices({
                indexTokenPrice: IReader.Price({ min: 1e30, max: 1e30 }),
                longTokenPrice: IReader.Price({ min: 1e30, max: 1e30 }),
                shortTokenPrice: IReader.Price({ min: 1e30, max: 1e30 })
            });
        }
        
        console.log("\n");
        
        // ========== 3. INFORMACIÓN COMPLETA CON PNL Y FEES ==========
        console.log("=== 3. PNL Y FEES (TIEMPO REAL) ===");
        console.log("Usando Position Key: ", uint256(positionKey));
        console.log("Account: ", position.account);
        console.log("Market: ", position.market);
        console.log("Collateral Token: ", position.collateralToken);
        console.log("Is Long: ", position.isLong);
        console.log("Size in USD: ", position.sizeInUsd);
        console.log("\n");
        
        // Intentar con el positionKey calculado (más confiable)
        // Primero intentamos con usePositionSizeAsSizeDeltaUsd = true
        bool success = false;
        IReader.PositionInfo memory positionInfo;
        
        // Intento 1: usePositionSizeAsSizeDeltaUsd = true, sizeDeltaUsd = 0
        try READER_GMX.getPositionInfo(
            DATASTORE,
            REFERRAL_STORAGE,
            positionKey,
            prices,
            0,
            address(0),
            true
        ) returns (IReader.PositionInfo memory info) {
            positionInfo = info;
            success = true;
            console.log("getPositionInfo exitoso (metodo 1: usePositionSizeAsSizeDeltaUsd = true)");
        } catch {
            // Intento 2: usePositionSizeAsSizeDeltaUsd = false, sizeDeltaUsd = position.sizeInUsd
            try READER_GMX.getPositionInfo(
                DATASTORE,
                REFERRAL_STORAGE,
                positionKey,
                prices,
                position.sizeInUsd,  // Usar el size completo de la posición
                address(0),
                false
            ) returns (IReader.PositionInfo memory info) {
                positionInfo = info;
                success = true;
                console.log("getPositionInfo exitoso (metodo 2: sizeDeltaUsd = position.sizeInUsd)");
            } catch {
                // Intento 3: usePositionSizeAsSizeDeltaUsd = false, sizeDeltaUsd = 0
                try READER_GMX.getPositionInfo(
                    DATASTORE,
                    REFERRAL_STORAGE,
                    positionKey,
                    prices,
                    0,
                    address(0),
                    false
                ) returns (IReader.PositionInfo memory info) {
                    positionInfo = info;
                    success = true;
                    console.log("getPositionInfo exitoso (metodo 3: usePositionSizeAsSizeDeltaUsd = false, sizeDeltaUsd = 0)");
                } catch Error(string memory reason) {
                    console.log("ERROR en todos los metodos: ", reason);
                } catch (bytes memory lowLevelData) {
                    console.log("ERROR en todos los metodos: Low-level revert");
                    console.logBytes(lowLevelData);
                }
            }
        }
        
        if (success) {
            
            // PNL
            console.log("\n--- PNL ---");
            int256 basePnlUsd = positionInfo.basePnlUsd;
            int256 uncappedBasePnlUsd = positionInfo.uncappedBasePnlUsd;
            int256 pnlAfterPriceImpactUsd = positionInfo.pnlAfterPriceImpactUsd;
            
            console.log("Base PNL USD (30 decimals): ", uint256(basePnlUsd > 0 ? basePnlUsd : -basePnlUsd));
            console.log("Base PNL USD (sign): ", basePnlUsd >= 0 ? "POSITIVO" : "NEGATIVO");
            
            // Convertir a formato legible (30 decimals -> 0 decimals para USD)
            uint256 basePnlReadable = uint256(basePnlUsd > 0 ? basePnlUsd : -basePnlUsd) / 1e30;
            console.log("Base PNL USD (readable): ", basePnlReadable, basePnlUsd >= 0 ? " USD (ganancia)" : " USD (perdida)");
            
            uint256 uncappedPnlReadable = uint256(uncappedBasePnlUsd > 0 ? uncappedBasePnlUsd : -uncappedBasePnlUsd) / 1e30;
            console.log("Uncapped Base PNL USD (readable): ", uncappedPnlReadable, " USD");
            
            uint256 pnlAfterImpactReadable = uint256(pnlAfterPriceImpactUsd > 0 ? pnlAfterPriceImpactUsd : -pnlAfterPriceImpactUsd) / 1e30;
            console.log("PNL After Price Impact USD (readable): ", pnlAfterImpactReadable, " USD");
            
            // FEES
            console.log("\n--- FEES ---");
            IReader.PositionFees memory fees = positionInfo.fees;
            
            console.log("Position Fee Amount (raw): ", fees.positionFeeAmount);
            console.log("Total Cost Amount (raw): ", fees.totalCostAmount);
            
            // Convertir fees a formato legible
            // fees están en token decimals (6 para USDC, 18 para WETH)
            uint256 positionFeeReadable;
            uint256 totalCostReadable;
            if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC
                positionFeeReadable = fees.positionFeeAmount / 1e6;
                totalCostReadable = fees.totalCostAmount / 1e6;
                console.log("Position Fee Amount (readable): ", positionFeeReadable, " USDC");
                console.log("Total Cost Amount (readable): ", totalCostReadable, " USDC");
            } else {
                positionFeeReadable = fees.positionFeeAmount / 1e12;
                totalCostReadable = fees.totalCostAmount / 1e12;
                console.log("Position Fee Amount (readable, assuming 18 decimals): ", positionFeeReadable / 1e6, " tokens");
                console.log("Total Cost Amount (readable, assuming 18 decimals): ", totalCostReadable / 1e6, " tokens");
            }
            
            // Borrowing Fees
            console.log("\n--- Borrowing Fees ---");
            console.log("Borrowing Fee USD (30 decimals): ", fees.borrowing.borrowingFeeUsd);
            console.log("Borrowing Fee Amount (raw): ", fees.borrowing.borrowingFeeAmount);
            
            // Convertir borrowing fee a formato legible
            // El valor está en 30 decimals, pero puede ser muy pequeño
            // Para mostrar correctamente, primero multiplicamos por 1e6 para tener precision
            // y luego dividimos por 1e30 para obtener USD con 6 decimales de precision
            uint256 borrowingFeeUsdScaled = (fees.borrowing.borrowingFeeUsd * 1e6) / 1e30;
            console.log("Borrowing Fee USD (readable, con 6 decimales): ", borrowingFeeUsdScaled / 1e6);
            console.log("Decimales: ", borrowingFeeUsdScaled % 1e6);
            console.log(" USD");
            
            // Tambien mostrar el valor raw para debug
            if (fees.borrowing.borrowingFeeUsd > 0 && fees.borrowing.borrowingFeeUsd < 1e30) {
                console.log("borrowing fee es muy pequeno");
            }
            
            if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC
                uint256 borrowingFeeAmountReadable = fees.borrowing.borrowingFeeAmount / 1e6;
                console.log("Borrowing Fee Amount (readable): ", borrowingFeeAmountReadable, " USDC");
            } else {
                uint256 borrowingFeeAmountReadable = fees.borrowing.borrowingFeeAmount / 1e12;
                console.log("Borrowing Fee Amount (readable, assuming 18 decimals): ", borrowingFeeAmountReadable / 1e6, " tokens");
            }
            
            // Funding Fees
            console.log("\n--- Funding Fees ---");
            console.log("Funding Fee Amount (raw): ", fees.funding.fundingFeeAmount);
            console.log("Claimable Long Token Amount (raw): ", fees.funding.claimableLongTokenAmount);
            console.log("Claimable Short Token Amount (raw): ", fees.funding.claimableShortTokenAmount);
            
            if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC
                uint256 fundingFeeReadable = fees.funding.fundingFeeAmount / 1e6;
                console.log("Funding Fee Amount (readable): ", fundingFeeReadable, " USDC");
            } else {
                uint256 fundingFeeReadable = fees.funding.fundingFeeAmount / 1e12;
                console.log("Funding Fee Amount (readable, assuming 18 decimals): ", fundingFeeReadable / 1e6, " tokens");
            }
            
            // Collateral Token Price
            console.log("\n--- Precios ---");
            console.log("Collateral Token Price (30 decimals): ", fees.collateralTokenPrice.min);
            uint256 collateralPriceReadable = fees.collateralTokenPrice.min / 1e30;
            console.log("Collateral Token Price (readable): ", collateralPriceReadable, " USD");
            
            // ========== 4. RESUMEN Y CALCULOS ==========
            console.log("\n=== 4. RESUMEN Y ANALISIS ===");
            
            // Calcular PNL como porcentaje
            uint256 sizeInUsdForCalc = position.sizeInUsd / 1e30;
            if (sizeInUsdForCalc > 0) {
                uint256 pnlPercent = (uint256(basePnlUsd > 0 ? basePnlUsd : -basePnlUsd) * 10000) / sizeInUsdForCalc;
                console.log("PNL como porcentaje: ", pnlPercent / 100);
                console.log("Decimales: ", pnlPercent % 100);
            }
            
            // Calcular fees totales como porcentaje
            if (sizeInUsdForCalc > 0) {
                // Convertir funding fee a USD
                // fundingFeeAmount está en token decimals (6 para USDC, 18 para WETH)
                // collateralTokenPrice está en 30 decimals
                // Para obtener USD: (amount * price) / (tokenDecimals * priceDecimals)
                uint256 fundingFeeUsd;
                if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC (6 decimals)
                    fundingFeeUsd = (fees.funding.fundingFeeAmount * fees.collateralTokenPrice.min) / 1e36; // 6 + 30 = 36 decimals
                } else { // WETH (18 decimals)
                    fundingFeeUsd = (fees.funding.fundingFeeAmount * fees.collateralTokenPrice.min) / 1e48; // 18 + 30 = 48 decimals
                }
                // borrowingFeeUsd ya está en 30 decimals, convertir a USD normal
                uint256 borrowingFeeUsdNormal = fees.borrowing.borrowingFeeUsd / 1e30;
                uint256 totalFeesUsd = borrowingFeeUsdNormal + fundingFeeUsd;
                uint256 feesPercent = (totalFeesUsd * 10000) / sizeInUsdForCalc;
                console.log("Fees totales como porcentaje: ", feesPercent / 100);
                console.log("Decimales: ", feesPercent % 100);
            }
            
            // Tiempo que lleva abierta la posición
            if (position.increasedAtTime > 0) {
                uint256 currentTime = block.timestamp;
                uint256 timeOpen = currentTime - position.increasedAtTime;
                uint256 hoursOpen = timeOpen / 3600;
                uint256 daysOpen = hoursOpen / 24;
                uint256 minutesOpen = (timeOpen % 3600) / 60;
                console.log("\nTiempo abierta: ", daysOpen, " dias");
                console.log("Horas: ", hoursOpen % 24);
                console.log("Minutos: ", minutesOpen);
            }
            
            console.log("\n=== 5. VALOR ESPERADO AL CERRAR ===");
            console.log("(Estimacion basada en PNL actual)");
            
            uint256 initialCollateral;
            if (position.collateralToken == address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)) { // USDC
                initialCollateral = position.collateralAmount / 1e6;
            } else {
                initialCollateral = position.collateralAmount / 1e18;
            }
            
            int256 estimatedOutput = int256(initialCollateral) + int256(basePnlReadable);
            
            // Restar fees que se cobraran al cerrar (0.06% position fee)
            uint256 estimatedCloseFee = (sizeInUsdForCalc * 6) / 10000; // 0.06%
            estimatedOutput -= int256(estimatedCloseFee);
            
            console.log("Collateral inicial: ", initialCollateral, " tokens");
            console.log("PNL actual: ", basePnlReadable, basePnlUsd >= 0 ? " USD" : " USD");
            console.log("Position fee al cerrar (estimada): ", estimatedCloseFee, " USD");
            uint256 outputEstimate = estimatedOutput > 0 ? uint256(estimatedOutput) : 0;
            console.log("Output estimado al cerrar: ", outputEstimate, " tokens");
            console.log("\nNOTA: Este es solo una estimacion. El output real dependera de:");
            console.log("   - Price impact al cerrar");
            console.log("   - Funding fees acumuladas hasta el cierre");
            console.log("   - Borrowing fees acumuladas hasta el cierre");
            console.log("   - Precio de ejecucion real");
        } else {
            console.log("\nNo se pudo obtener PositionInfo con ningun metodo");
            console.log("La posicion existe pero getPositionInfo() falla.");
            console.log("Esto puede deberse a:");
            console.log("  1. Problemas con los precios del mercado");
            console.log("  2. La posicion esta en un estado inconsistente");
            console.log("  3. Problemas con el ReferralStorage");
        }
        
        console.log("\n==========================================");
        console.log("   FIN DE LECTURA");
        console.log("==========================================\n");
    }
    //command to run the script: forge script script/readData/ReadPositionData.sol:ReadPositionData --rpc-url https://1rpc.io/arb -vvvv
    /**
     * @notice Helper function para obtener precios del mercado usando GMXPrices
     * @dev Esta función necesita ser external para poder hacer try-catch
     */
    function getMarketPrices(address market) external view returns (IReader.MarketPrices memory) {
        GMXPrices gmxPrices = GMXPrices(ADDRESS_PROVIDER.getAddress("GMXPrices"));
        
        (uint256 indexPrice, uint256 longPrice, uint256 shortPrice) = gmxPrices.getMarketPrices(market);
        
        return IReader.MarketPrices({
            indexTokenPrice: IReader.Price({
                min: indexPrice,
                max: indexPrice
            }),
            longTokenPrice: IReader.Price({
                min: longPrice,
                max: longPrice
            }),
            shortTokenPrice: IReader.Price({
                min: shortPrice,
                max: shortPrice
            })
        });
    }
    
    // Helper function para calcular position key
    // positionKey = keccak256(abi.encode(account, market, collateralToken, isLong))
    function calculatePositionKey(
        address account,
        address market,
        address collateralToken,
        bool isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(account, market, collateralToken, isLong));
    }
}
//   forge script script/readData/ReadPositionData.sol:ReadPositionData --rpc-url https://1rpc.io/arb -vvvv
