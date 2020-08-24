// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IOneSwapRouter {
    event AddLiquidity(uint stockAmount, uint moneyAmount, uint liquidity);
    event PairCreated(address indexed pair, address stock, address money, bool isOnlySwap);

    function factory() external pure returns (address);
    function weth() external pure returns (address);

    // liquidity
    function addLiquidity(
        address stock,
        address money,
        bool isOnlySwap,
        uint amountStockDesired,
        uint amountMoneyDesired,
        uint amountStockMin,
        uint amountMoneyMin,
        address to,
        uint deadline
    ) external returns (uint amountStock, uint amountMoney, uint liquidity);
    function addLiquidityETH(
        address token,
        bool tokenIsStock,
        bool isOnlySwap,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountStock, uint amountMoney, uint liquidity);
    function removeLiquidity(
        address pair,
        uint liquidity,
        uint amountStockMin,
        uint amountMoneyMin,
        address to,
        uint deadline
    ) external returns (uint amountStock, uint amountMoney);
    function removeLiquidityETH(
        address pair,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountStock, uint amountMoney);

    // swap token
    function swapToken(
        address token,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    // limit order
    function limitOrder(
        bool isBuy,
        address pair,
        uint prevKey,
        uint price,
        uint32 id,
        uint stockAmount,
        uint deadline
    ) external;
    function limitOrderWithETH(
        bool isBuy,
        address pair,
        uint prevKey,
        uint price,
        uint32 id,
        uint stockAmount,
        uint deadline
    ) external payable;
    function removeLimitOrder(
        bool isBuy,
        address pair,
        uint prevKey,
        uint orderId
    ) external;
}
