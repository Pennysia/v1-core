// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {Market} from "../../src/Market.sol";
import {ILiquidity} from "../../src/interfaces/ILiquidity.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IPayment} from "../../src/interfaces/IPayment.sol";

contract TestLiquidityCallback is IPayment {
    Market public market;
    address public lpOwner;

    constructor(Market _market) {
        market = _market;
    }

    function setLpOwner(address _lpOwner) external {
        lpOwner = _lpOwner;
    }

    function requestLiquidity(
        address, /*to*/
        uint256 poolId,
        uint128 amountForLongX,
        uint128 amountForShortX,
        uint128 amountForLongY,
        uint128 amountForShortY
    ) external override {
        console.log("=== requestLiquidity called ===");
        console.log("lpOwner:", lpOwner);
        console.log("lpOwner == address(0):", lpOwner == address(0));

        if (lpOwner == address(0)) {
            console.log("ERROR: lpOwner not set!");
            revert("lpOwner not set");
        }

        console.log("--- TestLiquidityCallback --- ");
        console.log("msg.sender (market contract):", msg.sender);
        console.log("callback address:", address(this));
        console.log("poolId:", poolId);

        uint256 allowance = ILiquidity(address(market)).allowance(lpOwner, address(this), poolId);
        console.log("Allowance:", allowance);
        console.log("block.timestamp:", block.timestamp);
        console.log("allowance >= block.timestamp:", allowance >= block.timestamp);

        console.log("About to call transferFrom...");
        ILiquidity(address(market)).transferFrom(
            lpOwner, address(0), poolId, amountForLongX, amountForShortX, amountForLongY, amountForShortY
        );
        console.log("transferFrom completed successfully");
    }

    function requestToken(address, /*_to*/ address[] memory tokens, uint256[] memory amounts)
        external
        payable
        override
    {
        // Transfer tokens to the market contract
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(address(market), amounts[i]);
        }
    }
}
