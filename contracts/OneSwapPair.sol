// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./libraries/Math.sol";
import "./libraries/SafeMath256.sol";
import "./libraries/DecFloat32.sol";
import "./libraries/ProxyData.sol";
import "./interfaces/IOneSwapFactory.sol";
import "./interfaces/IOneSwapToken.sol";
import "./interfaces/IOneSwapPair.sol";
import "./interfaces/IERC20.sol";

abstract contract OneSwapERC20 is IOneSwapERC20 {
    using SafeMath256 for uint;

    uint internal _unusedVar0;
    uint internal _unusedVar1;
    uint internal _unusedVar2;
    uint internal _unusedVar3;
    uint internal _unusedVar4;
    uint internal _unusedVar5;
    uint internal _unusedVar6;
    uint internal _unusedVar7;
    uint internal _unusedVar8;
    uint internal _unusedVar9;
    uint internal _unlocked = 1;

    modifier lock() {
        require(_unlocked == 1, "OneSwap: LOCKED");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    string private constant _NAME = "OneSwap-Share";
    uint8 private constant _DECIMALS = 18;
    uint  public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    function symbol() virtual external override returns (string memory);

    function name() external view override returns (string memory) {
        return _NAME;
    }

    function decimals() external view override returns (uint8) {
        return _DECIMALS;
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (allowance[from][msg.sender] != uint(- 1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
}

// An order can be compressed into 256 bits and saved using one SSTORE instruction
// The orders form a single-linked list. The preceding order points to the following order with nextID
struct Order { //total 256 bits
    address sender; //160 bits, sender creates this order
    uint32 price; // 32-bit decimal floating point number
    uint64 amount; // 42 bits are used, the stock amount to be sold or bought
    uint32 nextID; // 22 bits are used
}

// When the match engine of orderbook runs, it uses follow context to cache data in memory
struct Context {
    // this order is a limit order
    bool isLimitOrder;
    // the new order's id, it is only used when a limit order is not fully dealt
    uint32 newOrderID;
    // for buy-order, it's remained money amount; for sell-order, it's remained stock amount
    uint remainAmount;
    // it points to the first order in the opposite order book against current order
    uint32 firstID;
    // it points to the first order in the buy-order book
    uint32 firstBuyID;
    // it points to the first order in the sell-order book
    uint32 firstSellID;
    // the amount goes into the pool, for buy-order, it's money amount; for sell-order, it's stock amount
    uint amountIntoPool;
    // the total dealt money and stock in the order book
    uint dealMoneyInBook;
    uint dealStockInBook;
    // cache these values from storage to memory
    uint reserveMoney;
    uint reserveStock;
    uint bookedMoney;
    uint bookedStock;
    // reserveMoney or reserveStock is changed
    bool reserveChanged;
    // the taker has dealt in the orderbook
    bool hasDealtInOrderBook;
    // the current taker order
    Order order;
    // the following data come from proxy
    uint64 stockUnit;
    uint64 priceMul;
    uint64 priceDiv;
    address stockToken;
    address moneyToken;
    address ones;
    address factory;
}

// OneSwapPair combines a Uniswap-like AMM and an orderbook
abstract contract OneSwapPool is OneSwapERC20, IOneSwapPool {
    using SafeMath256 for uint;

    uint private constant _MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 internal constant _SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    // reserveMoney and reserveStock are both uint112, id is 22 bits; they are compressed into a uint256 word
    uint internal _reserveStockAndMoneyAndFirstSellID;
    // bookedMoney and bookedStock are both uint112, id is 22 bits; they are compressed into a uint256 word
    uint internal _bookedStockAndMoneyAndFirstBuyID;

    uint private _kLast;

    uint32 private constant _OS = 2; // owner's share
    uint32 private constant _LS = 3; // liquidity-provider's share

    function internalStatus() external override view returns(uint[3] memory res) {
        res[0] = _reserveStockAndMoneyAndFirstSellID;
        res[1] = _bookedStockAndMoneyAndFirstBuyID;
        res[2] = _kLast;
    }

    function stock() external override returns (address) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+0));
        return ProxyData.stock(proxyData);
    }

    function money() external override returns (address) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+0));
        return ProxyData.money(proxyData);
    }

    // the following 4 functions load&store compressed storage
    function getReserves() public override view returns (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) {
        uint temp = _reserveStockAndMoneyAndFirstSellID;
        reserveStock = uint112(temp);
        reserveMoney = uint112(temp>>112);
        firstSellID = uint32(temp>>224);
    }
    function _setReserves(uint stockAmount, uint moneyAmount, uint32 firstSellID) internal {
        require(stockAmount < uint(1<<112) && moneyAmount < uint(1<<112), "OneSwap: OVERFLOW");
        uint temp = (moneyAmount<<112)|stockAmount;
        emit Sync(temp);
        temp = (uint(firstSellID)<<224)| temp;
        _reserveStockAndMoneyAndFirstSellID = temp;
    }
    function getBooked() public override view returns (uint112 bookedStock, uint112 bookedMoney, uint32 firstBuyID) {
        uint temp = _bookedStockAndMoneyAndFirstBuyID;
        bookedStock = uint112(temp);
        bookedMoney = uint112(temp>>112);
        firstBuyID = uint32(temp>>224);
    }
    function _setBooked(uint stockAmount, uint moneyAmount, uint32 firstBuyID) internal {
        require(stockAmount < uint(1<<112) && moneyAmount < uint(1<<112), "OneSwap: OVERFLOW");
        _bookedStockAndMoneyAndFirstBuyID = (uint(firstBuyID)<<224)|(moneyAmount<<112)|stockAmount;
    }

    function _myBalance(address token) internal view returns (uint) {
        if(token==address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    // safely transfer ERC20 tokens, or ETH (when token==0)
    function _safeTransfer(address token, address to, uint value, address ones) internal {
        if(value==0) {return;}
        if(token==address(0)) {
            // limit gas to 9000 to prevent gastoken attacks
            // solhint-disable-next-line avoid-low-level-calls 
            to.call{value: value, gas: 9000}(new bytes(0)); //we ignore its return value purposely
            return;
        }
        // solhint-disable-next-line avoid-low-level-calls 
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(_SELECTOR, to, value));
        success = success && (data.length == 0 || abi.decode(data, (bool)));
        if(!success) { // for failsafe
            address onesOwner = IOneSwapToken(ones).owner();
            // solhint-disable-next-line avoid-low-level-calls 
            (success, data) = token.call(abi.encodeWithSelector(_SELECTOR, onesOwner, value));
            require(success && (data.length == 0 || abi.decode(data, (bool))), "OneSwap: TRANSFER_FAILED");
        }
    }

    // Give feeTo some liquidity tokens if K got increased since last liquidity-changing
    function _mintFee(uint112 _reserve0, uint112 _reserve1, uint[5] memory proxyData) private returns (bool feeOn) {
        address feeTo = IOneSwapFactory(ProxyData.factory(proxyData)).feeTo();
        feeOn = feeTo != address(0);
        uint kLast = _kLast;
        // gas savings to use cached kLast
        if (feeOn) {
            if (kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast)).mul(_OS);
                    uint denominator = rootK.mul(_LS).add(rootKLast.mul(_OS));
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (kLast != 0) {
            _kLast = 0;
        }
    }

    // mint new liquidity tokens to 'to'
    function mint(address to) external override lock returns (uint liquidity) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+1));
        (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) = getReserves();
        (uint112 bookedStock, uint112 bookedMoney, ) = getBooked();
        uint stockBalance = _myBalance(ProxyData.stock(proxyData));
        uint moneyBalance = _myBalance(ProxyData.money(proxyData));
        require(stockBalance >= uint(bookedStock) + uint(reserveStock) &&
                moneyBalance >= uint(bookedMoney) + uint(reserveMoney), "OneSwap: INVALID_BALANCE");
        stockBalance -= uint(bookedStock);
        moneyBalance -= uint(bookedMoney);
        uint stockAmount = stockBalance - uint(reserveStock);
        uint moneyAmount = moneyBalance - uint(reserveMoney);

        bool feeOn = _mintFee(reserveStock, reserveMoney, proxyData);
        uint _totalSupply = totalSupply;
        // gas savings by caching totalSupply in memory,
        // must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(stockAmount.mul(moneyAmount)).sub(_MINIMUM_LIQUIDITY);
            _mint(address(0), _MINIMUM_LIQUIDITY);
            // permanently lock the first _MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(stockAmount.mul(_totalSupply) / uint(reserveStock),
                                 moneyAmount.mul(_totalSupply) / uint(reserveMoney));
        }
        require(liquidity > 0, "OneSwap: INSUFFICIENT_MINTED");
        _mint(to, liquidity);

        _setReserves(stockBalance, moneyBalance, firstSellID);
        if (feeOn) _kLast = stockBalance.mul(moneyBalance);
        emit Mint(msg.sender, (moneyAmount<<112)|stockAmount, to);
    }

    // burn liquidity tokens and send stock&money to 'to'
    function burn(address to) external override lock returns (uint stockAmount, uint moneyAmount) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+1));
        (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) = getReserves();
        (uint bookedStock, uint bookedMoney, ) = getBooked();
        uint stockBalance = _myBalance(ProxyData.stock(proxyData)).sub(bookedStock);
        uint moneyBalance = _myBalance(ProxyData.money(proxyData)).sub(bookedMoney);
        require(stockBalance >= uint(reserveStock) && moneyBalance >= uint(reserveMoney), "OneSwap: INVALID_BALANCE");

        bool feeOn = _mintFee(reserveStock, reserveMoney, proxyData);
        {
            uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
            uint liquidity = balanceOf[address(this)]; // we're sure liquidity < totalSupply
            stockAmount = liquidity.mul(stockBalance) / _totalSupply;
            moneyAmount = liquidity.mul(moneyBalance) / _totalSupply;
            require(stockAmount > 0 && moneyAmount > 0, "OneSwap: INSUFFICIENT_BURNED");

            //_burn(address(this), liquidity);
            balanceOf[address(this)] = 0;
            totalSupply = totalSupply.sub(liquidity);
            emit Transfer(address(this), address(0), liquidity);
        }

        address ones = ProxyData.ones(proxyData);
        _safeTransfer(ProxyData.stock(proxyData), to, stockAmount, ones);
        _safeTransfer(ProxyData.money(proxyData), to, moneyAmount, ones);

        stockBalance = stockBalance - stockAmount;
        moneyBalance = moneyBalance - moneyAmount;

        _setReserves(stockBalance, moneyBalance, firstSellID);
        if (feeOn) _kLast = stockBalance.mul(moneyBalance);
        emit Burn(msg.sender, (moneyAmount<<112)|stockAmount, to);
    }

    // take the extra money&stock in this pair to 'to'
    function skim(address to) external override lock {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+1));
        address stockToken = ProxyData.stock(proxyData);
        address moneyToken = ProxyData.money(proxyData);
        (uint112 reserveStock, uint112 reserveMoney, ) = getReserves();
        (uint bookedStock, uint bookedMoney, ) = getBooked();
        uint balanceStock = _myBalance(stockToken);
        uint balanceMoney = _myBalance(moneyToken);
        require(balanceStock >= uint(bookedStock) + uint(reserveStock) &&
                balanceMoney >= uint(bookedMoney) + uint(reserveMoney), "OneSwap: INVALID_BALANCE");
        address ones = ProxyData.ones(proxyData);
        _safeTransfer(stockToken, to, balanceStock-reserveStock-bookedStock, ones);
        _safeTransfer(moneyToken, to, balanceMoney-reserveMoney-bookedMoney, ones);
    }

    // sync-up reserve stock&money in pool according to real balance
    function sync() external override lock {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+0));
        (, , uint32 firstSellID) = getReserves();
        (uint bookedStock, uint bookedMoney, ) = getBooked();
        uint balanceStock = _myBalance(ProxyData.stock(proxyData));
        uint balanceMoney = _myBalance(ProxyData.money(proxyData));
        require(balanceStock >= bookedStock && balanceMoney >= bookedMoney, "OneSwap: INVALID_BALANCE");
        _setReserves(balanceStock-bookedStock, balanceMoney-bookedMoney, firstSellID);
    }

}

contract OneSwapPair is OneSwapPool, IOneSwapPair {
    // the orderbooks. Gas is saved when using array to store them instead of mapping
    uint[1<<22] private _sellOrders;
    uint[1<<22] private _buyOrders;

    uint32 private constant _MAX_ID = (1<<22)-1; // the maximum value of an order ID

    function _expandPrice(uint32 price32, uint[5] memory proxyData) private pure returns (RatPrice memory price) {
        price = DecFloat32.expandPrice(price32);
        price.numerator *= ProxyData.priceMul(proxyData);
        price.denominator *= ProxyData.priceDiv(proxyData);
    }

    function _expandPrice(Context memory ctx, uint32 price32) private pure returns (RatPrice memory price) {
        price = DecFloat32.expandPrice(price32);
        price.numerator *= ctx.priceMul;
        price.denominator *= ctx.priceDiv;
    }

    function symbol() external override returns (string memory) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+0));
        string memory s = "ETH";
        address stock = ProxyData.stock(proxyData);
        if(stock != address(0)) {
            s = IERC20(stock).symbol();
        }
        string memory m = "ETH";
        address money = ProxyData.money(proxyData);
        if(money != address(0)) {
            m = IERC20(money).symbol();
        }
        return string(abi.encodePacked(s, "/", m));  //to concat strings
    }

    // when emitting events, solidity's ABI pads each entry to uint256, which is so wasteful
    // we compress the entries into one uint256 to save gas
    function _emitNewLimitOrder(
        uint64 addressLow, /*255~192*/
        uint64 totalStockAmount, /*191~128*/
        uint64 remainedStockAmount, /*127~64*/
        uint32 price, /*63~32*/
        uint32 orderID, /*31~8*/
        bool isBuy /*7~0*/) private {
        uint data = uint(addressLow);
        data = (data<<64) | uint(totalStockAmount);
        data = (data<<64) | uint(remainedStockAmount);
        data = (data<<32) | uint(price);
        data = (data<<32) | uint(orderID<<8);
        if(isBuy) {
            data = data | 1;
        }
        emit NewLimitOrder(data);
    }
    function _emitNewMarketOrder(
        uint136 addressLow, /*255~120*/
        uint112 amount, /*119~8*/
        bool isBuy /*7~0*/) private {
        uint data = uint(addressLow);
        data = (data<<112) | uint(amount);
        data = data<<8;
        if(isBuy) {
            data = data | 1;
        }
        emit NewMarketOrder(data);
    }
    function _emitOrderChanged(
        uint64 makerLastAmount, /*159~96*/
        uint64 makerDealAmount, /*95~32*/
        uint32 makerOrderID, /*31~8*/
        bool isBuy /*7~0*/) private {
        uint data = uint(makerLastAmount);
        data = (data<<64) | uint(makerDealAmount);
        data = (data<<32) | uint(makerOrderID<<8);
        if(isBuy) {
            data = data | 1;
        }
        emit OrderChanged(data);
    }
    function _emitDealWithPool(
        uint112 inAmount, /*131~120*/
        uint112 outAmount,/*119~8*/
        bool isBuy/*7~0*/) private {
        uint data = uint(inAmount);
        data = (data<<112) | uint(outAmount);
        data = data<<8;
        if(isBuy) {
            data = data | 1;
        }
        emit DealWithPool(data);
    }
    function _emitRemoveOrder(
        uint64 remainStockAmount, /*95~32*/
        uint32 orderID, /*31~8*/
        bool isBuy /*7~0*/) private {
        uint data = uint(remainStockAmount);
        data = (data<<32) | uint(orderID<<8);
        if(isBuy) {
            data = data | 1;
        }
        emit RemoveOrder(data);
    }

    // compress an order into a 256b integer
    function _order2uint(Order memory order) internal pure returns (uint) {
        uint n = uint(order.sender);
        n = (n<<32) | order.price;
        n = (n<<42) | order.amount;
        n = (n<<22) | order.nextID;
        return n;
    }

    // extract an order from a 256b integer
    function _uint2order(uint n) internal pure returns (Order memory) {
        Order memory order;
        order.nextID = uint32(n & ((1<<22)-1));
        n = n >> 22;
        order.amount = uint64(n & ((1<<42)-1));
        n = n >> 42;
        order.price = uint32(n & ((1<<32)-1));
        n = n >> 32;
        order.sender = address(n);
        return order;
    }

    // returns true if this order exists
    function _hasOrder(bool isBuy, uint32 id) internal view returns (bool) {
        if(isBuy) {
            return _buyOrders[id] != 0;
        } else {
            return _sellOrders[id] != 0;
        }
    }

    // load an order from storage, converting its compressed form into an Order struct
    function _getOrder(bool isBuy, uint32 id) internal view returns (Order memory order, bool findIt) {
        if(isBuy) {
            order = _uint2order(_buyOrders[id]);
            return (order, order.price != 0);
        } else {
            order = _uint2order(_sellOrders[id]);
            return (order, order.price != 0);
        }
    }

    // save an order to storage, converting it into compressed form
    function _setOrder(bool isBuy, uint32 id, Order memory order) internal {
        if(isBuy) {
            _buyOrders[id] = _order2uint(order);
        } else {
            _sellOrders[id] = _order2uint(order);
        }
    }

    // delete an order from storage
    function _deleteOrder(bool isBuy, uint32 id) internal {
        if(isBuy) {
            delete _buyOrders[id];
        } else {
            delete _sellOrders[id];
        }
    }

    function _getFirstOrderID(Context memory ctx, bool isBuy) internal pure returns (uint32) {
        if(isBuy) {
            return ctx.firstBuyID;
        }
        return ctx.firstSellID;
    }

    function _setFirstOrderID(Context memory ctx, bool isBuy, uint32 id) internal pure {
        if(isBuy) {
            ctx.firstBuyID = id;
        } else {
            ctx.firstSellID = id;
        }
    }

    function removeOrders(uint[] calldata rmList) external override lock {
        uint[5] memory proxyData;
        uint expectedCallDataSize = 4+32*(ProxyData.COUNT+2+rmList.length);
        ProxyData.fill(proxyData, expectedCallDataSize);
        for(uint i = 0; i < rmList.length; i++) {
            uint rmInfo = rmList[i];
            bool isBuy = uint8(rmInfo) != 0;
            uint32 id = uint32(rmInfo>>8);
            uint72 prevKey = uint72(rmInfo>>40);
            _removeOrder(isBuy, id, prevKey, proxyData);
        }
    }

    function removeOrder(bool isBuy, uint32 id, uint72 prevKey) external override lock {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+3));
        _removeOrder(isBuy, id, prevKey, proxyData);
    }

    function _removeOrder(bool isBuy, uint32 id, uint72 prevKey, uint[5] memory proxyData) private {
        Context memory ctx;
        (ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID) = getBooked();
        if(!isBuy) {
            (ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID) = getReserves();
        }
        Order memory order = _removeOrderFromBook(ctx, isBuy, id, prevKey); // this is the removed order
        require(msg.sender == order.sender, "OneSwap: NOT_OWNER");
        uint64 stockUnit = ProxyData.stockUnit(proxyData);
        uint stockAmount = uint(order.amount)/*42bits*/ * uint(stockUnit);
        address ones = ProxyData.ones(proxyData);
        if(isBuy) {
            RatPrice memory price = _expandPrice(order.price, proxyData);
            uint moneyAmount = stockAmount * price.numerator/*54+64bits*/ / price.denominator;
            ctx.bookedMoney -= moneyAmount;
            _safeTransfer(ProxyData.money(proxyData), order.sender, moneyAmount, ones);
        } else {
            ctx.bookedStock -= stockAmount;
            _safeTransfer(ProxyData.stock(proxyData), order.sender, stockAmount, ones);
        }
        _setBooked(ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID);
    }

    // remove an order from orderbook and return it
    function _removeOrderFromBook(Context memory ctx, bool isBuy,
                                 uint32 id, uint72 prevKey) internal returns (Order memory) {
        (Order memory order, bool ok) = _getOrder(isBuy, id);
        require(ok, "OneSwap: NO_SUCH_ORDER");
        if(prevKey == 0) {
            uint32 firstID = _getFirstOrderID(ctx, isBuy);
            require(id == firstID, "OneSwap: NOT_FIRST");
            _setFirstOrderID(ctx, isBuy, order.nextID);
            if(!isBuy) {
                _setReserves(ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID);
            }
        } else {
            (uint32 currID, Order memory prevOrder, bool findIt) = _getOrder3Times(isBuy, prevKey);
            require(findIt, "OneSwap: INVALID_POSITION");
            while(prevOrder.nextID != id) {
                currID = prevOrder.nextID;
                require(currID != 0, "OneSwap: REACH_END");
                (prevOrder, ) = _getOrder(isBuy, currID);
            }
            prevOrder.nextID = order.nextID;
            _setOrder(isBuy, currID, prevOrder);
        }
        _emitRemoveOrder(order.amount, id, isBuy);
        _deleteOrder(isBuy, id);
        return order;
    }

    // insert an order at the head of single-linked list
    // this function does not check price, use it carefully
    function _insertOrderAtHead(Context memory ctx, bool isBuy, Order memory order, uint32 id) private {
        order.nextID = _getFirstOrderID(ctx, isBuy);
        _setOrder(isBuy, id, order);
        _setFirstOrderID(ctx, isBuy, id);
    }

    // prevKey contains 3 orders. try to get the first existing order
    function _getOrder3Times(bool isBuy, uint72 prevKey) private view returns (
        uint32 currID, Order memory prevOrder, bool findIt) {
        currID = uint32(prevKey&_MAX_ID);
        (prevOrder, findIt) = _getOrder(isBuy, currID);
        if(!findIt) {
            currID = uint32((prevKey>>24)&_MAX_ID);
            (prevOrder, findIt) = _getOrder(isBuy, currID);
            if(!findIt) {
                currID = uint32((prevKey>>48)&_MAX_ID);
                (prevOrder, findIt) = _getOrder(isBuy, currID);
            }
        }
    }

    // Given a valid start position, find a proper position to insert order
    // prevKey contains three suggested order IDs, each takes 24 bits.
    // We try them one by one to find a valid start position
    // can not use this function to insert at head! if prevKey is all zero, it will return false
    function _insertOrderFromGivenPos(bool isBuy, Order memory order,
                                     uint32 id, uint72 prevKey) private returns (bool inserted) {
        (uint32 currID, Order memory prevOrder, bool findIt) = _getOrder3Times(isBuy, prevKey);
        if(!findIt) {
            return false;
        }
        return _insertOrder(isBuy, order, prevOrder, id, currID);
    }
    
    // Starting from the head of orderbook, find a proper position to insert order
    function _insertOrderFromHead(Context memory ctx, bool isBuy, Order memory order,
                                 uint32 id) private returns (bool inserted) {
        uint32 firstID = _getFirstOrderID(ctx, isBuy);
        bool canBeFirst = (firstID == 0);
        Order memory firstOrder;
        if(!canBeFirst) {
            (firstOrder, ) = _getOrder(isBuy, firstID);
            canBeFirst = (isBuy && (firstOrder.price < order.price)) ||
                (!isBuy && (firstOrder.price > order.price));
        }
        if(canBeFirst) {
            order.nextID = firstID;
            _setOrder(isBuy, id, order);
            _setFirstOrderID(ctx, isBuy, id);
            return true;
        }
        return _insertOrder(isBuy, order, firstOrder, id, firstID);
    }

    // starting from 'prevOrder', whose id is 'currID', find a proper position to insert order
    function _insertOrder(bool isBuy, Order memory order, Order memory prevOrder,
                         uint32 id, uint32 currID) private returns (bool inserted) {
        while(currID != 0) {
            bool canFollow = (isBuy && (order.price <= prevOrder.price)) ||
                (!isBuy && (order.price >= prevOrder.price));
            if(!canFollow) {break;} 
            Order memory nextOrder;
            if(prevOrder.nextID != 0) {
                (nextOrder, ) = _getOrder(isBuy, prevOrder.nextID);
                bool canPrecede = (isBuy && (nextOrder.price < order.price)) ||
                    (!isBuy && (nextOrder.price > order.price));
                canFollow = canFollow && canPrecede;
            }
            if(canFollow) {
                order.nextID = prevOrder.nextID;
                _setOrder(isBuy, id, order);
                prevOrder.nextID = id;
                _setOrder(isBuy, currID, prevOrder);
                return true;
            }
            currID = prevOrder.nextID;
            prevOrder = nextOrder;
        }
        return false;
    }

    // to query the first sell price, the first buy price and the price of pool
    function getPrices() external override view returns (
        uint firstSellPriceNumerator,
        uint firstSellPriceDenominator,
        uint firstBuyPriceNumerator,
        uint firstBuyPriceDenominator,
        uint poolPriceNumerator,
        uint poolPriceDenominator) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+0));
        (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) = getReserves();
        poolPriceNumerator = uint(reserveMoney);
        poolPriceDenominator = uint(reserveStock);
        firstSellPriceNumerator = 0;
        firstSellPriceDenominator = 0;
        firstBuyPriceNumerator = 0;
        firstBuyPriceDenominator = 0;
        if(firstSellID!=0) {
            uint order = _sellOrders[firstSellID];
            RatPrice memory price = _expandPrice(uint32(order>>64), proxyData);
            firstSellPriceNumerator = price.numerator;
            firstSellPriceDenominator = price.denominator;
        }
        uint32 id = uint32(_bookedStockAndMoneyAndFirstBuyID>>224);
        if(id!=0) {
            uint order = _buyOrders[id];
            RatPrice memory price = _expandPrice(uint32(order>>64), proxyData);
            firstBuyPriceNumerator = price.numerator;
            firstBuyPriceDenominator = price.denominator;
        }
    }

    // Get the orderbook's content, starting from id, to get no more than maxCount orders
    function getOrderList(bool isBuy, uint32 id, uint32 maxCount) external override view returns (uint[] memory) {
        if(id == 0) {
            if(isBuy) {
                id = uint32(_bookedStockAndMoneyAndFirstBuyID>>224);
            } else {
                id = uint32(_reserveStockAndMoneyAndFirstSellID>>224);
            }
        }
        uint[1<<22] storage orderbook;
        if(isBuy) {
            orderbook = _buyOrders;
        } else {
            orderbook = _sellOrders;
        }
        //record block height at the first entry
        uint order = (block.number<<24) | id;
        uint addrOrig; // start of returned data
        uint addrLen; // the slice's length is written at this address
        uint addrStart; // the address of the first entry of returned slice
        uint addrEnd; // ending address to write the next order
        uint count = 0; // the slice's length
        // solhint-disable-next-line no-inline-assembly
        assembly {
            addrOrig := mload(0x40) // There is a “free memory pointer” at address 0x40 in memory
            mstore(addrOrig, 32) //the meaningful data start after offset 32
        }
        addrLen = addrOrig + 32;
        addrStart = addrLen + 32;
        addrEnd = addrStart;
        while(count < maxCount) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                mstore(addrEnd, order) //write the order
            }
            addrEnd += 32;
            count++;
            if(id == 0) {break;}
            order = orderbook[id];
            require(order!=0, "OneSwap: INCONSISTENT_BOOK");
            id = uint32(order&_MAX_ID);
        }
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(addrLen, count) // record the returned slice's length
            let byteCount := sub(addrEnd, addrOrig)
            return(addrOrig, byteCount)
        }
    }

    // Get an unused id to be used with new order
    function _getUnusedOrderID(bool isBuy, uint32 id) internal view returns (uint32) {
        if(id == 0) { // 0 is reserved
            // solhint-disable-next-line avoid-tx-origin
            id = uint32(uint(blockhash(block.number-1))^uint(tx.origin)) & _MAX_ID; //get a pseudo random number
        }
        for(uint32 i = 0; i < 100 && id <= _MAX_ID; i++) { //try 100 times
            if(!_hasOrder(isBuy, id)) {
                return id;
            }
            id++;
        }
        require(false, "OneSwap: CANNOT_FIND_VALID_ID");
        return 0;
    }

    function calcStockAndMoney(uint64 amount, uint32 price32) external pure override returns (uint stockAmount, uint moneyAmount) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+2));
        (stockAmount, moneyAmount, ) = _calcStockAndMoney(amount, price32, proxyData);
    }

    function _calcStockAndMoney(uint64 amount, uint32 price32, uint[5] memory proxyData) private pure returns (uint stockAmount, uint moneyAmount, RatPrice memory price) {
        price = _expandPrice(price32, proxyData);
        uint64 stockUnit = ProxyData.stockUnit(proxyData);
        stockAmount = uint(amount)/*42bits*/ * uint(stockUnit);
        moneyAmount = stockAmount * price.numerator/*54+64bits*/ /price.denominator;
    }

    function addLimitOrder(bool isBuy, address sender, uint64 amount, uint32 price32,
                           uint32 id, uint72 prevKey) external payable override lock {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+6));
        require(ProxyData.isOnlySwap(proxyData)==false, "OneSwap: LIMIT_ORDER_NOT_SUPPORTED");
        Context memory ctx;
        ctx.stockUnit = ProxyData.stockUnit(proxyData);
        ctx.ones = ProxyData.ones(proxyData);
        ctx.factory = ProxyData.factory(proxyData);
        ctx.stockToken = ProxyData.stock(proxyData);
        ctx.moneyToken = ProxyData.money(proxyData);
        ctx.priceMul = ProxyData.priceMul(proxyData);
        ctx.priceDiv = ProxyData.priceDiv(proxyData);
        ctx.hasDealtInOrderBook = false;
        ctx.isLimitOrder = true;
        ctx.order.sender = sender;
        ctx.order.amount = amount;
        ctx.order.price = price32;

        ctx.newOrderID = _getUnusedOrderID(isBuy, id);
        RatPrice memory price;
    
        {// to prevent "CompilerError: Stack too deep, try removing local variables."
            require((amount >> 42) == 0, "OneSwap: INVALID_AMOUNT");
            uint32 m = price32 & DecFloat32.MANTISSA_MASK;
            require(DecFloat32.MIN_MANTISSA <= m && m <= DecFloat32.MAX_MANTISSA, "OneSwap: INVALID_PRICE");

            uint stockAmount;
            uint moneyAmount;
            (stockAmount, moneyAmount, price) = _calcStockAndMoney(amount, price32, proxyData);
            if(isBuy) {
                ctx.remainAmount = moneyAmount;
            } else {
                ctx.remainAmount = stockAmount;
            }
        }

        require(ctx.remainAmount < uint(1<<112), "OneSwap: OVERFLOW");
        (ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID) = getReserves();
        (ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID) = getBooked();
        _checkRemainAmount(ctx, isBuy);
        if(prevKey != 0) { // try to insert it
            bool inserted = _insertOrderFromGivenPos(isBuy, ctx.order, ctx.newOrderID, prevKey);
            if(inserted) { //  if inserted successfully, record the booked tokens
                _emitNewLimitOrder(uint64(ctx.order.sender), amount, amount, price32, ctx.newOrderID, isBuy);
                if(isBuy) {
                    ctx.bookedMoney += ctx.remainAmount;
                } else {
                    ctx.bookedStock += ctx.remainAmount;
                }
                _setBooked(ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID);
                if(ctx.reserveChanged) {
                    _setReserves(ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID);
                }
                return;
            }
            // if insertion failed, we try to match this order and make it deal
        }
        _addOrder(ctx, isBuy, price);
    }

    function addMarketOrder(address inputToken, address sender,
                            uint112 inAmount) external payable override lock returns (uint) {
        uint[5] memory proxyData;
        ProxyData.fill(proxyData, 4+32*(ProxyData.COUNT+3));
        Context memory ctx;
        ctx.moneyToken = ProxyData.money(proxyData);
        ctx.stockToken = ProxyData.stock(proxyData);
        require(inputToken == ctx.moneyToken || inputToken == ctx.stockToken, "OneSwap: INVALID_TOKEN");
        bool isBuy = inputToken == ctx.moneyToken;
        ctx.stockUnit = ProxyData.stockUnit(proxyData);
        ctx.priceMul = ProxyData.priceMul(proxyData);
        ctx.priceDiv = ProxyData.priceDiv(proxyData);
        ctx.ones = ProxyData.ones(proxyData);
        ctx.factory = ProxyData.factory(proxyData);
        ctx.hasDealtInOrderBook = false;
        ctx.isLimitOrder = false;
        ctx.remainAmount = inAmount;
        (ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID) = getReserves();
        (ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID) = getBooked();
        _checkRemainAmount(ctx, isBuy);
        ctx.order.sender = sender;
        if(isBuy) {
            ctx.order.price = DecFloat32.MAX_PRICE;
        } else {
            ctx.order.price = DecFloat32.MIN_PRICE;
        }

        RatPrice memory price; // leave it to zero, actually it will not be used;
        _emitNewMarketOrder(uint136(ctx.order.sender), inAmount, isBuy);
        return _addOrder(ctx, isBuy, price);
    }

    // Check router contract did send me enough tokens.
    // If Router sent to much tokens, take them as reserve money&stock
    function _checkRemainAmount(Context memory ctx, bool isBuy) private view {
        ctx.reserveChanged = false;
        uint diff;
        if(isBuy) {
            uint balance = _myBalance(ctx.moneyToken);
            require(balance >= ctx.bookedMoney + ctx.reserveMoney, "OneSwap: MONEY_MISMATCH");
            diff = balance - ctx.bookedMoney - ctx.reserveMoney;
            if(ctx.remainAmount < diff) {
                ctx.reserveMoney += (diff - ctx.remainAmount);
                ctx.reserveChanged = true;
            }
        } else {
            uint balance = _myBalance(ctx.stockToken);
            require(balance >= ctx.bookedStock + ctx.reserveStock, "OneSwap: STOCK_MISMATCH");
            diff = balance - ctx.bookedStock - ctx.reserveStock;
            if(ctx.remainAmount < diff) {
                ctx.reserveStock += (diff - ctx.remainAmount);
                ctx.reserveChanged = true;
            }
        }
        require(ctx.remainAmount <= diff, "OneSwap: DEPOSIT_NOT_ENOUGH");
    }

    // internal helper function to add new limit order & market order
    // returns the amount of tokens which were sent to the taker (from AMM pool and booked tokens)
    function _addOrder(Context memory ctx, bool isBuy, RatPrice memory price) private returns (uint) {
        (ctx.dealMoneyInBook, ctx.dealStockInBook) = (0, 0);
        ctx.firstID = _getFirstOrderID(ctx, !isBuy);
        uint32 currID = ctx.firstID;
        ctx.amountIntoPool = 0;
        while(currID != 0) { // while not reaching the end of single-linked 
            (Order memory orderInBook, ) = _getOrder(!isBuy, currID);
            bool canDealInOrderBook = (isBuy && (orderInBook.price <= ctx.order.price)) ||
                (!isBuy && (orderInBook.price >= ctx.order.price));
            if(!canDealInOrderBook) {break;} // no proper price in orderbook, stop here

            // Deal in liquid pool
            RatPrice memory priceInBook = _expandPrice(ctx, orderInBook.price);
            bool allDeal = _tryDealInPool(ctx, isBuy, priceInBook);
            if(allDeal) {break;}

            // Deal in orderbook
            _dealInOrderBook(ctx, isBuy, currID, orderInBook, priceInBook);

            // if the order in book did NOT fully deal, then this new order DID fully deal, so stop here
            if(orderInBook.amount != 0) {
                _setOrder(!isBuy, currID, orderInBook);
                break;
            }
            // if the order in book DID fully deal, then delete this order from storage and move to the next
            _deleteOrder(!isBuy, currID);
            currID = orderInBook.nextID;
        }
        // Deal in liquid pool
        if(ctx.isLimitOrder) {
            // use current order's price to deal with pool
            _tryDealInPool(ctx, isBuy, price);
            // If a limit order did NOT fully deal, we add it into orderbook
            // Please note a market order always fully deals
            _insertOrderToBook(ctx, isBuy, price);
        } else {
            // the AMM pool can deal with orders with any amount
            ctx.amountIntoPool += ctx.remainAmount; // both of them are less than 112 bits
            ctx.remainAmount = 0;
        }
        uint amountToTaker = _dealWithPoolAndCollectFee(ctx, isBuy);
        if(isBuy) {
            ctx.bookedStock -= ctx.dealStockInBook; //If this subtraction overflows, _setBooked will fail
        } else {
            ctx.bookedMoney -= ctx.dealMoneyInBook; //If this subtraction overflows, _setBooked will fail
        }
        if(ctx.firstID != currID) { //some orders DID fully deal, so the head of single-linked list change
            _setFirstOrderID(ctx, !isBuy, currID);
        }
        // write the cached values to storage
        _setBooked(ctx.bookedStock, ctx.bookedMoney, ctx.firstBuyID);
        _setReserves(ctx.reserveStock, ctx.reserveMoney, ctx.firstSellID);
        return amountToTaker;
    }

    // Given reserveMoney and reserveStock in AMM pool, calculate how much tokens will go into the pool if the
    // final price is 'price'
    function _intopoolAmountTillPrice(bool isBuy, uint reserveMoney, uint reserveStock,
                                     RatPrice memory price) private pure returns (uint result) {
        // sqrt(Pold/Pnew) = sqrt((2**32)*M_old*PnewDenominator / (S_old*PnewNumerator)) / (2**16)
        // sell, stock-into-pool, Pold > Pnew
        uint numerator = reserveMoney/*112bits*/ * price.denominator/*76+64bits*/;
        uint denominator = reserveStock/*112bits*/ * price.numerator/*54+64bits*/;
        if(isBuy) { // buy, money-into-pool, Pold < Pnew
            // sqrt(Pnew/Pold) = sqrt((2**32)*S_old*PnewNumerator / (M_old*PnewDenominator)) / (2**16)
            (numerator, denominator) = (denominator, numerator);
        }
        while(numerator >= (1<<192)) { // can not equal to (1<<192) !!!
            numerator >>= 16;
            denominator >>= 16;
        }
        require(denominator != 0, "OneSwapPair: DIV_BY_ZERO");
        numerator = numerator * (1<<64);
        uint quotient = numerator / denominator;
        if(quotient <= (1<<64)) {
            return 0;
        } else if(quotient <= ((1<<64)*5/4)) {
            // Taylor expansion: x/2 - x*x/8 + x*x*x/16
            uint x = quotient - (1<<64);
            uint y = x*x;
            y = x/2 - y/(8*(1<<64)) + y*x/(16*(1<<128));
            if(isBuy) {
                result = reserveMoney * y;
            } else {
                result = reserveStock * y;
            }
            result /= (1<<64);
            return result;
        }
        uint root = Math.sqrt(quotient); //root is at most 110bits
        uint diff =  root - (1<<32);  //at most 110bits
        if(isBuy) {
            result = reserveMoney * diff;
        } else {
            result = reserveStock * diff;
        }
        result /= (1<<32);
        return result;
    }

    // Current order tries to deal against the AMM pool. Returns whether current order fully deals.
    function _tryDealInPool(Context memory ctx, bool isBuy, RatPrice memory price) private pure returns (bool) {
        uint currTokenCanTrade = _intopoolAmountTillPrice(isBuy, ctx.reserveMoney, ctx.reserveStock, price);
        require(currTokenCanTrade < uint(1<<112), "OneSwap: CURR_TOKEN_TOO_LARGE");
        // all the below variables are less than 112 bits
        if(!isBuy) {
            currTokenCanTrade /= ctx.stockUnit; //to round
            currTokenCanTrade *= ctx.stockUnit;
        }
        if(currTokenCanTrade > ctx.amountIntoPool) {
            uint diffTokenCanTrade = currTokenCanTrade - ctx.amountIntoPool;
            bool allDeal = diffTokenCanTrade >= ctx.remainAmount;
            if(allDeal) {
                diffTokenCanTrade = ctx.remainAmount;
            }
            ctx.amountIntoPool += diffTokenCanTrade;
            ctx.remainAmount -= diffTokenCanTrade;
            return allDeal;
        }
        return false;
    }

    // Current order tries to deal against the orders in book
    function _dealInOrderBook(Context memory ctx, bool isBuy, uint32 currID,
                             Order memory orderInBook, RatPrice memory priceInBook) internal {
        ctx.hasDealtInOrderBook = true;
        uint stockAmount;
        if(isBuy) {
            uint a = ctx.remainAmount/*112bits*/ * priceInBook.denominator/*76+64bits*/;
            uint b = priceInBook.numerator/*54+64bits*/ * ctx.stockUnit/*64bits*/;
            stockAmount = a/b;
        } else {
            stockAmount = ctx.remainAmount/ctx.stockUnit;
        }
        if(uint(orderInBook.amount) < stockAmount) {
            stockAmount = uint(orderInBook.amount);
        }
        require(stockAmount < (1<<42), "OneSwap: STOCK_TOO_LARGE");
        uint stockTrans = stockAmount/*42bits*/ * ctx.stockUnit/*64bits*/;
        uint moneyTrans = stockTrans * priceInBook.numerator/*54+64bits*/ / priceInBook.denominator/*76+64bits*/;

        _emitOrderChanged(orderInBook.amount, uint64(stockAmount), currID, isBuy);
        orderInBook.amount -= uint64(stockAmount);
        if(isBuy) { //subtraction cannot overflow: moneyTrans and stockTrans are calculated from remainAmount
            ctx.remainAmount -= moneyTrans;
        } else {
            ctx.remainAmount -= stockTrans;
        }
        // following accumulations can not overflow, because stockTrans(moneyTrans) at most 106bits(160bits)
        // we know for sure that dealStockInBook and dealMoneyInBook are less than 192 bits
        ctx.dealStockInBook += stockTrans;
        ctx.dealMoneyInBook += moneyTrans;
        if(isBuy) {
            _safeTransfer(ctx.moneyToken, orderInBook.sender, moneyTrans, ctx.ones);
        } else {
            _safeTransfer(ctx.stockToken, orderInBook.sender, stockTrans, ctx.ones);
        }
    }

    // make real deal with the pool and then collect fee, which will be added to AMM pool
    function _dealWithPoolAndCollectFee(Context memory ctx, bool isBuy) internal returns (uint) {
        (uint outpoolTokenReserve, uint inpoolTokenReserve, uint otherToTaker) = (
              ctx.reserveMoney, ctx.reserveStock, ctx.dealMoneyInBook);
        if(isBuy) {
            (outpoolTokenReserve, inpoolTokenReserve, otherToTaker) = (
                ctx.reserveStock, ctx.reserveMoney, ctx.dealStockInBook);
        }

        // all these 4 varialbes are less than 112 bits
        // outAmount is sure to less than outpoolTokenReserve (which is ctx.reserveStock or ctx.reserveMoney)
        uint outAmount = (outpoolTokenReserve*ctx.amountIntoPool)/(inpoolTokenReserve+ctx.amountIntoPool);
        if(ctx.amountIntoPool > 0) {
            _emitDealWithPool(uint112(ctx.amountIntoPool), uint112(outAmount), isBuy);
        }
        uint32 feeBPS = IOneSwapFactory(ctx.factory).feeBPS();
        // the token amount that should go to the taker, 
        // for buy-order, it's stock amount; for sell-order, it's money amount
        uint amountToTaker = outAmount + otherToTaker;
        require(amountToTaker < uint(1<<112), "OneSwap: AMOUNT_TOO_LARGE");
        uint fee = (amountToTaker * feeBPS + 9999) / 10000;
        amountToTaker -= fee;

        if(isBuy) {
            ctx.reserveMoney = ctx.reserveMoney + ctx.amountIntoPool;
            ctx.reserveStock = ctx.reserveStock - outAmount + fee;
        } else {
            ctx.reserveMoney = ctx.reserveMoney - outAmount + fee;
            ctx.reserveStock = ctx.reserveStock + ctx.amountIntoPool;
        }

        address token = ctx.moneyToken;
        if(isBuy) {
            token = ctx.stockToken;
        }
        _safeTransfer(token, ctx.order.sender, amountToTaker, ctx.ones);
        return amountToTaker;
    }

    // Insert a not-fully-deal limit order into orderbook
    function _insertOrderToBook(Context memory ctx, bool isBuy, RatPrice memory price) internal {
        (uint smallAmount, uint moneyAmount, uint stockAmount) = (0, 0, 0);
        if(isBuy) {
            uint tempAmount1 = ctx.remainAmount /*112bits*/ * price.denominator /*76+64bits*/;
            uint temp = ctx.stockUnit * price.numerator/*54+64bits*/;
            stockAmount = tempAmount1 / temp;
            uint tempAmount2 = stockAmount * temp; // Now tempAmount1 >= tempAmount2
            moneyAmount = (tempAmount2+price.denominator-1)/price.denominator; // round up
            if(ctx.remainAmount > moneyAmount) {
                // smallAmount is the gap where remainAmount can not buy an integer of stocks
                smallAmount = ctx.remainAmount - moneyAmount;
            } else {
                moneyAmount = ctx.remainAmount;
            } //Now ctx.remainAmount >= moneyAmount
        } else {
            // for sell orders, remainAmount were always decreased by integral multiple of StockUnit
            // and we know for sure that ctx.remainAmount % StockUnit == 0
            stockAmount = ctx.remainAmount / ctx.stockUnit;
            smallAmount = ctx.remainAmount - stockAmount * ctx.stockUnit;
        }
        ctx.amountIntoPool += smallAmount; // Deal smallAmount with pool
        //ctx.reserveMoney += smallAmount; // If this addition overflows, _setReserves will fail
        _emitNewLimitOrder(uint64(ctx.order.sender), ctx.order.amount, uint64(stockAmount),
                           ctx.order.price, ctx.newOrderID, isBuy);
        if(stockAmount != 0) {
            ctx.order.amount = uint64(stockAmount);
            if(ctx.hasDealtInOrderBook) {
                // if current order has ever dealt, it has the best price and can be inserted at head
                _insertOrderAtHead(ctx, isBuy, ctx.order, ctx.newOrderID);
            } else {
                // if current order has NEVER dealt, we must find a proper position for it.
                // we may scan a lot of entries in the single-linked list and run out of gas
                _insertOrderFromHead(ctx, isBuy, ctx.order, ctx.newOrderID);
            }
        }
        // Any overflow/underflow in following calculation will be caught by _setBooked
        if(isBuy) {
            ctx.bookedMoney += moneyAmount;
        } else {
            ctx.bookedStock += (ctx.remainAmount - smallAmount);
        }
    }
}

// solhint-disable-next-line max-states-count
contract OneSwapPairProxy {
    uint internal _unusedVar0;
    uint internal _unusedVar1;
    uint internal _unusedVar2;
    uint internal _unusedVar3;
    uint internal _unusedVar4;
    uint internal _unusedVar5;
    uint internal _unusedVar6;
    uint internal _unusedVar7;
    uint internal _unusedVar8;
    uint internal _unusedVar9;
    uint internal _unlocked;

    uint internal immutable _immuFactory;
    uint internal immutable _immuMoneyToken;
    uint internal immutable _immuStockToken;
    uint internal immutable _immuOnes;
    uint internal immutable _immuOther;

    constructor(address stockToken, address moneyToken, bool isOnlySwap, uint64 stockUnit, uint64 priceMul, uint64 priceDiv, address ones) public {
        _immuFactory = uint(msg.sender);
        _immuMoneyToken = uint(moneyToken);
        _immuStockToken = uint(stockToken);
        _immuOnes = uint(ones);
        uint temp = 0;
        if(isOnlySwap) {
            temp = 1;
        }
        temp = (temp<<64) | stockUnit;
        temp = (temp<<64) | priceMul;
        temp = (temp<<64) | priceDiv;
        _immuOther = temp;
        _unlocked = 1;
    }

    receive() external payable { }
    // solhint-disable-next-line no-complex-fallback
    fallback() payable external {
        uint factory     = _immuFactory;
        uint moneyToken  = _immuMoneyToken;
        uint stockToken  = _immuStockToken;
        uint ones        = _immuOnes;
        uint other       = _immuOther;
        address impl = IOneSwapFactory(address(_immuFactory)).pairLogic();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := mload(0x40)
            let size := calldatasize()
            calldatacopy(ptr, 0, size)
            let end := add(ptr, size)
            // append immutable variables to the end of calldata
            mstore(end, factory)
            end := add(end, 32)
            mstore(end, moneyToken)
            end := add(end, 32)
            mstore(end, stockToken)
            end := add(end, 32)
            mstore(end, ones)
            end := add(end, 32)
            mstore(end, other)
            size := add(size, 160)
            let result := delegatecall(gas(), impl, ptr, size, 0, 0)
            size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}

