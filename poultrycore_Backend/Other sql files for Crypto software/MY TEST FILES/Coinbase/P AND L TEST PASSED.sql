SELECT COUNT(*) FROM tblEthTransaction WHERE ToAddress = '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45' 
SELECT * FROM tblEthTransaction WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4'

SELECT * FROM tblTaxCalculations WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' AND WALLETCODE = 'MmBnb'
SELECT TotalCostBasis, TotalIncomeFromSelling, TotalCapitalGain FROM tblTaxCalculations WHERE userID = 'c48408cc-c3d9-4545-b03e-fd3a028c46c4' AND WALLETCODE = 'MmBnb'
--WE SIMPLY READ WHAT WAS CALCULATED
--SHORT TERM AND LONG TERMS DO NOT APPLY HERE