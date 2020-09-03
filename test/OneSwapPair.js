const tokenCon = artifacts.require("OneSwapToken");
const pairCon = artifacts.require("OneSwapPair");
const facCon = artifacts.require("OneSwapFactoryPXYTEST");
const weth9Con = artifacts.require("WETH9");
const revert = require("./exceptions.js").revert;

const BUY = true;
const SELL = false;

function makePrice32(s, e) {
    return s | (e << 27)
}
function makePrice32Big(s, e) {
    return BigInt(s) | (BigInt(e) << 27n);
}

function merge3(a0, a1, a2) {
    let n = BigInt(0);
    n = n | BigInt(a2);
    n = (n << BigInt(32)) | BigInt(a1);
    n = (n << BigInt(32)) | BigInt(a0);
    return n.toString();
}

async function initializeToken(boss) {
    weth = await weth9Con.new();
    impl = await pairCon.new();
    factory = await facCon.new(weth.address);
    btc = await tokenCon.new("btc", "btc", 100000000000000, 18, {from: boss});
    usd = await tokenCon.new("usd", "usd", 100000000000000, 18, {from: boss});


    console.log("stock address: ", btc.address)
    console.log("money address: ", usd.address)

    result = await factory.createPair(btc.address, usd.address, impl.address);
    pairAddr = result.logs[0].args.pair;
    console.log("pairAddr: ", pairAddr)
    pair = await pairCon.at(pairAddr)
    result = await pair.stock()
    for(let i=0; i < result.logs.length; i++) {
        console.log("========hehe ", i, result.logs[i].event, result.logs[i].args);
    }
    stock = await pair.stock.call()
    money = await pair.money.call()
    console.log("stock and money: ", stock, money)
}

async function initializeTokenWithWETH(boss) {
    weth = await weth9Con.new();
    impl = await pairCon.new();
    factory = await facCon.new();
    usd = await tokenCon.new("usd", "usd", 100000000000000, 18, {from: boss});

    console.log("stock address: ", weth.address)
    console.log("money address: ", usd.address)

    result = await factory.createPair(weth.address, usd.address, impl.address);
    pairAddr = result.logs[0].args.pair;
    console.log("pairAddr: ", pairAddr)
    pair = await pairCon.at(pairAddr)
    stock = await pair.stock.call()
    money = await pair.money.call()
    console.log("stock and money: ", stock, money)
}

async function initializeTokenWithETH(boss) {

    impl = await pairCon.new();
    eth = '0x0000000000000000000000000000000000000000';
    factory = await facCon.new();
    usd = await tokenCon.new("usd", "usd", 100000000000000, 18, {from: boss});

    console.log("stock address: ", eth)
    console.log("money address: ", usd.address)

    result = await factory.createPair(eth, usd.address, impl.address);
    pairAddr = result.logs[0].args.pair;
    console.log("pairAddr: ", pairAddr)
    pair = await pairCon.at(pairAddr)
    stock = await pair.stock.call()
    money = await pair.money.call()
    console.log("stock and money: ", stock, money)
}

async function initializeBalanceWithETH(boss, lp, maker, taker) {
    // no need to transfer eth to all accounts
    let balance= await web3.eth.getBalance(boss)
    console.log(balance)
    balance= await web3.eth.getBalance(lp)
    console.log(balance)
    balance= await web3.eth.getBalance(maker)
    console.log(balance)

    await usd.transfer(lp, 1000000, {from: boss}); //1 million
    await usd.transfer(taker, 10000000, {from: boss});
    lpBalance = await usd.balanceOf.call(lp);
    let takerBalance = await usd.balanceOf.call(taker);
    assert.equal(lpBalance, 1000000, "lp usd balance is not correct");
    assert.equal(takerBalance, 10000000, "taker usd balance is not correct");
}

async function initializeBalance(boss, lp, maker, taker) {
    await btc.transfer(lp, 10000, {from: boss});
    await btc.transfer(maker, 10000, {from: boss});
    let lpBalance = await btc.balanceOf.call(lp);
    let makerBalance = await btc.balanceOf.call(maker);
    assert.equal(lpBalance, 10000, "lp btc balance is not correct");
    assert.equal(makerBalance, 10000, "maker btc balance is not correct");

    await usd.transfer(lp, 1000000, {from: boss}); //1 million
    await usd.transfer(taker, 10000000, {from: boss});
    lpBalance = await usd.balanceOf.call(lp);
    let takerBalance = await usd.balanceOf.call(taker);
    assert.equal(lpBalance, 1000000, "lp usd balance is not correct");
    assert.equal(takerBalance, 10000000, "taker usd balance is not correct");
}

async function mint(btc, usd, lp, boss, pair, shareReceiver) {
    await btc.approve(boss, 1000000000, {from: lp});
    await usd.approve(boss, 1000000000, {from: lp});
    await btc.transferFrom(lp, pair.address, 10000, {from: boss});
    await usd.transferFrom(lp, pair.address, 1000000, {from: boss});
    let gas = await pair.mint.estimateGas(shareReceiver);
    console.log("gas on mint: ", gas);
    result = await pair.mint(shareReceiver);
    console.log("real gas on mint: ", result.receipt.gasUsed)
    //for(let i=0; i < result.logs.length; i++) {
    //    console.log("========log ", i, result.logs[i].event, result.logs[i].args);
    //}
}

function orderIdFromEvent(data) {
    return ((BigInt(data) >> 8n) & (BigInt(Math.pow(2, 24)) - 1n)).valueOf()
}
function dealAmountFromEventDealWithPool(data){
    //[amountIn,amountOut]
    return [((BigInt(data)>>120n) & (BigInt(Math.pow(2, 112)) - 1n)).valueOf(),
        ((BigInt(data)>>8n) & (BigInt(Math.pow(2, 112)) - 1n)).valueOf()]
}
function stockAmountFromEventNewLimitOrder(data){
    //[remainedStockAmount,totalStockAmount]
    return [((BigInt(data)>>128n) & (BigInt(Math.pow(2, 64)) - 1n)).valueOf(),
        ((BigInt(data)>>64n) & (BigInt(Math.pow(2, 64)) - 1n)).valueOf()]
}
function syncAmountFromEventSync(data){
    //[stockAmount,moneyAmount]
    return [((BigInt(data)>>112n) & (BigInt(Math.pow(2, 112)) - 1n)).valueOf(),
        ((BigInt(data)) & (BigInt(Math.pow(2, 112)) - 1n)).valueOf()]
}

contract("pair", async accounts => {

    const owner = accounts[0];
    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];
    // let factory, btc, usd, weth, pair;

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
        assert.equal(await pair.name.call(), "OneSwap-Liquidity-Share");
        assert.equal(await pair.decimals.call(), 18);
        assert.equal(await pair.symbol.call(), "btc/usd-Share");
    });

   // it("test emitEvents", async () => {
	// 	result = await pair._emitNewLimitOrder("0x123456789ABCDEF", 0x289, 0x189, 0x88bc614e, 0x500, true)
	// 	assert.equal(result.logs[0].args.data.toString(16), "123456789abcdef0000000000000289000000000000018988bc614e00050001", "NewOrder err")
	// 	result = await pair._emitNewMarketOrder("0x123456789ABCDEF", "0xEFCDBA9876543210", true)
	// 	assert.equal(result.logs[0].args.data.toString(16), "123456789abcdef000000000000efcdba987654321001", "NewOrder err")
	// 	result = await pair._emitOrderChanged(0x489, 0x389, 0x6666, true)
	// 	assert.equal(result.logs[0].args.data.toString(16), "489000000000000038900666601", "OrderChanged err")
	// 	result = await pair._emitDealWithPool("0x123456789ABCDEF", "0xEFCDBA9876543210", true)
	// 	assert.equal(result.logs[0].args.data.toString(16), "123456789abcdef000000000000efcdba987654321001", "DealWithPool err")
	// 	result = await pair._emitRemoveOrder(0x8866886655, 0xf2222, true)
	// 	assert.equal(result.logs[0].args.data.toString(16), "88668866550f222201", "RemoveOrder err")
	// });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });

    it("mint", async () => {

        await mint(btc, usd, lp, boss, pair, shareReceiver);

        let balance = await pair.balanceOf.call(shareReceiver);
        assert.equal(balance, 99000, "share mint is not correct");
        let reserves = await pair.getReserves.call();
        console.log("reserves: ", reserves)
        assert.equal(reserves.reserveStock, 10000, "reserve stock is not correct");
        assert.equal(reserves.reserveMoney, 1000000, "reserve money is not correct");
        balance = await pair.balanceOf.call("0x0000000000000000000000000000000000000000");
        assert.equal(balance, 1000, "locked liquidity is not correct");
    });

    it("insert sell order with 0 deal", async () => {
        await btc.approve(boss, 1000000000, {from: maker});
        await usd.approve(boss, 1000000000, {from: maker});
        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        let result = await pair.addLimitOrder(false, maker, 100, makePrice32(10000000, 18), 1, merge3(0, 0, 0), {from: maker})
        console.log("gas on first insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        result = await pair.addLimitOrder(false, maker, 100, makePrice32(10300000, 18), 2, merge3(0, 0, 0), {from: maker})
        console.log("gas on second insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        result = await pair.addLimitOrder(false, maker, 100, makePrice32(10500000, 18), 3, merge3(2, 0, 0), {from: maker})
        console.log("gas on third insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        result = await pair.addLimitOrder(false, maker, 100, makePrice32(10700000, 18), 4, merge3(3, 0, 0), {from: maker})
        console.log("gas on forth insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        result = await pair.addLimitOrder(false, maker, 100, makePrice32(10900000, 18), 5, merge3(4, 0, 0), {from: maker})
        console.log("gas on fifth insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 1, {from: boss});
        result = await pair.addLimitOrder(false, maker, 1, makePrice32(10200000, 18), 6, merge3(1, 0, 0), {from: maker})
        console.log("gas on 6th insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 1, {from: boss});
        result = await pair.addLimitOrder(false, maker, 1, makePrice32(10400000, 18), 7, merge3(2, 0, 0), {from: maker})
        console.log("gas on 7th insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 1, {from: boss});
        result = await pair.addLimitOrder(false, maker, 1, makePrice32(10600000, 18), 8, merge3(3, 0, 0), {from: maker})
        console.log("gas on 8th insert: ", result.receipt.gasUsed);

        await btc.transferFrom(maker, pair.address, 1, {from: boss});
        result = await pair.addLimitOrder(false, maker, 1, makePrice32(10800000, 18), 9, merge3(4, 0, 0), {from: maker})
        console.log("gas on 9th insert: ", result.receipt.gasUsed);

        let balance = await btc.balanceOf.call(maker);
        assert.equal(balance.toNumber(), 9496, "btc balance of maker is not correct");
        balance = await usd.balanceOf.call(maker);
        assert.equal(balance.toNumber(), 0, "usd balance of maker is not correct");

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(), 10000, "reserve stock balance is not correct");
        assert.equal(reserves.reserveMoney.toNumber(), 1000000, "reserve money balance is not correct");
        assert.equal(reserves.firstSellID.toNumber(), 1, "firstSellID is not correct");
        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(), 504, "booked stock balance is not correct");
        assert.equal(booked.bookedMoney.toNumber(), 0, "booked money balance is not correct");
        assert.equal(booked.firstBuyID.toNumber(), 0, "firstBuyID is not correct");

        result = await pair.getOrderList.call(false, 0, 10);
        //console.log("========result ", result);
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("========orderlist ", i, result.logs[i].event, result.logs[i].args);
        //}
    });

    it("insert buy order with only 1 incomplete deal with orderbook", async () => {
        await btc.approve(boss, 1000000000, {from: taker});
        await usd.approve(boss, 1000000000, {from: taker});
        await usd.transferFrom(taker, pair.address, 5000, {from: boss});
        result = await pair.addLimitOrder(true, taker, 50, makePrice32(10000000, 18), 11, [0, 0, 0], {from: taker})
        console.log("gas on only 1 incomplete deal: ", result.receipt.gasUsed);
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("------log ", i, result.logs[i].args);
        //}

        let balance = await usd.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 9995000, "usd balance of taker is not correct");
        balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 50, "btc balance of taker is not correct");

        let reserves = await pair.getReserves.call();
        let booked = await pair.getBooked.call();
        console.log("reserveStock", reserves.reserveStock.toNumber())
        console.log("reserveMoney", reserves.reserveMoney.toNumber())
        console.log("firstSellID", reserves.firstSellID.toNumber())
        console.log("bookedStock", booked.bookedStock.toNumber())
        console.log("bookedMoney", booked.bookedMoney.toNumber())
        console.log("firstBuyID", booked.firstBuyID.toNumber())
        assert.equal(reserves.reserveStock.toNumber(), 10000, "reserve stock balance is not correct");
        assert.equal(reserves.reserveMoney.toNumber(), 1000000, "reserve money balance is not correct");
        assert.equal(reserves.firstSellID.toNumber(), 1, "firstSellID is not correct");
        assert.equal(booked.bookedStock.toNumber(), 454, "booked stock balance is not correct");
        assert.equal(booked.bookedMoney.toNumber(), 0, "booked money balance is not correct");
        assert.equal(booked.firstBuyID.toNumber(), 0, "firstBuyID is not correct");

    });

    it("insert buy order with only 1 complete deal with orderbook", async () => {
        await usd.transferFrom(taker, pair.address, 5000, {from: boss});
        result = await pair.addLimitOrder(true, taker, 50, makePrice32(10000000, 18), 12, [0, 0, 0], {from: taker})
        console.log("gas on only 1 complete deal: ", result.receipt.gasUsed);
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("------log ", i, result.logs[i].args);
        //}

        let reserves = await pair.getReserves.call();
        let booked = await pair.getBooked.call();
        console.log("reserveStock", reserves.reserveStock.toNumber())
        console.log("reserveMoney", reserves.reserveMoney.toNumber())
        console.log("firstSellID", reserves.firstSellID.toNumber())
        console.log("bookedStock", booked.bookedStock.toNumber())
        console.log("bookedMoney", booked.bookedMoney.toNumber())
        console.log("firstBuyID", booked.firstBuyID.toNumber())
        assert.equal(reserves.reserveStock.toNumber(), 10000, "reserve stock balance is not correct");
        assert.equal(reserves.reserveMoney.toNumber(), 1000000, "reserve money balance is not correct");
        assert.equal(reserves.firstSellID.toNumber(), 6, "firstSellID is not correct");
        assert.equal(booked.bookedStock.toNumber(), 404, "booked stock balance is not correct");
        assert.equal(booked.bookedMoney.toNumber(), 0, "booked money balance is not correct");
        assert.equal(booked.firstBuyID.toNumber(), 0, "firstBuyID is not correct");

        let balance = await usd.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 9990000, "usd balance of taker is not correct");
        balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 100, "btc balance of taker is not correct");
    });

    it("insert buy order with 7 complete deal with orderbook and 4 swap", async () => {
        await usd.transferFrom(taker, pair.address, 99000, {from: boss});
        result = await pair.addLimitOrder(true, taker, 900, makePrice32(11000000, 18), 12, [0, 0, 0], {from: taker})
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("========log ", i, result.logs[i].event, result.logs[i].args);
        //}
        console.log("gas on complete 7 buy: ", result.receipt.gasUsed);

        let reserves = await pair.getReserves.call();
        let booked = await pair.getBooked.call();
        console.log("reserveStock", reserves.reserveStock.toNumber())
        console.log("reserveMoney", reserves.reserveMoney.toNumber())
        console.log("firstSellID", reserves.firstSellID.toNumber())
        console.log("bookedStock", booked.bookedStock.toNumber())
        console.log("bookedMoney", booked.bookedMoney.toNumber())
        console.log("firstBuyID", booked.firstBuyID.toNumber())
        // 1048809/9537 = 109.97
        // 1048809*9537 = 10002491433.0
        assert.equal(reserves.reserveStock.toNumber(), 9536, "reserve stock balance is not correct");
        assert.equal(reserves.reserveMoney.toNumber(), 1048920, "reserve money balance is not correct");
        assert.equal(reserves.firstSellID.toNumber(), 0, "firstSellID is not correct");
        assert.equal(booked.bookedStock.toNumber(), 0, "booked stock balance is not correct");
        assert.equal(booked.bookedMoney.toNumber(), 7260, "booked money balance is not correct"); // 33*110=3630 < 7371
        assert.equal(booked.firstBuyID.toNumber(), 12, "firstBuyID is not correct");

        let balance = await usd.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 9891000, "usd balance of taker is not correct"); // 9990000-99000=9891000
        balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 968, "btc balance of taker is not correct"); // 867 newly income
    });

    it("remove sell order", async () => {
        result = await pair.removeOrder(true, 12, 0, {from: taker})
        console.log("gas on remove order: ", result.receipt.gasUsed);
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("========log ", i, result.logs[i].args);
        //}

        let reserves = await pair.getReserves.call();
        let booked = await pair.getBooked.call();
        console.log("reserveStock", reserves.reserveStock.toNumber())
        console.log("reserveMoney", reserves.reserveMoney.toNumber())
        console.log("firstSellID", reserves.firstSellID.toNumber())
        console.log("bookedStock", booked.bookedStock.toNumber())
        console.log("bookedMoney", booked.bookedMoney.toNumber())
        console.log("firstBuyID", booked.firstBuyID.toNumber())
        // 1048809/9537 = 109.97
        // 1048809*9537 = 10002491433.0
        assert.equal(reserves.reserveStock.toNumber(), 9536, "reserve stock balance is not correct");
        assert.equal(reserves.reserveMoney.toNumber(), 1048920, "reserve money balance is not correct");
        assert.equal(reserves.firstSellID.toNumber(), 0, "firstSellID is not correct");
        assert.equal(booked.bookedStock.toNumber(), 0, "booked stock balance is not correct");
        assert.equal(booked.bookedMoney.toNumber(), 0, "booked money balance is not correct"); // 1 is rounding error
        assert.equal(booked.firstBuyID.toNumber(), 0, "firstBuyID is not correct");

        let balance = await usd.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 9898260, "usd balance of taker is not correct"); // 9891000+7370 = 9898370
        balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 968, "btc balance of taker is not correct");
    });

});

contract("insert & delete order", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
    });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });
    it("mint", async () => {
        await mint(btc, usd, lp, boss, pair, shareReceiver)
    });
    it("insert sell order with duplicated id", async () => {
        await btc.approve(boss, 1000000000, {from: maker});
        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        let result = await pair.addLimitOrder(false, maker, 100, makePrice32(11000000, 18), 1, merge3(0, 0, 0), {from: maker})
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 1, "orderId is not correct");

        await btc.transferFrom(maker, pair.address, 50, {from: boss});
        result = await pair.addLimitOrder(false, maker, 50, makePrice32(12000000, 18), 1, merge3(0, 0, 0), {from: maker})
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 2, "orderId is not correct");

    });
    it("insert sell order with invalid prevkey", async () => {
        await btc.transferFrom(maker, pair.address, 100, {from: boss});
        let result = await pair.addLimitOrder(false, maker, 100, makePrice32(10500000, 18), 1, merge3(1, 2, 3), {from: maker})
        assert.equal(result.logs[0].event, "NewLimitOrder", "limit order is not correctly inserted")
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 3, "orderId is not correct");


    });
    it("insert buy order with invalid price", async () => {
        await revert(pair.addLimitOrder(true, maker, 100, makePrice32(105000, 18), 1, merge3(1, 2, 3), {from: taker}),
            "OneSwap: INVALID_PRICE")

        await revert(pair.addLimitOrder(true, maker, 100, makePrice32(105000000, 18), 1, merge3(1, 2, 3), {from: taker}),
            "OneSwap: INVALID_PRICE")
    });
    it("insert buy order with unenough usd", async () => {
        await usd.approve(boss, 1000000000, {from: taker});
        await usd.transferFrom(taker, pair.address, 500, {from: boss});
        await revert(pair.addLimitOrder(true, taker, 50, makePrice32(10000000, 18), 1, merge3(0, 0, 0), {from: taker}),
            "OneSwap: DEPOSIT_NOT_ENOUGH")
    });

    it("remove buy order with non existed id", async () => {
        await revert(pair.removeOrder(true, 1, merge3(0, 0, 0), {from: taker}),
            "OneSwap: NO_SUCH_ORDER",);
    });

    it("remove sell order with invalid prevKey", async () => {
        await revert(pair.removeOrder(false, 1, merge3(2, 3, 3), {from: maker}),
            "OneSwap: REACH_END")
    })
    it("only order sender can remove order", async () => {
        await revert(pair.removeOrder(false, 3, merge3(0, 0, 0), {from: boss}),
            "OneSwap: NOT_OWNER")
    })
    it("remove sell order successfully", async () => {
        // remove first sell id emits sync event at first
        let result = await pair.removeOrder(false, 3, merge3(0, 0, 0), {from: maker})
        // console.log(result.logs)
        assert.equal(result.logs[1].event, "RemoveOrder", "remove order event is not correct");

        result = await pair.removeOrder(false, 2, merge3(1, 0, 0), {from: maker})
        // console.log(result.logs)
        assert.equal(result.logs[0].event, "RemoveOrder", "remove order event is not correct");

        result = await pair.removeOrder(false, 1, merge3(0, 0, 0), {from: maker})
        // console.log(result.logs)
        assert.equal(result.logs[1].event, "RemoveOrder", "remove order event is not correct");

    })
});

contract("swap on low liquidity", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
    });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint only 1000 shares", async () => {
        await btc.approve(boss, 1000000000, {from: lp});
        await usd.approve(boss, 1000000000, {from: lp});
        await btc.transferFrom(lp, pair.address, 10000, {from: boss});
        await usd.transferFrom(lp, pair.address, 1000000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        await pair.transfer(pair.address, balance, {from: shareReceiver});
        await pair.burn(shareReceiver);
        balance = await pair.balanceOf.call(shareReceiver);
        console.log("balance: ", balance.toNumber());
        balance = await pair.balanceOf.call(ZERO_ADDR);
        console.log("balance: ", balance.toNumber());
    });

    it("swap with pool", async () => {
        await btc.transfer(maker, 90000000000000, {from: boss});
        await btc.transfer(pair.address, 90000000000000, {from: maker});
        let balance = await usd.balanceOf.call(maker);
        assert.equal(balance.toNumber(), 0);
        await pair.addMarketOrder(btc.address, maker, 90000000000000, {from: maker});
        balance = await usd.balanceOf.call(maker);
        if (10000 < balance.toNumber()) {
            throw "usd balance of maker incorrect!"
        }
    });
});

contract("big deal on low liquidity", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
    });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint only 1000 shares", async () => {
        await btc.approve(boss, 1000000000, {from: lp});
        await usd.approve(boss, 1000000000, {from: lp});
        await btc.transferFrom(lp, pair.address, 10000, {from: boss});
        await usd.transferFrom(lp, pair.address, 1000000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        await pair.transfer(pair.address, balance, {from: shareReceiver});
        await pair.burn(shareReceiver);
        balance = await pair.balanceOf.call(shareReceiver);
        assert.equal(balance.toNumber(), 0, "share balance of share receiver incorrect");
        balance = await pair.balanceOf.call(ZERO_ADDR);
        assert.equal(balance.toNumber(), 1000, "share balance of zero address incorrect");
    });

    //should not deal with pool
    it("insert sell order at pool current price", async () => {
        await btc.transfer(maker, 90000000000000, {from: boss});
        await btc.transfer(pair.address, 10, {from: maker});
        await pair.addLimitOrder(false, maker, 10, makePrice32(10000000, 18), 1, merge3(0, 0, 0), {from: maker});
        let balance = await usd.balanceOf.call(maker);
        assert.equal(balance.toNumber(), 0);
        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 0);
        assert.equal(booked.bookedStock.toNumber(), 10);
    });

    it("insert three small buy order at lower price", async () => {
        await usd.transfer(pair.address, 20, {from: taker});
        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 0);
        let result = await pair.addLimitOrder(true, maker, 10, makePrice32(20000000, 16), 1, merge3(0, 0, 0), {from: taker});
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 1, "orderId is not correct");

        booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 20);
        await usd.transfer(pair.address, 30, {from: taker});
        result = await pair.addLimitOrder(true, maker, 10, makePrice32(30000000, 16), 1, merge3(0, 0, 0), {from: taker});
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 2, "orderId is not correct");

        booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 50);
        await usd.transfer(pair.address, 40, {from: taker});
        result = await pair.addLimitOrder(true, maker, 10, makePrice32(40000000, 16), 1, merge3(0, 0, 0), {from: taker});
        assert.equal(orderIdFromEvent(result.logs[0].args.data), 3, "orderId is not correct");
        booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 90);
    });

    it("insert big sell order not deal", async () => {
        await btc.transfer(pair.address, 1000000000, {from: maker});
        await pair.addLimitOrder(false, maker, 1000000000, makePrice32(10100000, 18), 2, merge3(0, 0, 0), {from: maker});
        let balance = await usd.balanceOf.call(maker);
        assert.equal(balance.toNumber(), 0);
        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedMoney.toNumber(), 90);
        assert.equal(booked.bookedStock.toNumber(), 1000000010);
        let result = await pair.getReserves.call();
        console.log("current price: ", result[1] / result[0]);
        assert.equal(result[2].toNumber(), 1, "firstSellID incorrect")
    });

    //fee added to pool makes current price is very low
    it("insert big order deal with biggest sell order ", async () => {
        await usd.transfer(taker, 100000_0000_0000, {from: boss});
        await usd.transfer(pair.address, 10_0000_0000 * 101 + 10000, {from: taker});
        let usdBalance = await usd.balanceOf.call(pair.address);
        console.log("usd balance of taker: ", usdBalance.toNumber());
        await pair.addLimitOrder(true, taker, 10_0000_0000, makePrice32(10100000, 18), 1, merge3(0, 0, 0), {from: taker});
        usdBalance = await usd.balanceOf.call(pair.address);
        console.log("usd balance of taker: ", usdBalance.toNumber());
        let result = await pair.getReserves.call();
        //function getReserves() public override view returns (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) {
        console.log("current price: ", result[1] / result[0]);
        console.log("firstSellID: ", result[2].toNumber());
        console.log("pooled usd: ", result[1].toNumber());
        console.log("pooled usd: ", result[0].toNumber());
        let booked = await pair.getBooked.call();
        console.log("booked usd: ", booked.bookedMoney.toNumber());
        console.log("booked btc: ", booked.bookedStock.toNumber());
        let balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 9_9700_0000);
    });

    //use a little usd buy a lot of btc, deal with pool first
    it("insert big buy order to hao yang mao", async () => {
        await usd.transfer(pair.address, 10_0000, {from: taker});
        let balance = await btc.balanceOf.call(taker);
        let booked = await pair.getBooked.call();
        console.log("booked usd: ", booked.bookedMoney.toNumber());
        await pair.addMarketOrder(usd.address, taker, 10_0000, {from: taker});
        let balanceAfter = await btc.balanceOf.call(taker);
        let diff = balanceAfter - balance;
        assert.equal(diff, 2492376);
        let result = await pair.getReserves.call();
        //function getReserves() public override view returns (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) {
        console.log("current price: ", result[1] / result[0]);
        console.log("firstSellID: ", result[2].toNumber());
        booked = await pair.getBooked.call();
        console.log("booked usd: ", booked.bookedMoney.toNumber());
        console.log("firstBuyID", booked.firstBuyID.toNumber());
    });

    //deal with buy order first which price is higher than current price
    it("insert sell order", async () => {
        await btc.transfer(pair.address, 100, {from: maker});
        let balance = await usd.balanceOf.call(taker);
        let booked = await pair.getBooked.call();
        console.log("booked usd: ", booked.bookedMoney.toNumber())
        await pair.addMarketOrder(btc.address, taker, 100, {from: taker});
        let balanceAfter = await usd.balanceOf.call(taker);
        let diff = balanceAfter - balance;
        assert.equal(diff, 106);
        let result = await pair.getReserves.call();
        //function getReserves() public override view returns (uint112 reserveStock, uint112 reserveMoney, uint32 firstSellID) {
        console.log("current price: ", result[1] / result[0]);
        console.log("firstSellID: ", result[2].toNumber());
        booked = await pair.getBooked.call();
        console.log("booked usd: ", booked.bookedMoney.toNumber());
        console.log("firstBuyID", booked.firstBuyID.toNumber());
    });
});

contract("deal with pool", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
    });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint only 1000 shares", async () => {
        await btc.approve(boss, 1000000000, {from: lp});
        await usd.approve(boss, 1000000000, {from: lp});
        await btc.transferFrom(lp, pair.address, 10000, {from: boss});
        await usd.transferFrom(lp, pair.address, 1000000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        await pair.transfer(pair.address, balance, {from: shareReceiver});
        await pair.burn(shareReceiver);
        balance = await pair.balanceOf.call(shareReceiver);
        console.log("balance: ", balance.toNumber());
        balance = await pair.balanceOf.call(ZERO_ADDR);
        console.log("balance: ", balance.toNumber());
    });

    it("insert buy order which can not be dealt", async ()=>{
        let reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        await usd.approve(maker,10000,{from:boss})
        await usd.transferFrom(boss, pair.address, 10000, {from: maker});
        await pair.addLimitOrder(true, maker, 100, makePrice32(1000_0000, 18), 1, merge3(0, 0, 0), {from: maker});

        reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });

    it("insert sell order which can deal totally", async ()=>{

        await btc.approve(taker,10,{from:boss})
        await btc.transferFrom(boss, pair.address, 10, {from: taker});
        await pair.addLimitOrder(false, maker, 10, makePrice32(9000_0000, 17), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    })

    it("insert sell order which eats all buy order", async ()=>{
        await btc.approve(taker,90,{from:boss})
        await btc.transferFrom(boss, pair.address, 90, {from: taker});
        await pair.addLimitOrder(false, maker, 90, makePrice32(1000_0000, 18), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())
        assert.equal(reserves.reserveStock.toNumber(),100)
        assert.equal(reserves.reserveMoney.toNumber(),10030)

        let booked = await pair.getBooked.call();
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    })


    // pool is updated while
    it("insert buy order which can not be dealt", async ()=>{
        let reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        await usd.approve(maker,1010,{from:boss})
        await usd.transferFrom(boss, pair.address, 1010, {from: maker});
        let result = await pair.addLimitOrder(true, maker, 10, makePrice32(1010_0000, 18), 1, merge3(0, 0, 0), {from: maker});
        //for(let i=0; i < result.logs.length; i++) {
        //    console.log("----===log ", i, result.logs[i].event, result.logs[i].args);
        //}
        console.log(result.logs)
        let amounts = dealAmountFromEventDealWithPool(result.logs[1].args.data)
        console.log(amounts[0],amounts[1])
        amounts = stockAmountFromEventNewLimitOrder(result.logs[0].args.data)
        console.log(amounts[0],amounts[1])
        amounts = syncAmountFromEventSync(result.logs[3].args.reserveStockAndMoney)
        console.log(amounts[0],amounts[1])
        reserves = await pair.getReserves.call();
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())
        assert.equal(reserves.reserveStock.toNumber(),100)
        assert.equal(reserves.reserveMoney.toNumber(),10131)
        let booked = await pair.getBooked.call();
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });
});

contract("deal after donate and sync", async (accounts) => {
    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss);
    });

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint only 1000 shares", async () => {
        await btc.approve(boss, 1000000000, {from: lp});
        await usd.approve(boss, 1000000000, {from: lp});
        await btc.transferFrom(lp, pair.address, 10000, {from: boss});
        await usd.transferFrom(lp, pair.address, 1000000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        assert.equal(balance.toNumber(), 99000, "share balance incorrect");
    });

    //should not deal with pool
    it("deal with pool", async () => {
        await usd.transfer(taker, 100000, {from: boss});
        await usd.transfer(pair.address, 100000, {from: taker});
        await pair.addMarketOrder(usd.address, taker, 100000, {from: taker});
        let balance = await btc.balanceOf.call(taker);
        assert.equal(balance.toNumber(), 907);
    });
});

contract("pair with weth token", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with weth/usd", async () => {
        await initializeTokenWithWETH(boss);
    });

    it("initialize balances", async () => {
        await initializeBalanceWithETH(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint only 1000 shares", async () => {

        await weth.deposit({value:10000,from:lp});
        await weth.transfer(pair.address,10000,{from:lp})
        await usd.approve(boss, 1000000000, {from: lp});
        await usd.transferFrom(lp, pair.address, 100_0000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        console.log("balance: ", balance.toNumber());
        balance = await pair.balanceOf.call(ZERO_ADDR);
        console.log("balance: ", balance.toNumber());
    });

    it("insert buy order which can not be dealt", async ()=>{
        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0000,"reserve money amount is not correct")

        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        await usd.approve(maker,10000,{from:boss})
        await usd.transferFrom(boss, pair.address, 10000, {from: maker});
        await pair.addLimitOrder(true, maker, 100, makePrice32(1000_0000, 18), 1, merge3(0, 0, 0), {from: maker});

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)

        reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0000,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),10000,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });

    it("insert sell order which can deal totally", async ()=>{

        await weth.deposit({from:taker,value:100})
        await weth.transfer(pair.address, 100, {from: taker});

        await pair.addLimitOrder(false, taker, 10, makePrice32(9000_0000, 17), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10090,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0003,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),9000,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)
    })

    it("insert sell order which eats up buy order", async ()=>{

        await weth.deposit({from:taker,value:90})
        await weth.transfer(pair.address, 90, {from: taker});

        await pair.addLimitOrder(false, taker, 90, makePrice32(9000_0000, 17), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10090,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0030,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)

    })

    it("addMarketOrder to buy eth", async ()=>{

       await usd.approve(maker,10000,{from:boss})
       await usd.transferFrom(boss, pair.address, 10000, {from: maker});

       let balance = await web3.eth.getBalance(maker)
       console.log(balance)

       await pair.addMarketOrder(usd.address,maker,10000, {from: maker});

       let new_balance = await web3.eth.getBalance(maker)
       console.log(new_balance)

       let reserves = await pair.getReserves.call();
       assert.equal(reserves.reserveStock.toNumber(),9991,"reserve stock amount is not correct")
       assert.equal(reserves.reserveMoney.toNumber(),101_0030,"reserve money amount is not correct")
       console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
       console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

       let booked = await pair.getBooked.call();
       assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
       assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
       console.log("booked stock amount: ", booked.bookedStock.toNumber())
       console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });

    it("addMarketOrder to sell eth", async ()=>{

       await weth.deposit({from:taker,value:99})
       await weth.transfer(pair.address, 99, {from: taker});

       let balance = await usd.balanceOf(taker)
       console.log(balance)

       await pair.addMarketOrder(weth.address,taker,99, {from: taker});

       let new_balance = await web3.eth.getBalance(maker)
       console.log(new_balance)

       let reserves = await pair.getReserves.call();
       assert.equal(reserves.reserveStock.toNumber(),10090,"reserve stock amount is not correct")
       assert.equal(reserves.reserveMoney.toNumber(),1000149,"reserve money amount is not correct")
       console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
       console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

       let booked = await pair.getBooked.call();
       assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
       assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
       console.log("booked stock amount: ", booked.bookedStock.toNumber())
       console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });
});

contract("pair with eth token", async (accounts) => {

    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[5];

    it("initialize pair with eth/usd", async () => {
        await initializeTokenWithETH(boss);
    });

    it("initialize balances", async () => {
        await initializeBalanceWithETH(boss, lp, maker, taker);
    });

    const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
    it("mint", async () => {
        let eth_balance = web3.eth.getBalance(pair.address);
        console.log(eth_balance);
        await web3.eth.sendTransaction({from:lp,to:pair.address,value:10000});
        eth_balance = web3.eth.getBalance(pair.address);
        console.log(eth_balance);

        await usd.approve(boss, 1000000000, {from: lp});
        await usd.transferFrom(lp, pair.address, 100_0000, {from: boss});
        await pair.mint(shareReceiver);
        let balance = await pair.balanceOf.call(shareReceiver);
        console.log("balance: ", balance.toNumber());
        balance = await pair.balanceOf.call(ZERO_ADDR);
        console.log("balance: ", balance.toNumber());
    });

    it("insert buy order which can not be dealt", async ()=>{
        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0000,"reserve money amount is not correct")

        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        await usd.approve(maker,10000,{from:boss})
        await usd.transferFrom(boss, pair.address, 10000, {from: maker});
        await pair.addLimitOrder(true, maker, 100, makePrice32(1000_0000, 18), 1, merge3(0, 0, 0), {from: maker});

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)
        reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0000,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),10000,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });

    it("insert sell order which can deal totally", async ()=>{

        await web3.eth.sendTransaction({from:taker,to:pair.address,value:10});
        await pair.addLimitOrder(false, taker, 10, makePrice32(9000_0000, 17), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0003,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),9000,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)
    })

    it("insert sell order which eats up buy order", async ()=>{

        await web3.eth.sendTransaction({from:taker,to:pair.address,value:90});
        await pair.addLimitOrder(false, taker, 90, makePrice32(9000_0000, 17), 1, merge3(0, 0, 0), {from: taker});

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),100_0030,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)

    })

    it("addMarketOrder to buy eth", async ()=>{

        await usd.approve(maker,10000,{from:boss})
        await usd.transferFrom(boss, pair.address, 10000, {from: maker});

        let balance = await web3.eth.getBalance(maker)
        console.log(balance)

        await pair.addMarketOrder(usd.address,maker,10000, {from: maker});

        let new_balance = await web3.eth.getBalance(maker)
        console.log(new_balance)

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),9901,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),101_0030,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });

    it("addMarketOrder to sell eth", async ()=>{

        let balance = await web3.eth.getBalance(taker)
        console.log(balance)
        await web3.eth.sendTransaction({from:taker,to:pair.address,value:99});

        await pair.addMarketOrder(eth,taker,99, {from: taker});

        let new_balance = await web3.eth.getBalance(taker)
        console.log(new_balance)

        let reserves = await pair.getReserves.call();
        assert.equal(reserves.reserveStock.toNumber(),10000,"reserve stock amount is not correct")
        assert.equal(reserves.reserveMoney.toNumber(),1000060,"reserve money amount is not correct")
        console.log("reserve stock amount: ", reserves.reserveStock.toNumber())
        console.log("reserve money amount: ", reserves.reserveMoney.toNumber())

        let booked = await pair.getBooked.call();
        assert.equal(booked.bookedStock.toNumber(),0,"booked stock amount is not correct")
        assert.equal(booked.bookedMoney.toNumber(),0,"booked money amount is not correct")
        console.log("booked stock amount: ", booked.bookedStock.toNumber())
        console.log("booked money amount: ", booked.bookedMoney.toNumber())
    });
});

contract("OneSwapPair/addMarketOrder", async (accounts) => {

    const taker = accounts[2];
    const maker = accounts[3];
    const boss  = accounts[5];

    before(async () => {
        await initializeToken(boss);
        // assert.equal((await pair.totalSupply.call()), 0, "pair.totalSupply");
    });

    it('addMarketOrder failed: INVALID_TOKEN', async () => {
        await revert(pair.addMarketOrder(weth.address, taker, 10000000000, {from: taker}),
            "OneSwap: INVALID_TOKEN");
    });
    it('addMarketOrder failed: DEPOSIT_NOT_ENOUGH', async () => {
        await revert(pair.addMarketOrder(usd.address, taker, 10000000000, {from: taker}),
            "OneSwap: DEPOSIT_NOT_ENOUGH");
        await revert(pair.addMarketOrder(btc.address, taker, 20000000000, {from: taker}),
            "OneSwap: DEPOSIT_NOT_ENOUGH");
    });

    it('addMarketOrder/buy: event', async () => {
        await usd.transfer(pair.address, 10000000000, {from: boss});
        const result = await pair.addMarketOrder(usd.address, taker, 10000000000, {from: taker});
        assert.deepEqual(getLog(result, "NewMarketOrder", decodeNewMarketOrderLog), {
            isBuy:   true,
            amount:  10000000000n,
            addrLow: BigInt(taker) & 0xffffffffffffffffffffffffffffffffffn,
        });
    });
    it('addMarketOrder/sell: event', async () => {
        await btc.transfer(pair.address, 20000000000, {from: boss});
        const result = await pair.addMarketOrder(btc.address, taker, 20000000000, {from: taker});
        assert.deepEqual(getLog(result, "NewMarketOrder", decodeNewMarketOrderLog), {
            isBuy:   false,
            amount:  20000000000n,
            addrLow: BigInt(taker) & 0xffffffffffffffffffffffffffffffffffn,
        });
    });

});

contract("OneSwapPair/addMarketOrder/emptyAMM", async (accounts) => {

    const taker = accounts[2];
    const maker = accounts[3];
    const boss  = accounts[5];

    beforeEach(async () => {
        await initializeToken(boss);
        assert.equal((await pair.totalSupply.call()), 0, "pair.totalSupply");
    });

    it('addMarketOrder/buy: deal with empty AMM pool', async () => {
        assert.equal((await btc.balanceOf(taker)), 0, "taker.btc");
        assert.equal((await usd.balanceOf(taker)), 0, "taker.usd");

        await usd.transfer(pair.address, 10000000000, {from: boss});
        await pair.addMarketOrder(usd.address, taker, 10000000000, {from: taker});

        assert.equal(await getFirstOrderID(pair, BUY), 0);
        assert.equal(await getFirstOrderID(pair, SELL), 0);
        assert.equal((await btc.balanceOf(taker)), 0, "taker.btc");
        assert.equal((await usd.balanceOf(taker)), 0, "taker.usd");
    });
    it('addMarketOrder/sell: deal with empty AMM pool', async () => {
        assert.equal((await btc.balanceOf(taker)), 0, "taker.btc");
        assert.equal((await usd.balanceOf(taker)), 0, "taker.usd");

        await btc.transfer(pair.address, 20000000000, {from: boss});
        await pair.addMarketOrder(btc.address, taker, 20000000000, {from: taker});

        assert.equal(await getFirstOrderID(pair, BUY), 0);
        assert.equal(await getFirstOrderID(pair, SELL), 0);
        assert.equal((await btc.balanceOf(taker)), 0, "taker.btc");
        assert.equal((await usd.balanceOf(taker)), 0, "taker.usd");
    });

});

contract("OneSwapPair/addMarketOrder/eat", async (accounts) => {

    const owner = accounts[0];
    const lp    = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const boss  = accounts[5];

    before(async () => {
        await initializeToken(boss);
        assert.equal((await pair.totalSupply.call()), 0, "pair.totalSupply");
        await btc.transfer(pair.address, 100, {from: boss});
        await usd.transfer(pair.address, 4000000, {from: boss});
        await pair.mint(lp);
        assert.equal(await pair.totalSupply.call(), 20000);
    });

    it('buy eat sell', async () => {
        await btc.transfer(pair.address, 100, {from: boss});
        let result = await pair.addLimitOrder(SELL, maker, 100, makePrice32(50000000, 23), 1, merge3(0, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 1n, isBuy: false,
            price: makePrice32Big(50000000, 23),
            remainedStockAmount: 100n,
            totalStockAmount: 100n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });
        await btc.transfer(pair.address, 200, {from: boss});
        result = await pair.addLimitOrder(SELL, maker, 200, makePrice32(60000000, 23), 2, merge3(1, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 2n, isBuy: false,
            price: makePrice32Big(60000000, 23),
            remainedStockAmount: 200n,
            totalStockAmount: 200n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });
        await btc.transfer(pair.address, 300, {from: boss});
        result = await pair.addLimitOrder(SELL, maker, 300, makePrice32(70000000, 23), 3, merge3(2, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 3n, isBuy: false,
            price: makePrice32Big(70000000, 23),
            remainedStockAmount: 300n,
            totalStockAmount: 300n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });

        // assert.deepEqual(await getOrdersByID(pair, SELL, [1, 2, 3]), []);
        assert.deepEqual(await getAllOrders(pair, SELL), [
            {
                id: 1n, nextID: 2n, amount: 100n,
                price: makePrice32Big(50000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 2n, nextID: 3n, amount: 200n,
                price: makePrice32Big(60000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 3n, nextID: 0n, amount: 300n,
                price: makePrice32Big(70000000, 23),
                sender: BigInt(maker),
            },
        ]);

        await usd.transfer(pair.address, 500000000, {from: boss});
        result = await pair.addMarketOrder(usd.address, taker, 500000000, {from: taker});
        assert.deepEqual(getLog(result, "NewMarketOrder", decodeNewMarketOrderLog), {
            isBuy:   true,
            amount:  500000000n,
            addrLow: BigInt(taker) & 0xffffffffffffffffffffffffffffffffffn,
        });
        assert.deepEqual(await getAllOrders(pair, SELL), [
            {
                id: 1n, nextID: 2n, amount: 93n,
                price: makePrice32Big(50000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 2n, nextID: 3n, amount: 200n,
                price: makePrice32Big(60000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 3n, nextID: 0n, amount: 300n,
                price: makePrice32Big(70000000, 23),
                sender: BigInt(maker),
            },
        ]);

        // test removeOrders
        await pair.removeOrders([(1 << 8) | SELL, (2 << 8) | SELL], {from: maker});
        assert.deepEqual(await getAllOrders(pair, SELL), [
            {
                id: 3n, nextID: 0n, amount: 300n,
                price: makePrice32Big(70000000, 23),
                sender: BigInt(maker),
            },
        ]);
    });

    it('sell eat buy', async () => {
        await usd.transfer(pair.address, 30000000*300, {from: boss});
        let result = await pair.addLimitOrder(BUY, maker, 300, makePrice32(30000000, 23), 1, merge3(0, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 1n, isBuy: true,
            price: makePrice32Big(30000000, 23),
            remainedStockAmount: 300n,
            totalStockAmount: 300n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });
        await usd.transfer(pair.address, 20000000*200, {from: boss});
        result = await pair.addLimitOrder(BUY, maker, 200, makePrice32(20000000, 23), 1, merge3(0, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 2n, isBuy: true,
            price: makePrice32Big(20000000, 23),
            remainedStockAmount: 200n,
            totalStockAmount: 200n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });
        await usd.transfer(pair.address, 10000000*100, {from: boss});
        result = await pair.addLimitOrder(BUY, maker, 100, makePrice32(10000000, 23), 1, merge3(0, 0, 0), {from: maker});
        assert.deepEqual(getLog(result, "NewLimitOrder", decodeNewLimitOrderLog), {
            orderID: 3n, isBuy: true,
            price: makePrice32Big(10000000, 23),
            remainedStockAmount: 100n,
            totalStockAmount: 100n,
            addrLow: BigInt(maker) & 0xffffffffffffffffn,
        });

        assert.deepEqual(await getAllOrders(pair, BUY), [
            {
                id: 1n, nextID: 2n, amount: 300n,
                price: makePrice32Big(30000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 2n, nextID: 3n, amount: 200n,
                price: makePrice32Big(20000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 3n, nextID: 0n, amount: 100n,
                price: makePrice32Big(10000000, 23),
                sender: BigInt(maker),
            },
        ]);

        await btc.transfer(pair.address, 20, {from: boss});
        result = await pair.addMarketOrder(btc.address, taker, 20, {from: taker});
        assert.deepEqual(getLog(result, "NewMarketOrder", decodeNewMarketOrderLog), {
            isBuy:   false,
            amount:  20n,
            addrLow: BigInt(taker) & 0xffffffffffffffffffffffffffffffffffn,
        });
        assert.deepEqual(await getAllOrders(pair, BUY), [
            {
                id: 1n, nextID: 2n, amount: 280n,
                price: makePrice32Big(30000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 2n, nextID: 3n, amount: 200n,
                price: makePrice32Big(20000000, 23),
                sender: BigInt(maker),
            },
            {
                id: 3n, nextID: 0n, amount: 100n,
                price: makePrice32Big(10000000, 23),
                sender: BigInt(maker),
            },
        ]);

        // test removeOrders
        await pair.removeOrders([(1 << 8) | BUY, (2 << 8) | BUY], {from: maker});
        assert.deepEqual(await getAllOrders(pair, BUY), [
            {
                id: 3n, nextID: 0n, amount: 100n,
                price: makePrice32Big(10000000, 23),
                sender: BigInt(maker),
            },
        ]);
    });

});

function getLog(result, eventType, decoder) {
    const log = result.logs.find(log => log.event == eventType);
    assert.isNotNull(log, "log not found: " + eventType);
    return decoder(log);
}
// [addrLow][amount][isBuy]
//   136      112      8
function decodeNewMarketOrderLog(log) {
    const data = BigInt(log.args.data);
    return {
        isBuy  : (data & 0xffn) > 0n,
        amount : (data >> 8n) & 0xffffffffffffffffffffffffffffn,
        addrLow:  data >> 120n,
    }
}
// [addrLow][totalStockAmount][remainedStockAmount][price][orderID][isBuy]
//    64             64                   64          32      24      8
function decodeNewLimitOrderLog(log) {
    const data = BigInt(log.args.data);
    return {
        isBuy              : (data & 0xffn) > 0n,
        orderID            : (data >>   8n) & 0xffffffn,
        price              : (data >>  32n) & 0xffffffffn,
        remainedStockAmount: (data >>  64n) & 0xffffffffffffffffn,
        totalStockAmount   : (data >> 128n) & 0xffffffffffffffffn,
        addrLow            :  data >> 192n,
    }
}

async function getFirstOrderID(pair, isBuy) {
    if (isBuy) {
        const booked = await pair.getBooked.call();
        return booked.firstBuyID;
    } else {
        const reserves = await pair.getReserves.call();
        return reserves.firstSellID;
    }
}
async function getAllOrders(pair, isBuy) {
    // let firstID = await getFirstOrderID(pair, isBuy);
    let orders = await pair.getOrderList(isBuy, 0, 10000);
    orders = orders.map(uint2order);
    if (orders.length > 1) {
        for (let i = 1; i < orders.length; i++) {
            orders[i].id = orders[i - 1].nextID;
        }
        return orders.slice(1);
    }
    return [];
}
async function getOrdersByID(pair, isBuy, ids) {
    return Promise.all(ids.map(id => getOrderByID(pair, isBuy, id)));
}
async function getOrderByID(pair, isBuy, id) {
    const orders = await pair.getOrderList(isBuy, id, 1);
    assert.lengthOf(orders, 1, "order not found, id=" + id);
    return uint2order(orders[0]);
}

// [sender][price][amount][nextID]
//   160     32      42      22
function uint2order(n) {
    n = BigInt(n.toString());
    return {
        nextID:  n         & 0x3fffffn,
        amount: (n >> 22n) & 0x3ffffffffffn,
        price : (n >> 64n) & 0xffffffffn,
        sender:  n >> 96n,
    };
}
