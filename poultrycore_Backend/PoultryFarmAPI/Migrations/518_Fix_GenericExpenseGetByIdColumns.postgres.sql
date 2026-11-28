-- 518: fix spgenericexpense_getbyid — it returns `SELECT g.* FROM
-- spgenericexpense_getall(...)`, but migration 505 added two columns to
-- getall's output (expensereversalid, reversalnumber) without widening
-- getbyid's RETURNS TABLE. getbyid is LANGUAGE sql, so the planner inlines it
-- and the column count check fails:
--   ERROR 42P13: return type mismatch in function declared to return record
--   DETAIL: Final statement returns too many columns.
-- This broke EVERY call that returns one expense — e.g. POST /expenses (Create
-- Expense) which reads the row back by id. Here we realign getbyid's RETURNS
-- TABLE with getall's current 31 columns; the body is unchanged.
--
-- A RETURNS TABLE change cannot go through CREATE OR REPLACE ("cannot change
-- return type of existing function"), so drop first. Idempotent.

BEGIN;

DROP FUNCTION IF EXISTS public.spgenericexpense_getbyid(integer, text);

CREATE FUNCTION public.spgenericexpense_getbyid(p_genericexpenseid integer, p_farmid text)
RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp without time zone,
              genericexpensecategoryid integer, categoryname text, genericsupplierid integer,
              suppliername text, description text, amount numeric, paidto text, paymentmethod text,
              genericcashaccountid integer, cashaccountname text, receipturl text, branchid integer,
              staffid integer, status text, notes text, createdby text, approvedby text,
              approvedat timestamp without time zone, rejectionreason text,
              createdat timestamp without time zone, updatedat timestamp without time zone,
              amountpaid numeric, duedate date, paymentstatus text, sourcetype text,
              paymentsapplied numeric, expensereversalid integer, reversalnumber text)
LANGUAGE sql STABLE
AS $fn$
    SELECT g.* FROM public.spgenericexpense_getall(p_farmid) g
    WHERE  g.genericexpenseid = p_genericexpenseid;
$fn$;

COMMIT;
