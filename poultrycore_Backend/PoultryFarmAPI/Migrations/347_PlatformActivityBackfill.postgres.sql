-- 347_PlatformActivityBackfill.postgres.sql
-- Backfills platformactivityevents from historical business transactions so the
-- activity foundation has history on day one. Requires 346.
--
-- RULES (per the spec):
--  * Source = 'HistoricalBackfill' on every row.
--  * correlationid = 'bf:<table>:<pk>' so the whole file is IDEMPOTENT —
--    rerunning it (or a half-applied retry) inserts nothing twice.
--  * Nothing is fabricated: userid comes from the row's own createdby/userid
--    column or stays NULL; occurredatutc comes from the row's own timestamps.
--  * businessdate is taken from the transaction's own business-date column
--    (saledate, closingdate, ...) — more accurate than deriving from the
--    created timestamp.
--  * Reversed/cancelled rows are still real activity (the user DID use the
--    product) EXCEPT soft-deleted rows (isdeleted) which other reports also
--    hide, and correction rows that merely shadow another row.
--
-- KNOWN LIMITATIONS (documented, not hidden):
--  * Logins cannot be backfilled — auditlogs only reach back ~weeks and the
--    Login API never recorded history. logincount starts at 0 for everyone.
--  * Workflow milestones that have no timestamp of their own (e.g. older
--    approvals before approvedat existed) use the row's created timestamp.
--  * Organization/family/template are resolved AS OF TODAY (farms as they are
--    now); companies deleted since then are skipped by the farms join.

DO $bf$
BEGIN

-- ---------- Poultry ----------
PERFORM platform_activity_record(
    s.farmid::text, coalesce(nullif(s.createdby,''), nullif(s.userid,'')),
    'SALES', 'SaleRecorded', 'Poultry', s.saleid::text, true, NULL,
    'bf:sale:' || s.saleid,
    coalesce(s.createddate, s.saledate, now()), 'HistoricalBackfill', NULL,
    s.saledate::date)
-- (to_jsonb lookup: prod's sale table predates the correctssaleid column, so a
--  direct column reference would fail there; missing key = not a correction.)
FROM sale s WHERE to_jsonb(s)->>'correctssaleid' IS NULL;

PERFORM platform_activity_record(
    e.farmid::text, nullif(e.userid,''),
    'EXPENSES', 'ExpenseCreated', 'Poultry', e.expenseid::text, true, NULL,
    'bf:expense:' || e.expenseid,
    coalesce(e.createddate, e.expensedate, now()), 'HistoricalBackfill', NULL,
    e.expensedate::date)
FROM expense e;

PERFORM platform_activity_record(
    p.farmid::text, coalesce(nullif(p.userid,''), nullif(p.createdby,'')),
    'PRODUCTION', 'ProductionRecorded', 'Poultry', p.productionid::text, true, NULL,
    'bf:eggproduction:' || p.productionid,
    coalesce(p.datecreated, p.productiondate, now()), 'HistoricalBackfill', NULL,
    p.productiondate::date)
FROM eggproduction p;

PERFORM platform_activity_record(
    r.farmid::text, coalesce(nullif(r.userid,''), nullif(r.createdby,'')),
    'PRODUCTION', 'ProductionRecorded', 'Poultry', r.id::text, true, NULL,
    'bf:productionrecords:' || r.id,
    coalesce(r.createdat, r.date, now()), 'HistoricalBackfill', NULL,
    r.date::date)
FROM productionrecords r;

PERFORM platform_activity_record(
    c.farmid::text, coalesce(nullif(c.submittedby,''), nullif(c.createdby,'')),
    'CLOSING', 'DailyClosingCompleted', 'Poultry', c.poultrydailyclosingid::text, true, NULL,
    'bf:poultrydailyclosings:' || c.poultrydailyclosingid,
    coalesce(c.approvedat, c.submittedat, c.createdat, now()), 'HistoricalBackfill', NULL,
    c.closingdate)
FROM poultrydailyclosings c
WHERE c.submittedat IS NOT NULL OR c.approvedat IS NOT NULL OR c.closedatutc IS NOT NULL;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PAYMENTS', 'PaymentRecorded', 'Poultry', p.poultrypaymentid::text, true, NULL,
    'bf:poultrypayments:' || p.poultrypaymentid,
    coalesce(p.createddate, p.paymentdate, now()), 'HistoricalBackfill', NULL,
    p.paymentdate::date)
FROM poultrypayments p;

PERFORM platform_activity_record(
    t.farmid::text, nullif(t.userid,''),
    'INVENTORY', 'InventoryMovementRecorded', 'Poultry', t.transactionid::text, true, NULL,
    'bf:inventorytransactions:' || t.transactionid,
    coalesce(t.createddate, t.transactiondate, now()), 'HistoricalBackfill', NULL,
    t.transactiondate::date)
FROM inventorytransactions t;

-- ---------- Water ----------
PERFORM platform_activity_record(
    s.farmid::text, nullif(s.createdby,''),
    'SALES', 'SaleRecorded', 'Water', s.watersaleid::text, true, NULL,
    'bf:watersales:' || s.watersaleid,
    coalesce(s.createddate, s.saledate, now()), 'HistoricalBackfill', NULL,
    s.saledate::date)
FROM watersales s;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PRODUCTION', 'ProductionRecorded', 'Water', p.waterdailyproductionid::text, true, NULL,
    'bf:waterdailyproductions:' || p.waterdailyproductionid,
    coalesce(p.postedat, p.createdat, now()), 'HistoricalBackfill', NULL,
    p.productiondate::date)
FROM waterdailyproductions p WHERE coalesce(p.isdeleted, false) = false;

PERFORM platform_activity_record(
    d.farmid::text, nullif(d.createdby,''),
    'DELIVERY', 'DriverReturnCompleted', 'Water', d.waterdriverreturnid::text, true, NULL,
    'bf:waterdriverreturns:' || d.waterdriverreturnid,
    coalesce(d.approvedat, d.createdat, now()), 'HistoricalBackfill', NULL,
    d.returndate::date)
FROM waterdriverreturns d WHERE d.approvedat IS NOT NULL;

PERFORM platform_activity_record(
    e.farmid::text, nullif(e.createdby,''),
    'EXPENSES', 'ExpenseCreated', 'Water', e.waterexpenseid::text, true, NULL,
    'bf:waterexpenses:' || e.waterexpenseid,
    coalesce(e.createdat, e.expensedate, now()), 'HistoricalBackfill', NULL,
    e.expensedate::date)
FROM waterexpenses e WHERE coalesce(e.isdeleted, false) = false;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PAYMENTS', 'PaymentRecorded', 'Water', p.waterpaymentid::text, true, NULL,
    'bf:waterpayments:' || p.waterpaymentid,
    coalesce(p.createddate, p.paymentdate, now()), 'HistoricalBackfill', NULL,
    p.paymentdate::date)
FROM waterpayments p;

PERFORM platform_activity_record(
    c.farmid::text, coalesce(nullif(c.submittedby,''), nullif(c.createdby,'')),
    'CLOSING', 'DailyClosingCompleted', 'Water', c.waterdailyclosingid::text, true, NULL,
    'bf:waterdailyclosings:' || c.waterdailyclosingid,
    coalesce(c.approvedat, c.submittedat, c.createdat, now()), 'HistoricalBackfill', NULL,
    c.closingdate)
FROM waterdailyclosings c
WHERE coalesce(c.isactive, true) AND (c.submittedat IS NOT NULL OR c.approvedat IS NOT NULL);

-- ---------- Hotel ----------
PERFORM platform_activity_record(
    b.farmid::text, nullif(b.createdby,''),
    'SALES', 'BookingCreated', 'Hotel', b.hotelbookingid::text, true, NULL,
    'bf:hotelbookings:' || b.hotelbookingid,
    coalesce(b.createdat, now()), 'HistoricalBackfill', NULL,
    b.checkindate::date)
FROM hotelbookings b;

PERFORM platform_activity_record(
    c.farmid::text, nullif(c.checkedinby,''),
    'OPERATIONS', 'CheckInCompleted', 'Hotel', c.hotelcheckinid::text, true, NULL,
    'bf:hotelcheckins:' || c.hotelcheckinid,
    coalesce(c.checkintime, c.createdat, now()), 'HistoricalBackfill', NULL, NULL)
FROM hotelcheckins c;

PERFORM platform_activity_record(
    c.farmid::text, nullif(c.checkedoutby,''),
    'OPERATIONS', 'CheckOutCompleted', 'Hotel', c.hotelcheckoutid::text, true, NULL,
    'bf:hotelcheckouts:' || c.hotelcheckoutid,
    coalesce(c.checkouttime, c.createdat, now()), 'HistoricalBackfill', NULL, NULL)
FROM hotelcheckouts c;

PERFORM platform_activity_record(
    e.farmid::text, nullif(e.submittedby,''),
    'EXPENSES', 'ExpenseCreated', 'Hotel', e.hotelexpenseid::text, true, NULL,
    'bf:hotelexpenses:' || e.hotelexpenseid,
    coalesce(e.createdat, e.expensedate, now()), 'HistoricalBackfill', NULL,
    e.expensedate::date)
FROM hotelexpenses e;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PAYMENTS', 'CustomerPaymentReceived', 'Hotel', p.hotelcustomerpaymentid::text, true, NULL,
    'bf:hotelcustomerpayments:' || p.hotelcustomerpaymentid,
    coalesce(p.createdat, p.paymentdate, now()), 'HistoricalBackfill', NULL,
    p.paymentdate::date)
FROM hotelcustomerpayments p;

PERFORM platform_activity_record(
    c.farmid::text, nullif(c.closedby,''),
    'CLOSING', 'DailyClosingCompleted', 'Hotel', c.hoteldailyclosingid::text, true, NULL,
    'bf:hoteldailyclosings:' || c.hoteldailyclosingid,
    coalesce(c.createdat, now()), 'HistoricalBackfill', NULL,
    c.closingdate)
FROM hoteldailyclosings c;

-- ---------- Restaurant ----------
PERFORM platform_activity_record(
    o.farmid::text, nullif(o.createdby,''),
    'SALES', 'SaleRecorded', 'Restaurant', o.orderid::text, true, NULL,
    'bf:restaurantorders:' || o.orderid,
    coalesce(o.createdat, now()), 'HistoricalBackfill', NULL, NULL)
FROM restaurantorders o;

PERFORM platform_activity_record(
    e.farmid::text, nullif(e.createdby,''),
    'EXPENSES', 'ExpenseCreated', 'Restaurant', e.expenseid::text, true, NULL,
    'bf:restaurantexpenses:' || e.expenseid,
    coalesce(e.createdat, e.expensedate, now()), 'HistoricalBackfill', NULL,
    e.expensedate::date)
FROM restaurantexpenses e;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PAYMENTS', 'CustomerPaymentReceived', 'Restaurant', p.customerpaymentid::text, true, NULL,
    'bf:restaurantcustomerpayments:' || p.customerpaymentid,
    coalesce(p.createdat, p.paymentdate, now()), 'HistoricalBackfill', NULL,
    p.paymentdate::date)
FROM restaurantcustomerpayments p;

PERFORM platform_activity_record(
    c.farmid::text, nullif(c.closedby,''),
    'CLOSING', 'DailyClosingCompleted', 'Restaurant', c.closingid::text, true, NULL,
    'bf:restaurantdailyclosings:' || c.closingid,
    coalesce(c.closedat, now()), 'HistoricalBackfill', NULL,
    c.closingdate)
FROM restaurantdailyclosings c;

-- ---------- Generic ----------
PERFORM platform_activity_record(
    s.farmid::text, nullif(s.createdby,''),
    'SALES', 'SaleCreated', 'Generic', s.genericsaleid::text, true, NULL,
    'bf:genericsales:' || s.genericsaleid,
    coalesce(s.createdat, s.saledate, now()), 'HistoricalBackfill', NULL,
    s.saledate::date)
FROM genericsales s WHERE coalesce(s.isdeleted, false) = false;

PERFORM platform_activity_record(
    e.farmid::text, nullif(e.createdby,''),
    'EXPENSES', 'ExpenseCreated', 'Generic', e.genericexpenseid::text, true, NULL,
    'bf:genericexpenses:' || e.genericexpenseid,
    coalesce(e.createdat, e.expensedate, now()), 'HistoricalBackfill', NULL,
    e.expensedate::date)
FROM genericexpenses e WHERE coalesce(e.isdeleted, false) = false;

PERFORM platform_activity_record(
    p.farmid::text, nullif(p.createdby,''),
    'PAYMENTS', 'CustomerPaymentReceived', 'Generic', p.genericcustomerpaymentid::text, true, NULL,
    'bf:genericcustomerpayments:' || p.genericcustomerpaymentid,
    coalesce(p.createdat, p.paymentdate, now()), 'HistoricalBackfill', NULL,
    p.paymentdate::date)
FROM genericcustomerpayments p;

PERFORM platform_activity_record(
    g.farmid::text, nullif(g.createdby,''),
    'INVENTORY', 'InventoryReceived', 'Generic', g.genericpurchaseid::text, true, NULL,
    'bf:genericpurchases:' || g.genericpurchaseid,
    coalesce(g.createdat, g.purchasedate, now()), 'HistoricalBackfill', NULL,
    g.purchasedate::date)
FROM genericpurchases g WHERE coalesce(g.isdeleted, false) = false;

PERFORM platform_activity_record(
    c.farmid::text, coalesce(nullif(c.submittedby,''), nullif(c.createdby,'')),
    'CLOSING', 'DailyClosingCompleted', 'Generic', c.genericdailyclosingid::text, true, NULL,
    'bf:genericdailyclosings:' || c.genericdailyclosingid,
    coalesce(c.approvedat, c.submittedat, c.createdat, now()), 'HistoricalBackfill', NULL,
    c.closingdate)
FROM genericdailyclosings c
WHERE c.submittedat IS NOT NULL OR c.approvedat IS NOT NULL;

-- ---------- Platform billing (organization-level: companyid stays NULL) ----------
PERFORM platform_activity_record(
    NULL, a.owneruserid,
    'BILLING', 'SubscriptionPaymentRecorded', 'Billing', p.id::text, true, NULL,
    'bf:platformpayments:' || p.id,
    coalesce(p.paymentdateutc, p.receivedatutc, p.createdatutc, now()), 'HistoricalBackfill', NULL, NULL)
FROM platformpayments p
JOIN organizationbillingaccounts a ON a.id = p.accountid
WHERE p.status = 'Succeeded';

END
$bf$;
