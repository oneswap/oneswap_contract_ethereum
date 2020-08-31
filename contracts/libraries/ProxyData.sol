// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

library ProxyData {
    uint constant IndexFactory = 0;
    uint constant IndexMoneyToken = 1;
    uint constant IndexStockToken = 2;
    uint constant IndexOnes = 3;
    uint constant IndexOther = 4;
    uint constant Count = 5;
    uint constant OffsetPriceDiv = 0;
    uint constant OffsetPriceMul = 64;
    uint constant OffsetStockUnit = 64+64;
    uint constant OffsetIsOnlySwap = 64+64+64;

    function fill(uint[5] memory proxyData, uint expectedCallDataSize) internal {
		uint size;
        assembly {
            size := calldatasize()
        }
        require(size == expectedCallDataSize, "INVALID_CALLDATASIZE");
        assembly {
            let offset := sub(size, 160)
            calldatacopy(proxyData, offset, 160)
        }
    }
}

