// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Liquidity} from "./abstracts/Liquidity.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {Validation} from "./libraries/Validation.sol";
import {PairLibrary} from "./libraries/PairLibrary.sol";
import {Math} from "./libraries/Math.sol";
import {Callback} from "./libraries/Callback.sol";

contract Market is IMarket, Liquidity {
    using SafeCast for uint256;

    uint8 private constant FEE = 3; // 0.3%
    uint256 private constant SCALE = 340282366920938463463374607431768211456; // 2**128

    address public owner;

    mapping(uint256 => Pair) public pairs;
    mapping(address => uint256) public tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, forbidden());
        owner = _owner;
    }

    function getPairId(address token0, address token1) public pure returns (uint256 pairId) {
        Validation.checkTokenOrder(token0, token1);
        pairId = PairLibrary.computePairId(token0, token1);
    }

    function getReserves(address token0, address token1)
        public
        view
        returns (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short)
    {
        Validation.checkTokenOrder(token0, token1);
        uint256 pairId = PairLibrary.computePairId(token0, token1);
        reserve0Long = pairs[pairId].reserve0Long;
        reserve0Short = pairs[pairId].reserve0Short;
        reserve1Long = pairs[pairId].reserve1Long;
        reserve1Short = pairs[pairId].reserve1Short;
    }

    function getSweepable(address token) public view returns (uint256) {
        return PairLibrary.getBalance(token) - tokenBalances[token];
    }

    // this low-level function should be called from a contract which performs important safety checks
    function createLiquidity(
        address to,
        address token0,
        address token1,
        uint256 amount0Long,
        uint256 amount0Short,
        uint256 amount1Long,
        uint256 amount1Short
    )
        external
        returns (
            uint256 pairId,
            uint256 liquidity0Long,
            uint256 liquidity0Short,
            uint256 liquidity1Long,
            uint256 liquidity1Short
        )
    {
        address callback = msg.sender;
        Validation.notThis(to);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens
        pairId = PairLibrary.computePairId(token0, token1);
        //request payment
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0Long + amount0Short;
        amounts[1] = amount1Long + amount1Short;
        uint256[] memory balancesBefore = new uint256[](2);
        balancesBefore[0] = PairLibrary.getBalance(token0);
        balancesBefore[1] = PairLibrary.getBalance(token1);

        Callback.tokenCallback(callback, to, tokens, balancesBefore, amounts); //user pays within this callback

        uint256 reserve0Long;
        uint256 reserve0Short;
        uint256 reserve1Long;
        uint256 reserve1Short;

        uint256 balance0 = tokenBalances[token0];
        uint256 balance1 = tokenBalances[token1];

        if (pairs[pairId].reserve0Long == 0) {
            reserve0Long = 1000;
            reserve0Short = 1000;
            reserve1Long = 1000;
            reserve1Short = 1000;
            uint128 million = 1000000;
            _mint(address(0), pairId, million, million, million, million); // intial ratio 1:1000
            emit Mint(callback, address(0), pairId, 1000000, 1000000);

            balance0 += 2000;
            balance1 += 2000;
            require(
                amount0Long >= reserve0Long && amount0Short >= reserve0Short && amount1Long >= reserve1Long
                    && amount1Short >= reserve1Short,
                minimumLiquidity()
            );
            amount0Long -= reserve0Long;
            amount0Short -= reserve0Short;
            amount1Long -= reserve1Long;
            amount1Short -= reserve1Short;
            emit Create(token0, token1, pairId);
        } else {
            reserve0Long = pairs[pairId].reserve0Long;
            reserve0Short = pairs[pairId].reserve0Short;
            reserve1Long = pairs[pairId].reserve1Long;
            reserve1Short = pairs[pairId].reserve1Short;
        }

        LpInfo storage lpInfo = _totalSupply[pairId];

        if (amount0Long > 0) {
            liquidity0Long = Math.fullMulDiv(amount0Long, lpInfo.longX, reserve0Long);
            reserve0Long += amount0Long;
        }
        if (amount0Short > 0) {
            liquidity0Short = Math.fullMulDiv(amount0Short, lpInfo.shortX, reserve0Short);
            reserve0Short += amount0Short;
        }
        if (amount1Long > 0) {
            liquidity1Long = Math.fullMulDiv(amount1Long, lpInfo.longY, reserve1Long);
            reserve1Long += amount1Long;
        }
        if (amount1Short > 0) {
            liquidity1Short = Math.fullMulDiv(amount1Short, lpInfo.shortY, reserve1Short);
            reserve1Short += amount1Short;
        }

        uint256 totalAmount0 = amount0Long + amount0Short;
        uint256 totalAmount1 = amount1Long + amount1Short;
        balance0 += totalAmount0;
        balance1 += totalAmount1;

        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        _updateBalance(token0, token1, balance0, balance1);
        _mint(
            to,
            pairId,
            liquidity0Long.safe128(),
            liquidity0Short.safe128(),
            liquidity1Long.safe128(),
            liquidity1Short.safe128()
        );
        emit Mint(callback, to, pairId, totalAmount0, totalAmount1);
    }

    function _updatePair(
        uint256 pairId,
        uint256 reserve0Long,
        uint256 reserve0Short,
        uint256 reserve1Long,
        uint256 reserve1Short
    ) private {
        uint256 reserve0Total = reserve0Long + reserve0Short;
        uint256 reserve1Total = reserve1Long + reserve1Short;
        uint64 blockTimestamp = uint64(block.timestamp); // won't overflow until the year 292 billion AD.
        uint64 timeElasped = blockTimestamp - pairs[pairId].blockTimestampLast;
        if (timeElasped > 0) {
            uint256 priceX128 = Math.fullMulDiv(reserve1Total, SCALE, reserve0Total);
            uint256 cbrtPriceX128 = Math.cbrt(priceX128);
            pairs[pairId].cbrtPriceX128CumulativeLast += uint192(cbrtPriceX128 * timeElasped); // won't overflow
        }
        pairs[pairId].blockTimestampLast = blockTimestamp;

        require(reserve0Long > 0 && reserve0Short > 0 && reserve1Long > 0 && reserve1Short > 0, minimumLiquidity());
        pairs[pairId].reserve0Long = reserve0Long.safe128();
        pairs[pairId].reserve0Short = reserve0Short.safe128();
        pairs[pairId].reserve1Long = reserve1Long.safe128();
        pairs[pairId].reserve1Short = reserve1Short.safe128();
    }

    function _updateBalance(address token0, address token1, uint256 balance0, uint256 balance1) private {
        tokenBalances[token0] = balance0;
        tokenBalances[token1] = balance1;
    }
}
