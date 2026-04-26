SELECT COUNT(*) FROM tblEthTransaction WHERE ToAddress = '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45' 
SELECT * FROM tblEthTransaction WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4'
SELECT * FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' ORDER BY TransactionDate asc


--FIFO TEST STARTED HERE -- IT PASSED PERFECTLY.
SELECT SUM(ShortTermCostBasis),SUM(ShortTermSalesProceed), SUM(ShortTermCapitalGainOrLoss)  
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' 
--214.537232033344751	203.019476967386122	-11.517755065958629

SELECT TransactionDate,type, Value, valueUSD, HistoricalPrice, TransactionFeeUSD,ShortTermCostBasis,ShortTermSalesProceed,ShortTermCapitalGainOrLoss  
FROM tblTransactionS WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' ORDER BY Value DESC
