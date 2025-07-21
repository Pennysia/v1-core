# Pennysia AMM V1-Core 

[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue.svg)](https://docs.soliditylang.org/) [![Foundry](https://img.shields.io/badge/Built%20with-Foundry-red.svg)](https://getfoundry.sh/) [![License: Dual](https://img.shields.io/badge/License-BUSL%2FGPL-blue.svg)](#-license) [![CI](https://github.com/Pennysia/v1-core/actions/workflows/test.yml/badge.svg)](https://github.com/Pennysia/v1-core/actions/workflows/test.yml)

An innovative Automated Market Maker (AMM) protocol featuring a unique **long/short liquidity model** for enhanced capital efficiency and liquidity provider incentives.

## 🌟 Innovation: Long/Short Liquidity Model

Unlike traditional AMMs that treat all liquidity equally, Pennysia splits token reserves into **"long"** and **"short"** positions with **directional rewards**:

- **Correct directional predictions** are rewarded with swap fees
- **Incorrect predictions** face dilution as their relative share decreases
- **Example**: When token X is bought → `longX` and `shortY` earn rewards, while `shortX` and `longY` are diluted
- **Bi-directional incentives** reward both long and short positions when they predict correctly

This creates a **prediction market mechanism** within the AMM, encouraging informed liquidity provision and natural price discovery through directional incentives.

### 🎯 **How Directional Rewards Work**

When a swap occurs, the system redistributes fees based on directional correctness:

#### **Token X Purchase Example:**
```
Initial State: [longX: 1000] [shortX: 1000] [longY: 1000] [shortY: 1000]
User buys 100 X tokens with Y tokens

Fee Distribution:
✅ longX  += feeOut  (predicted X would be bought - CORRECT)
❌ shortX += 0       (predicted X would be sold - WRONG, gets diluted)
✅ shortY += feeIn   (predicted Y would be sold - CORRECT) 
❌ longY  -= feeIn   (predicted Y would be bought - WRONG, pays penalty)
```

#### **Result:**
- **Winners**: `longX` holders (bet on X demand) + `shortY` holders (bet against Y)
- **Losers**: `shortX` holders (bet against X) + `longY` holders (bet on Y demand)

This mechanism creates **natural hedging** and rewards liquidity providers who correctly anticipate market direction!

## ✨ Key Features

### 🔄 **Advanced Trading**
- **Multi-hop swaps** with optimal routing through multiple pairs
- **Flash loans** (0.1% fee) for arbitrage, liquidations, and complex strategies
- **Constant-product invariant** ensures predictable slippage

### 🏦 **Liquidity Management**
- **Directional liquidity** (long/short) per token with prediction rewards
- **Cross-token fee distribution** rewards correct directional bets
- **Dynamic rebalancing** through fee allocation and dilution
- **Minimum liquidity** enforcement prevents pool drainage
- **TTL-based approvals** using timestamps for enhanced security

### 📊 **Price Oracle**
- **Time-weighted cbrt(price)** cumulative for manipulation resistance
- **Block timestamp** based accumulation
- **Smooth price transitions** reduce oracle attack vectors

### 🛡️ **Security First**
- **Reentrancy guards** on all state-changing functions
- **Delegatecall prevention** protects against proxy attacks
- **Balance verification** in callback systems
- **Safe math** operations prevent overflows

### 🚀 **Performance Advantages**
- **Singleton architecture** eliminates per-pair deployment costs
- **Native multi-hop swaps** without external router dependencies
- **Batch LP operations** for capital-efficient position management
- **Assembly-optimized math** for gas-efficient calculations
- **Packed storage layouts** minimize SSTORE operations

## 🏗️ Architecture & Design Advantages

### 🎯 **Singleton Design Pattern**
Unlike traditional AMMs that deploy separate contracts per pair, Pennysia uses a **single Market contract** that manages all trading pairs:

- **🔹 Gas Efficiency**: No deployment costs for new pairs, just storage updates
- **🔹 Unified Liquidity**: Cross-pair operations in a single transaction
- **🔹 Simplified Integration**: One contract address for all pairs
- **🔹 Atomic Multi-Hop**: Native support for complex routing without external calls
- **🔹 Reduced Attack Surface**: Single codebase to audit and secure

### 🧠 **Architectural Innovations**

#### **📊 Multi-Dimensional LP Tokens**
- **4-component balances** per pair: `(longX, shortX, longY, shortY)`
- **Directional exposure** allows betting on token price movements
- **Cross-token rewards** when predictions align with market direction
- **TTL-based approvals** using timestamps instead of traditional allowances
- **Batch operations** for efficient multi-position management
- **Native permit support** for gasless approvals

#### **🔄 Callback-Based Interactions**
- **Just-in-time payments** via `IPayment` callbacks
- **Atomic execution** ensures all-or-nothing transactions
- **Flexible integration** allows custom payment logic
- **Gas optimization** through lazy evaluation

#### **🛡️ Security-First Design**
- **Reentrancy protection** on all external calls
- **Delegatecall prevention** blocks proxy-based attacks
- **Balance verification** in all callback flows
- **Input validation** at library level for reusability

#### **⚡ Gas-Optimized Storage**
- **Packed structs** minimize storage slots
- **Efficient mappings** for O(1) pair lookups
- **Assembly optimizations** in critical math operations
- **Minimal external calls** reduce transaction costs

### 📁 **Code Structure**

```
src/
├── Market.sol                 # 🏦 Singleton AMM core
├── abstracts/
│   ├── Liquidity.sol         # 🎫 Multi-dimensional LP tokens (BUSL-1.1)
│   ├── ReentrancyGuard.sol   # 🛡️ Reentrancy protection
│   ├── NoDelegatecall.sol    # 🚫 Delegatecall prevention
│   └── Deadline.sol          # ⏰ Transaction deadlines
├── libraries/
│   ├── Math.sol              # 🧮 Precision math with assembly
│   ├── Callback.sol          # 📞 Payment verification system
│   ├── TransferHelper.sol    # 💸 Safe token transfers
│   ├── Validation.sol        # ✅ Input validation utilities
│   ├── PairLibrary.sol       # 🔍 Efficient pair ID computation
│   └── SafeCast.sol          # 🔄 Type casting safety
└── interfaces/
    ├── IMarket.sol           # 🏪 Main contract interface
    ├── ILiquidity.sol        # 🎫 LP token interface
    ├── IPayment.sol          # 💰 Callback interface
    └── IERC20.sol            # 🪙 Token interface
```

### 🎨 **Design Patterns Used**

| Pattern | Implementation | Benefit |
|---------|----------------|---------|
| **Singleton** | Single Market contract | Gas efficiency, unified liquidity |
| **Factory Method** | Pair creation via `createLiquidity` | On-demand pair initialization |
| **Callback Pattern** | `IPayment` interface | Flexible, atomic payments |
| **Library Pattern** | Stateless utility functions | Code reusability, gas savings |
| **Guard Pattern** | Reentrancy & delegatecall guards | Security by design |

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) toolkit
- Git for cloning the repository

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/pennysia-v1-core.git
cd pennysia-v1-core

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test
```

### Basic Usage

```solidity
// Deploy the Market contract
Market market = new Market(owner);

// Create a liquidity pair (via callback)
(uint256 pairId, , , , ) = market.createLiquidity(
    recipient,
    token0,
    token1,
    amount0Long,
    amount0Short,
    amount1Long,
    amount1Short
);

// Perform a swap
uint256 amountOut = market.swap(
    recipient,
    [token0, token1], // path
    amountIn
);

// Flash loan
market.flash(
    recipient,
    [token0],
    [flashAmount]
);
```

## 🧪 Testing

Comprehensive test suite with **113/113 tests passing**:

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with coverage
forge coverage

# Run specific test file
forge test test/Market.t.sol

# Run tests with detailed traces
forge test -vvv
```

### Test Categories

- **Unit Tests**: Individual function testing
- **Integration Tests**: Multi-step workflows
- **Fuzz Tests**: Property-based testing with random inputs
- **Security Tests**: Reentrancy, access control, edge cases
- **Edge Cases**: Boundary conditions and error handling

## 💡 Usage Examples

### Creating Liquidity

```solidity
contract LiquidityProvider {
    function addLiquidity(Market market, address token0, address token1) external {
        // Implement IPayment interface
        market.createLiquidity(
            msg.sender,
            token0,
            token1,
            1000e18, // long0
            500e18,  // short0
            1000e18, // long1
            500e18   // short1
        );
    }
    
    // Callback function for payment
    function requestToken(
        address to,
        address[] memory tokens,
        uint256[] memory amounts
    ) external {
        // Transfer tokens to market
        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(address(market), amounts[i]);
        }
    }
}
```

### Flash Loan Arbitrage

```solidity
contract FlashArbitrage {
    function executeArbitrage(Market market, address token, uint256 amount) external {
        market.flash(address(this), [token], [amount]);
    }
    
    function requestToken(
        address to,
        address[] memory tokens,
        uint256[] memory paybackAmounts
    ) external {
        // Perform arbitrage logic here
        // ...
        
        // Repay flash loan with fee
        IERC20(tokens[0]).transfer(msg.sender, paybackAmounts[0]);
    }
}
```

## 🔧 Configuration

### Foundry Configuration

The project uses Foundry with the following key settings in `foundry.toml`:

```toml
[profile.default]
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
via_ir = true
```

### Gas Optimization

- Uses assembly for critical math operations
- Optimized storage layouts
- Efficient error handling with custom errors
- Minimal external calls

## 🛡️ Security Considerations

### Auditing Notes

- **Callback Security**: All callbacks verify payment before proceeding
- **Reentrancy**: Protected by `nonReentrant` modifier
- **Integer Overflow**: Uses safe math throughout
- **Access Control**: Owner-only functions properly protected
- **Input Validation**: Comprehensive checks on all inputs

### Known Limitations

- Low-level design requires careful integration
- Router contracts recommended for end-user interactions
- Slippage protection must be implemented at router level

## 📈 Gas Benchmarks

| Function | Gas Usage | Notes |
|----------|-----------|-------|
| `swap` (single hop) | ~200k | Includes callback |
| `createLiquidity` | ~350k | First-time pair creation |
| `withdrawLiquidity` | ~250k | Includes protocol fees |
| `flash` | ~150k | Plus callback execution |

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Ensure all tests pass
5. Submit a pull request

### Development Guidelines

- Follow Solidity style guide
- Write clear commit messages
- Add tests for new features
- Update documentation

## 📜 License

This project uses a **dual licensing approach** to protect core IP while keeping supporting code open source:

### 🔒 **BUSL-1.1 Licensed (Core IP)**
The following files contain proprietary innovations and are licensed under **Business Source License 1.1**:
- `src/Market.sol` - Core AMM contract with long/short liquidity model
- `src/abstracts/Liquidity.sol` - LP token management system

**BUSL-1.1 Key Terms:**
- ✅ Free for non-production use, research, and development
- ✅ Source code is publicly available for review and learning
- ❌ Commercial production use requires a commercial license
- 🕐 Will convert to GPL-3.0 after 4 years (change date: [2029-06-15])

### 📖 **GPL-3.0 Licensed (Supporting Code)**
All other files are licensed under **GPL-3.0-or-later**, including:
- Libraries (`src/libraries/`)
- Interfaces (`src/interfaces/`)
- Abstract contracts (except `Liquidity.sol`)
- Tests (`test/`)
- Documentation and tooling

For commercial licensing of BUSL-1.1 components, please contact: [dev@pennysia.com](mailto:dev@pennysia.com)

## ⚠️ Disclaimer

This software is provided "as is" without warranty. Use at your own risk. This is experimental software and has not been audited. 

**Important Legal Notes:**
- Core components (`Market.sol`, `Liquidity.sol`) are under BUSL-1.1 license
- Commercial production use of BUSL-1.1 components requires proper licensing
- Do not use in production without proper security audit and legal review
- Always verify licensing requirements for your specific use case

---

**Built with ❤️ by the Pennysia Team**