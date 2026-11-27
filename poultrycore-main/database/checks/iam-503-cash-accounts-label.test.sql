-- 503_Enock_CashAccountsLabel. Self-contained: BEGIN ... ROLLBACK.
BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.iampermissions WHERE resourcelabel LIKE '%&%Account%') THEN
        RAISE EXCEPTION 'FAIL 503.1: a permission is still labelled "Cash & Accounts"'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.iampermissions WHERE resourcelabel = 'Cash Accounts') THEN
        RAISE EXCEPTION 'FAIL 503.1: no "Cash Accounts" permissions'; END IF;
    RAISE NOTICE 'ok 503.1 the roles screen says Cash Accounts';
    RAISE NOTICE 'iam 503: all checks passed';
END $$;
ROLLBACK;
