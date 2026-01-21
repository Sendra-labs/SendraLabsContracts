# Sendra Labs - Smart Contracts
Modular, Arbitrum-native DeFi infrastructure combining execution, analytics, and strategy-level accounting.

**Solidity Foundry Arbitrum**

## Overview
Sendra Labs is a modular, Arbitrum-native DeFi infrastructure that combines execution, analytics, and strategy-level accounting into a single operational layer. We are building the platform where liquidity learns, strategies execute, and DeFi evolves.

**Current Status:** MVP fully deployed on Arbitrum mainnet with all core components operational.

## Architecture Overview
Sendra Labs smart contracts are structured around five interoperable layers: **Execution**, **Storage**, **Access Control**, **Configuration**, and **Reading**. Each built as an independent module but designed to work together seamlessly.

## Links
- **Website:** sendralabs.com
- **Twitter:** @SendraLabs
- **Contact:** sendralabs.eth@gmail.com

## Tech Stack

### Core
| Technology | Version | Purpose |
|------------|---------|---------|
| Solidity | ^0.8.28 | Smart Contract Language |
| Foundry | Latest | Development, Testing & Deployment |
| OpenZeppelin | Latest | Security Primitives |
| GMX Synthetics | Latest | DEX Integration |

### Security Libraries
- **ReentrancyGuard** - Protection against reentrancy attacks
- **SafeERC20** - Safe token transfer operations
- **Roles** - Multi-admin governance system
- **ProxyAccessControl** - Proxy authorization management

### Infrastructure
- **AddressProvider** - Central registry for all contract addresses
- **Proxy System** - Gas-efficient proxy pool for position isolation
- **Callback Handlers** - GMX order execution callbacks

## Deployed Contracts (Arbitrum One)

| Contract | Address | Purpose |
|----------|---------|---------|
| **Roles** | `0x4F2710766682e28D9846f5Fb9eED62AE7fcb5de6` | Multi-admin governance |
| **AddressProvider** | `0x73836d093005Dafeb3446c6DB10f325a52ea6f0E` | Central address registry |
| **PairTrading** | `0xd501Ec732eA13C8f4aEcd4A770bE80FF9Aa42AB2` | Main executor contract |
| **ProtocolStorage** | `0x51A7ae8997E371b3749bbe9c17D9779d0fb265F6` | Central data storage |
| **GMXMarketsRegistry** | `0xA205c7e8407e79Fdee80F069988a40E9d8DD4A62` | Market configuration |
| **GMXPrices** | `0xa2C1dE158d8916dCaa07f3A72762910E4a3f39D4` | Price utilities |
| **ProxyFactory** | `0x397123FB5e96913a66E343df788911f7Ef1D98a6` | Proxy deployment |
| **ProxyManager** | `0xf575Cd9B522bf95bE2fA0ff20B4Bc9eBaA718FfA` | Proxy lifecycle manager |
| **PairTradingStorage** | `0x113298C2fe3A770B170c7Dc91Ed55Df9ECd32BB2` | Pair trading data |
| **ClosePositionCallbacks** | `0x996e027f2FccBED934128A0115227c0391FD6887` | GMX close callbacks |
| **PairTradingReader** | `0x1811057d40086F6b3aA29d14EacC462d58E5A9FC` | Pair trading reader |
| **MainReader** | `0xe989C151391F51b5544bF15acb54a551C6B68a87` | Main data reader |
| **PositionInitializer** | `0x09EcCBaC2dB1b3fffe5e30eD1BDFA5f9f1DB2D73` | Position creator |
| **ProxyAccessControl** | `0xA4BFa76A45bCCF1895f562352f6Fad457505cF02` | Proxy authorization |

## Architecture

### Modular Layer Structure
The protocol follows a modular architecture with clear separation between execution, storage, access control, and data reading layers.

```
┌─────────────────────────────────────────────────────────────┐
│                    User Layer (Frontend)                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Execution Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ PairTrading  │  │PositionInit  │  │ ProxyFactory  │     │
│  │              │  │              │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         │                  │                  │             │
│         └──────────────────┴──────────────────┘             │
│                            │                                 │
│                            ▼                                 │
│                  ┌──────────────────┐                        │
│                  │ PairTradingProxy │                        │
│                  │  (User Instance) │                        │
│                  └──────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Callback Layer                             │
│  ┌──────────────────────┐  ┌──────────────────────┐         │
│  │OpenPositionCallbacks │  │ClosePositionCallbacks│         │
│  └──────────────────────┘  └──────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Storage Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │Protocol      │  │PairTrading   │  │Proxy        │       │
│  │Storage       │  │Storage       │  │Manager      │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 Access Control Layer                         │
│  ┌──────────────┐  ┌──────────────────────┐                │
│  │    Roles     │  │ ProxyAccessControl    │                │
│  └──────────────┘  └──────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                Configuration Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │Address       │  │GMXMarkets    │  │  GMXPrices   │        │
│  │Provider      │  │Registry      │  │              │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Reading Layer                              │
│  ┌──────────────┐  ┌──────────────┐                          │
│  │ MainReader   │  │PairTrading   │                          │
│  │              │  │Reader        │                          │
│  └──────────────┘  └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    External (GMX)                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          GMX Protocol (DEX)                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Execution Layer

#### PairTrading
**Address:** `0xd501Ec732eA13C8f4aEcd4A770bE80FF9Aa42AB2`

Main executor contract that handles pair trading position opening and closing. Supports both ETH and USDC collateral with slippage protection.

**Key Functions:**
- `openEtherPairTrading()` - Opens market neutral position with ETH collateral
- `openUSDCPairTrading()` - Opens market neutral position with USDC collateral
- `closePairTrading()` - Closes both sides of a position simultaneously
- `openPositionWithEther()` - Opens single position with ETH
- `openPositionWithUSDC()` - Opens single position with USDC

**Features:**
- Simultaneous long and short position execution
- Slippage protection via acceptable price calculations
- Automatic position key generation
- Support for 26 GMX tokens with 325 possible combinations

#### PositionInitializer
**Address:** `0x09EcCBaC2dB1b3fffe5e30eD1BDFA5f9f1DB2D73`

Creates and initializes new positions in the protocol storage system. Handles position data encoding and storage registration.

#### ProxyFactory
**Address:** `0x397123FB5e96913a66E343df788911f7Ef1D98a6`

Deploys new PairTradingProxy instances when needed. Implements gas-efficient proxy deployment pattern.

#### PairTradingProxy
User-specific proxy instances that isolate positions and enable efficient gas usage. Each proxy is owned by a single user and tracks market usage.

### Storage Layer

#### ProtocolStorage
**Address:** `0x51A7ae8997E371b3749bbe9c17D9779d0fb265F6`

Central storage for all user data, positions, and protocol statistics (TVL, total volume, PnL, etc.).

**Key Data:**
- User positions and metadata
- Protocol-wide statistics
- Global PnL tracking
- Transaction counts

#### PairTradingStorage
**Address:** `0x113298C2fe3A770B170c7Dc91Ed55Df9ECd32BB2`

Specialized storage for pair trading execution data, raw GMX callback data, and position information.

**Key Data:**
- GMX callback execution data
- Position keys and metadata
- Pending order tracking
- Execution history

#### ProxyManager
**Address:** `0xf575Cd9B522bf95bE2fA0ff20B4Bc9eBaA718FfA`

Manages the lifecycle of proxy contracts, including pooling, deployment, and availability tracking.

**Features:**
- Proxy pool management
- User-proxy ownership mapping
- Availability tracking
- Gas-efficient proxy reuse

### Access Control

#### Roles
**Address:** `0x4F2710766682e28D9846f5Fb9eED62AE7fcb5de6`

Multi-admin governance system requiring 2-of-3 admin consensus for contract approvals. Prevents single points of failure.

**Features:**
- 3-administrator setup
- Democratic contract approval (2 approvals required)
- Admin penalization system
- Protocol contract whitelisting

#### ProxyAccessControl
**Address:** `0xA4BFa76A45bCCF1895f562352f6Fad457505cF02`

Manages authorization for proxy contracts, ensuring only registered proxies can perform protocol operations.

### Configuration

#### AddressProvider
**Address:** `0x73836d093005Dafeb3446c6DB10f325a52ea6f0E`

Central registry storing addresses of all protocol contracts. Enables upgradeability and modularity.

**Key Functions:**
- `getAddress(string name)` - Retrieve contract address by name
- `setAddress(string name, address addr)` - Register new contract address

#### GMXMarketsRegistry
**Address:** `0xA205c7e8407e79Fdee80F069988a40E9d8DD4A62`

Configuration registry for GMX market addresses and identifiers. Supports 26 tokens with 325 trading combinations.

#### GMXPrices
**Address:** `0xa2C1dE158d8916dCaa07f3A72762910E4a3f39D4`

Utility contract for fetching and calculating GMX prices with slippage calculations.

**Key Functions:**
- `getPrice(address market)` - Get current market price
- `getAcceptablePrice()` - Calculate acceptable price with slippage

### Callback Handlers

#### OpenPositionCallbacks
Handles GMX order execution callbacks when positions are opened, storing execution data and updating protocol state.

**Key Functions:**
- `afterOrderExecution()` - Processes GMX order execution
- `afterOrderCancellation()` - Handles order cancellations

#### ClosePositionCallbacks
**Address:** `0x996e027f2FccBED934128A0115227c0391FD6887`

Handles GMX order execution callbacks when positions are closed, finalizing positions and releasing proxies for reuse.

**Key Functions:**
- `afterOrderExecution()` - Processes position closure
- `finalizePosition()` - Updates position state and calculates PnL
- `releaseProxy()` - Returns proxy to available pool

### Reading Layer

#### MainReader
**Address:** `0xe989C151391F51b5544bF15acb54a551C6B68a87`

Primary interface for reading protocol data, user positions, and global statistics.

**Key Functions:**
- `getGlobalUserData(address user)` - User statistics and metrics
- `getPairTradingPositionsData(address user)` - All pair trading positions
- `getPairTradingPositionDataById(address user, uint256 id)` - Specific position data
- `getProtocolStats()` - Protocol-wide statistics
- `isProxyNeeded(address user, string marketLong, string marketShort)` - Proxy availability check

#### PairTradingReader
**Address:** `0x1811057d40086F6b3aA29d14EacC462d58E5A9FC`

Specialized reader for pair trading positions, calculating real-time PnL and position sizes.

**Key Functions:**
- `getPairTradingRealTimePnL()` - Real-time profit/loss calculation
- `getPairTradingTotalSize()` - Current position size

## GMX Integration

### Market Support
- **26 tokens** combinable to create pair trading strategies
- **325 possible combinations** running on Arbitrum's infrastructure
- Deep integration handling GMX asynchronicity with callbacks

### Integration Pattern
Each contract interaction follows this pattern:

1. **Price Calculation** - Fetch current prices with slippage protection
2. **Position Initialization** - Create position data in storage
3. **Order Creation** - Submit orders to GMX ExchangeRouter
4. **Callback Handling** - Process execution results via callbacks
5. **State Updates** - Update protocol storage with execution data

### Key GMX Contracts Used
- **ExchangeRouter** - Order creation and execution
- **OrderVault** - Collateral and fee deposits
- **OrderHandler** - Order processing and callbacks
- **DataStore** - GMX position data storage

## Features

### 1. Pair Trading Strategies
**User Experience:** Execute institutional-grade pair trading strategies with simultaneous long and short positions

**Features:**
- Real-time position tracking
- Automatic PnL calculations
- Slippage protection
- Support for ETH and USDC collateral
- Gas-efficient proxy system

**Technical:**
- Simultaneous order execution on GMX
- Position key generation and tracking
- Callback-based execution confirmation
- Precise PnL calculations with BigInt

### 2. Proxy System
**Features:**
- Gas-efficient proxy pool management
- User position isolation
- Automatic proxy deployment and reuse
- Market conflict prevention

**Technical:**
- ProxyFactory for efficient deployment
- ProxyManager for lifecycle management
- ProxyAccessControl for authorization
- Market usage tracking per proxy

### 3. Real-time Analytics
**Features:**
- Live PnL calculations
- Position size tracking
- Protocol-wide statistics
- User performance metrics

**Technical:**
- On-chain price queries
- Real-time position data decoding
- Efficient batch reads via multicall
- Optimized storage access patterns

## Project Structure

```
src/
├── core/                          # Core protocol contracts
│   ├── bundles/                  # Trading strategy modules
│   │   ├── executors/            # Position execution
│   │   │   ├── callbacks/        # GMX callback handlers
│   │   │   │   ├── OpenPositionCallbacks.sol
│   │   │   │   └── ClosePositionCallbacks.sol
│   │   │   ├── PairTrading.sol   # Main executor
│   │   │   ├── PositionInitializer.sol
│   │   │   ├── proxy.sol         # User proxy
│   │   │   └── ProxyFactory.sol
│   │   ├── readers/              # Data reading contracts
│   │   │   └── pairTradingReader.sol
│   │   ├── security/             # Access control
│   │   │   └── proxyAccessControl.sol
│   │   └── storage/              # Data storage
│   │       ├── PairTradingStorage.sol
│   │       └── ProxyManager.sol
│   ├── config/                   # Configuration contracts
│   │   ├── AddressProvider.sol   # Central registry
│   │   └── gmxMarkets.sol        # Market registry
│   ├── MainReader.sol             # Main data reader
│   ├── ProtocolStorage.sol        # Central storage
│   └── UpgradeableLib.sol         # Upgrade utilities
│
├── interfaces/                    # External interfaces
│   ├── GMX/                       # GMX protocol interfaces
│   │   ├── IExchangeRouter.sol
│   │   ├── IOrderCallbackReceiver.sol
│   │   ├── IOrderVault.sol
│   │   ├── IReader.sol
│   │   └── price/
│   └── IWETH.sol
│
├── lib/                           # Library contracts
│   ├── PairTrading/               # Pair trading utilities
│   │   └── PairTradingLib.sol
│   ├── GMX lib/                   # GMX integration utilities
│   ├── Protocol.lib.sol           # Protocol data structures
│   ├── Prices.lib.sol             # Price calculation utilities
│   └── security/                  # Security libraries
│       └── Roles.lib.sol
│
├── periphery/                     # Peripheral contracts
│   └── utilsGMX/
│       └── GMXPrices.sol          # Price utilities
│
├── security/                      # Security contracts
│   └── Roles.sol                  # Multi-admin governance
│
└── team/                          # Team management
    ├── Equity.sol
    ├── MainAdmin.sol
    └── PartnerManager.sol
```

## Security

### Access Control

**Multi-Admin Governance:**
- 3-administrator system
- Requires 2 approvals for contract registration
- Prevents single points of failure
- Democratic consensus mechanism

**Protocol Contract Whitelisting:**
- Only approved contracts can modify protocol state
- Contract registration requires admin consensus
- Automatic validation on state changes

**Proxy Authorization:**
- Separate access control for user proxy instances
- ProxyAccessControl manages proxy registry
- Only registered proxies can execute operations

### Security Features

**Reentrancy Protection:**
- ReentrancyGuard on all critical functions
- Prevents reentrancy attacks
- Applied to position opening/closing

**Safe Token Operations:**
- SafeERC20 for all token transfers
- Prevents token transfer failures
- Handles non-standard token implementations

**Input Validation:**
- Slippage protection on all trades
- Price validation before execution
- Position state verification

**Proxy Isolation:**
- User positions isolated in separate proxies
- Limits attack surface per user
- Prevents cross-position contamination

### Audit Status

⚠️ **This protocol has not been audited yet. Use at your own risk.**

## Testing

### Strategy
Testing Pyramid:

```
        /\
       /E2E\      10%  Critical user flows
      /------\
     /  Int   \   20%  Feature workflows
    /----------\
   /    Unit    \ 70%  Functions, hooks, utils
  /--------------\
```

### Tools
- **Foundry** - Unit and integration testing
- **Forge Test** - Test execution framework
- **Fork Testing** - Mainnet fork integration tests

### Test Structure
```
test/
├── fork/                    # Fork tests
├── integration/             # Integration tests
│   └── bundles/
├── unit/                    # Unit tests
└── mocks/                   # Mock contracts
```

## Code Quality

### Solidity Standards
- **Solidity 0.8.28** - Latest stable version
- **Strict mode** - Maximum compiler warnings
- **Comprehensive NatSpec** - Full documentation
- **Error handling** - Custom errors for gas efficiency

### Code Organization
- **Modular architecture** - Clear separation of concerns
- **Single Responsibility** - Each contract has one purpose
- **Library pattern** - Reusable code in libraries
- **Consistent naming** - Clear, descriptive names

### Best Practices
- **Access control** - Modifiers for all restricted functions
- **Event emission** - Comprehensive event logging
- **Gas optimization** - Efficient storage patterns
- **Upgradeability** - Proxy pattern for key contracts

## Deployment

### Deployment Order
1. **Core Infrastructure**: Roles → AddressProvider
2. **Storage**: ProtocolStorage, PairTradingStorage, ProxyManager
3. **Configuration**: GMXMarketsRegistry, GMXPrices
4. **Execution**: PairTrading, PositionInitializer, ProxyFactory
5. **Callbacks**: OpenPositionCallbacks, ClosePositionCallbacks
6. **Reading**: MainReader, PairTradingReader
7. **Access Control**: ProxyAccessControl

### Deployment Script
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url <rpc-url> --broadcast --verify
```

### Configuration
1. Set environment variables in `.env`
2. Configure RPC endpoints in `foundry.toml`
3. Set Etherscan API key for verification

## Gas Optimization

### Strategies
- **Proxy pooling** - Reuse proxies to save deployment gas
- **Batch operations** - Multicall for multiple operations
- **Storage optimization** - Packed structs and efficient mappings
- **Library usage** - Delegatecall for code reuse

### Gas Costs (Estimated)
- **Open Position**: ~500,000 - 800,000 gas
- **Close Position**: ~400,000 - 600,000 gas
- **Proxy Deployment**: ~1,500,000 gas (one-time)
- **Proxy Reuse**: ~0 gas (reuse existing)

## License
MIT License - See LICENSE for details

## Contact
- **Email:** sendralabs.eth@gmail.com
- **Twitter:** @SendraLabs
- **Website:** sendralabs.com
