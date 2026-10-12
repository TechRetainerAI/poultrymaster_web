-- =============================================================================
-- 360_PoultrySaleSplitByProduct.postgres.sql                  (requires 358)
--
-- The New sale form lets one entry carry different products (Fresh Eggs and
-- Chicken). 358's sppoultrysale_creategroup deliberately keeps ONE product per
-- sale ("phase 1": bird stock, P&L by product and flock closeout still read
-- the sale header's product, which must be exact).
--
-- So a mixed entry is saved as one sale PER PRODUCT, all in this one call:
--   * lines are grouped by product (case- and space-insensitive), in the order
--     the products first appear; egg sizes of one product stay one sale;
--   * each group goes through sppoultrysale_creategroup UNCHANGED -- its own
--     SG number, stock, cash and (when paid) its own customer payment;
--   * one transaction: every sale lands, or none do;
--   * a request key gets a per-product suffix, so a double-click still returns
--     the sales already posted instead of posting them again.
--
-- creategroup itself is not touched. When phase 2 moves those readers onto
-- saleline, the form can send mixed lines straight to creategroup and this
-- function can be retired.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sppoultrysale_createsplit(
    p_farmid text, p_userid text, p_saledate timestamp without time zone,
    p_customername text, p_customerid integer, p_paymentmethod text, p_cashaccountid integer,
    p_paid boolean, p_description text, p_flockid integer, p_linesjson text,
    p_requestkey text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_lines  jsonb := COALESCE(NULLIF(btrim(COALESCE(p_linesjson, '')), ''), '[]')::jsonb;
    v_key    text  := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    g        record;
    v_res    jsonb;
    v_sales  jsonb := '[]'::jsonb;
    v_ids    jsonb := '[]'::jsonb;
    v_nos    text[] := '{}';
    v_total  numeric(14,2) := 0;
    v_n      integer := 0;
    v_dup    boolean := true;
BEGIN
    IF jsonb_typeof(v_lines) <> 'array' OR jsonb_array_length(v_lines) = 0 THEN
        RAISE EXCEPTION 'Add at least one line to the sale.';
    END IF;

    FOR g IN
        SELECT lower(btrim(e.v->>'product')) AS k,
               min(e.ord)                    AS first_ord,
               jsonb_agg(e.v ORDER BY e.ord) AS lines
        FROM   jsonb_array_elements(v_lines) WITH ORDINALITY e(v, ord)
        GROUP  BY lower(btrim(e.v->>'product'))
        ORDER  BY min(e.ord)
    LOOP
        v_n := v_n + 1;
        v_res := public.sppoultrysale_creategroup(
            p_farmid        => p_farmid,
            p_userid        => p_userid,
            p_saledate      => p_saledate,
            p_customername  => p_customername,
            p_customerid    => p_customerid,
            p_paymentmethod => p_paymentmethod,
            p_cashaccountid => p_cashaccountid,
            p_paid          => p_paid,
            p_description   => p_description,
            p_flockid       => p_flockid,
            p_linesjson     => g.lines::text,
            p_requestkey    => CASE WHEN v_key IS NULL THEN NULL ELSE v_key || '#' || v_n::text END);

        v_sales := v_sales || jsonb_build_array(v_res || jsonb_build_object('product', btrim(g.lines->0->>'product')));
        v_ids   := v_ids || jsonb_build_array((v_res->>'saleId')::int);
        v_nos   := v_nos || (v_res->>'saleGroupNo');
        v_total := v_total + COALESCE((v_res->>'totalAmount')::numeric, 0);
        v_dup   := v_dup AND COALESCE((v_res->>'duplicate')::boolean, false);
    END LOOP;

    RETURN jsonb_build_object(
        'saleGroupNo', array_to_string(v_nos, ', '),
        'saleId',      (v_ids->>0)::int,
        'saleIds',     v_ids,
        'totalAmount', v_total,
        'lineCount',   jsonb_array_length(v_lines),
        'saleCount',   v_n,
        'duplicate',   v_dup,
        'sales',       v_sales);
END;
$function$;
