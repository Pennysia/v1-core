# Pennysia v1-core Codebase Rules & Architecture Guide

## 🏗️ Core Architecture Overview

### Main Contract: `Market.sol`
- **Primary Function**: Automated Market Maker (AMM) with unique long/short position support
- **Inheritance Chain**: `IMarket` → `Liquidity` → `NoDelegatecall` → `ReentrancyGuard`
- **Key Constants**:
  - `FEE = 3` (0.3% trading fee)
  - `SCALE = 2^128` for mathematical precision
- **Core Data Structure**: 4-reserve system per trading pair

### Unique 4-Reserve System
```solidity
struct Pair {
    uint128 reserve0Long;   // Long position reserves for token0
    uint128 reserve0Short;  // Short position reserves for token0
    uint128 reserve1Long;   // Long position reserves for token1
    uint128 reserve1Short;  // Short position reserves for token1
    uint64 blockTimestampLast;
    uint192 cbrtPriceX128CumulativeLast; // Cube root price accumulator
}
```

## 🔐 Security Patterns & Rules

### 1. Access Control
- **Owner-based**: Single owner model with `setOwner()` function
- **Validation**: All functions use `Validation.sol` for input sanitization
- **Error Handling**: Custom errors (`forbidden()`, `pairNotFound()`, etc.)

### 2. Reentrancy Protection
- **Pattern**: `ReentrancyGuard` abstract contract
- **Usage**: All state-changing functions use `nonReentrant` modifier
- **Rule**: NEVER remove reentrancy guards from external functions

### 3. Delegate Call Protection
- **Pattern**: `NoDelegatecall` abstract contract
- **Usage**: Critical functions use `noDelegateCall` modifier
- **Rule**: Prevent proxy-based attacks on core functionality

### 4. Token Validation Rules
- **Ordering**: Tokens must be pre-sorted (`token0 < token1`)
- **Zero Address**: No zero addresses allowed in token operations
- **Self-Reference**: Contract cannot interact with itself as token

## 💰 Liquidity Management Rules

### TTL-Based Approval System
```solidity
// UNIQUE: Uses timestamps instead of amounts for approvals
mapping(address => mapping(address => mapping(uint256 => uint256))) public allowance;
```
- **Rule**: Approvals expire automatically based on `block.timestamp`
- **Benefit**: No need for explicit approval revocation
- **Implementation**: `allowance[owner][spender][poolId] = deadline`

### LP Token Structure
```solidity
struct LpInfo {
    uint128 longX;   // Long position for token X
    uint128 shortX;  // Short position for token X
    uint128 longY;   // Long position for token Y
    uint128 shortY;  // Short position for token Y
}
```

### Minting/Burning Rules
- **Minimum Liquidity**: First LP must provide minimum liquidity
- **Proportional**: Subsequent LPs must maintain reserve ratios
- **Deadline**: All operations must include deadline parameter

## 🔄 Trading & Swap Rules

### Fee Distribution Economics (CRITICAL FOR PERIPHERY)
- **Output Token Fees**: 100% goes to long positions of output token
- **Input Token Fees**: Proportionally distributed between long/short when possible
- **Protocol Fees**: 20% of withdrawal fees retained by Market contract
- **LP Fees**: 80% of withdrawal fees distributed to existing LPs
- **Asymmetric Design**: Intentional to incentivize directional liquidity

### Multi-Hop Swapping
- **Path Validation**: Must validate entire swap path
- **Slippage**: Minimum output amounts enforced
- **Gas Optimization**: Single transaction for multiple swaps
- **Fee Calculation**: `feeAmountIn = divUp(amountIn * FEE, 1000)`

### Flash Loan Rules
- **Callback Pattern**: Uses `IMarketCallback` interface
- **Repayment**: Must repay within same transaction
- **Fee Structure**: No additional fees beyond trading fees

### Price Calculation
- **Algorithm**: Uses cube root pricing (`cbrt(y/x * 10^128)`)
- **Precision**: 128-bit fixed-point arithmetic
- **Accumulator**: Time-weighted price tracking

## 📚 Library Usage Rules

### `Math.sol`
- **Purpose**: High-precision mathematical operations
- **Key Functions**: `fullMulDiv()`, `cbrt()`
- **Rule**: Always use for overflow-safe calculations

### `TransferHelper.sol`
- **Purpose**: Safe token transfers
- **Rule**: NEVER use raw `transfer()` calls
- **Pattern**: Always check return values and revert on failure

### `Validation.sol`
- **Purpose**: Input validation and security checks
- **Rule**: ALL external inputs must be validated
- **Functions**: `checkTokenOrder()`, `notThis()`, `notZero()`

### `Callback.sol`
- **Purpose**: External callback validation
- **Rule**: Validate callback sender before execution
- **Security**: Prevent unauthorized callback execution

## 🎯 Development Guidelines

### Code Organization
```
src/
├── Market.sol              # Main contract
├── abstracts/              # Base contracts
│   ├── Deadline.sol        # Deadline validation
│   ├── Liquidity.sol       # LP token implementation
│   ├── NoDelegatecall.sol  # Delegate call protection
│   └── ReentrancyGuard.sol # Reentrancy protection
├── interfaces/             # Contract interfaces
│   ├── IERC20.sol         # Standard ERC20
│   ├── ILiquidity.sol     # Liquidity interface
│   ├── IMarket.sol        # Market interface
│   └── IPayment.sol       # Payment interface
└── libraries/              # Utility libraries
    ├── Callback.sol        # Callback validation
    ├── Math.sol           # Mathematical operations
    ├── PairLibrary.sol    # Pair utilities
    ├── SafeCast.sol       # Type casting
    ├── TransferHelper.sol # Token transfers
    └── Validation.sol     # Input validation
```

### Testing Rules
- **Coverage**: All external functions must have tests
- **Edge Cases**: Test boundary conditions and error cases
- **Integration**: Test callback patterns and multi-contract interactions

### Gas Optimization Rules
- **Packing**: Use struct packing for storage efficiency
- **Caching**: Cache storage reads in memory
- **Batch Operations**: Combine multiple operations when possible

## ⚠️ Critical Warnings

### DO NOT:
1. Remove security modifiers (`nonReentrant`, `noDelegateCall`)
2. Modify the 4-reserve system without understanding implications
3. Change the TTL approval system without thorough testing
4. Skip input validation in any external function
5. Use raw token transfers instead of `TransferHelper`

### ALWAYS:
1. Validate token ordering before pair operations
2. Check deadlines in time-sensitive operations
3. Use safe mathematical operations from `Math.sol`
4. Implement proper callback validation
5. Test all edge cases thoroughly

## 🔧 Deployment Considerations

### Constructor Parameters
- `_owner`: Initial contract owner (critical for governance)

### Initial Setup
1. Deploy with proper owner address
2. Verify all library linkages
3. Test callback integrations
4. Validate fee calculations

### Upgrade Path
- Contract is not upgradeable by design
- Changes require new deployment
- Migration strategy needed for existing liquidity

## 🔗 Periphery Integration Guidelines

### Core Contract Interface Points
- **Market.sol**: Main integration point for all trading operations
- **Callback Requirements**: Periphery must implement `IMarketCallback` interface
- **Payment Flow**: Use `Callback.tokenCallback()` and `Callback.liquidityCallback()`
- **Balance Tracking**: Market contract maintains internal `tokenBalances` mapping

### Required Callback Implementations
```solidity
// For token payments (swaps, liquidity provision)
interface IMarketCallback {
    function tokenCallback(
        address to,
        address[] calldata tokens,
        uint256[] calldata balancesBefore,
        uint256[] calldata amounts
    ) external;
    
    function liquidityCallback(
        address to,
        uint256 poolId,
        uint128 longX, uint128 shortX,
        uint128 longY, uint128 shortY,
        LpInfo calldata lpInfo
    ) external;
}
```

### Integration Patterns
- **Router Pattern**: Periphery should validate inputs and handle slippage
- **Multicall Support**: Consider batching multiple operations
- **Deadline Enforcement**: Always include deadline parameters
- **Path Validation**: Ensure token ordering and path validity

### Security Considerations for Periphery
- **Slippage Protection**: Implement minimum output amount checks
- **Deadline Validation**: Enforce transaction deadlines
- **Access Control**: Consider who can call periphery functions
- **Callback Validation**: Ensure callbacks come from trusted Market contract

### TTL Approval Integration
- **Timestamp-based**: Approvals use `block.timestamp` for expiration
- **Permit Support**: Implement gasless approvals via EIP-712 signatures
- **Auto-expiry**: No need for explicit approval revocation

---

**Last Updated**: Based on codebase analysis and periphery preparation
**Version**: v1-core
**Solidity Version**: 0.8.28
