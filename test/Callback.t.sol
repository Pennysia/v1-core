// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Callback} from "../src/libraries/Callback.sol";
import {ILiquidity} from "../src/interfaces/ILiquidity.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {PairLibrary} from "../src/libraries/PairLibrary.sol";

// Mock ERC20 for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOfMap;

    function setBalance(address account, uint256 amount) external {
        balanceOfMap[account] = amount;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return balanceOfMap[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOfMap[msg.sender] >= amount, "Insufficient balance");
        balanceOfMap[msg.sender] -= amount;
        balanceOfMap[recipient] += amount;
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        balanceOfMap[sender] -= amount;
        balanceOfMap[recipient] += amount;
        return true;
    }

    function allowance(
        address,
        address
    ) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }
}

// Mock Payment contract that implements IPayment
contract MockPayment {
    bool public shouldPayCorrectly;

    constructor(bool _shouldPayCorrectly) {
        shouldPayCorrectly = _shouldPayCorrectly;
    }

    function requestToken(
        address,
        address[] memory tokens,
        uint256[] memory paybackAmounts
    ) external {
        if (shouldPayCorrectly) {
            // Pay the correct amounts
            for (uint256 i = 0; i < tokens.length; i++) {
                MockERC20(tokens[i]).transfer(msg.sender, paybackAmounts[i]);
            }
        } else {
            // Pay insufficient amounts (underpayment)
            for (uint256 i = 0; i < tokens.length; i++) {
                if (paybackAmounts[i] > 0) {
                    MockERC20(tokens[i]).transfer(
                        msg.sender,
                        paybackAmounts[i] - 1
                    );
                }
            }
        }
    }

    function requestLiquidity(
        address,
        uint256,
        uint128,
        uint128,
        uint128,
        uint128
    ) external view {
        // For liquidity callback, we need to simulate burning LP tokens
        // This would normally interact with the Market contract
        // For testing purposes, we'll just check if we should behave correctly
        if (!shouldPayCorrectly) {
            // Simulate insufficient burn by not doing anything
            return;
        }
        // In a real scenario, this would call market.transferFrom to burn LP tokens
    }
}

// Mock Liquidity contract to test liquidityCallback
contract MockLiquidity {
    mapping(uint256 => ILiquidity.LpInfo) public totalSupply;

    function setTotalSupply(
        uint256 pairId,
        uint128 longX,
        uint128 shortX,
        uint128 longY,
        uint128 shortY
    ) external {
        totalSupply[pairId] = ILiquidity.LpInfo({
            longX: longX,
            shortX: shortX,
            longY: longY,
            shortY: shortY
        });
    }

    function getTotalSupply(
        uint256 pairId
    ) external view returns (ILiquidity.LpInfo memory) {
        return totalSupply[pairId];
    }
}

contract CallbackTest is Test {
    MockERC20 public token0;
    MockERC20 public token1;
    MockPayment public correctPayment;
    MockPayment public underpayment;
    MockLiquidity public mockLiquidity;

    function setUp() public {
        token0 = new MockERC20();
        token1 = new MockERC20();
        correctPayment = new MockPayment(true);
        underpayment = new MockPayment(false);
        mockLiquidity = new MockLiquidity();
    }

    // Tests for tokenCallback
    function test_TokenCallbackSingleToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;

        // Set up balances
        token0.setBalance(address(correctPayment), 1000);

        // Record initial balance
        uint256 initialBalance = token0.balanceOf(address(this));

        // Prepare balancesBefore
        uint256[] memory balancesBefore = new uint256[](1);
        balancesBefore[0] = token0.balanceOf(address(this));

        // Call tokenCallback
        Callback.tokenCallback(
            address(correctPayment),
            address(0xDEF),
            tokens,
            balancesBefore,
            amounts
        );

        // Check that payment was made
        assertEq(
            token0.balanceOf(address(this)),
            initialBalance + 1000,
            "Should receive payment"
        );
    }

    function test_TokenCallbackMultipleTokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000;
        amounts[1] = 2000;

        // Set up balances
        token0.setBalance(address(correctPayment), 1000);
        token1.setBalance(address(correctPayment), 2000);

        // Record initial balances
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));

        // Prepare balancesBefore
        uint256[] memory balancesBefore = new uint256[](2);
        balancesBefore[0] = token0.balanceOf(address(this));
        balancesBefore[1] = token1.balanceOf(address(this));

        // Call tokenCallback
        Callback.tokenCallback(
            address(correctPayment),
            address(0xDEF),
            tokens,
            balancesBefore,
            amounts
        );

        // Check that payments were made
        assertEq(
            token0.balanceOf(address(this)),
            initialBalance0 + 1000,
            "Should receive token0 payment"
        );
        assertEq(
            token1.balanceOf(address(this)),
            initialBalance1 + 2000,
            "Should receive token1 payment"
        );
    }

    function test_TokenCallbackRevertsOnUnderpayment() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;

        // Set up balance for underpayment - callback needs enough to pay back, but will pay less
        token0.setBalance(address(underpayment), 1000);

        // The callback will be called and should pay back to address(this) (the test contract)
        // Initial balance should be 0, after underpayment should be 999, expected is 1000
        uint256 initialBalance = token0.balanceOf(address(this));
        assertEq(initialBalance, 0, "Initial balance should be 0");

        // Prepare balancesBefore
        uint256[] memory balancesBefore = new uint256[](1);
        balancesBefore[0] = token0.balanceOf(address(this));

        // Should revert due to underpayment (pays back 999 instead of 1000)
        vm.expectRevert(Callback.InsufficientPayback.selector);
        this.callTokenCallback(
            address(underpayment),
            tokens,
            balancesBefore,
            amounts
        );
    }

    function callTokenCallback(
        address caller,
        address[] memory tokens,
        uint256[] memory balancesBefore,
        uint256[] memory amounts
    ) external {
        Callback.tokenCallback(
            caller,
            address(0xDEF),
            tokens,
            balancesBefore,
            amounts
        );
    }

    function test_TokenCallbackZeroAmount() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        uint256[] memory balancesBefore = new uint256[](1);
        balancesBefore[0] = token0.balanceOf(address(this));
        // Should work with zero amounts
        Callback.tokenCallback(
            address(correctPayment),
            address(0xDEF),
            tokens,
            balancesBefore,
            amounts
        );
    }

    function test_TokenCallbackFuzz(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        token0.setBalance(address(correctPayment), amount);

        uint256 initialBalance = token0.balanceOf(address(this));
        uint256[] memory balancesBefore = new uint256[](1);
        balancesBefore[0] = token0.balanceOf(address(this));

        Callback.tokenCallback(
            address(correctPayment),
            address(0xDEF),
            tokens,
            balancesBefore,
            amounts
        );

        assertEq(
            token0.balanceOf(address(this)),
            initialBalance + amount,
            "Should receive correct payment"
        );
    }

    // Tests for liquidityCallback
    function test_LiquidityCallbackSuccess() public {
        uint256 pairId = 123;
        uint128 liquidity0Long = 1000;
        uint128 liquidity0Short = 2000;
        uint128 liquidity1Long = 3000;
        uint128 liquidity1Short = 4000;

        // Set up initial total supply
        mockLiquidity.setTotalSupply(
            pairId,
            liquidity0Long + 1000,
            liquidity0Short + 2000,
            liquidity1Long + 3000,
            liquidity1Short + 4000
        );

        // Mock the liquidity contract call by setting up storage
        // In a real scenario, this would interact with the Market contract
        // For testing, we'll use vm.mockCall to simulate the totalSupply call
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("_totalSupply(uint256)", pairId),
            abi.encode(
                ILiquidity.LpInfo({
                    longX: liquidity0Long + 1000,
                    shortX: liquidity0Short + 2000,
                    longY: liquidity1Long + 3000,
                    shortY: liquidity1Short + 4000
                })
            )
        );

        // This test would need to be integrated with the Market contract
        // to properly test the liquidityCallback function
        // For now, we'll test the basic structure

        // The actual test would call:
        // Callback.liquidityCallback(address(correctPayment), address(0xDEF), pairId, liquidity0Long, liquidity0Short, liquidity1Long, liquidity1Short, totalSupplyBefore);

        // And verify that the total supply decreased by the burned amounts
    }

    function test_LiquidityCallbackRevertsOnInsufficientBurn() public view {
        // uint256 pairId = 123;
        // uint128 liquidity0Long = 1000;
        // uint128 liquidity0Short = 2000;
        // uint128 liquidity1Long = 3000;
        // uint128 liquidity1Short = 4000;
        // This test would verify that liquidityCallback reverts when
        // the total supply doesn't decrease by the expected amount
        // Implementation would require integration with Market contract
        // vm.expectRevert(Callback.InsufficientPayback.selector);
        // Callback.liquidityCallback(address(underpayment), address(0xDEF), pairId, liquidity0Long, liquidity0Short, liquidity1Long, liquidity1Short, totalSupplyBefore);
    }

    // Test checkBal function
    function test_CheckBal() public view {
        uint256 balance = token0.balanceOf(address(this));
        uint256 result = PairLibrary.getBalance(address(token0));
        assertEq(result, balance, "checkBal should return correct balance");
    }

    function test_CheckBalZero() public view {
        uint256 result = PairLibrary.getBalance(address(token0));
        assertEq(result, 0, "checkBal should return 0 for zero balance");
    }

    function test_CheckBalFuzz(uint256 balance) public {
        token0.setBalance(address(this), balance);
        uint256 result = PairLibrary.getBalance(address(token0));
        assertEq(result, balance, "checkBal should return correct balance");
    }
}
