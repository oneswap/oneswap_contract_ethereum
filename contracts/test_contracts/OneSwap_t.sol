// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import '../OneSwapRouter.sol';
import '../OneSwapPair.sol';
import './token.sol';
import '../libraries/Math.sol';
import '../libraries/SafeMath256.sol';

contract OneSwapFuzzTest {
    using SafeMath256 for uint;

    event Succeed(bool isSuccedd);
    event PrintNumber(uint stock, uint money, uint sqrt);

    struct Context{
        uint pairStockAmount;
        uint pairMoneyAmount;
        uint112 pairReserveStock;
        uint112 pairReserveMoney;
        uint userStockAmount;
        uint userMoneyAmount;
        uint pairLiquidity;
        uint userLiquidity;
        uint totalLiquidity;
    }

    address _stock;
    address _money;
    bool _isOnlySwap;
    DSToken _token0;
    DSToken _token1;
    OneSwapRouter _router;
    uint _MINIMUM_LIQUIDITY = 10 ** 3;
    IOneSwapFactory _factory;

    constructor (address stock, address money, bool isOnlySwap, address payable router, address factory ) public {
        _stock = stock;
        _money = money;
        _isOnlySwap = isOnlySwap;
        _token0 = DSToken(stock);
        _token1 = DSToken(money);
        _router = OneSwapRouter(router);
        _factory = IOneSwapFactory(factory);
    }

    receive() external payable {}

    function approve() public {
        if (_stock != address(0)) { _token0.approve(address(_router)); }
        if (_money != address(0)) { _token1.approve(address(_router)); }
    }

    function approveLiquidity() public {
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        bool isOk = IERC20(pair).approve(address(_router), uint(-1));
        require(isOk == true, 'approve failed');
    }

    function balanceOf(address token, address user) internal returns(uint){
        if (token == address(0)){ return user.balance;}
        return IERC20(token).balanceOf(user);
    }

    function transferFrom(address from, address to, address token, uint amount) internal {
        if (token != address(0)) {
            IERC20(token).transferFrom(from, to, amount);
        }
    }

    function transfer(address payable to, address token, uint amount) internal {
        if (token == address(0)) {
            (bool success,) = to.call{value:amount}(new bytes(0));
            require(success, "Transfer: ETH_TRANSFER_FAILED");
        }
        else{ IERC20(token).transfer(to, amount); }
    }

    function addLiquidityInitial(uint[2] calldata inputAmounts) public payable {
        if (inputAmounts[0] == 0 || inputAmounts[1] == 0) { emit Succeed(true); return; }

        uint userBal0 = balanceOf(_stock, msg.sender);
        uint userBal1 = balanceOf(_money, msg.sender);
        if (userBal0 < inputAmounts[0] || userBal1 < inputAmounts[1]) { emit Succeed(true); return; }
        uint expectLiquidity = Math.sqrt(inputAmounts[0] * inputAmounts[1]) - _MINIMUM_LIQUIDITY;
        if (expectLiquidity <_MINIMUM_LIQUIDITY) { emit Succeed(true); return; }

        uint ethAmount;
        if (_stock == address(0)){  ethAmount = inputAmounts[0]; }
        else if (_money == address(0)) { ethAmount = inputAmounts[1]; }
        transferFrom(msg.sender, address(this), _stock, inputAmounts[0]);
        transferFrom(msg.sender, address(this), _money, inputAmounts[1]);
        (uint outAmountStock, uint outAmountMoney, uint outLiquidity) = _router.addLiquidity{value: ethAmount}(_stock, _money,
            _isOnlySwap, inputAmounts[0], inputAmounts[1], 0, 0, msg.sender, 99999999999);

        require(outAmountStock == inputAmounts[0], 'stock amount wrong in initial add liquidity');
        require(outAmountMoney == inputAmounts[1], 'money amount wrong in initial add liquidity');
        require(outLiquidity == expectLiquidity, 'liquidity wrong in initial add liquidity');

        // liquidity in pair
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        require(balanceOf(pair, address(0)) == _MINIMUM_LIQUIDITY, 'pair selfAddress liquidity wrong in initial add liquidity');
        require(balanceOf(pair, msg.sender) == expectLiquidity, 'msg.sender liquidity wrong in initial add liquidity');
        require(OneSwapERC20(pair).totalSupply() == _MINIMUM_LIQUIDITY + expectLiquidity, 'total liquidity wrong in initial add liquidity');

        // tokens balance require in msg.sender
        _stock == address(0) ? require(balanceOf(_stock, msg.sender) == userBal0, 'userA stock amount wrong in liquidity late')
            : require(balanceOf(_stock, msg.sender) == (userBal0 - inputAmounts[0]), 'userA stock amount wrong in liquidity late');
        _money == address(0) ? require(balanceOf(_money, msg.sender) == userBal1, 'userA money amount wrong in liquidity late')
            : require(balanceOf(_money, msg.sender) == (userBal1 - inputAmounts[1]), 'userA money amount wrong in liquidity late');

        // tokens balance require in pair
        require(balanceOf(_stock, pair) == inputAmounts[0], 'pair stock amount wrong in initial liquidity late');
        require(balanceOf(_money, pair) == inputAmounts[1], 'pair money amount wrong in initial liquidity late');

        emit Succeed(true);
    }

    function addLiquiditySubsequent(uint[2] calldata inputAmounts) public payable {
        if (inputAmounts[0] == 0 || inputAmounts[1] == 0) { emit Succeed(true); return; }

        Context memory ctx;
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        ctx.totalLiquidity = OneSwapERC20(pair).totalSupply();
        if (ctx.totalLiquidity == 0) return;

        ctx.pairStockAmount = balanceOf(_stock, pair);
        ctx.pairMoneyAmount = balanceOf(_money, pair);
        ctx.userStockAmount = balanceOf(_stock, msg.sender);
        ctx.userMoneyAmount = balanceOf(_money, msg.sender);
        ctx.userLiquidity = balanceOf(pair, msg.sender);
        (ctx.pairReserveStock, ctx.pairReserveMoney,) = IOneSwapPool(pair).getReserves();
        uint contractOldBalance = address(this).balance;

        uint ethAmount;
        if (_stock == address(0)){  ethAmount = inputAmounts[0]; }
        else if (_money == address(0)) { ethAmount = inputAmounts[1]; }
        transferFrom(msg.sender, address(this), _stock, inputAmounts[0]);
        transferFrom(msg.sender, address(this), _money, inputAmounts[1]);
        (uint outAmountStock, uint outAmountMoney, uint outLiquidity) = _router.addLiquidity{value: ethAmount}(_stock, _money,
            _isOnlySwap , inputAmounts[0], inputAmounts[1], 0, 0, msg.sender, 99999999999);

        if (outAmountStock < inputAmounts[0]) { transfer(msg.sender, _stock, inputAmounts[0] - outAmountStock); }
        else if (outAmountMoney < inputAmounts[1]) { transfer(msg.sender, _money, inputAmounts[1] - outAmountMoney); }

        uint expectLiquidity = Math.min(outAmountStock.mul(ctx.totalLiquidity) / ctx.pairStockAmount,
            outAmountMoney.mul(ctx.totalLiquidity) / ctx.pairMoneyAmount);
        // check out and expection
        require(outAmountStock == inputAmounts[0] || outAmountMoney == inputAmounts[1], 'amount stock and amount money mismatch');
        require(outLiquidity == expectLiquidity, 'liquidity mismatch in subsequent add');

        // liquidity in pair
        require(OneSwapERC20(pair).totalSupply() == ctx.totalLiquidity + expectLiquidity, 'total liquidity mismatch in subsequent add');
        require(balanceOf(pair, address(0)) == _MINIMUM_LIQUIDITY, 'pair self liquidity mismatch');
        require(balanceOf(pair, msg.sender) == ctx.userLiquidity + expectLiquidity, 'user liquidity mismatch');

        // tokens balance require in msg.sender
        _stock == address(0) ? require( balanceOf(_stock, msg.sender) == ctx.userStockAmount + inputAmounts[0] - outAmountStock, 'user amount stock mismatch')
            : require( balanceOf(_stock, msg.sender) == ctx.userStockAmount - outAmountStock, 'user amount stock mismatch');
        _money == address(0) ? require( balanceOf(_money, msg.sender) == ctx.userMoneyAmount + inputAmounts[1] - outAmountMoney, 'user amount money mismatch')
            : require( balanceOf(_money, msg.sender) == ctx.userMoneyAmount - outAmountMoney, 'user amount money mismatch');

        // tokens balance require in pair
        require( balanceOf(_stock, pair) == ctx.pairStockAmount + outAmountStock, 'pair amount stock mismatch');
        require( balanceOf(_money, pair) == ctx.pairMoneyAmount + outAmountMoney, 'pair amount stock mismatch');

        // The constant-product invariant x · y = const must increase
        {
            (uint112 nowStockAmount, uint112 nowMoneyAmount,)= IOneSwapPool(pair).getReserves();
            require( ctx.pairReserveStock * ctx.pairReserveMoney <= nowStockAmount * nowMoneyAmount,
                'The constant-product invariant mismatch');
        }

        emit Succeed(true);
    }

    function removeLiquidity(uint liquidity) public {
        if (liquidity <= 0) {emit Succeed(true); return;}

        Context memory ctx;
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        ctx.totalLiquidity = OneSwapERC20(pair).totalSupply();
        if (liquidity > balanceOf(pair, msg.sender)) {emit Succeed(true); return;}
        ctx.pairStockAmount = balanceOf(_stock, pair);
        ctx.pairMoneyAmount = balanceOf(_money, pair);
        ctx.userStockAmount = balanceOf(_stock, msg.sender);
        ctx.userMoneyAmount = balanceOf(_money, msg.sender);
        ctx.userLiquidity = balanceOf(pair, msg.sender);
        (ctx.pairReserveStock, ctx.pairReserveMoney,) = IOneSwapPool(pair).getReserves();

        uint expectOutStockAmount = liquidity.mul(ctx.pairStockAmount) / ctx.totalLiquidity;
        uint expectOutMoneyAmount = liquidity.mul(ctx.pairMoneyAmount) / ctx.totalLiquidity;
        if (expectOutMoneyAmount == 0 || expectOutStockAmount == 0) {emit Succeed(true); return;}

        transferFrom(msg.sender, address(this), pair, liquidity);
        (uint outAmountStock, uint outAmountMoney) = _router.removeLiquidity(pair, liquidity, 0, 0, msg.sender, 99999999999);

        // check out and expection
        require(outAmountStock == expectOutStockAmount, 'outStockAmount mismatch in remove liquidity');
        require(outAmountMoney == expectOutMoneyAmount, 'outAmountMoney mismatch in remove liquidity');

        // check liquidity balance
        require(balanceOf(pair, address(0)) == _MINIMUM_LIQUIDITY, 'pair self liquidity mismatch');
        require(balanceOf(pair, msg.sender) == ctx.userLiquidity - liquidity, 'user liquidity mismatch');
        require(OneSwapERC20(pair).totalSupply() == ctx.totalLiquidity - liquidity, 'total liquidity mismatch in subsequent add');

        // check token balance
        require( balanceOf(_stock, msg.sender) == ctx.userStockAmount + outAmountStock, 'user amount stock mismatch');
        require( balanceOf(_money, msg.sender) == ctx.userMoneyAmount + outAmountMoney, 'user amount money mismatch');

        require( balanceOf(_stock, pair) == ctx.pairStockAmount - outAmountStock, 'pair amount stock mismatch');
        require( balanceOf(_money, pair) == ctx.pairMoneyAmount - outAmountMoney, 'pair amount stock mismatch');

        // The constant-product invariant x · y = const must increase
        {
            (uint112 nowStockAmount, uint112 nowMoneyAmount,)= IOneSwapPool(pair).getReserves();
            require( ctx.pairReserveStock * ctx.pairReserveMoney >= nowStockAmount * nowMoneyAmount,
                'The constant-product invariant mismatch');
        }
        emit Succeed(true);
    }

    function swapTokens(address token, uint inputAmount, address[] calldata path) public payable {
        if (inputAmount <= 0) return;
        if (token != _stock && token != _money) { emit Succeed(true); return; }

        Context memory ctx;
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        ctx.totalLiquidity = OneSwapERC20(pair).totalSupply();
        ctx.pairStockAmount = balanceOf(_stock, pair);
        ctx.pairMoneyAmount = balanceOf(_money, pair);
        ctx.userStockAmount = balanceOf(_stock, msg.sender);
        ctx.userMoneyAmount = balanceOf(_money, msg.sender);
        (ctx.pairReserveStock, ctx.pairReserveMoney,) = IOneSwapPool(pair).getReserves();
        if (balanceOf(token, msg.sender) < inputAmount) { emit Succeed(true); return; }

        uint ethValue;
        if (token == address(0)){ ethValue = inputAmount;}
        else{ transferFrom(msg.sender, address(this), token, inputAmount);}

        uint expectAmount;
        if (token == _stock ){ expectAmount = ctx.pairMoneyAmount * inputAmount / (ctx.pairStockAmount + inputAmount); }
        else{ expectAmount = ctx.pairStockAmount * inputAmount / (ctx.pairMoneyAmount + inputAmount); }
        expectAmount -= expectAmount * _factory.feeBPS() / 10000;
        uint[] memory amounts = _router.swapToken{value:ethValue}(token, inputAmount, 0, path, msg.sender, 99999999999);

        // check output
         require(amounts[amounts.length - 1] + 1 == expectAmount, 'swap token amount mismatch');
        // check token balance
        if (token == _stock) {
            _stock == address(0) ? require(balanceOf(_stock, msg.sender) == ctx.userStockAmount, "user amount stock mismatch")
                : require(balanceOf(_stock, msg.sender) == ctx.userStockAmount - inputAmount, "user amount stock mismatch");
            require( balanceOf(_money, msg.sender) == ctx.userMoneyAmount + amounts[amounts.length - 1], 'user amount money mismatch');

            require( balanceOf(_stock, pair) == ctx.pairStockAmount + inputAmount, 'pair amount stock mismatch');
            require( balanceOf(_money, pair) == ctx.pairMoneyAmount - amounts[amounts.length - 1], 'pair amount money mismatch');
        }else{
            _money == address(0) ? require(balanceOf(_money, msg.sender) == ctx.userMoneyAmount, "user amount money mismatch")
                : require(balanceOf(_money, msg.sender) == ctx.userMoneyAmount - inputAmount, 'user amount money mismatch');
            require( balanceOf(_stock, msg.sender) == ctx.userStockAmount + amounts[amounts.length - 1], 'user amount stock mismatch');

            require( balanceOf(_money, pair) == ctx.pairMoneyAmount + inputAmount, 'pair amount stock mismatch');
            require( balanceOf(_stock, pair) == ctx.pairStockAmount - amounts[amounts.length - 1], 'pair amount stock mismatch');
        }

        // The constant-product invariant x · y = const must increase
        {
            (uint112 nowStockAmount, uint112 nowMoneyAmount,)= IOneSwapPool(pair).getReserves();
            require( ctx.pairReserveStock * ctx.pairReserveMoney <= nowStockAmount * nowMoneyAmount,
                'The constant-product invariant mismatch');
        }
        emit Succeed(true);
    }

    // inputs : prevKey, price, id, stockAmount
    function limitOrder(bool isBuy, uint[] calldata inputs ) public payable{
        if (inputs[1] == 0 || inputs[3] == 0) { emit Succeed(true); return; }

        Context memory ctx;
        address pair = _factory.tokensToPair(_stock, _money, _isOnlySwap);
        ctx.totalLiquidity = OneSwapERC20(pair).totalSupply();
        ctx.pairStockAmount = balanceOf(_stock, pair);
        ctx.pairMoneyAmount = balanceOf(_money, pair);
        ctx.userStockAmount = balanceOf(_stock, msg.sender);
        ctx.userMoneyAmount = balanceOf(_money, msg.sender);
        (ctx.pairReserveStock, ctx.pairReserveMoney,) = IOneSwapPool(pair).getReserves();

        (uint stockAmount, uint moneyAmount) = IOneSwapPair(pair).calcStockAndMoney(uint64(inputs[3]), uint32(inputs[1]));
        if (isBuy) {
            _money == address(0) ? transferFrom(msg.sender, address(_router), _money, moneyAmount)
                : transferFrom(msg.sender, address(this), _money, moneyAmount);
        }else{
            _stock == address(0) ? transferFrom(msg.sender, address(_router), _stock, stockAmount)
                : transferFrom(msg.sender, address(this), _stock, stockAmount);
        }
        _router.limitOrder{value:address(this).balance}(isBuy, pair, inputs[0], inputs[1], uint32(inputs[2]), inputs[3], 99999999999);

        // check token balance
        if (isBuy) {
            require( balanceOf(_money, msg.sender) == ctx.userMoneyAmount - moneyAmount, 'user amount stock mismatch');
        }else{
            require( balanceOf(_stock, msg.sender) == ctx.userStockAmount - stockAmount, 'user amount stock mismatch');
        }

        // The constant-product invariant x · y = const must increase
        {
            (uint112 nowStockAmount, uint112 nowMoneyAmount,)= IOneSwapPool(pair).getReserves();
            require( ctx.pairReserveStock * ctx.pairReserveMoney <= nowStockAmount * nowMoneyAmount,
                'The constant-product invariant mismatch');
        }
        emit Succeed(true);
    }

}
