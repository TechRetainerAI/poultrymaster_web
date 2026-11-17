-- Checks for migration 430 (Water sourced-expense guard + stock messages).
--
-- SELF-ROLLING BACK: every change happens inside one PL/pgSQL block that ends
-- by raising a sentinel, which undoes it all -- running this file on its own
-- against a real database changes nothing.
DO $t$
DECLARE
    r record; msg text; n int := 0;
BEGIN
    BEGIN
        -- A. cancel / reject refused for every sourced expense whose source exists
        FOR r IN SELECT e.waterexpenseid, e.farmid, e.sourcetype FROM waterexpenses e
                 WHERE e.status = 'Approved' AND NOT e.isdeleted AND e.sourcetype IS NOT NULL LOOP
            IF public.fnwaterexpense_sourceblock(r.waterexpenseid, r.farmid, 'cancelled') IS NULL THEN CONTINUE; END IF;
            BEGIN
                PERFORM public.spwaterexpense_cancel(r.waterexpenseid, r.farmid, NULL, '430 check');
                RAISE EXCEPTION 'FAIL: cancel of % #% went through', r.sourcetype, r.waterexpenseid;
            EXCEPTION WHEN raise_exception THEN
                IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
                IF SQLERRM NOT LIKE 'This expense was created automatically by %' THEN
                    RAISE EXCEPTION 'FAIL: unexpected cancel error: %', SQLERRM;
                END IF;
                n := n + 1;
            END;
        END LOOP;
        RAISE NOTICE 'ok A: % automatic expenses cannot be cancelled', n;

        -- B. a manual expense still cancels
        SELECT e.waterexpenseid, e.farmid INTO r FROM waterexpenses e
        WHERE e.status = 'Approved' AND NOT e.isdeleted AND e.sourcetype IS NULL LIMIT 1;
        IF FOUND THEN
            PERFORM public.spwaterexpense_cancel(r.waterexpenseid, r.farmid, NULL, '430 check');
            IF (SELECT status FROM waterexpenses WHERE waterexpenseid = r.waterexpenseid) <> 'Cancelled' THEN
                RAISE EXCEPTION 'FAIL: manual expense % not cancelled', r.waterexpenseid;
            END IF;
            RAISE NOTICE 'ok B: manual expense still cancels';
        END IF;

        -- C/D/E. purchase edit / delete messages; normal edit unaffected
        SELECT p.waterrawmaterialpurchaseid id, p.farmid, p.waterrawmaterialitemid item, p.quantity q,
               p.unitcost, p.paymentmethod, p.amountpaid
          INTO r
        FROM   waterrawmaterialpurchases p
        WHERE  COALESCE(p.lotsource, '') <> 'ManualDeferredCost' AND p.quantity > 1
          AND  NOT EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub
                           WHERE ub.waterrawmaterialpurchaseid = p.waterrawmaterialpurchaseid)
        LIMIT 1;
        IF FOUND THEN
            UPDATE waterrawmaterialitems SET currentquantity = -539.1 WHERE waterrawmaterialitemid = r.item;
            BEGIN
                PERFORM public.spwaterrawmaterialpurchase_update(p_waterrawmaterialpurchaseid => r.id, p_farmid => r.farmid,
                        p_quantity => r.q - 1, p_unitcost => r.unitcost, p_paymentmethod => r.paymentmethod, p_amountpaid => r.amountpaid);
                RAISE EXCEPTION 'FAIL: reduce below zero went through';
            EXCEPTION WHEN raise_exception THEN
                IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
                IF SQLERRM NOT LIKE '%already below zero (-539.1 %' THEN
                    RAISE EXCEPTION 'FAIL: unexpected edit message: %', SQLERRM;
                END IF;
            END;
            RAISE NOTICE 'ok C: edit with negative stock explains the stock figure';

            UPDATE waterrawmaterialitems SET currentquantity = 0.5 WHERE waterrawmaterialitemid = r.item;
            BEGIN
                PERFORM public.spwaterrawmaterialpurchase_delete(r.id, r.farmid);
                RAISE EXCEPTION 'FAIL: delete went through';
            EXCEPTION WHEN raise_exception THEN
                IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
                IF SQLERRM NOT LIKE '%but only 0.5 remain%' THEN
                    RAISE EXCEPTION 'FAIL: unexpected delete message: %', SQLERRM;
                END IF;
            END;
            RAISE NOTICE 'ok D: delete says how much usage to undo';

            UPDATE waterrawmaterialitems SET currentquantity = 100000 WHERE waterrawmaterialitemid = r.item;
            PERFORM public.spwaterrawmaterialpurchase_update(p_waterrawmaterialpurchaseid => r.id, p_farmid => r.farmid,
                    p_quantity => r.q - 1, p_unitcost => r.unitcost, p_paymentmethod => r.paymentmethod, p_amountpaid => r.amountpaid);
            IF (SELECT quantity FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = r.id) <> r.q - 1 THEN
                RAISE EXCEPTION 'FAIL: normal edit did not save';
            END IF;
            RAISE NOTICE 'ok E: normal edit still saves';
        END IF;

        RAISE EXCEPTION '__430_rollback__';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> '__430_rollback__' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'all 430 checks passed (changes rolled back)';
END
$t$;
