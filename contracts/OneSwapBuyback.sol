// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapToken.sol";
import "./interfaces/IOneSwapFactory.sol";
import "./interfaces/IOneSwapRouter.sol";
import "./interfaces/IOneSwapBuyback.sol";

contract OneSwapBuyback is IOneSwapBuyback {

    uint256 private constant _MAX_UINT256 = uint256(-1); 

    address public immutable override weth;
    address public immutable override ones;
    address public immutable override router;
    address public immutable override factory;

    mapping (address => bool) private _mainTokens;
    address[] private _mainTokenArr;

    constructor(address _weth, address _ones, address _router, address _factory) public {
        weth = _weth;
        ones = _ones;
        router = _router;
        factory = _factory;

        // add WETH to main token list
        _mainTokens[_ones] = true;
        _mainTokenArr.push(_ones);
        _mainTokens[_weth] = true;
        _mainTokenArr.push(_weth);
    }

    // add token into main token list
    function addMainToken(address token) external override {
        require(msg.sender == IOneSwapToken(ones).owner(), "OneSwapBuyback: NOT_ONES_OWNER");
        if (!_mainTokens[token]) {
            _mainTokens[token] = true;
            _mainTokenArr.push(token);
        }
    }
    // remove token from main token list
    function removeMainToken(address token) external override {
        require(msg.sender == IOneSwapToken(ones).owner(), "OneSwapBuyback: NOT_ONES_OWNER");
        require(token != ones, "OneSwapBuyback: REMOVE_ONES_FROM_MAIN");
        require(token != weth, "OneSwapBuyback: REMOVE_WETH_FROM_MAIN");
        if (_mainTokens[token]) {
            _mainTokens[token] = false;
            uint256 lastIdx = _mainTokenArr.length - 1;
            for (uint256 i = 1; i < lastIdx; i++) { // skip WETH (idx 0)
                if (_mainTokenArr[i] == token) {
                    _mainTokenArr[i] = _mainTokenArr[lastIdx];
                    break;
                }
            }
            _mainTokenArr.pop();
        }
    }
    // check if token is in main token list
    function isMainToken(address token) external view override returns (bool) {
        return _mainTokens[token];
    }
    // query main token list
    function mainTokens() external view override returns (address[] memory list) {
        list = _mainTokenArr;
    }

    // remove Buyback's liquidity from all pairs
    // swap got minor tokens for main tokens if possible
    function removeLiquidity(address[] calldata pairs) external override {
        for (uint256 i = 0; i < pairs.length; i++) {
            _removeLiquidity(pairs[i]);
        }
    }
    function _removeLiquidity(address pair) private {
        uint256 amt = IERC20(pair).balanceOf(address(this));
        require(amt > 0, "OneSwapBuyback: NO_LIQUIDITYS");

        IERC20(pair).approve(router, amt);
        IOneSwapRouter(router).removeLiquidity(
            pair, amt, 0, 0, address(this), _MAX_UINT256);

        // minor -> main
        (address a, address b) = IOneSwapFactory(factory).getTokensFromPair(pair);
        bool aIsMain = _mainTokens[a];
        bool bIsMain = _mainTokens[b];
        if ((aIsMain && !bIsMain) || (!aIsMain && bIsMain)) {
            _swapForMainToken(pair);
        }
    }

    // swap minor tokens for main tokens
    function swapForMainToken(address[] calldata pairs) external override {
        for (uint256 i = 0; i < pairs.length; i++) {
            _swapForMainToken(pairs[i]);
        }
    }
    function _swapForMainToken(address pair) private {
        (address a, address b) = IOneSwapFactory(factory).getTokensFromPair(pair);

        address mainToken;
        address minorToken;
        if (_mainTokens[a]) {
            require(!_mainTokens[b], "OneSwapBuyback: SWAP_TWO_MAIN_TOKENS");
            (mainToken, minorToken) = (a, b);
        } else {
            require(_mainTokens[b], "OneSwapBuyback: SWAP_TWO_MINOR_TOKENS");
            (mainToken, minorToken) = (b, a);
        }

        uint256 minorTokenAmt = IERC20(minorToken).balanceOf(address(this));
        require(minorTokenAmt > 0, "OneSwapBuyback: NO_MINOR_TOKENS");

        address[] memory path = new address[](1);
        path[0] = pair;

        // minor -> main
        IERC20(minorToken).approve(router, minorTokenAmt);
        IOneSwapRouter(router).swapToken(
            minorToken, minorTokenAmt, 0, path, address(this), _MAX_UINT256);
    }

    // swap main tokens for ones, then burn all ones
    function swapForOnesAndBurn(address[] calldata pairs) external override {
        for (uint256 i = 0; i < pairs.length; i++) {
            _swapForOnesAndBurn(pairs[i]);
        }

        // burn all ones
        uint256 allOnes = IERC20(ones).balanceOf(address(this));
        IOneSwapToken(ones).burn(allOnes);
        emit BurnOnes(allOnes);
    }
    function _swapForOnesAndBurn(address pair) private {
        (address a, address b) = IOneSwapFactory(factory).getTokensFromPair(pair);
        require(a == ones || b == ones, "OneSwapBuyback: ONES_NOT_IN_PAIR");

        address token = (a == ones) ? b : a;
        require(_mainTokens[token], "OneSwapBuyback: MAIN_TOKEN_NOT_IN_PAIR");
        uint256 tokenAmt = IERC20(token).balanceOf(address(this));
        require(tokenAmt > 0, "OneSwapBuyback: NO_MAIN_TOKENS");

        address[] memory path = new address[](1);
        path[0] = pair;

        // token -> ones
        IERC20(token).approve(router, tokenAmt);
        IOneSwapRouter(router).swapToken(
            token, tokenAmt, 0, path, address(this), _MAX_UINT256);
    }

}
