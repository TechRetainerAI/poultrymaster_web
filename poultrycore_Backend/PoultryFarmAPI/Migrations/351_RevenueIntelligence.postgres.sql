-- 351_RevenueIntelligence.postgres.sql
-- PROMPT 6 OF 7 — Revenue intelligence over the AUTHORITATIVE billing tables.
--
-- This adds NO new invoice/payment source of truth. The only storage is a
-- monthly MRR snapshot per organization, captured when revenue analytics run,
-- so month-over-month movement (New / Expansion / Contraction / Churned MRR)
-- can be computed deterministically. Everything else is read-time aggregation
-- of organizationbillingaccounts / platforminvoices / platformpayments /
-- platformdiscounts / platformaccountcredits via the SAME evaluation code the
-- customer-facing billing uses (PlatformBillingService.GetSummaryAsync).

CREATE TABLE IF NOT EXISTS revenuemrrsnapshots (
    organizationid  text NOT NULL,            -- owner user id
    snapshotmonth   date NOT NULL,            -- first day of month (UTC)
    currencycode    text NOT NULL,
    grossmrr        numeric NOT NULL DEFAULT 0,   -- Σ billable companies' monthly price
    netmrr          numeric NOT NULL DEFAULT 0,   -- after discounts, pre-tax, credits excluded
    payingcompanies int NOT NULL DEFAULT 0,
    accountstatus   text NOT NULL,            -- Trial|Active|PastDue|GracePeriod|Suspended|Cancelled
    billingcycle    text NOT NULL DEFAULT 'monthly',
    capturedatutc   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (organizationid, snapshotmonth)
);
CREATE INDEX IF NOT EXISTS ix_mrrsnapshots_month ON revenuemrrsnapshots (snapshotmonth);

-- Upsert used by the revenue service each time analytics run: the CURRENT
-- month's row always reflects the latest evaluation; history stays frozen.
CREATE OR REPLACE FUNCTION platform_mrr_snapshot(
    p_organizationid  text,
    p_currencycode    text,
    p_grossmrr        numeric,
    p_netmrr          numeric,
    p_payingcompanies int,
    p_accountstatus   text,
    p_billingcycle    text
) RETURNS void
LANGUAGE sql
AS $fn$
    INSERT INTO revenuemrrsnapshots
        (organizationid, snapshotmonth, currencycode, grossmrr, netmrr,
         payingcompanies, accountstatus, billingcycle, capturedatutc)
    VALUES
        (p_organizationid, date_trunc('month', now() AT TIME ZONE 'UTC')::date,
         p_currencycode, p_grossmrr, p_netmrr, p_payingcompanies, p_accountstatus,
         p_billingcycle, now())
    ON CONFLICT (organizationid, snapshotmonth) DO UPDATE SET
        currencycode = excluded.currencycode,
        grossmrr = excluded.grossmrr,
        netmrr = excluded.netmrr,
        payingcompanies = excluded.payingcompanies,
        accountstatus = excluded.accountstatus,
        billingcycle = excluded.billingcycle,
        capturedatutc = now();
$fn$;
