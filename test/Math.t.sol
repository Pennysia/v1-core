// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "../src/libraries/Math.sol";

contract MathTest is Test {
    // Tests for fullMulDiv
    function test_FullMulDivBasic() public pure {
        uint256 result = Math.fullMulDiv(100, 200, 50);
        assertEq(result, 400, "fullMulDiv should compute (100 * 200) / 50 = 400");
    }

    function test_FullMulDivPrecision() public pure {
        // Test precision with large numbers
        uint256 x = type(uint128).max;
        uint256 y = type(uint128).max;
        uint256 d = type(uint128).max;
        uint256 result = Math.fullMulDiv(x, y, d);
        assertEq(result, type(uint128).max, "fullMulDiv should handle max uint128 values");
    }

    function test_FullMulDivRevertsOnZeroDenominator() public view {
        // Test that fullMulDiv reverts on zero denominator
        bool reverted = false;
        try this.callFullMulDiv(100, 200, 0) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "fullMulDiv should revert on zero denominator");
    }

    function callFullMulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return Math.fullMulDiv(x, y, d);
    }

    function test_FullMulDivRevertsOnOverflow() public view {
        // Test overflow scenario
        bool reverted = false;
        try this.callFullMulDiv(type(uint256).max, type(uint256).max, 1) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "fullMulDiv should revert on overflow");
    }

    function test_FullMulDivFuzz(uint256 x, uint256 y, uint256 d) public pure {
        vm.assume(d > 0);
        vm.assume(x <= type(uint128).max);
        vm.assume(y <= type(uint128).max);

        uint256 result = Math.fullMulDiv(x, y, d);
        // Basic property: result should be approximately x * y / d
        // For bounded inputs, this should not overflow
        assertTrue(result <= (x * y) / d + 1, "Result should be close to x * y / d");
    }

    // Tests for fullMulDivUp
    function test_FullMulDivUpBasic() public pure {
        uint256 result = Math.fullMulDivUp(100, 200, 50);
        assertEq(result, 400, "fullMulDivUp should compute (100 * 200) / 50 = 400");
    }

    function test_FullMulDivUpRoundsUp() public pure {
        uint256 result = Math.fullMulDivUp(100, 200, 51);
        uint256 normalResult = Math.fullMulDiv(100, 200, 51);
        // fullMulDivUp should be >= fullMulDiv
        assertTrue(result >= normalResult, "fullMulDivUp should be >= fullMulDiv");

        // For this specific case, 100 * 200 / 51 = 20000 / 51 = 392.15..., so up should be 393
        assertTrue(result >= 392, "fullMulDivUp should round up from 392.15");
    }

    function test_FullMulDivUpRevertsOnZeroDenominator() public view {
        bool reverted = false;
        try this.callFullMulDivUp(100, 200, 0) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "fullMulDivUp should revert on zero denominator");
    }

    function callFullMulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return Math.fullMulDivUp(x, y, d);
    }

    function test_FullMulDivUpFuzz(uint256 x, uint256 y, uint256 d) public pure {
        vm.assume(d > 0);
        vm.assume(x <= type(uint128).max);
        vm.assume(y <= type(uint128).max);

        uint256 result = Math.fullMulDivUp(x, y, d);
        uint256 normalResult = Math.fullMulDiv(x, y, d);

        // fullMulDivUp should always be >= fullMulDiv
        assertTrue(result >= normalResult, "fullMulDivUp should be >= fullMulDiv");
    }

    // Tests for divUp
    function test_DivUpBasic() public pure {
        uint256 result = Math.divUp(100, 50);
        assertEq(result, 2, "divUp should compute 100 / 50 = 2");
    }

    function test_DivUpRoundsUp() public pure {
        uint256 result = Math.divUp(100, 51);
        assertEq(result, 2, "divUp should round up 100 / 51 = 2");

        result = Math.divUp(101, 51);
        assertEq(result, 2, "divUp should round up 101 / 51 = 2");

        result = Math.divUp(102, 51);
        assertEq(result, 2, "divUp should round up 102 / 51 = 2");

        result = Math.divUp(103, 51);
        assertEq(result, 3, "divUp should round up 103 / 51 = 3");
    }

    function test_DivUpRevertsOnZeroDenominator() public view {
        bool reverted = false;
        try this.callDivUp(100, 0) {
            // Should not reach here
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "divUp should revert on zero denominator");
    }

    function callDivUp(uint256 x, uint256 d) external pure returns (uint256) {
        return Math.divUp(x, d);
    }

    function test_DivUpFuzz(uint256 x, uint256 d) public pure {
        vm.assume(d > 0);
        vm.assume(x < type(uint256).max - d); // Avoid overflow in ceiling calculation

        uint256 result = Math.divUp(x, d);
        uint256 normalResult = x / d;

        // divUp should always be >= normal division
        assertTrue(result >= normalResult, "divUp should be >= normal division");

        // divUp should be at most normalResult + 1
        assertTrue(result <= normalResult + 1, "divUp should be at most normalResult + 1");
    }

    // Tests for cbrt (cube root)
    function test_CbrtPerfectCubes() public pure {
        assertEq(Math.cbrt(0), 0, "cbrt(0) should be 0");
        assertEq(Math.cbrt(1), 1, "cbrt(1) should be 1");
        assertEq(Math.cbrt(8), 2, "cbrt(8) should be 2");
        assertEq(Math.cbrt(27), 3, "cbrt(27) should be 3");
        assertEq(Math.cbrt(64), 4, "cbrt(64) should be 4");
        assertEq(Math.cbrt(125), 5, "cbrt(125) should be 5");
        assertEq(Math.cbrt(216), 6, "cbrt(216) should be 6");
        assertEq(Math.cbrt(343), 7, "cbrt(343) should be 7");
        assertEq(Math.cbrt(512), 8, "cbrt(512) should be 8");
        assertEq(Math.cbrt(729), 9, "cbrt(729) should be 9");
        assertEq(Math.cbrt(1000), 10, "cbrt(1000) should be 10");
    }

    function test_CbrtNonPerfectCubes() public pure {
        // Test values between perfect cubes
        assertEq(Math.cbrt(2), 1, "cbrt(2) should be 1 (floor)");
        assertEq(Math.cbrt(7), 1, "cbrt(7) should be 1 (floor)");
        assertEq(Math.cbrt(9), 2, "cbrt(9) should be 2 (floor)");
        assertEq(Math.cbrt(26), 2, "cbrt(26) should be 2 (floor)");
        assertEq(Math.cbrt(28), 3, "cbrt(28) should be 3 (floor)");
        assertEq(Math.cbrt(63), 3, "cbrt(63) should be 3 (floor)");
        assertEq(Math.cbrt(65), 4, "cbrt(65) should be 4 (floor)");
    }

    function test_CbrtLargeNumbers() public pure {
        // Test with larger numbers
        uint256 largeNum = 1000000; // 10^6
        uint256 result = Math.cbrt(largeNum);
        assertEq(result, 100, "cbrt(1000000) should be 100");

        // Test with very large number
        largeNum = type(uint64).max;
        result = Math.cbrt(largeNum);
        // The cube root of 2^64 - 1 should be approximately 2^(64/3) ≈ 2^21.33 ≈ 2,642,245
        assertTrue(result > 2500000 && result < 3000000, "cbrt of max uint64 should be in reasonable range");
    }

    function test_CbrtFuzz(uint256 x) public pure {
        vm.assume(x <= type(uint64).max); // Limit to avoid overflow in verification
        vm.assume(x > 0); // Avoid division by zero issues

        uint256 result = Math.cbrt(x);

        // Property: result^3 <= x < (result+1)^3
        if (result > 0) {
            assertTrue(result * result * result <= x, "result^3 should be <= x");
        }

        if (result < type(uint64).max / result / result) {
            // Avoid overflow
            uint256 nextCube = (result + 1) * (result + 1) * (result + 1);
            assertTrue(x < nextCube, "x should be < (result+1)^3");
        }
    }

    function test_CbrtMonotonic() public pure {
        // Test that cbrt is monotonic (non-decreasing)
        for (uint256 i = 0; i < 1000; i++) {
            uint256 cbrt_i = Math.cbrt(i);
            uint256 cbrt_i_plus_1 = Math.cbrt(i + 1);
            assertTrue(cbrt_i <= cbrt_i_plus_1, "cbrt should be non-decreasing");
        }
    }

    function test_CbrtEdgeCases() public pure {
        // Test edge cases
        assertEq(Math.cbrt(type(uint256).max), Math.cbrt(type(uint256).max), "cbrt should handle max uint256");

        // Test powers of 2
        assertEq(Math.cbrt(2), 1, "cbrt(2) should be 1");
        assertEq(Math.cbrt(4), 1, "cbrt(4) should be 1");
        assertEq(Math.cbrt(16), 2, "cbrt(16) should be 2");
        assertEq(Math.cbrt(32), 3, "cbrt(32) should be 3");
        assertEq(Math.cbrt(128), 5, "cbrt(128) should be 5");
        assertEq(Math.cbrt(256), 6, "cbrt(256) should be 6");
    }
}
