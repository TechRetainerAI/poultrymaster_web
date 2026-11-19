-- 444_WidenCashTransactionType.postgres.sql
-- Widen genericcashtransactions.transactiontype from varchar(20) to varchar(50).
-- The employee-loan functions (migration 387) insert values up to 29 characters
-- (e.g. 'EmployeeLoanRepaymentReversal'), which overflow the original limit.

ALTER TABLE genericcashtransactions
    ALTER COLUMN transactiontype TYPE varchar(50);
