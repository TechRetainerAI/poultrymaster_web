using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business;

public partial class GenericReportService
{
    public async Task<List<GenericProfitLossEntry>> GetProfitLossEntriesAsync(
        string farmId, DateOnly from, DateOnly to, CancellationToken cancellationToken)
    {
        // Use the recorded sale-out cost when available. Older sales can carry
        // their historical unit cost only on the item. Never reprice at today's cost.
        const string sql = """
            WITH sales AS (
                SELECT s.genericsaleid, s.saledate::date AS day, s.genericsubscriptionid,
                       coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
                       coalesce(c.customername, s.notes, 'Walk-in sale') AS description,
                       s.totalamount - coalesce(s.taxamount, 0) AS revenue
                FROM genericsales s
                LEFT JOIN genericcustomers c ON c.farmid = s.farmid AND c.genericcustomerid = s.genericcustomerid
                WHERE s.farmid = @farm AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false)
                  AND s.saledate >= @start AND s.saledate < @finish + 1
            ), movement_cost AS (
                SELECT m.referenceid, m.genericproductid, sum(abs(coalesce(m.totalcostvalue, m.unitcost * m.quantity))) AS cost
                FROM genericstockmovements m JOIN sales s ON s.genericsaleid = m.referenceid
                WHERE m.farmid = @farm AND m.referencetype = 'Sale' AND m.movementtype = 'SaleOut'
                GROUP BY m.referenceid, m.genericproductid
            ), item_cost AS (
                SELECT i.genericsaleid, i.genericproductid, sum(i.costamount * i.quantity) AS cost
                FROM genericsaleitems i JOIN sales s USING (genericsaleid)
                WHERE i.farmid = @farm AND i.itemtype = 'Product'
                GROUP BY i.genericsaleid, i.genericproductid
            ), costs AS (
                SELECT coalesce(m.referenceid, i.genericsaleid) AS id, sum(coalesce(m.cost, i.cost, 0)) AS cost
                FROM movement_cost m FULL JOIN item_cost i ON m.referenceid = i.genericsaleid AND m.genericproductid = i.genericproductid
                GROUP BY coalesce(m.referenceid, i.genericsaleid)
            ), loans AS (
                SELECT * FROM spgenericloan_list(@farm) WHERE "Status" NOT IN ('Cancelled', 'Reversed')
            ), entries(section, line, day, ref, description, amount) AS (
                SELECT 'revenue', CASE WHEN genericsubscriptionid IS NULL THEN 'Sales' ELSE 'Subscription income' END,
                       day, ref, description, revenue FROM sales
                UNION ALL
                SELECT 'direct', 'Cost of goods sold', s.day, s.ref, s.description, c.cost
                FROM costs c JOIN sales s ON s.genericsaleid = c.id
                UNION ALL
                SELECT 'direct', 'Stock losses', a.adjustmentdate::date, 'Adjustment #' || a.genericstockadjustmentid,
                       coalesce(a.reason, 'Stock decrease'), abs(coalesce(m.totalcostvalue, m.quantity * m.unitcost))
                FROM genericstockadjustments a JOIN genericstockmovements m ON m.farmid = a.farmid
                     AND m.referenceid = a.genericstockadjustmentid AND m.referencetype = 'Adjustment' AND m.movementtype = 'AdjustmentOut'
                WHERE a.farmid = @farm AND a.adjustmenttype = 'Decrease' AND a.status = 'Approved'
                  AND a.adjustmentdate >= @start AND a.adjustmentdate < @finish + 1
                UNION ALL
                SELECT CASE WHEN e.sourcetype = 'AssetDepreciation' OR lower(c.name) = 'depreciation' THEN 'other' ELSE 'operating' END,
                       CASE WHEN e.sourcetype = 'AssetDepreciation' THEN 'Depreciation' ELSE coalesce(c.name, 'Uncategorised expenses') END,
                       e.expensedate::date, 'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Expense'), e.amount
                FROM genericexpenses e LEFT JOIN genericexpensecategories c ON c.farmid = e.farmid AND c.genericexpensecategoryid = e.genericexpensecategoryid
                WHERE e.farmid = @farm AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
                  AND coalesce(e.sourcetype, '') NOT IN ('GenericPurchase', 'GenericSupplierPayment', 'Purchase', 'SupplierPayment')
                  AND e.expensedate >= @start AND e.expensedate < @finish + 1
                UNION ALL
                SELECT 'operating', 'Payroll', coalesce(p.paydate, p.paidat)::date, 'Payroll #' || p.genericpayrollrunid,
                       concat('Pay period ', p.periodstart::date, ' to ', p.periodend::date), p.totalgrosspay
                FROM genericpayrollruns p
                WHERE p.farmid = @farm AND p.status = 'Paid' AND NOT coalesce(p.isdeleted, false)
                  AND coalesce(p.paydate, p.paidat) >= @start AND coalesce(p.paydate, p.paidat) < @finish + 1
                  AND NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.farmid = p.farmid AND e.sourcetype = 'GenericPayrollRun'
                                  AND e.sourceid = p.genericpayrollrunid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false))
                UNION ALL
                SELECT 'owner', CASE WHEN entrytype = 'Contribution' THEN 'Owner contributions' ELSE 'Owner draws' END,
                       entrydate::date, coalesce(referenceno, 'Owner entry #' || genericownerentryid), coalesce(ownername, notes, 'Owner'),
                       CASE WHEN entrytype = 'Contribution' THEN amount ELSE -amount END
                FROM genericownercontributiondraws
                WHERE farmid = @farm AND status = 'Posted' AND entrydate >= @start AND entrydate < @finish + 1
                UNION ALL
                SELECT 'borrowing', 'Loan proceeds', "LoanDate"::date, 'Loan #' || "GenericLoanId", "LenderName", "AmountReceived"
                FROM loans WHERE "LoanDate" >= @start AND "LoanDate" < @finish + 1
                UNION ALL
                SELECT v.section, v.line, p."PaymentDate"::date, 'Payment #' || p."GenericLoanPaymentId", l."LenderName", v.amount
                FROM loans l CROSS JOIN LATERAL spgenericloan_payments(l."GenericLoanId", @farm) p
                CROSS JOIN LATERAL (VALUES ('borrowing', 'Principal repaid', -p."PrincipalAmount"),
                                           ('other', 'Loan interest', p."InterestAmount"),
                                           ('other', 'Loan fees', p."FeeAmount")) v(section, line, amount)
                WHERE NOT p."IsReversed" AND p."PaymentDate" >= @start AND p."PaymentDate" < @finish + 1
                UNION ALL
                SELECT 'capital', 'Asset purchases', "PurchaseDate"::date, 'Asset #' || "GenericAssetId", "AssetName", "PurchaseCost"
                FROM spgenericasset_list(@farm) WHERE "PurchaseDate" >= @start AND "PurchaseDate" < @finish + 1
            )
            SELECT section, line, day, ref, coalesce(description, ''), amount FROM entries
            WHERE amount <> 0 ORDER BY day DESC, ref, section, line
            """;
        using var connection = new NpgsqlConnection(_connectionString);
        using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("farm", NpgsqlDbType.Text, farmId);
        command.Parameters.AddWithValue("start", NpgsqlDbType.Date, from);
        command.Parameters.AddWithValue("finish", NpgsqlDbType.Date, to);

        await connection.OpenAsync(cancellationToken);
        using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var entries = new List<GenericProfitLossEntry>();
        while (await reader.ReadAsync(cancellationToken))
        {
            entries.Add(new GenericProfitLossEntry(reader.GetString(0), reader.GetString(1),
                reader.GetFieldValue<DateOnly>(2), reader.GetString(3), reader.GetString(4), reader.GetDecimal(5)));
        }
        return entries;
    }
}
