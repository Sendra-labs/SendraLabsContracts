# GMX Funding Fees - Documentación para Proxies

## Resumen

Los **Funding Fees** en GMX son fees que se cobran o se pagan periódicamente basados en el desbalance entre posiciones long y short en un mercado. Cuando tienes una posición que está del lado "correcto" del desbalance, **recibes** funding fees (positivos). Cuando estás del lado "incorrecto", **pagas** funding fees (negativos).

Esta documentación explica cómo implementar una función en los proxies para reclamar funding fees cuando sean positivos y estén disponibles.

## Conceptos Clave

### ¿Qué son los Funding Fees?

- Los funding fees se calculan basados en el **funding factor** del mercado
- Se acumulan continuamente mientras tienes una posición abierta
- Pueden ser **positivos** (recibes tokens) o **negativos** (pagas tokens)
- Se pueden reclamar en cualquier momento si son positivos
- Los funding fees se almacenan en el DataStore de GMX

### Tipos de Tokens Claimables

En un mercado de GMX, puedes reclamar funding fees en dos tipos de tokens:

1. **Long Token** (`claimableLongTokenAmount`): Funding fees en el token long del mercado
2. **Short Token** (`claimableShortTokenAmount`): Funding fees en el token short del mercado

## Función de GMX: `claimFundingFees`

### Firma de la Función

```solidity
function claimFundingFees(
    address[] memory markets,
    address[] memory tokens,
    address receiver
) external
```

### Parámetros

- `markets`: Array de direcciones de mercados donde quieres reclamar funding fees
- `tokens`: Array de direcciones de tokens que quieres reclamar (debe tener la misma longitud que `markets`)
- `receiver`: Dirección que recibirá los funding fees reclamados

### Requisitos

- `markets.length` debe ser igual a `tokens.length`
- El `msg.sender` debe ser el account que tiene los funding fees claimables
- Debe haber funding fees positivos disponibles para reclamar

### Ejemplo de Uso

```solidity
address[] memory markets = new address[](1);
markets[0] = 0x...; // Market address

address[] memory tokens = new address[](1);
tokens[0] = 0x...; // Token address (WETH o USDC)

exchangeRouter.claimFundingFees(markets, tokens, receiver);
```

## Verificar Funding Fees Claimables

### Método 1: Usando DataStore (Directo)

Puedes verificar directamente en el DataStore de GMX:

```solidity
import "gmx-synthetics/utils/keys.sol";

bytes32 key = keys.claimableFundingAmountKey(market, token, account);
uint256 claimableAmount = dataStore.getUint(key);
```

### Método 2: Usando Reader (Recomendado)

Usando el Reader de GMX, puedes obtener información completa de la posición incluyendo funding fees:

```solidity
IReader.PositionInfo memory positionInfo = reader.getPositionInfo(
    dataStore,
    referralStorage,
    positionKey,
    prices,
    0,
    address(0),
    true
);

// Funding fees claimables
uint256 claimableLong = positionInfo.fees.funding.claimableLongTokenAmount;
uint256 claimableShort = positionInfo.fees.funding.claimableShortTokenAmount;
```

### Estructura PositionFundingFees

```solidity
struct PositionFundingFees {
    uint256 fundingFeeAmount;                    // Fee total (puede ser negativo)
    uint256 claimableLongTokenAmount;            // Claimable en long token
    uint256 claimableShortTokenAmount;           // Claimable en short token
}
```

## Implementación en el Proxy

### Función Propuesta

```solidity
function claimFundingFees(
    address[] memory markets,
    address[] memory tokens,
    address receiver
) public onlyOwner nonReentrant {
    require(markets.length == tokens.length, "Invalid arrays length");
    require(receiver != address(0), "Invalid receiver");
    
    address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
    
    // Llamar a claimFundingFees en ExchangeRouter
    IExchangeRouter(exchangeRouter).claimFundingFees(markets, tokens, receiver);
}
```

### Verificación Antes de Reclamar

Es recomendable verificar que hay funding fees claimables antes de intentar reclamarlos:

```solidity
function getClaimableFundingFees(
    address market,
    address token
) public view returns (uint256) {
    address dataStore = addressProvider.getAddress("GMXDataStore");
    bytes32 key = keccak256(abi.encode(
        keccak256("CLAIMABLE_FUNDING_AMOUNT"),
        market,
        token,
        address(this)
    ));
    
    return IDataStore(dataStore).getUint(key);
}

function canClaimFundingFees(
    address market,
    address token
) public view returns (bool) {
    uint256 claimable = getClaimableFundingFees(market, token);
    return claimable > 0;
}
```

## Consideraciones Importantes

### 1. Funding Fees Negativos

- Los funding fees pueden ser **negativos** (debes pagar)
- Solo debes reclamar cuando son **positivos**
- Si intentas reclamar cuando son negativos, la transacción fallará

### 2. Tokens del Mercado

- Para cada mercado, puedes reclamar en:
  - **Long Token**: Normalmente WETH en mercados ETH/USD
  - **Short Token**: Normalmente USDC en mercados ETH/USD
- Debes especificar qué token quieres reclamar en el array `tokens`

### 3. Gas Costs

- Reclamar funding fees tiene un costo de gas
- Solo vale la pena reclamar si el monto es significativo
- Considera implementar un threshold mínimo

### 4. Posiciones Market Neutral

En posiciones market neutral (long + short):
- Puedes recibir funding fees en un lado y pagar en el otro
- El neto puede ser positivo o negativo
- Debes verificar ambos lados antes de reclamar

## Ejemplo Completo de Implementación

```solidity
//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProxyManager } from "../storage/ProxyManager.sol";
import { IExchangeRouter } from "../../../interfaces/GMX/IExchangeRouter.sol";
import { IDataStore } from "gmx-synthetics/data/IDataStore.sol";

contract MarketNeutralProxy is ReentrancyGuard {
    
    AddressProvider public immutable addressProvider;
    address public marketNeutral;
    uint256 public immutable id;
    
    // ... resto del código ...
    
    /**
     * @notice Reclama funding fees de GMX para los mercados y tokens especificados
     * @param markets Array de direcciones de mercados
     * @param tokens Array de direcciones de tokens (debe coincidir con markets)
     * @param receiver Dirección que recibirá los funding fees
     */
    function claimFundingFees(
        address[] memory markets,
        address[] memory tokens,
        address receiver
    ) public onlyOwner nonReentrant {
        require(markets.length == tokens.length, "Invalid arrays length");
        require(receiver != address(0), "Invalid receiver");
        require(markets.length > 0, "Empty arrays");
        
        address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        
        // Verificar que hay funding fees claimables antes de reclamar
        address dataStore = addressProvider.getAddress("GMXDataStore");
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 claimable = _getClaimableFundingAmount(dataStore, markets[i], tokens[i]);
            require(claimable > 0, "No claimable funding fees");
        }
        
        // Reclamar funding fees
        IExchangeRouter(exchangeRouter).claimFundingFees(markets, tokens, receiver);
    }
    
    /**
     * @notice Obtiene el monto de funding fees claimables para un mercado y token
     * @param dataStore Dirección del DataStore de GMX
     * @param market Dirección del mercado
     * @param token Dirección del token
     * @return claimableAmount Monto claimable
     */
    function _getClaimableFundingAmount(
        address dataStore,
        address market,
        address token
    ) internal view returns (uint256) {
        bytes32 key = keccak256(abi.encode(
            keccak256("CLAIMABLE_FUNDING_AMOUNT"),
            market,
            token,
            address(this)
        ));
        
        return IDataStore(dataStore).getUint(key);
    }
    
    /**
     * @notice Verifica si hay funding fees claimables para un mercado y token
     * @param market Dirección del mercado
     * @param token Dirección del token
     * @return canClaim true si hay funding fees claimables
     * @return claimableAmount Monto claimable
     */
    function checkClaimableFundingFees(
        address market,
        address token
    ) public view returns (bool canClaim, uint256 claimableAmount) {
        address dataStore = addressProvider.getAddress("GMXDataStore");
        claimableAmount = _getClaimableFundingAmount(dataStore, market, token);
        canClaim = claimableAmount > 0;
    }
}
```

## Interfaz IExchangeRouter Actualizada

Necesitarás actualizar la interfaz `IExchangeRouter` para incluir la función:

```solidity
interface IExchangeRouter {
    function createOrder(IBaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external payable;
    function multicall(bytes[] calldata data) external payable;
    function claimFundingFees(address[] memory markets, address[] memory tokens, address receiver) external;
}
```

## Testing

### Casos de Prueba Importantes

1. **Reclamar funding fees positivos**: Debe funcionar correctamente
2. **Intentar reclamar cuando no hay funding fees**: Debe revertir
3. **Arrays de diferente longitud**: Debe revertir
4. **Receiver inválido (address(0))**: Debe revertir
5. **Múltiples mercados y tokens**: Debe procesar todos correctamente

### Ejemplo de Test

```solidity
function testClaimFundingFees() public {
    // Setup: Crear posición que genere funding fees positivos
    // ...
    
    // Verificar funding fees claimables
    (bool canClaim, uint256 amount) = proxy.checkClaimableFundingFees(market, token);
    assertTrue(canClaim);
    assertGt(amount, 0);
    
    // Reclamar
    address[] memory markets = new address[](1);
    markets[0] = market;
    
    address[] memory tokens = new address[](1);
    tokens[0] = token;
    
    uint256 balanceBefore = IERC20(token).balanceOf(receiver);
    proxy.claimFundingFees(markets, tokens, receiver);
    uint256 balanceAfter = IERC20(token).balanceOf(receiver);
    
    assertEq(balanceAfter - balanceBefore, amount);
}
```

## Referencias

- **GMX Documentation**: [GMX Docs](https://docs.gmx.io/)
- **ExchangeRouter Contract**: `lib/gmx-synthetics/contracts/router/ExchangeRouter.sol`
- **MarketUtils Library**: `lib/gmx-synthetics/contracts/market/MarketUtils.sol`
- **Keys Utils**: `lib/gmx-synthetics/utils/keys.ts` (para generar keys del DataStore)

## Notas Finales

- Los funding fees se acumulan continuamente, así que es beneficioso reclamarlos periódicamente
- Considera implementar un sistema de auto-claim o notificaciones cuando hay funding fees disponibles
- Los funding fees pueden variar significativamente dependiendo del desbalance del mercado
- En posiciones market neutral, el neto de funding fees puede ser positivo o negativo dependiendo de las condiciones del mercado

