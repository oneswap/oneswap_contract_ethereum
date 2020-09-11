// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "../OneSwapPair.sol";

// this contract is only used for test
contract OneSwapFactoryPXYTEST {
    address public feeTo;
    address public feeToSetter;
    address public pairLogic;

    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairs;

    event PairCreated(address indexed stock, address indexed money, address pair, uint);

    function createPair(address stock, address money, address impl) external {
        require(stock != money, "OneSwap: IDENTICAL_ADDRESSES");
        require(stock != address(0) || money != address(0), "OneSwap: ZERO_ADDRESS");
        require(pairs[stock][money] == address(0), "OneSwap: PAIR_EXISTS"); // single check is sufficient
        uint8 dec;
        if (stock == address(0)){
            dec = 18;
        } else{
            dec = IERC20(stock).decimals();
        }
        require(25 >= dec && dec >= 6, "OneSwap: DECIMALS_NOT_SUPPORTED");
        dec -= 6;
        bytes32 salt = keccak256(abi.encodePacked(stock, money));
        OneSwapPairProxy oneswap = new OneSwapPairProxy{salt: salt}(stock, money, false, 1, 1, 1, address(0));
        address pair = address(oneswap);
        pairs[stock][money] = pair;
        allPairs.push(pair);
        pairLogic = impl;
        emit PairCreated(stock, money, pair, allPairs.length);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function feeBPS() external pure returns (uint32) {
        return 30;
    }
}

