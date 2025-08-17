// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Validation} from "../src/libraries/Validation.sol";

contract ValidationTest is Test {
    // Tests for checkTokenOrder
    function test_CheckTokenOrderSuccess() public pure {
        address token0 = address(0x1);
        address token1 = address(0x2);

        // Should not revert when token0 < token1
        Validation.checkTokenOrder(token0, token1);
    }

    function test_CheckTokenOrderRevertsOnUnsorted() public {
        address token0 = address(0x2);
        address token1 = address(0x1);

        bool reverted = false;
        try this.callCheckTokenOrder(token0, token1) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "checkTokenOrder should revert when token0 >= token1");
    }

    function test_CheckTokenOrderRevertsOnEqual() public {
        address token = address(0x1);

        bool reverted = false;
        try this.callCheckTokenOrder(token, token) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "checkTokenOrder should revert when tokens are equal");
    }

    function test_CheckTokenOrderFuzz(address token0, address token1) public {
        if (token0 < token1) {
            // Should not revert
            Validation.checkTokenOrder(token0, token1);
        } else {
            // Should revert
            bool reverted = false;
            try this.callCheckTokenOrder(token0, token1) {
                // Should not reach here
            } catch {
                reverted = true;
            }
            assertTrue(reverted, "checkTokenOrder should revert when token0 >= token1");
        }
    }

    function callCheckTokenOrder(address token0, address token1) external pure {
        Validation.checkTokenOrder(token0, token1);
    }

    // Tests for equalLengths
    function test_EqualLengthsSuccess() public pure {
        Validation.equalLengths(5, 5);
        Validation.equalLengths(0, 0);
        Validation.equalLengths(100, 100);
    }

    function test_EqualLengthsRevertsOnMismatch() public {
        bool reverted = false;
        try this.callEqualLengths(5, 3) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "equalLengths should revert on length mismatch");
    }

    function test_EqualLengthsFuzz(uint256 length0, uint256 length1) public {
        if (length0 == length1) {
            // Should not revert
            Validation.equalLengths(length0, length1);
        } else {
            // Should revert
            bool reverted = false;
            try this.callEqualLengths(length0, length1) {
                // Should not reach here
            } catch {
                reverted = true;
            }
            assertTrue(reverted, "equalLengths should revert on length mismatch");
        }
    }

    function callEqualLengths(uint256 length0, uint256 length1) external pure {
        Validation.equalLengths(length0, length1);
    }

    // Tests for notThis
    function test_NotThisSuccess() public view {
        address other = address(0x1);
        Validation.notThis(other);
    }

    function test_NotThisRevertsOnSelfAddress() public {
        bool reverted = false;
        try this.callNotThis(address(this)) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "notThis should revert when input is address(this)");
    }

    function test_NotThisFuzz(address input) public {
        if (input != address(this)) {
            // Should not revert
            Validation.notThis(input);
        } else {
            // Should revert
            bool reverted = false;
            try this.callNotThis(input) {
                // Should not reach here
            } catch {
                reverted = true;
            }
            assertTrue(reverted, "notThis should revert when input is address(this)");
        }
    }

    function callNotThis(address input) external view {
        Validation.notThis(input);
    }

    // Tests for notZero
    function test_NotZeroSuccess() public pure {
        Validation.notZero(1);
        Validation.notZero(100);
        Validation.notZero(type(uint256).max);
    }

    function test_NotZeroRevertsOnZero() public {
        bool reverted = false;
        try this.callNotZero(0) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "notZero should revert when input is 0");
    }

    function test_NotZeroFuzz(uint256 input) public {
        if (input > 0) {
            // Should not revert
            Validation.notZero(input);
        } else {
            // Should revert
            bool reverted = false;
            try this.callNotZero(input) {
                // Should not reach here
            } catch {
                reverted = true;
            }
            assertTrue(reverted, "notZero should revert when input is 0");
        }
    }

    function callNotZero(uint256 input) external pure {
        Validation.notZero(input);
    }

    // Edge cases and comprehensive tests
    function test_ValidationEdgeCases() public view {
        // Test with zero addresses
        Validation.checkTokenOrder(address(0), address(1));

        // Test with max addresses
        Validation.checkTokenOrder(address(0), address(type(uint160).max));

        // Test notThis with zero address
        Validation.notThis(address(0));

        // Test equalLengths with large numbers
        Validation.equalLengths(type(uint256).max, type(uint256).max);

        // Test notZero with max value
        Validation.notZero(type(uint256).max);
    }

    function test_ValidationCombinations() public view {
        // Test multiple validations in sequence
        address token0 = address(0x1);
        address token1 = address(0x2);

        Validation.checkTokenOrder(token0, token1);
        Validation.equalLengths(5, 5);
        Validation.notThis(token0);
        Validation.notZero(100);

        // All should pass without reverting
    }
}
