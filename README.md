# Pennysia AMM V1 Core 

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue.svg)](https://docs.soliditylang.org/) [![Foundry](https://img.shields.io/badge/Built%20with-Foundry-yellow.svg)](https://getfoundry.sh/) [![License: GPL-3.0-or-later](https://img.shields.io/badge/License-Business_Source_1.1-red)](https://en.wikipedia.org/wiki/Business_Source_License) [![CI](https://github.com/Pennysia/v1-core/actions/workflows/test.yml/badge.svg)](https://github.com/Pennysia/v1-core/actions/workflows/test.yml)

An innovative Automated Market Maker (AMM) protocol featuring a unique **long/short liquidity model** for enhanced capital efficiency and liquidity provider incentives.

This codebase implements a sophisticated AMM with position-based fee mechanics featuring a unique **long/short liquidity model**, aiming for better LP incentives (e.g., choose "long" for fee capture in output-heavy pairs).

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
- **Flash loans** for arbitrage, liquidations, and complex strategies
- **Constant-product invariant** ensures predictable slippage

### 🏦 **Liquidity Management**
- **Directional liquidity** (long/short) per token with prediction rewards
- **Cross-token fee distribution** rewards correct directional bets
- **LP position swapping** via `lpSwap` to rebalance long/short without leaving the pool
- **Dynamic rebalancing** through fee allocation and dilution
- **Minimum liquidity** enforcement prevents pool drainage
- **TTL-based approvals** using timestamps for enhanced security

### 📊 **Price Oracle**
- **Time-weighted cbrt(price)** cumulative for manipulation resistance
- **Q128 price input with cube-root accumulation; consumers compute TWAPs via deltas over time**
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
│   ├── Liquidity.sol         # 🎫 Multi-dimensional LP tokens
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
git clone https://github.com/Pennysia/v1-core.git
cd v1-core

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

// Read reserves (pairId-based)
(uint128 r0L, uint128 r0S, uint128 r1L, uint128 r1S) = market.getReserves(pairId);

// Perform a token swap
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

// Swap LP between long/short within a pair
// Example: move some longX to shortX and longY to shortY
(, uint256 lOut0, uint256 lOut1) = market.lpSwap(
    recipient,
    token0,
    token1,
    /* longToShort0 */ true,
    /* liquidity0    */ 500_000,
    /* longToShort1 */ true,
    /* liquidity1    */ 250_000
);
```

## 🧪 Testing

Comprehensive test suite with **112/112 tests passing**:

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
| `swap` (single hop) | ~100k | Internal avg; ~150-200k including callback |
| `createLiquidity` (create pool) | ~350k | Avg for first-time pair creation |
| `createLiquidity` (subsequent) | ~225k | Avg for adding to existing pair |
| `withdrawLiquidity` | ~210k | Internal avg; ~250-300k including protocol fees and callback |
| `flash` | ~70k | Internal avg; ~120-150k plus callback execution |

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

This project is licensed under the GPL-3.0-or-later License. See the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided "as is" without warranty of any kind. Use at your own risk. This is experimental software and has not been formally audited.

---

**Built with ❤️ by the Pennysia Team**