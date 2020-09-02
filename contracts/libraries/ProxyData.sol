// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

library ProxyData {
    uint public constant COUNT = 5;
    uint public constant INDEX_FACTORY = 0;
    uint public constant INDEX_MONEY_TOKEN = 1;
    uint public constant INDEX_STOCK_TOKEN = 2;
    uint public constant INDEX_ONES = 3;
    uint public constant INDEX_OTHER = 4;
    uint public constant OFFSET_PRICE_DIV = 0;
    uint public constant OFFSET_PRICE_MUL = 64;
    uint public constant OFFSET_STOCK_UNIT = 64+64;
    uint public constant OFFSET_IS_ONLY_SWAP = 64+64+64;

    function factory(uint[5] memory proxyData) internal pure returns (address) {
         return address(proxyData[INDEX_FACTORY]);
    }

    function money(uint[5] memory proxyData) internal pure returns (address) {
         return address(proxyData[INDEX_MONEY_TOKEN]);
    }

    function stock(uint[5] memory proxyData) internal pure returns (address) {
         return address(proxyData[INDEX_STOCK_TOKEN]);
    }

    function ones(uint[5] memory proxyData) internal pure returns (address) {
         return address(proxyData[INDEX_ONES]);
    }

    function priceMul(uint[5] memory proxyData) internal pure returns (uint64) {
        return uint64(proxyData[INDEX_OTHER]>>OFFSET_PRICE_MUL);
    }

    function priceDiv(uint[5] memory proxyData) internal pure returns (uint64) {
        return uint64(proxyData[INDEX_OTHER]>>OFFSET_PRICE_DIV);
    }

    function stockUnit(uint[5] memory proxyData) internal pure returns (uint64) {
        return uint64(proxyData[INDEX_OTHER]>>OFFSET_STOCK_UNIT);
    }

    function isOnlySwap(uint[5] memory proxyData) internal pure returns (bool) {
        return uint8(proxyData[INDEX_OTHER]>>OFFSET_IS_ONLY_SWAP) != 0;
    }

    function fill(uint[5] memory proxyData, uint expectedCallDataSize) internal {
        uint size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := calldatasize()
        }
        require(size == expectedCallDataSize, "INVALID_CALLDATASIZE");
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let offset := sub(size, 160)
            calldatacopy(proxyData, offset, 160)
        }
    }
}

