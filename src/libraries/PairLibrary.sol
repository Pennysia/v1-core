// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

library PairLibrary {
    // error zeroAmount();
    // error zeroReserve();
    // error invalidTokenPair();
    function computePairId(address token0, address token1) internal pure returns (uint256 pairId) {
        pairId = uint256(keccak256(abi.encodePacked(token0, token1)));
    }

    // function getReserves(address tokenIn, address tokenOut) internal pure returns(uint256 reserveIn, uint256 reserveOut){
    //     require(tokenIn != tokenOut, invalidTokenPair());
    //     uint256 reserve0;
    //     uint256 reserve1;
    //     bool switch;
    //     if(tokenIn < tokenOut){

    //     }else{

    //     }
    // }

    // function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns(uint256 amountOut){
    //     require(amountIn > 0, zeroAmount());
    //     require(reserveIn > 0 && reserveOut >0,zeroReserve() );
    //     uint256 amountInWithFee = amountIn * 997;
    //     uint256 numerator = amountInWithFee * reserveOut;
    //     uint256 denominator = (reserveIn * 1000) + amountInWithFee;
    //     amountOut = numerator / denominator;
    // }

    // function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns(uint256 amountIn){
    //     require(amountOut > 0, zeroAmount());
    //     require(reserveIn > 0 && reserveOut >0,zeroReserve() );
    //     uint256 numerator = reserveIn * amountOut * 1000;
    //     uint256 denominator = (reserveOut - amountOut) * 997;
    //     amountIn = (numerator / denominator) + 1;
    // }

    // function getReserves(address token0, address token1) internal pure returns()
}
