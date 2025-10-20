# 🏗️ ARQUITECTURA DEL PROTOCOLO - SISTEMA DE EXTENSIBILIDAD DINÁMICA

## 📋 TABLA DE CONTENIDOS
1. [Visión General](#visión-general)
2. [Por Qué Este Diseño](#por-qué-este-diseño)
3. [Sistema de Encoding/Decoding Dinámico](#sistema-de-encodingdecoding-dinámico)
4. [Flujo Completo de Ejecución](#flujo-completo-de-ejecución)
5. [Comparación: Arquitectura Tradicional vs Esta Arquitectura](#comparación-arquitectura-tradicional-vs-esta-arquitectura)
6. [Sistema de Posiciones Dinámicas](#sistema-de-posiciones-dinámicas)
7. [Casos de Uso Futuros](#casos-de-uso-futuros)

---

## 🎯 VISIÓN GENERAL

Este protocolo es un **agregador/orquestador de estrategias DeFi** con un sistema de extensibilidad sin precedentes que permite:

✅ **Agregar nuevas estrategias sin redeployment de contratos**  
✅ **Soportar cualquier combinación de parámetros**  
✅ **Registrar datos de posición flexibles en formato bytes**  
✅ **Sistema de governance descentralizado con consenso democrático**  
✅ **Arquitectura modular con separación de concerns**

### 🏛️ Componentes Principales

```
Main.sol (Entry Point)
    ↓
BundlesRouter.sol (Orchestrator)
    ↓
MarketNeutral.sol (Strategy Executor)
    ↓
GMX Protocol (External DeFi Protocol)

ProtocolStorage.sol (Data Layer)
    ↑
UpgradeableLib.sol (Dynamic Schemas)

DecoderLib.sol (Universal Decoder)
ProtocolLib.sol (Type Definitions)
Roles.sol (Access Control with Consensus)
```

---

## 🤔 POR QUÉ ESTE DISEÑO

### ❌ Problema con Arquitecturas Tradicionales

**Arquitectura Tradicional (Ejemplo: GMX nativo):**

```solidity
// Si quieres agregar una nueva estrategia, necesitas:

contract NewStrategy {
    function executeStrategyA(
        address market,
        uint256 amount,
        bool isLong
    ) external { }
    
    function executeStrategyB(
        address market,
        uint256 collateral,
        uint256 leverage,
        address[] calldata swapPath
    ) external { }
    
    function executeStrategyC(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 minAmountB,
        bytes calldata extraData
    ) external { }
}
```

**Problemas:**
1. ❌ Cada nueva estrategia → **nuevo contrato** → **nuevo deployment** → **nuevo gas**
2. ❌ Cada función tiene firma diferente → **no hay interface unificado**
3. ❌ Frontend debe conocer todas las firmas → **mantenimiento pesado**
4. ❌ No puedes agregar estrategias sin upgrade del sistema completo
5. ❌ Difícil de escalar: 50 estrategias = 50 funciones diferentes

---

### ✅ Nuestra Solución: Sistema Universal de Parámetros

**Nuestro Diseño:**

```solidity
// UNA SOLA FUNCIÓN para TODAS las estrategias presentes y futuras
contract BundlesRouter {
    function route(
        address _bundle,           // Qué executor usar
        uint8 functionId,          // Qué función del executor
        bytes[] calldata _data     // Parámetros universales
    ) external payable;
}
```

**Ventajas:**
1. ✅ **Una función para gobernarlas a todas**
2. ✅ Agregar nueva estrategia = **deploy solo del nuevo executor**
3. ✅ **Interface unificado** para frontend
4. ✅ **Sistema extensible infinitamente**
5. ✅ 1000 estrategias = **misma función route()**

---

## 🔧 SISTEMA DE ENCODING/DECODING DINÁMICO

### 📦 La Estructura DeFiParam

```solidity
struct DeFiParam {
    uint8 _type;      // Tipo del parámetro (0=address, 1=uint256, 2=int256, 3=bool, 4=bytes)
    bytes v;          // bytesValue   - datos arbitrarios en bytes
    address w;        // addressValue - direcciones de wallets/contratos
    uint256 x;        // uintValue    - números sin signo
    int256 y;         // intValue     - números con signo (PnL, deltas, etc)
    bool z;           // boolValue    - flags booleanos
}
```

**¿Por qué esta estructura?**

En lugar de tener múltiples structs para cada tipo de parámetro:
```solidity
// ❌ Enfoque tradicional - múltiples structs
struct AddressParam { address value; }
struct UintParam { uint256 value; }
struct BoolParam { bool value; }
// ... necesitarías 5 structs diferentes
```

**Tenemos UN SOLO struct que puede representar CUALQUIER tipo:**
```solidity
// ✅ Nuestro enfoque - struct universal
DeFiParam memory param;
if (tipo == address) → usa param.w
if (tipo == uint256) → usa param.x
if (tipo == int256) → usa param.y
if (tipo == bool)    → usa param.z
if (tipo == bytes)   → usa param.v
```

---

### 🔄 Flujo de Encoding (Main.sol → BundlesRouter)

#### Paso 1: Usuario llama función en Main.sol

```solidity
// Main.sol
function openPositionSimpleParams(
    uint256 _ethAmount,        // 0.5 ETH
    uint256 _sizeDeltaUsd,     // $1000 USD
    uint256 _acceptablePrice,  // $2000
    uint256 _executionFee,     // 0.001 ETH
    address _market,           // 0xABC...
    bool _isLong               // true
) public payable nonReentrant {
```

#### Paso 2: Definir TIPOS de cada parámetro

```solidity
    // Definimos el "schema" de los parámetros
    uint256[] memory _types = new uint256[](7);
    _types[0] = 1; // uint256 (ethAmount)
    _types[1] = 1; // uint256 (sizeDeltaUsd)
    _types[2] = 1; // uint256 (acceptablePrice)
    _types[3] = 1; // uint256 (executionFee)
    _types[4] = 0; // address (market)
    _types[5] = 0; // address (msg.sender)
    _types[6] = 3; // bool    (isLong)
```

#### Paso 3: Encodear VALORES

```solidity
    // Encodeamos cada valor a bytes
    bytes[] memory _values = new bytes[](7); 
    _values[0] = abi.encode(_ethAmount);      // 0.5 ETH → bytes
    _values[1] = abi.encode(_sizeDeltaUsd);   // 1000   → bytes
    _values[2] = abi.encode(_acceptablePrice); // 2000   → bytes
    _values[3] = abi.encode(_executionFee);   // 0.001  → bytes
    _values[4] = abi.encode(_market);         // 0xABC  → bytes
    _values[5] = abi.encode(msg.sender);      // 0x123  → bytes
    _values[6] = abi.encode(_isLong);         // true   → bytes
```

#### Paso 4: Crear paquete de parámetros

```solidity
    // Empaquetamos TODO en un array de 2 elementos
    function createParams(uint256[] memory _types, bytes[] memory _values) 
        public pure returns (bytes[] memory) 
    {
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(_types);   // [1,1,1,1,0,0,3] → bytes
        params[1] = abi.encode(_values);  // [bytes,bytes,...] → bytes
        return params;
    }
```

**Resultado:**
```
params[0] = bytes que contiene: [1, 1, 1, 1, 0, 0, 3]
params[1] = bytes que contiene: [0.5_ETH_bytes, 1000_bytes, 2000_bytes, ...]
```

---

### 🔓 Flujo de Decoding (BundlesRouter → MarketNeutral)

#### Paso 1: BundlesRouter llama al executor

```solidity
// BundlesRouter.sol
function route(address _bundle, uint8 functionId, bytes[] calldata _data) 
    public payable 
{
    // Llamada dinámica al executor
    _bundle.call{value: msg.value}(
        abi.encodeWithSelector(
            bytes4(keccak256("execute(uint8,bytes[])")),
            functionId,  // 0 = openPositionWithEther
            _data        // [params[0], params[1]]
        )
    );
}
```

#### Paso 2: DecoderLib decodifica los parámetros

```solidity
// DecoderLib.sol
function decoder(bytes[] calldata _data) 
    external pure returns(ProtocolLib.DeFiParam[] memory)
{
    // 1. Decodificar array de tipos
    uint256[] memory paramsTypes = abi.decode(_data[0], (uint256[]));
    // paramsTypes = [1, 1, 1, 1, 0, 0, 3]
    
    // 2. Preparar array de DeFiParams
    ProtocolLib.DeFiParam[] memory params = new ProtocolLib.DeFiParam[](paramsTypes.length);
    
    // 3. Decodificar cada valor según su tipo
    uint256 offset = 0;
    for(uint256 i = 0; i < paramsTypes.length; i++) {
        ProtocolLib.DeFiParam memory param;
        
        if(paramsTypes[i] == 0) {  // address
            param._type = 0;
            param.w = abi.decode(_data[1][offset:offset+32], (address));
            
        } else if(paramsTypes[i] == 1) {  // uint256
            param._type = 1;
            param.x = abi.decode(_data[1][offset:offset+32], (uint256));
            
        } else if(paramsTypes[i] == 3) {  // bool
            param._type = 3;
            param.z = abi.decode(_data[1][offset:offset+32], (bool));
        }
        
        params[i] = param;
        offset += 32;
    }
    
    return params;
}
```

#### Paso 3: MarketNeutral usa los parámetros decodificados

```solidity
// MarketNeutral.sol
function execute(uint8 functionId, bytes[] calldata _data) external payable {
    // Decodificar parámetros universales
    ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
    
    if(functionId == 0) {
        // Extraer valores según el tipo
        uint256 ethAmount = params[0].x;        // tipo 1 → uint256 → campo .x
        uint256 sizeDeltaUsd = params[1].x;     // tipo 1 → uint256 → campo .x
        uint256 acceptablePrice = params[2].x;  // tipo 1 → uint256 → campo .x
        uint256 executionFee = params[3].x;     // tipo 1 → uint256 → campo .x
        address market = params[4].w;           // tipo 0 → address → campo .w
        address receiver = params[5].w;         // tipo 0 → address → campo .w
        bool isLong = params[6].z;              // tipo 3 → bool    → campo .z
        
        // Ahora ejecutar la estrategia con GMX
        openPositionWithEther(params);
    }
}
```

---

## 🔄 FLUJO COMPLETO DE EJECUCIÓN

### Ejemplo: Abrir posición en GMX con 0.5 ETH

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. USUARIO LLAMA A MAIN.SOL                                     │
└─────────────────────────────────────────────────────────────────┘
    ↓
Main.openPositionSimpleParams(
    _ethAmount: 0.5 ETH,
    _sizeDeltaUsd: 1000 USD,
    _acceptablePrice: 2000,
    _executionFee: 0.001 ETH,
    _market: 0xABC...,
    _isLong: true
)
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. MAIN.SOL REGISTRA DATOS EN PROTOCOLSTORAGE                  │
└─────────────────────────────────────────────────────────────────┘
    ↓
protocolStorage.updateUserTransactionCount(msg.sender, 1)
protocolStorage.updateUserGlobalPosition(msg.sender, newPosition)
    ↓
    Position guardada:
    {
        positionType: 0,  // GMX Market Neutral
        pnl: 0,
        positionData: [
            abi.encode(0.5 ETH),     // ethAmount
            abi.encode(true),        // isActive
            abi.encode(1000),        // sizeDeltaUsd
            abi.encode(true),        // isLong
            abi.encode(0xABC...)     // market
        ]
    }
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. MAIN.SOL ENCODEA PARÁMETROS                                  │
└─────────────────────────────────────────────────────────────────┘
    ↓
_types  = [1, 1, 1, 1, 0, 0, 3]
_values = [bytes(0.5), bytes(1000), bytes(2000), bytes(0.001), bytes(0xABC), bytes(0x123), bytes(true)]
params  = [abi.encode(_types), abi.encode(_values)]
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. BUNDLESROUTER RUTEA AL EXECUTOR                              │
└─────────────────────────────────────────────────────────────────┘
    ↓
bundlesRouter.route{value: 0.501 ETH}(
    address(marketNeutral),  // Qué executor
    0,                       // functionId
    params                   // Parámetros universales
)
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. MARKETNEUTRAL DECODIFICA Y EJECUTA                           │
└─────────────────────────────────────────────────────────────────┘
    ↓
DeFiParam[] memory decodedParams = DecoderLib.decoder(params)
    ↓
    decodedParams[0] = { _type: 1, x: 0.5 ETH }
    decodedParams[1] = { _type: 1, x: 1000 }
    decodedParams[2] = { _type: 1, x: 2000 }
    decodedParams[3] = { _type: 1, x: 0.001 }
    decodedParams[4] = { _type: 0, w: 0xABC... }
    decodedParams[5] = { _type: 0, w: 0x123... }
    decodedParams[6] = { _type: 3, z: true }
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. MARKETNEUTRAL CREA ORDEN EN GMX                              │
└─────────────────────────────────────────────────────────────────┘
    ↓
BaseOrderUtils.CreateOrderParams memory orderParams = {
    addresses: {
        receiver: 0x123...,
        market: 0xABC...,
        initialCollateralToken: WETH,
        ...
    },
    numbers: {
        sizeDeltaUsd: 1000,
        acceptablePrice: 2000,
        executionFee: 0.001,
        ...
    },
    isLong: true,
    ...
}
    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. GMX EJECUTA LA ORDEN                                         │
└─────────────────────────────────────────────────────────────────┘
    ↓
exchangeRouter.multicall{value: 0.501 ETH}([
    sendWnt(orderVault, 0.501 ETH),
    createOrder(orderParams)
])
    ↓
    ✅ Posición abierta en GMX
    ✅ Datos registrados en ProtocolStorage
    ✅ Usuario puede ver su posición en frontend
```

---

## 📊 COMPARACIÓN: ARQUITECTURA TRADICIONAL VS ESTA ARQUITECTURA

### Escenario: Agregar 3 nuevas estrategias

| Aspecto | Arquitectura Tradicional | Nuestra Arquitectura |
|---------|-------------------------|----------------------|
| **Contracts a deployar** | 3 nuevos contracts completos | 3 executors pequeños |
| **Modificar Main** | ✅ Sí, agregar 3 funciones nuevas | ❌ No |
| **Modificar Frontend** | ✅ Sí, 3 ABIs nuevos | ❌ No, mismo ABI |
| **Gas de deployment** | ~5M gas × 3 = 15M gas | ~1M gas × 3 = 3M gas |
| **Testing** | 3 test suites completos | Reusar decoder tests |
| **Mantenibilidad** | Baja (código duplicado) | Alta (DRY) |
| **Type safety** | Alta (Solidity nativo) | Media (runtime checks) |
| **Flexibilidad** | Baja (hardcoded) | Alta (dinámico) |

---

### Ejemplo Concreto

#### ❌ Arquitectura Tradicional

```solidity
// Main.sol - ANTES
contract Main {
    // Estrategia 1: GMX Market Neutral
    function openGMXPosition(
        uint256 ethAmount,
        uint256 sizeDelta,
        address market,
        bool isLong
    ) external payable { }
    
    // Estrategia 2: Uniswap V3 LP
    function addUniswapLiquidity(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external payable { }
    
    // Estrategia 3: Aave Leveraged Yield
    function openAaveLeveragedPosition(
        address asset,
        uint256 amount,
        uint256 leverage,
        bytes calldata flashloanParams
    ) external payable { }
}

// Frontend necesita conocer 3 firmas diferentes:
const openGMXABI = [...];
const addUniswapABI = [...];
const openAaveABI = [...];
```

#### ✅ Nuestra Arquitectura

```solidity
// Main.sol - DESPUÉS (sin cambios!)
contract Main {
    // UNA función para todas las estrategias
    function executeStrategy(
        address executor,
        uint8 functionId,
        uint256[] types,
        bytes[] values
    ) external { }
}

// Agregar estrategia = solo deploy del executor
contract UniswapV3Executor {
    function execute(uint8 functionId, bytes[] calldata _data) external {
        DeFiParam[] memory params = DecoderLib.decoder(_data);
        // usar params...
    }
}

// Frontend usa SIEMPRE la misma función:
const executeStrategyABI = [...]; // Solo UNA vez
```

---

## 🗄️ SISTEMA DE POSICIONES DINÁMICAS

### UpgradeableLib: Schemas Dinámicos

```solidity
// UpgradeableLib.sol
contract UpgradeableLib {
    mapping(uint256 => ProtocolLib.PositionType) public positionsTypes;
    
    function addPositionType(ProtocolLib.PositionType memory _positionType) 
        public onlyAdmin 
    {
        positionsTypes[positionsTypesCount] = _positionType;
        positionsTypesCount++;
    }
}
```

### Ejemplo: Definir tipos de posición

```solidity
// Tipo 0: GMX Market Position
PositionParam[] memory gmxParams = new PositionParam[](5);
gmxParams[0] = PositionParam(1, "ethAmount");      // uint256
gmxParams[1] = PositionParam(3, "isActive");       // bool
gmxParams[2] = PositionParam(1, "sizeDeltaUsd");   // uint256
gmxParams[3] = PositionParam(3, "isLong");         // bool
gmxParams[4] = PositionParam(0, "market");         // address

addPositionType(PositionType("GMX Market Position", 1, gmxParams));

// Tipo 1: Uniswap V3 LP Position
PositionParam[] memory uniParams = new PositionParam[](6);
uniParams[0] = PositionParam(0, "tokenA");         // address
uniParams[1] = PositionParam(0, "tokenB");         // address
uniParams[2] = PositionParam(1, "fee");            // uint256
uniParams[3] = PositionParam(2, "tickLower");      // int256
uniParams[4] = PositionParam(2, "tickUpper");      // int256
uniParams[5] = PositionParam(1, "liquidity");      // uint256

addPositionType(PositionType("Uniswap V3 LP", 1, uniParams));

// Tipo 2: Aave Leveraged Position
PositionParam[] memory aaveParams = new PositionParam[](4);
aaveParams[0] = PositionParam(0, "asset");         // address
aaveParams[1] = PositionParam(1, "supplied");      // uint256
aaveParams[2] = PositionParam(1, "borrowed");      // uint256
aaveParams[3] = PositionParam(1, "leverage");      // uint256

addPositionType(PositionType("Aave Leveraged", 1, aaveParams));
```

### Guardar posición con datos flexibles

```solidity
// Guardar posición GMX
bytes[] memory positionData = new bytes[](5);
positionData[0] = abi.encode(0.5 ether);           // ethAmount
positionData[1] = abi.encode(true);                // isActive
positionData[2] = abi.encode(1000e30);             // sizeDeltaUsd
positionData[3] = abi.encode(true);                // isLong
positionData[4] = abi.encode(0xABC...);            // market

Position memory newPosition = Position({
    positionType: 0,  // GMX Market Position
    pnl: 0,
    positionData: positionData
});

// Guardar posición Uniswap
bytes[] memory uniData = new bytes[](6);
uniData[0] = abi.encode(WETH);                     // tokenA
uniData[1] = abi.encode(USDC);                     // tokenB
uniData[2] = abi.encode(3000);                     // fee (0.3%)
uniData[3] = abi.encode(int24(-887220));           // tickLower
uniData[4] = abi.encode(int24(887220));            // tickUpper
uniData[5] = abi.encode(1000000);                  // liquidity

Position memory uniPosition = Position({
    positionType: 1,  // Uniswap V3 LP
    pnl: 0,
    positionData: uniData
});
```

### Leer posición y decodificar

```solidity
// Frontend o backend puede leer el tipo y decodificar
Position memory pos = protocolStorage.getUser(userAddress).positions[0];

// Obtener el schema del tipo
PositionType memory schema = upgradeableLib.getPositionType(pos.positionType);

// Decodificar datos según el schema
if (pos.positionType == 0) {  // GMX
    uint256 ethAmount = abi.decode(pos.positionData[0], (uint256));
    bool isActive = abi.decode(pos.positionData[1], (bool));
    uint256 sizeDelta = abi.decode(pos.positionData[2], (uint256));
    bool isLong = abi.decode(pos.positionData[3], (bool));
    address market = abi.decode(pos.positionData[4], (address));
    
    // Mostrar en UI...
    
} else if (pos.positionType == 1) {  // Uniswap
    address tokenA = abi.decode(pos.positionData[0], (address));
    address tokenB = abi.decode(pos.positionData[1], (address));
    // ...
}
```

---

## 🚀 CASOS DE USO FUTUROS

### 1. Agregar Soporte para Curve Pools

```solidity
// 1. Deploy del executor
contract CurveExecutor {
    function execute(uint8 functionId, bytes[] calldata _data) external {
        DeFiParam[] memory params = DecoderLib.decoder(_data);
        
        if (functionId == 0) addLiquidity(params);
        if (functionId == 1) removeLiquidity(params);
    }
    
    function addLiquidity(DeFiParam[] memory params) internal {
        address pool = params[0].w;
        uint256[] memory amounts = abi.decode(params[1].v, (uint256[]));
        uint256 minMintAmount = params[2].x;
        
        // Interactuar con Curve...
    }
}

// 2. Registrar tipo de posición
PositionParam[] memory curveParams = new PositionParam[](3);
curveParams[0] = PositionParam(0, "pool");
curveParams[1] = PositionParam(4, "amounts");  // bytes (array de uints)
curveParams[2] = PositionParam(1, "lpTokens");

upgradeableLib.addPositionType(PositionType("Curve LP", 1, curveParams));

// 3. ¡Listo! Sin modificar Main.sol
```

### 2. Agregar Soporte para Perpetual Protocol

```solidity
contract PerpetualExecutor {
    function execute(uint8 functionId, bytes[] calldata _data) external {
        DeFiParam[] memory params = DecoderLib.decoder(_data);
        
        address market = params[0].w;
        uint256 size = params[1].x;
        int256 direction = params[2].y;  // 1 = long, -1 = short
        uint256 leverage = params[3].x;
        
        // Abrir posición perpetual...
    }
}
```

### 3. Agregar Estrategia Compleja Multi-Protocolo

```solidity
contract YieldFarmingAggregator {
    function execute(uint8 functionId, bytes[] calldata _data) external {
        DeFiParam[] memory params = DecoderLib.decoder(_data);
        
        // Paso 1: Swap en Uniswap
        // Paso 2: Deposit en Aave
        // Paso 3: Borrow contra collateral
        // Paso 4: Farm en Curve
        // Paso 5: Stake rewards en Convex
        
        // TODO en UNA sola transacción
        // Usando el MISMO sistema de parámetros
    }
}
```

---

## 🎯 CONCLUSIÓN

### Este diseño NO es over-engineering, es:

✅ **Future-proof**: Agregar 100 estrategias sin redeployment  
✅ **Gas-efficient a largo plazo**: Un deployment inicial vs N deployments  
✅ **Mantenible**: Un ABI para el frontend, un sistema de testing  
✅ **Extensible**: Schemas dinámicos con UpgradeableLib  
✅ **Type-safe**: Runtime checks + off-chain validation  
✅ **Modular**: Cada executor es independiente  

### Comparado con GMX:

GMX es un **protocolo especializado** en derivados.  
Este protocolo es un **orquestador universal** de estrategias DeFi.

**Son diferentes categorías de productos.**

GMX optimiza para: velocidad, gas, especificidad.  
Este protocolo optimiza para: flexibilidad, extensibilidad, agregación.

---

## 📚 REFERENCIAS

- **DecoderLib.sol**: Sistema universal de decodificación
- **ProtocolLib.sol**: Definiciones de tipos y estructuras
- **UpgradeableLib.sol**: Schemas dinámicos de posiciones
- **BundlesRouter.sol**: Orquestador de executors
- **MarketNeutral.sol**: Ejemplo de executor para GMX

---

**Autor**: @Diego-AVZ  
**Versión**: 1.0  
**Última actualización**: 2025

---

_"Un sistema que puede evolucionar sin reconstruirse es un sistema diseñado para durar."_

