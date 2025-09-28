// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PairLibrary} from "../src/libraries/PairLibrary.sol";

contract PairLibraryTest is Test {
    // Tests for computePairId
    function test_ComputePairIdBasic() public pure {
        address token0 = address(0xA);
        address token1 = address(0xB);

        uint256 pairId = PairLibrary.computePairId(token0, token1);
        uint256 expectedId = uint256(keccak256(abi.encodePacked(token0, token1)));

        assertEq(pairId, expectedId, "computePairId should return correct keccak256 hash");
    }

    function test_ComputePairIdConsistency() public pure {
        address token0 = address(0x1234567890123456789012345678901234567890);
        address token1 = address(0xaBcDef1234567890123456789012345678901234);

        uint256 pairId1 = PairLibrary.computePairId(token0, token1);
        uint256 pairId2 = PairLibrary.computePairId(token0, token1);

        assertEq(pairId1, pairId2, "computePairId should be deterministic");
    }

    function test_ComputePairIdDifferentTokens() public pure {
        address token0 = address(0xA);
        address token1 = address(0xB);
        address token2 = address(0xC);

        uint256 pairId1 = PairLibrary.computePairId(token0, token1);
        uint256 pairId2 = PairLibrary.computePairId(token0, token2);

        assertTrue(pairId1 != pairId2, "Different token pairs should have different IDs");
    }

    function test_ComputePairIdZeroAddresses() public pure {
        address token0 = address(0);
        address token1 = address(0xB);

        uint256 pairId = PairLibrary.computePairId(token0, token1);
        uint256 expectedId = uint256(keccak256(abi.encodePacked(token0, token1)));

        assertEq(pairId, expectedId, "computePairId should handle zero addresses");
    }

    function test_ComputePairIdMaxAddresses() public pure {
        address token0 = address(type(uint160).max);
        address token1 = address(type(uint160).max - 1);

        uint256 pairId = PairLibrary.computePairId(token0, token1);
        uint256 expectedId = uint256(keccak256(abi.encodePacked(token0, token1)));

        assertEq(pairId, expectedId, "computePairId should handle max addresses");
    }

    function test_ComputePairIdOrderMatters() public pure {
        address token0 = address(0xA);
        address token1 = address(0xB);

        uint256 pairId1 = PairLibrary.computePairId(token0, token1);
        uint256 pairId2 = PairLibrary.computePairId(token1, token0);

        assertTrue(pairId1 != pairId2, "Token order should matter for pair ID");
    }

    function test_ComputePairIdFuzz(address token0, address token1) public pure {
        // Skip if tokens are the same (would be caught by validation in Market)
        vm.assume(token0 != token1);

        uint256 pairId = PairLibrary.computePairId(token0, token1);
        uint256 expectedId = uint256(keccak256(abi.encodePacked(token0, token1)));

        assertEq(pairId, expectedId, "computePairId should always return correct hash");
    }

    function test_ComputePairIdNonZero() public pure {
        address token0 = address(0xA);
        address token1 = address(0xB);

        uint256 pairId = PairLibrary.computePairId(token0, token1);

        assertTrue(pairId != 0, "Pair ID should not be zero for non-zero tokens");
    }

    function test_ComputePairIdCollisionResistance() public pure {
        // Test that similar addresses produce different hashes
        address token0 = address(0x1000000000000000000000000000000000000000);
        address token1 = address(0x2000000000000000000000000000000000000000);
        address token2 = address(0x1000000000000000000000000000000000000001);

        uint256 pairId1 = PairLibrary.computePairId(token0, token1);
        uint256 pairId2 = PairLibrary.computePairId(token0, token2);

        assertTrue(pairId1 != pairId2, "Similar addresses should produce different pair IDs");
    }

    function test_ComputePairIdGasUsage() public view {
        address token0 = address(0xA);
        address token1 = address(0xB);

        uint256 gasBefore = gasleft();
        PairLibrary.computePairId(token0, token1);
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;
        // keccak256 should be relatively cheap
        assertTrue(gasUsed < 10000, "computePairId should be gas efficient");
    }

    // Note: Other functions in PairLibrary.sol are commented out
    // If they get implemented, add tests here:

    // function test_SortTokens() public pure {
    //     // Test sortTokens function if implemented
    // }

    // function test_GetReserves() public {
    //     // Test getReserves function if implemented
    // }

    // function test_Quote() public pure {
    //     // Test quote function if implemented
    // }

    // function test_GetAmountOut() public pure {
    //     // Test getAmountOut function if implemented
    // }

    // function test_GetAmountIn() public pure {
    //     // Test getAmountIn function if implemented
    // }

    // function test_GetAmountsOut() public pure {
    //     // Test getAmountsOut function if implemented
    // }

    // function test_GetAmountsIn() public pure {
    //     // Test getAmountsIn function if implemented
    // }
}
