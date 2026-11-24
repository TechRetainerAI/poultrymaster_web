-- =============================================================================
-- 491_Winchester_GenericStatementDebtWording.postgres.sql
--
-- Found when cross-checking Generic customer debt (488) against Poultry (369).
-- Poultry's customer statement shows a debt line as "Debt" and a payment made
-- only against debts as "... against a debt" / "... across N debts". Generic's
-- showed the raw code "CustomerDebt" and a plain "Payment received".
--
-- spgenericcustomerstatement (live body patched; skipped when already applied):
--   * entry type of a debt line: 'Debt' (its documenttype stays 'CustomerDebt');
--   * a payment applied only to debts: ' against a debt' / ' across N debts'.
-- Amounts and running balance are unchanged. No BEGIN/COMMIT.
-- =============================================================================

DO $patch$
DECLARE
    v_def text;
    v_old1 text := 'SELECT d.documentdate, d.documenttype, d.reference, d.label,';
    v_old2 text := '(''Payment received'' ||';
BEGIN
    v_def := pg_get_functiondef('public.spgenericcustomerstatement(text,integer,date,date)'::regprocedure);
    IF position('491:' IN v_def) = 0 THEN
        IF (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1) <> 1
           OR (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1 THEN
            RAISE EXCEPTION '491: spgenericcustomerstatement is not the expected shape.';
        END IF;
        v_def := replace(v_def, v_old1,
'SELECT d.documentdate,
               CASE WHEN d.documenttype = ''CustomerDebt'' THEN ''Debt'' ELSE d.documenttype END,   -- 491: as Poultry
               d.reference, d.label,');
        v_def := replace(v_def, v_old2,
'(''Payment received'' ||
                -- 491: a payment applied only to customer debts says so (as Poultry 369).
                CASE WHEN NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                                      WHERE ca.farmid = p_farmid AND ca.module = ''generic''
                                        AND ca.paymentid = p.genericcustomerpaymentid)
                     THEN COALESCE((SELECT CASE WHEN COUNT(*) = 1 THEN '' against a debt''
                                                ELSE '' across '' || COUNT(*)::text || '' debts'' END
                                    FROM   customerpaymentallocation ca
                                    WHERE  ca.farmid = p_farmid AND ca.module = ''generic-debt''
                                      AND  ca.paymentid = p.genericcustomerpaymentid
                                    HAVING COUNT(*) > 0), '''')
                     ELSE '''' END ||');
        EXECUTE v_def;
    END IF;
END
$patch$;
