// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

/*
This library defines a decimal floating point number. It has 8 decimal significant digits. Its maximum value is 9.9999999e+15.
And its minimum value is 1.0e-16. The following golang code explains its detail implementation.

func buildPrice(significant int, exponent int) uint32 {
	if !(10000000 <= significant && significant <= 99999999) {
		panic("Invalid significant")
	}
	if !(-16 <= exponent && exponent <= 15) {
		panic("Invalid exponent")
	}
	return uint32(((exponent+16)<<27)|significant);
}

func priceToFloat(price uint32) float64 {
	exponent := int(price>>27)
	significant := float64(price&((1<<27)-1))
	return significant * math.Pow10(exponent-23)
}

*/

// A price presented as a rational number
struct RatPrice {
    uint numerator;   // at most 54bits
    uint denominator; // at most 76bits
}

library DecFloat32 {
    uint32 constant MantissaMask = (1<<27) - 1;
    uint32 constant MaxMantissa = 9999_9999;
    uint32 constant MinMantissa = 1000_0000;
    uint32 constant MinPrice = MinMantissa;
    uint32 constant MaxPrice = (31<<27)|MaxMantissa;

    function powSmall(uint32 i) internal pure returns (uint) {
        uint X = 2695994666777834996822029817977685892750687677375768584125520488993233305610;
        return (X >> (32*i)) & ((1<<32)-1);
    }

    function powBig(uint32 i) internal pure returns (uint) {
        uint Y = 3402823669209384634633746076162356521930955161600000001;
        return (Y >> (64*i)) & ((1<<64)-1);
    }

    // if price32=( 0<<27)|12345678 then numerator=12345678 denominator=100000000000000000000000
    // if price32=( 1<<27)|12345678 then numerator=12345678 denominator=10000000000000000000000
    // if price32=( 2<<27)|12345678 then numerator=12345678 denominator=1000000000000000000000
    // if price32=( 3<<27)|12345678 then numerator=12345678 denominator=100000000000000000000
    // if price32=( 4<<27)|12345678 then numerator=12345678 denominator=10000000000000000000
    // if price32=( 5<<27)|12345678 then numerator=12345678 denominator=1000000000000000000
    // if price32=( 6<<27)|12345678 then numerator=12345678 denominator=100000000000000000
    // if price32=( 7<<27)|12345678 then numerator=12345678 denominator=10000000000000000
    // if price32=( 8<<27)|12345678 then numerator=12345678 denominator=1000000000000000
    // if price32=( 9<<27)|12345678 then numerator=12345678 denominator=100000000000000
    // if price32=(10<<27)|12345678 then numerator=12345678 denominator=10000000000000
    // if price32=(11<<27)|12345678 then numerator=12345678 denominator=1000000000000
    // if price32=(12<<27)|12345678 then numerator=12345678 denominator=100000000000
    // if price32=(13<<27)|12345678 then numerator=12345678 denominator=10000000000
    // if price32=(14<<27)|12345678 then numerator=12345678 denominator=1000000000
    // if price32=(15<<27)|12345678 then numerator=12345678 denominator=100000000
    // if price32=(16<<27)|12345678 then numerator=12345678 denominator=10000000
    // if price32=(17<<27)|12345678 then numerator=12345678 denominator=1000000
    // if price32=(18<<27)|12345678 then numerator=12345678 denominator=100000
    // if price32=(19<<27)|12345678 then numerator=12345678 denominator=10000
    // if price32=(20<<27)|12345678 then numerator=12345678 denominator=1000
    // if price32=(21<<27)|12345678 then numerator=12345678 denominator=100
    // if price32=(22<<27)|12345678 then numerator=12345678 denominator=10
    // if price32=(23<<27)|12345678 then numerator=12345678 denominator=1
    // if price32=(24<<27)|12345678 then numerator=123456780 denominator=1
    // if price32=(25<<27)|12345678 then numerator=1234567800 denominator=1
    // if price32=(26<<27)|12345678 then numerator=12345678000 denominator=1
    // if price32=(27<<27)|12345678 then numerator=123456780000 denominator=1
    // if price32=(28<<27)|12345678 then numerator=1234567800000 denominator=1
    // if price32=(29<<27)|12345678 then numerator=12345678000000 denominator=1
    // if price32=(30<<27)|12345678 then numerator=123456780000000 denominator=1
    // if price32=(31<<27)|12345678 then numerator=1234567800000000 denominator=1
    function expandPrice(uint32 price32) internal pure returns (RatPrice memory) {
        uint s = price32&((1<<27)-1);
        uint32 a = price32 >> 27;
        RatPrice memory price;
        if(a >= 24) {
            uint32 b = a - 24;
            price.numerator = s * powSmall(b);
            price.denominator = 1;
        } else if(a == 23) {
            price.numerator = s;
            price.denominator = 1;
        } else {
            uint32 b = 22 - a;
            price.numerator = s;
            price.denominator = powSmall(b&0x7) * powBig(b>>3);
        }
        return price;
    }

    function getExpandPrice(uint price) internal pure returns(uint numerator, uint denominator) {
        uint32 m = uint32(price) & DecFloat32.MantissaMask;
        require(DecFloat32.MinMantissa <= m && m <= DecFloat32.MaxMantissa, "Invalid Price");
        RatPrice memory actualPrice = DecFloat32.expandPrice(uint32(price));
        return (actualPrice.numerator, actualPrice.denominator);
    }

}

