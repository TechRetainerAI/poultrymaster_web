SELECT distinct (userID) FROM tblTransactions 

SELECT sum(valueUSD), sum(ShortTermSalesProceed) 
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4'  AND WALLETCODE = 'Kucoin' and type = 'sell' 

SELECT TransactionPairIdentifier, CurrencyType, TransactionDate,type, Value, valueUSD, HistoricalPrice, TransactionFeeUSD,ShortTermCostBasis,ShortTermSalesProceed,ShortTermCapitalGainOrLoss  
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4'  AND WALLETCODE = 'Kucoin' and type = 'sell' ORDER BY TransactionDate asc 


--THE OTHER
SELECT TransactionPairIdentifier, CurrencyType, TransactionDate,type, Value, valueUSD, HistoricalPrice, TransactionFeeUSD,ShortTermCostBasis,ShortTermSalesProceed,ShortTermCapitalGainOrLoss  
FROM tblTransactionS WHERE userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND WALLETCODE = 'Kucoin' and type = 'sell'  ORDER BY TransactionDate asc 


SELECT TransactionPairIdentifier, CurrencyType, TransactionDate,type, Value, valueUSD, HistoricalPrice, TransactionFeeUSD,ShortTermCostBasis,ShortTermSalesProceed,ShortTermCapitalGainOrLoss  
FROM tblTransactionS WHERE userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND WALLETCODE = 'Kucoin' and type = 'sell' 
AND ValueUSD <> ShortTermSalesProceed
ORDER BY TransactionDate asc 

SELECT count(*) FROM tblTransactionS WHERE userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND WALLETCODE = 'Kucoin' and type = 'sell' 
AND ValueUSD <> ShortTermSalesProceed
ORDER BY TransactionDate asc 

--LUNA-USDC
select * from tblTransactions where TransactionPairIdentifier = '6b8005eafd6847eca6ced1e5143db3511ff39afa6012fbf556883ea4017b681e'
select * from tblKucoinTransaction  where TransactionPairIdentifier = 'd3287ba036828b2b88f785ab9d391612ec49bb11d317ce198bd40cbe636e4527'
select * from tblTransactions  where TransactionPairIdentifier = '913cbeeb6e0cd14bfea84525de76129cd31978470383d86b9a1ecd3454fbd478'
select * from tblKucoinTransaction  where TransactionPairIdentifier = '87b65149104a975a9b6c7e72b44570f9ccacf8fd7f3b71629c662f69bc0e7aee'
select * from tblTransactions  where TransactionPairIdentifier = '87b65149104a975a9b6c7e72b44570f9ccacf8fd7f3b71629c662f69bc0e7aee'
select count(*) from tblTransactions  where userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND 
TransactionPairIdentifier = 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'
select count(*) from tblTransactions  where Type='buy' and TransactionPairIdentifier = 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'
select count(*) from tblTransactions  where Type='sell' and TransactionPairIdentifier = 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'

select * from tblTransactions  where TransactionPairIdentifier = 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'

select * from tblTransactions where userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND TransactionPairIdentifier = '6b8005eafd6847eca6ced1e5143db3511ff39afa6012fbf556883ea4017b681e'
select * from tblKucoinTransaction  where userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND TransactionPairIdentifier = 'd3287ba036828b2b88f785ab9d391612ec49bb11d317ce198bd40cbe636e4527'
select * from tblTransactions  where TransactionPairIdentifier = '913cbeeb6e0cd14bfea84525de76129cd31978470383d86b9a1ecd3454fbd478'




select * from tblTransactions where CurrencyType = 'LUNC-USDC'
-- The following accounted for 147 of 154 rejections/ignoring
select count(*) from tblTransactions where CurrencyType = 'LUNC-USDC' --67
select count(*) from tblTransactions where CurrencyType like '%USDC' --76
select count(*) from tblTransactions where CurrencyType like 'USDC%'  -- 4


SELECT sum(valueUSD), sum(ShortTermSalesProceed) 
FROM tblTransactionS WHERE userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND WALLETCODE = 'Kucoin' and type = 'sell' 
and TransactionPairIdentifier  <> 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'



and TransactionPairIdentifier  <> 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d'


select * from tblTransactions where TransactionPairIdentifier in ('302682060', '1015341156')
select * from tblEthTransaction  where Txhash = '0xa973f60320cba98e40c3bbf056187bee04da8bc8a7ef9fc5279d3578e09b36f1'
select * from tblEthTransaction  where Method = 'Sell To Uniswap'
select * from tblEthTransaction  where  fromAddress = '0xdef1c0ded9bec7f1a1670819833240f027b25eff'
select * from tblEthTransaction  where  toAddress = '0xdef1c0ded9bec7f1a1670819833240f027b25eff'
select * from tblEthTransaction  where  type = 'sell'
select * from tblEthTransaction  where  type = 'sell'
select * from tblKucoinTransaction  where  TransactionPairIdentifier = 'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d' and OrderId = '63765ad2bedbd40001a1fe41'

select 0.104188293508255 * 1095.670000000000000

select * from tblEthTransaction where userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND TransactionPairIdentifier in ('302682060', '1015341156')

select * from tblTransactions where userID = '806473c8-c845-4973-b7d3-e86b45ee26d6'  AND Type = 'Buy' and Value = 0
select * from tblTransactions where TransactionPairIdentifier = '-1832131178'


-- the following failed if (coinHoldings.TryGetValue(sellTransaction.TransactionPairIdentifier, out var buyTransactions) && buyTransactions.Count > 0)
--Were not found at all in the buy transactions.
--Caused 80 sells to be missed
select * from tblKucoinTransaction where TransactionPairIdentifier in (
'd3287ba036828b2b88f785ab9d391612ec49bb11d317ce198bd40cbe636e4527') 
-- the last two are for USDT-USDT AND VICE VERSA So can be avoided
select * from tblKucoinTransaction where TransactionPairIdentifier in (
'd3287ba036828b2b88f785ab9d391612ec49bb11d317ce198bd40cbe636e4527', 
'87b65149104a975a9b6c7e72b44570f9ccacf8fd7f3b71629c662f69bc0e7aee') 

select * from tblKucoinTransaction where Symbol = 'USDC-USDT' and Side = 'Buy'
select * from tblKucoinTransaction where Symbol = 'USDT-USDC' and Side = 'Buy'
select * from tblKucoinTransaction where Symbol like 'USDt%' and Side = 'Buy'
select * from tblKucoinTransaction where Symbol = 'USDT-USDC' and Side = 'Buy'

-- Had 172 buy transactions - aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78
--txhash= 
select * from tblTransactions where txhash in ('6289b92c7023eb0001afcb66', '62970a80ea4bd000010e7d96', '6327b2af3b7e10000176858e')



-- Now I have to think about the airdrops from LUNA that I recieved without buying -- should be classified as income.
select * from tblTransactions where txhash  '63765ad2bedbd40001a1fe41'  -- the one buy 
select * from tblTransactions where txhash in ('636aa738fe97f30001bdee2f', '')


select * from tblTransactions where TransactionPairIdentifier in (
'aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78')

select count(*) from tblTransactions where TransactionPairIdentifier in (
'aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78') and type = 'sell' 

select count(*) from tblTransactions where TransactionPairIdentifier in (
'aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78') and type = 'buy' 

--The 172 txs left behind is valid.
select sum(Value) + 25827659.450834800000000M from tblTransactions where TransactionPairIdentifier in (
'aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78') and type = 'sell' 

select sum(value) from tblTransactions where TransactionPairIdentifier in (
'aacf27463613d2f642b2e7229ad3e3a4a52a3c3d0fcf8a48aa6a3cd25d348d78') and type = 'buy' 


select * from tblKucoinTransaction where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and side = 'sell' 

select count(*) from tblKucoinTransaction where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and side = 'sell' 

select count(*) from tblKucoinTransaction where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and side = 'buy' 

select count(*) from tblKucoinTransaction where symbol like 'Lunc%'

select count(*) from tblTransactions where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and type = 'sell' 

select count(*) from tblTransactions where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and  type = 'buy'


select sum(Value)  from tblTransactions where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and type = 'sell' 

select sum(value)  from tblTransactions where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and type = 'buy' 

select 312602170.260496500000000 - 291308777.700487840000000

select distinct(TransactionPairIdentifier) from tblKucoinTransaction where Symbol = 'LUNC-USDT'

select sum(size)  from tblKucoinTransaction where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and side = 'sell' 

select sum(size)  from tblKucoinTransaction where TransactionPairIdentifier in (
'a331b7317b65c0605c026870dddebd4b1af2035627635b016fe95d408b77e68d') and side = 'buy' 

--conclusion is that for the tx above, there are 448 buys and 1113 sells
--However what really matters is the values -- it turned that the sells are 21293392.560008660000000 more than the toal buys
---- there fore will just skip all those sells that we do not have buys for
--
--I also have to fix that one issue with eth