// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IOneSwapFactory {
    event PairCreated(address indexed pair, address stock, address money, bool isOnlySwap);

    function createPair(address stock, address money, bool isOnlySwap) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function setFeeBPS(uint32 bps) external;

    function allPairsLength() external view returns (uint);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function feeBPS() external view returns (uint32);
    function getTokensFromPair(address pair) external view returns (address stock, address money);
    function tokensToPair(address stock, address money, bool isOnlySwap) external view returns (address pair);
}
