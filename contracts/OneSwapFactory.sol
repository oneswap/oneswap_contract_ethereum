// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapFactory.sol";
import "./OneSwapPair.sol";

contract OneSwapFactory is IOneSwapFactory {
    struct TokensInPair {
        address stock;
        address money;
    }

    address public override feeTo;
    address public override feeToSetter;
    address public immutable gov;
    address public immutable weth;
    uint32 public override feeBPS = 50;
    mapping(address => TokensInPair) private _pairWithToken;
    mapping(bytes32 => address) private _tokensToPair;
    address[] public allPairs;

    constructor(address _feeToSetter, address _gov, address _weth) public {
        feeToSetter = _feeToSetter;
        weth = _weth;
        gov = _gov;
    }

    function createPair(address stock, address money, bool isOnlySwap) external override returns (address pair) {
        require(stock != money, "OneSwapFactory: IDENTICAL_ADDRESSES");
        require(stock != address(0) && money != address(0), "OneSwapFactory: ZERO_ADDRESS");
        uint moneyDec = uint(IERC20(money).decimals());
        uint stockDec = uint(IERC20(stock).decimals());
        require(23 >= stockDec && stockDec >= 0, "OneSwapFactory: STOCK_DECIMALS_NOT_SUPPORTED");
        uint dec = 0;
        if(stockDec >= 4) {
            dec = stockDec - 4; // now 19 >= dec && dec >= 0
        }
        // 10**19 = 10000000000000000000
        //  1<<64 = 18446744073709551616
        uint64 priceMul = 1;
        uint64 priceDiv = 1;
        bool differenceTooLarge = false;
        if(moneyDec > stockDec) {
            if(moneyDec > stockDec + 19) {
                differenceTooLarge = true;
            } else {
                priceMul = uint64(uint(10)**(moneyDec - stockDec));
            }
        }
        if(stockDec > moneyDec) {
            if(stockDec > moneyDec + 19) {
                differenceTooLarge = true;
            } else {
                priceDiv = uint64(uint(10)**(stockDec - moneyDec));
            }
        }
        require(!differenceTooLarge, "OneSwapFactory: DECIMALS_DIFF_TOO_LARGE");
        bytes32 salt = keccak256(abi.encodePacked(stock, money, isOnlySwap));
        require(_tokensToPair[salt] == address(0), "OneSwapFactory: PAIR_EXISTS");
        OneSwapPair oneswap = new OneSwapPair{salt: salt}(weth, stock, money, isOnlySwap, uint64(uint(10)**dec), priceMul, priceDiv);

        pair = address(oneswap);
        allPairs.push(pair);
        _tokensToPair[salt] = pair;
        _pairWithToken[pair] = TokensInPair(stock, money);
        emit PairCreated(pair, stock, money, isOnlySwap);
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "OneSwapFactory: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "OneSwapFactory: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function setFeeBPS(uint32 _bps) external override {
        require(msg.sender == gov, "OneSwapFactory: SETTER_MISMATCH");
        require(0 <= _bps && _bps <= 50 , "OneSwapFactory: BPS_OUT_OF_RANGE");
        feeBPS = _bps;
    }

    function getTokensFromPair(address pair) external view override returns (address stock, address money) {
        stock = _pairWithToken[pair].stock;
        money = _pairWithToken[pair].money;
    }

    function tokensToPair(address stock, address money, bool isOnlySwap) external view override returns (address pair){
        bytes32 key = keccak256(abi.encodePacked(stock, money, isOnlySwap));
        return _tokensToPair[key];
    }
}
