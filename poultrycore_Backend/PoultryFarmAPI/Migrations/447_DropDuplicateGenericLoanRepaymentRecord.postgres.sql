-- 447_DropDuplicateGenericLoanRepaymentRecord.postgres.sql
-- Recording any repayment on Generic Employee Loans & Advances failed with
--   function spgenericemployeeloanrepayment_record(...) is not unique   (SQLSTATE 42725)
-- 445 re-created spgenericemployeeloanrepayment_record with a different parameter
-- list from 387's, so CREATE OR REPLACE added a SECOND function instead of replacing
-- the first. The old 387 version takes an extra optional p_genericstaffid, so the
-- service's named-argument call (GenericEmployeeLoanService.cs, which never passes
-- p_genericstaffid) matches both versions and Postgres refuses to choose.
-- Drop the old 387 version; the 445 version (with balanceaftertransaction) stays.
-- Nothing else calls it (only GenericEmployeeLoanService). Idempotent.

DROP FUNCTION IF EXISTS public.spgenericemployeeloanrepayment_record(
    text, integer, numeric, text, numeric, numeric, timestamp without time zone,
    integer, text, text, text, text, integer, integer, integer, text
);
