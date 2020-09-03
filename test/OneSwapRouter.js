const OneswapFactory = artifacts.require("OneSwapFactory")
const TokenComplexContract = artifacts.require("OneSwapToken")
const TokenSimpleERC20Contract = artifacts.require("DSToken")
const Router = artifacts.require('OneSwapRouter')
const Impl = artifacts.require("OneSwapPair")

const revert = require("./exceptions.js").revert;
const Decimal = 1000000000000000000
const ZeroAddr = "0x0000000000000000000000000000000000000000"


async function deployContracts(accounts) {
	impl = await Impl.new()
    stock = await TokenSimpleERC20Contract.new("abc", "abc", BigInt( 100000000 * Decimal).toString(), 18)
    money = await TokenSimpleERC20Contract.new("def", "def", BigInt(100000000 * Decimal).toString(), 18)
    factory = await OneswapFactory.new(accounts[0], accounts[1], accounts[9], impl.address)
    router = await Router.new(factory.address)
    console.log('router addr: ' + router.address)
}

contract('Router', async accounts => {
    before(async () => {
        await deployContracts(accounts)
    })

    it('QueryTokenBalance', async () =>{
        const stockAmount = await stock.balanceOf.call(accounts[0])
        const moneyAmount = await money.balanceOf.call(accounts[0])
        assert.equal(stockAmount.toString(), BigInt( 100000000 * Decimal).toString(), 'Invalid balance in erc20 token')
        assert.equal(moneyAmount.toString(), BigInt( 100000000 * Decimal).toString(), 'Invalid balance in erc20 token')
    })
    it('Approve token to router', async () =>{
        await stock.approve(router.address, BigInt( 100000000 * Decimal).toString())
        await money.approve(router.address, BigInt( 100000000 * Decimal).toString())
    })
    it('AddLiquidity', async () =>{
        let result = await router.addLiquidity(stock.address, money.address, false, 100000, 10000, 100000, 10000, accounts[2], 9999999999)
        assert.equal(result.logs[1].args.stockAmount, 100000, 'stock amount should be equal')
        assert.equal(result.logs[1].args.moneyAmount, 10000, 'money amount should be equal')
        console.log("create erc20 pair and add liquidity : ", result.receipt.gasUsed)

        pairWithTokens = await factory.tokensToPair(stock.address, money.address, false)
        console.log('pairWithTokens addr : ' + pairWithTokens)
        let pairContract = await Impl.at(pairWithTokens)
        let liquidity = await pairContract.balanceOf.call(accounts[2])
        console.log('liquidity in pair: ' + liquidity.toNumber())
        assert.equal(result.logs[1].args.liquidity.toNumber(), liquidity, 'Liquidity should be equal')

        result = await router.addLiquidity(stock.address, money.address, false, 100000, 10000, 100000, 10000, accounts[2], 9999999999)
        console.log("only add liquidity in erc20 pair: ", result.receipt.gasUsed)

        await revert(router.addLiquidity(stock.address, money.address, false, 100000, 10000, 100000, 10000, accounts[2], 1),
            'OneSwapRouter: EXPIRED')
        await revert(router.addLiquidity(stock.address, money.address, false, 100000, 10000, 100000, 100000, accounts[2], 9999999999),
            'OneSwapRouter: INSUFFICIENT_MONEY_AMOUNT')
        await revert(router.addLiquidity(stock.address, money.address, false, 100000, 1000, 200000, 10000, accounts[2], 9999999999),
            'OneSwapRouter: INSUFFICIENT_STOCK_AMOUNT')

        result = await router.addLiquidity(stock.address, ZeroAddr, false, 100000, 10000, 100000, 10000, accounts[2], 9999999999, {value:10000})
        assert.equal(result.logs[1].args.stockAmount, 100000, 'stock amount should be equal')
        assert.equal(result.logs[1].args.moneyAmount, 10000, 'money amount should be equal')
        console.log("create eth pair and add liquidity : ", result.receipt.gasUsed)

        pairWithETH = await factory.tokensToPair(stock.address, ZeroAddr, false)
        console.log('pairWithETH addr : ' + pairWithETH)
        pairContract = await Impl.at(pairWithETH)
        liquidity = await pairContract.balanceOf.call(accounts[2])
        console.log('liquidity in pair: ' + liquidity.toNumber())
        assert.equal(result.logs[1].args.liquidity.toNumber(), liquidity, 'Liquidity should be equal')

        result = await router.addLiquidity(stock.address, ZeroAddr, false, 100000, 10000, 100000, 10000, accounts[2], 9999999999, {value:10000})
        console.log("only add liquidity in eth pair: ", result.receipt.gasUsed)
    })
    it('RemoveLiquidity With Tokens', async () =>{
        let pairContract = await Impl.at(pairWithTokens)
        await pairContract.approve(router.address, 1000, {from: accounts[2]})
        await revert(router.removeLiquidity(pairWithTokens, 1000, 1000, 100, accounts[0], 1, {from: accounts[2]}),
            'OneSwapRouter: EXPIRED')
        await revert(router.removeLiquidity(pairWithTokens, 1000, 100000, 100, accounts[0], 9999999999, {from: accounts[2]}),
            'OneSwapRouter: INSUFFICIENT_STOCK_AMOUNT')
        await revert(router.removeLiquidity(pairWithTokens, 1000, 10, 10000, accounts[0], 9999999999, {from: accounts[2]}),
            'OneSwapRouter: INSUFFICIENT_MONEY_AMOUNT')

        let beforeStockAmount = await stock.balanceOf.call(accounts[0])
        let beforeMoneyAmount = await money.balanceOf.call(accounts[0])
        let result = await router.removeLiquidity(pairWithTokens, 1000, 10, 10, accounts[0], 9999999999, {from: accounts[2]})
        let afterStockAmount = await stock.balanceOf.call(accounts[0])
        let afterMoneyAmount = await money.balanceOf.call(accounts[0])
        assert.ok(beforeStockAmount < afterStockAmount, 'RemoveLiquidity should add stock amount')
        assert.ok(beforeMoneyAmount < afterMoneyAmount, 'RemoveLiquidity should add money amount')
        console.log("remove liquidity in erc20 pair : ", result.receipt.gasUsed)

        pairContract = await Impl.at(pairWithETH)
        await pairContract.approve(router.address, 1000, {from: accounts[2]})
        beforeStockAmount = await stock.balanceOf.call(accounts[0])
        beforeMoneyAmount = await web3.eth.getBalance(accounts[0])
        result = await router.removeLiquidity(pairWithETH, 1000, 10, 10, accounts[0], 9999999999, {from: accounts[2]})
        afterStockAmount = await stock.balanceOf.call(accounts[0])
        afterMoneyAmount = await web3.eth.getBalance(accounts[0])
        assert.ok(beforeStockAmount < afterStockAmount, 'RemoveLiquidity should add stock amount')
        assert.ok(beforeMoneyAmount < afterMoneyAmount, 'RemoveLiquidity should add money amount')
        console.log("remove liquidity in eth pair : ", result.receipt.gasUsed)
    })
    it('SwapTokens in basic check', async () =>{
        await revert(router.swapToken(stock.address, 1000, 80,  [pairWithTokens.toString(), pairWithETH.toString()], accounts[2], 1),
            'OneSwapRouter: EXPIRED')
        await revert(router.swapToken(stock.address, 1000, 80, [], accounts[2], 9999999999),
            'OneSwapRouter: INVALID_PATH')
    })
    async function prepareToSwap () {
        let token1 = await TokenSimpleERC20Contract.new("abc", "abc", 1000000000, 18)
        let token2 = await TokenSimpleERC20Contract.new("def", "def", 1000000000, 18)
        let token3 = await TokenSimpleERC20Contract.new("qwe", "qwe", 1000000000, 18)
        let token4 = await TokenSimpleERC20Contract.new("wer", "wer", 1000000000, 18)

        const token1Amount = await token1.balanceOf.call(accounts[0])
        const token2Amount = await token2.balanceOf.call(accounts[0])
        const token3Amount = await token3.balanceOf.call(accounts[0])
        const token4Amount = await token4.balanceOf.call(accounts[0])
        assert.equal(token1Amount, 1000000000, 'balance mismatch in token contract')
        assert.equal(token2Amount, 1000000000, 'balance mismatch in token contract')
        assert.equal(token3Amount, 1000000000, 'balance mismatch in token contract')
        assert.equal(token4Amount, 1000000000, 'balance mismatch in token contract')

        await token1.approve(router.address, 1000000000)
        await token2.approve(router.address, 1000000000)
        await token3.approve(router.address, 1000000000)
        await token4.approve(router.address, 1000000000)

        let result1 = await router.addLiquidity(token1.address, token2.address, false, 10000000, 1000000, 10000000, 1000000, accounts[2], 9999999999)
        let result2 = await router.addLiquidity(token2.address, token3.address, false, 1000000, 100000, 1000000, 100000, accounts[2], 9999999999)
        let result3 = await router.addLiquidity(token3.address, token4.address, false, 100000, 10000, 100000, 10000, accounts[2], 9999999999)
        let result4 = await router.addLiquidity(ZeroAddr, token4.address, false, 10000000, 1000000, 10000000, 1000000, accounts[2], 9999999999, {value: 10000000})
        let result5 = await router.addLiquidity(token3.address, ZeroAddr, false, 10000000, 1000000, 10000000, 1000000, accounts[2], 9999999999, {value: 10000000})

        let pair1 = result1.logs[0].args.pair;
        let pair2 = result2.logs[0].args.pair;
        let pair3 = result3.logs[0].args.pair;
        let pair4 = result4.logs[0].args.pair;
        let pair5 = result5.logs[0].args.pair;

        return [token1.address, token3.address, token4.address, pair1, pair2, pair3, pair4, pair5]
    }
    it('SwapToken', async () =>{
        let beforeAmount = await money.balanceOf(accounts[2])
        let result = await router.swapToken(stock.address, 1000, 60, [pairWithTokens.toString()], accounts[2], 9999999999)
        let afterAmount = await money.balanceOf(accounts[2])
        assert.ok(afterAmount - beforeAmount >= 60, 'SwapToken get token amount less the expected minAmount')
        console.log('swap erc20 pair once gas used : ' + result.receipt.gasUsed)

        let tokensAndPairsAddr = await prepareToSwap()

        // token1 --> token2 --> token3 --> token4
        // 10 : 1 : 0.1 : 0.01 ==> token1 : token4 = 1000 : 1
        let tokenContract = await TokenSimpleERC20Contract.at(tokensAndPairsAddr[2])
        beforeAmount = await tokenContract.balanceOf(accounts[2])
        result = await router.swapToken(tokensAndPairsAddr[0], 1000000, 700, [tokensAndPairsAddr[3].toString(),
            tokensAndPairsAddr[4].toString(), tokensAndPairsAddr[5].toString()], accounts[2], 9999999999)
        afterAmount =  await tokenContract.balanceOf(accounts[2])
        assert.ok(afterAmount - beforeAmount >= 700, 'SwapToken get token amount less the expected minAmount')
        console.log('swap erc20 pair fourth gas used : ' + result.receipt.gasUsed)

        // token3 --> eth --> token4
        // 10 : 1 : 0.1 ===> token3 : token4 = 100 : 1
        beforeAmount = await tokenContract.balanceOf(accounts[2])
        result = await router.swapToken(tokensAndPairsAddr[1], 1000000, 8000,
            [tokensAndPairsAddr[7].toString(), tokensAndPairsAddr[6].toString()], accounts[2], 9999999999)
        afterAmount =  await tokenContract.balanceOf(accounts[2])
        assert.ok(afterAmount - beforeAmount >= 8000, 'SwapToken get token amount less the expected minAmount')
        console.log('swap erc20 pair three gas used with one eth : ' + result.receipt.gasUsed)

        result = await router.swapToken(ZeroAddr, 10000, 60, [tokensAndPairsAddr[6].toString()], accounts[2], 9999999999, {from: accounts[0], value: 10000});
        console.log('swap eth pair once gas used : ' + result.receipt.gasUsed)
    })
    it('AddLimitOrder With Liquidity Pool', async () =>{
        await revert(router.limitOrder(true, pairWithTokens, 1, 80, 4, 2836, 1),
            'OneSwapRouter: EXPIRED')
        await revert(router.limitOrder(true, accounts[4], 1, 80, 4, 2836, 9999999999),
            'OneSwapRouter: PAIR_NOT_EXIST')

        let result1 = await router.limitOrder(true, pairWithTokens, 0, 20000000, 1, 10, 9999999999)
        let result2 = await router.limitOrder(true, pairWithTokens, 0, 21000000, 2, 10, 9999999999)
        let result3 = await router.limitOrder(true, pairWithTokens, 0, 22000000, 3, 10, 9999999999)
        let result4 = await router.limitOrder(true, pairWithETH, 0, 22000000, 3, 10, 9999999999, {value: 0.066 * (10 ** 18)})
        console.log("addLimitOrder first order gasUsed with pool: ", result1.receipt.gasUsed)
        console.log("addLimitOrder two order gasUsed with pool: ", result2.receipt.gasUsed)
        console.log("addLimitOrder three order gasUsed with pool: ", result3.receipt.gasUsed)
        console.log("addLimitOrder four order gasUsed with pool: ", result4.receipt.gasUsed)
    })
    it('AddLimitOrder With Only OrderBook', async () => {
        let token1 = await TokenSimpleERC20Contract.new("abc", "abc", BigInt(7000000000000000000).toString(), 18)
        await token1.approve(router.address, BigInt(7000000000000000000).toString())
        let result = await router.addLiquidity(token1.address, ZeroAddr,
            false, 1100, 1100, 1100, 1100, accounts[2], 9999999999,{value: 1100})
        let pair = result.logs[0].args.pair;
        let pairContract = await Impl.at(pair)

        let result1 = await router.limitOrder(true, pair, 0, 2025611598, 1, 10000, 9999999999, {from: accounts[2], value: 0.12345678 * (10 ** 18)})
        let result2 = await router.limitOrder(true, pair, 0, 2025611599, 2, 20000, 9999999999, {from: accounts[2], value: 2 * 0.12345679 * (10 ** 18)})
        let result3 = await router.limitOrder(true, pair, 0, 2025611600, 3, 30000, 9999999999, {from: accounts[2], value: 3 * 0.1234568 * (10 ** 18)})
        console.log("addLimitOrder first order gasUsed : ", result1.receipt.gasUsed)
        console.log("addLimitOrder two order gasUsed : ", result2.receipt.gasUsed)
        console.log("addLimitOrder three order gasUsed : ", result3.receipt.gasUsed)
        let orders = await pairContract.getOrderList(true, 0, 10)
        assert.equal(3, orders.length - 1, 'should have three orders')

        let result4 = await router.limitOrder(false, pair, 0, 2025611598, 4, 60000, 9999999999)
        console.log("addLimitOrder four order gasUsed : ", result4.receipt.gasUsed)
        orders = await pairContract.getOrderList(true, 0, 10)
        assert.equal(0, orders.length - 1, 'should have zero orders')
        result = await pairContract.getBooked()
        assert.equal(result[0].toNumber(), 0, 'book stock amount is 0')
        assert.equal(result[1].toNumber(), 0, 'book money amount is 0')
    })
})

async function initializeToken(boss, accounts) {
    impl = await Impl.new()
    factory = await OneswapFactory.new(accounts[0], accounts[1], accounts[9], impl.address)
    btc = await TokenSimpleERC20Contract.new("btc", "btc", 100000000000000, 18, {from: boss})
    usd = await TokenSimpleERC20Contract.new("usd", "usd", BigInt((1000000 + 20000000) * 1000000000000000000).toString(), 18, {from: boss})
    console.log("stock address: ", btc.address)
    console.log("money address: ", usd.address)
    router = await Router.new(factory.address)

    let result = await factory.createPair(ZeroAddr, usd.address, false)
    let pairAddr = result.logs[0].args.pair;
    console.log("pairAddr: ", pairAddr)
    pair = await Impl.at(pairAddr)
}

async function initializeBalance(boss, lp, maker, taker) {
    await btc.transfer(lp, 10000, {from: boss})
    await btc.transfer(maker, 10000, {from: boss})
    let lpBalance = await btc.balanceOf.call(lp)
    let makerBalance = await btc.balanceOf.call(maker)
    assert.equal(lpBalance, 10000, "lp btc balance is not correct")
    assert.equal(makerBalance, 10000, "maker btc balance is not correct")

    await usd.transfer(lp, BigInt(1000000 * 1000000000000000000).toString(), {from: boss}) //1 million
    await usd.transfer(taker, BigInt(10000000 * 1000000000000000000).toString(), {from: boss})
    lpBalance = await usd.balanceOf.call(lp)
    let takerBalance = await usd.balanceOf.call(taker)
    assert.equal(lpBalance, BigInt(1000000 * 1000000000000000000), "lp usd balance is not correct")
    assert.equal(takerBalance, BigInt(10000000 * 1000000000000000000), "taker usd balance is not correct")
}

async function mint(btc, usd, lp, boss, pair, shareReceiver) {
    await btc.approve(boss, 1000000000, {from: lp})
    await usd.approve(boss, 1000000000, {from: lp})
    await web3.eth.sendTransaction(
        {from: boss, to: pair.address, value:10000})
    await btc.transferFrom(lp, pair.address, 10000, {from: boss})
    await usd.transferFrom(lp, pair.address, 1000000, {from: boss})
    let gas = await pair.mint.estimateGas(shareReceiver)
    console.log("estimate gas on mint: ", gas)
    let result = await pair.mint(shareReceiver)
    console.log("real gas on mint: ", result.receipt.gasUsed)
}

contract("Pair", async accounts => {
    const lp = accounts[1];
    const taker = accounts[2];
    const maker = accounts[3];
    const shareReceiver = accounts[4];
    const boss = accounts[0];

    it("initialize pair with btc/usd", async () => {
        await initializeToken(boss, accounts)
    })

    it("initialize balances", async () => {
        await initializeBalance(boss, lp, maker, taker)
    })

    it("mint", async () => {
        await mint(btc, usd, lp, boss, pair, shareReceiver)
        let balance = await pair.balanceOf.call(shareReceiver)
        assert.equal(balance, 99000, "share mint is not correct")
        let reserves = await pair.getReserves.call()
        console.log("reserves: ", reserves)
        assert.equal(reserves.reserveStock, 10000, "reserve stock is not correct")
        assert.equal(reserves.reserveMoney, 1000000, "reserve money is not correct")
        balance = await pair.balanceOf.call("0x0000000000000000000000000000000000000000")
        assert.equal(balance, 1000, "locked liquidity is not correct")
    })
    it('Approve', async () =>{
        await btc.approve(router.address, BigInt(1000000000 * Decimal).toString(), {from: maker})
        await usd.approve(router.address, BigInt(1000000000 * Decimal).toString(), {from: maker})
        await btc.approve(router.address, BigInt(1000000000 * Decimal).toString(), {from: taker})
        await usd.approve(router.address, BigInt(1000000000 * Decimal).toString(), {from: taker})
    })
    it('add order and remove order', async () => {
        let result = await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10300000, 14), 1, 100, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        console.log('add first sell order: ' + result.receipt.gasUsed)
        result = await router.limitOrder(false, pair.address, merge3(0, 1, 2), makePrice32(10300000, 14), 2, 100, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        console.log('add two sell order: ' + result.receipt.gasUsed)
        result = await router.limitOrder(false, pair.address, merge3(0, 2, 3), makePrice32(10300000, 14), 3, 100, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        console.log('add three sell order: ' + result.receipt.gasUsed)
        result = await router.limitOrder(false, pair.address, merge3(0, 3, 4), makePrice32(10300000, 14), 4, 100, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        console.log('add three sell order: ' + result.receipt.gasUsed)
        result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 4 + 1, 'Orders number should be 1')

        //function removeOrder(bool isBuy, uint32 id, uint72 prevKey) external override lock {
        result = await pair.removeOrder(false, 2, 1, {from: maker})
        console.log("gas on remove middle order: ", result.receipt.gasUsed)
        result = await pair.removeOrder(false, 4, 3, {from: maker})
        console.log("gas on remove end order: ", result.receipt.gasUsed)
        result = await pair.removeOrder(false, 1, 0, {from: maker})
        console.log("gas on remove begin order: ", result.receipt.gasUsed)
        result = await pair.removeOrder(false, 3, 0, {from: maker})
        console.log("gas on remove last order: ", result.receipt.gasUsed)

        result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 0 + 1, 'Orders number should be 0')
    })
    it("deal 3 sell orders, and remain buy amount", async () =>{
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10000000, 14), 2, 1, 999999999999, {from: maker, value: BigInt( 0.01 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10300000, 14), 3, 1, 999999999999, {from: maker, value: BigInt( 0.013 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(2, 0, 0), makePrice32(10500000, 14), 4, 1, 999999999999, {from: maker, value: BigInt(0.015 *Decimal).toString()})
        let result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 3 + 1, 'Orders number should be 3')

        result = await router.limitOrder(true, pair.address, merge3(0, 0, 0), makePrice32(10500000, 14), 1, 5, 999999999999, {from: taker})
        console.log("gas on deal 3 sell orders, but remain amount: ", result.receipt.gasUsed)

        // check order nums
        result = await pair.getOrderList.call(true, 0, 10)
        console.log("buy order nums: ", result.length -1)
        assert.equal(result.length, 1 + 1, 'buy orders nums should be 1')
        result = await pair.getOrderList.call(false, 0, 10)
        console.log("sell order nums: ", result.length -1)
        assert.equal(result.length, 0 + 1, 'sell orders nums should be 0')

        // remove buy order
        result = await pair.removeOrder(true, 1, 0, {from: taker})
        console.log("gas on remove order: ", result.receipt.gasUsed)
        result = await pair.getOrderList.call(true, 0, 10)
        assert.equal(result.length, 0 + 1, 'buy orders nums should be 0')
    })
    it("deal 3 sell orders, and null buy amount", async () =>{
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10000000, 14), 2, 1, 999999999999, {from: maker, value: BigInt( 0.01 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10300000, 14), 3, 1, 999999999999, {from: maker, value: BigInt( 0.013 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(2, 0, 0), makePrice32(10500000, 14), 4, 1, 999999999999, {from: maker, value: BigInt(0.015 *Decimal).toString()})
        let result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 3 + 1, 'Orders number should be 3')

        result = await router.limitOrder(true, pair.address, merge3(0, 0, 0), makePrice32(10500000, 14), 1, 3, 999999999999, {from: taker})
        console.log("gas on deal 3 sell orders and null buy amount: ", result.receipt.gasUsed)

        // check order nums
        result = await pair.getOrderList.call(true, 0, 10)
        assert.equal(result.length, 0 + 1, 'buy orders nums should be 0')
        result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 0 + 1, 'sell orders nums should be 0')
    })
    it("deal 7 sell orders, and remain buy amount", async () => {
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10000000, 14), 1, 1, 999999999999, {from: maker, value: BigInt(100 * 0.01 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(1, 0, 0), makePrice32(10300000, 14), 2, 1, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(2, 0, 0), makePrice32(10500000, 14), 3, 1, 999999999999, {from: maker, value: BigInt(100 * 0.015 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(3, 0, 0), makePrice32(10700000, 14), 4, 1, 999999999999, {from: maker, value: BigInt(100 * 0.017 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(4, 0, 0), makePrice32(10900000, 14), 5, 1, 999999999999, {from: maker, value: BigInt(100 * 0.019 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(5, 0, 0), makePrice32(10200000, 14), 6, 1, 999999999999, {from: maker, value: BigInt(0.012 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(6, 0, 0), makePrice32(10400000, 14), 7, 1, 999999999999, {from: maker, value: BigInt(0.014 *Decimal).toString()})
        let result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 7 + 1, 'Orders number should be 7')

        result = await router.limitOrder(true, pair.address, merge3(0, 0, 0), makePrice32(10900000, 14), 1, 8, 999999999999, {from: taker})
        console.log("gas on deal 7 sell orders, but remain amount: ", result.receipt.gasUsed)

        // check order nums
        result = await pair.getOrderList.call(true, 0, 10)
        console.log("buy order nums: ", result.length -1)
        assert.equal(result.length, 1 + 1, 'buy orders nums should be 1')
        result = await pair.getOrderList.call(false, 0, 10)
        console.log("sell order nums: ", result.length -1)
        assert.equal(result.length, 0 + 1, 'sell orders nums should be 0')

        // remove buy order
        result = await pair.removeOrder(true, 1, 0, {from: taker})
        console.log("gas on remove order: ", result.receipt.gasUsed)
        result = await pair.getOrderList.call(true, 0, 10)
        assert.equal(result.length, 0 + 1, 'buy orders nums should be 0')
    })
    it("deal 7 sell orders, and null buy amount", async () => {
        await router.limitOrder(false, pair.address, merge3(0, 0, 0), makePrice32(10000000, 14), 1, 1, 999999999999, {from: maker, value: BigInt(100 * 0.01 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(1, 0, 0), makePrice32(10300000, 14), 2, 1, 999999999999, {from: maker, value: BigInt(100 * 0.013 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(2, 0, 0), makePrice32(10500000, 14), 3, 1, 999999999999, {from: maker, value: BigInt(100 * 0.015 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(3, 0, 0), makePrice32(10700000, 14), 4, 1, 999999999999, {from: maker, value: BigInt(100 * 0.017 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(4, 0, 0), makePrice32(10900000, 14), 5, 1, 999999999999, {from: maker, value: BigInt(100 * 0.019 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(5, 0, 0), makePrice32(10200000, 14), 6, 1, 999999999999, {from: maker, value: BigInt(0.012 *Decimal).toString()})
        await router.limitOrder(false, pair.address, merge3(6, 0, 0), makePrice32(10400000, 14), 7, 1, 999999999999, {from: maker, value: BigInt(0.014 *Decimal).toString()})
        let result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 7 + 1, 'Orders number should be 7')

        result = await router.limitOrder(true, pair.address, merge3(0, 0, 0), makePrice32(10900000, 14), 1, 7, 999999999999, {from: taker})
        console.log("gas on deal 7 sell orders and null amount: ", result.receipt.gasUsed)

        // check order nums
        result = await pair.getOrderList.call(true, 0, 10)
        assert.equal(result.length, 0 + 1, 'buy orders nums should be 0')
        result = await pair.getOrderList.call(false, 0, 10)
        assert.equal(result.length, 0 + 1, 'sell orders nums should be 0')
    })
})

function makePrice32(s, e) {
    return s | (e << 27)
}

function merge3(a0, a1, a2) {
    let n = BigInt(0)
    n = n | BigInt(a2)
    n = (n << BigInt(32)) | BigInt(a1)
    n = (n << BigInt(32)) | BigInt(a0)
    return n.toString()
}
