// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./interfaces/IOneSwapRouter.sol";
import "./interfaces/IOneSwapFactory.sol";
import "./interfaces/IOneSwapPair.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath256.sol";
import "./libraries/DecFloat32.sol";


contract OneSwapRouter is IOneSwapRouter {
    using SafeMath256 for uint;
    address public immutable override factory;

    modifier ensure(uint deadline) {
        // solhint-disable-next-line not-rely-on-time,
        require(deadline >= block.timestamp, "OneSwapRouter: EXPIRED");
        _;
    }

    constructor(address _factory) public {
        factory = _factory;
    }

    function _addLiquidity(address pair, uint amountStockDesired, uint amountMoneyDesired,
        uint amountStockMin, uint amountMoneyMin) private view returns (uint amountStock, uint amountMoney) {

        (uint reserveStock, uint reserveMoney, ) = IOneSwapPool(pair).getReserves();
        if (reserveStock == 0 && reserveMoney == 0) {
            (amountStock, amountMoney) = (amountStockDesired, amountMoneyDesired);
        } else {
            uint amountMoneyOptimal = _quote(amountStockDesired, reserveStock, reserveMoney);
            if (amountMoneyOptimal <= amountMoneyDesired) {
                require(amountMoneyOptimal >= amountMoneyMin, "OneSwapRouter: INSUFFICIENT_MONEY_AMOUNT");
                (amountStock, amountMoney) = (amountStockDesired, amountMoneyOptimal);
            } else {
                uint amountStockOptimal = _quote(amountMoneyDesired, reserveMoney, reserveStock);
                assert(amountStockOptimal <= amountStockDesired);
                require(amountStockOptimal >= amountStockMin, "OneSwapRouter: INSUFFICIENT_STOCK_AMOUNT");
                (amountStock, amountMoney) = (amountStockOptimal, amountMoneyDesired);
            }
        }
    }

    function addLiquidity(address stock, address money, bool isOnlySwap, uint amountStockDesired,
        uint amountMoneyDesired, uint amountStockMin, uint amountMoneyMin, address to, uint deadline) external
        payable override ensure(deadline) returns (uint amountStock, uint amountMoney, uint liquidity) {

        if (stock != address(0) && money != address(0)) {
            require(msg.value == 0, 'OneSwapRouter: NOT_ENTER_ETH_VALUE');
        }
        address pair = IOneSwapFactory(factory).tokensToPair(stock, money, isOnlySwap);
        if (pair == address(0)) {
            pair = IOneSwapFactory(factory).createPair(stock, money, isOnlySwap);
        }
        (amountStock, amountMoney) = _addLiquidity(pair, amountStockDesired,
            amountMoneyDesired, amountStockMin, amountMoneyMin);
        _safeTransferFrom(stock, msg.sender, pair, amountStock);
        _safeTransferFrom(money, msg.sender, pair, amountMoney);
        liquidity = IOneSwapPool(pair).mint(to);
        emit AddLiquidity(amountStock, amountMoney, liquidity);
    }

    function _removeLiquidity(address pair, uint liquidity, uint amountStockMin,
        uint amountMoneyMin, address to) private returns (uint amountStock, uint amountMoney) {
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (amountStock, amountMoney) = IOneSwapPool(pair).burn(to);
        require(amountStock >= amountStockMin, "OneSwapRouter: INSUFFICIENT_STOCK_AMOUNT");
        require(amountMoney >= amountMoneyMin, "OneSwapRouter: INSUFFICIENT_MONEY_AMOUNT");
    }

    function removeLiquidity(address pair, uint liquidity, uint amountStockMin, uint amountMoneyMin,
        address to, uint deadline) external override ensure(deadline) returns (uint amountStock, uint amountMoney) {
        // ensure pair exist
        _getTokensFromPair(pair);
        (amountStock, amountMoney) = _removeLiquidity(pair, liquidity, amountStockMin, amountMoneyMin, to);
    }

    function _swap(address input, uint amountIn, address[] memory path, address _to) internal virtual returns (uint[] memory amounts) {
        amounts = new uint[](path.length + 1);
        amounts[0] = amountIn;

        for (uint i = 0; i < path.length; i++) {
            (address to, bool isLastSwap) = i < path.length - 1 ? (path[i+1], false) : (_to, true);
            amounts[i + 1] = IOneSwapPair(path[i]).addMarketOrder(input, to, uint112(amounts[i]));
            if (!isLastSwap) {
                (address stock, address money) = _getTokensFromPair(path[i]);
                input = (stock != input) ? stock : money;
            }
        }
    }

    function swapToken(address token, uint amountIn, uint amountOutMin, address[] calldata path,
        address to, uint deadline) external payable override ensure(deadline) returns (uint[] memory amounts) {

        if (token != address(0)) { require(msg.value == 0, 'OneSwapRouter: NOT_ENTER_ETH_VALUE'); }
        require(path.length >= 1, "OneSwapRouter: INVALID_PATH");
        // ensure pair exist
        _getTokensFromPair(path[0]);
        _safeTransferFrom(token, msg.sender, path[0], amountIn);
        amounts = _swap(token, amountIn, path, to);
        require(amounts[path.length] >= amountOutMin, "OneSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function limitOrder(bool isBuy, address pair, uint prevKey, uint price, uint32 id,
        uint stockAmount, uint deadline) external payable override ensure(deadline) {

        (address stock, address money) = _getTokensFromPair(pair);
        {
            (uint _stockAmount, uint _moneyAmount) = IOneSwapPair(pair).calcStockAndMoney(uint64(stockAmount), uint32(price));
            if (isBuy) {
                if (money != address(0)) { require(msg.value == 0, 'OneSwapRouter: NOT_ENTER_ETH_VALUE'); }
                _safeTransferFrom(money, msg.sender, pair, _moneyAmount);
            } else {
                if (stock != address(0)) { require(msg.value == 0, 'OneSwapRouter: NOT_ENTER_ETH_VALUE'); }
                _safeTransferFrom(stock, msg.sender, pair, _stockAmount);
            }
        }
        IOneSwapPair(pair).addLimitOrder(isBuy, msg.sender, uint64(stockAmount), uint32(price), id, uint72(prevKey));
    }

    // todo. add encoded bytes interface for limitOrder.

    function _safeTransferFrom(address token, address from, address to, uint value) internal {
        if (token == address(0)) {
            _safeTransferETH(to, value);
            uint inputValue = msg.value;
            if (inputValue > value) { _safeTransferETH(msg.sender, inputValue - value); }
            return;
        }

        uint beforeAmount = IERC20(token).balanceOf(to);
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "OneSwapRouter: TRANSFER_FROM_FAILED");
        uint afterAmount = IERC20(token).balanceOf(to);
        require(afterAmount == beforeAmount + value, "OneSwapRouter: TRANSFER_FAILED");
    }

    function _safeTransferETH(address to, uint value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "OneSwapRouter: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "OneSwapRouter: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }

    function _getTokensFromPair(address pair) internal view returns(address stock, address money) {
        (stock, money) = IOneSwapFactory(factory).getTokensFromPair(pair);
        require(stock != address(0) || money != address(0), "OneSwapRouter: PAIR_NOT_EXIST");
    }
}
