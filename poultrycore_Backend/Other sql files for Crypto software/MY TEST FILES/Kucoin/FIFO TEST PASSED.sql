SELECT * FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' AND WALLETCODE = 'Kucoin' 
--FIFO TEST STARTED HERE -- IT PASSED PERFECTLY.
SELECT SUM(ShortTermCostBasis),SUM(ShortTermSalesProceed), SUM(ShortTermCapitalGainOrLoss)  
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' AND WALLETCODE = 'Kucoin' 
--160.173358768160000	142.966615694110000	-17.206743074050000

SELECT TransactionPairIdentifier, CurrencyType, TransactionDate,type, Value, valueUSD, HistoricalPrice, TransactionFeeUSD,ShortTermCostBasis,ShortTermSalesProceed,ShortTermCapitalGainOrLoss  
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4'  AND WALLETCODE = 'Kucoin' ORDER BY TransactionDate asc


--Fifo
DECLARE @DIFFDATA AS DECIMAL(18, 7)
--1st
SELECT 10.0554 * 7.61 + 0.1135 *7.606 + 1.9638 * 7.605+ 0.0844 *7.6 + 33.2731 *7.573 + 7.3636 *7.567  + 3.9174 *7.563 -- 430.2858577000000000000 
       --52.8538  - sum of first 6
SELECT 56.7712 - 52.8538
select 6.7 - (56.7712 - 52.8538) -- carry forward  2.7826

--tw0:
select 1.4706 *7.563  -- 11.1221478
select 2.7826 - 1.4706 -- carry forward  1.3120

--three
--tw0:
select 1.3120 *7.563  -- 9.9226560
 -- carry forward  0


--4:
select 3.788400000000000 * 4.797000000000000  -- 18.172954800000000
select 68.056400000000000 - 3.788400000000000 -- carry forward  0