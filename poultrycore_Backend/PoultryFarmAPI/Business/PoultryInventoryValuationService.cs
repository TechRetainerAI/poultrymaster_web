// Poultry inventory valuation (migrations 267 and 268).
//
// Reads only. Everything that decides what a valuation MEANS lives in the SQL
// functions -- fnpoultryinventoryvaluation and fnpoultrycostlayeraudit -- so
// there is exactly one definition of each number and this file only maps rows.
//
// The three reads are issued as one batch because they are one screen: a summary
// that disagreed with the item list underneath it, because a purchase landed
// between two round trips, would be worse than a slower page.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryInventoryValuationService
    {
        Task<PoultryInventoryValuationResponse> GetAsync(string farmId);
    }

    public class PoultryInventoryValuationService : IPoultryInventoryValuationService
    {
        private readonly string _cs;
        public PoultryInventoryValuationService(string cs) => _cs = cs;

        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }

        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }

        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }

        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }

        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }

        public async Task<PoultryInventoryValuationResponse> GetAsync(string farmId)
        {
            var res = new PoultryInventoryValuationResponse();

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryinventoryvaluation_summary(p_farmid => @FarmId::text); " +
                "SELECT * FROM sppoultryinventoryvaluation_getall(p_farmid => @FarmId::text); " +
                "SELECT * FROM sppoultrycostlayeraudit_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync())
            {
                res.Summary = new PoultryInventoryValuationSummaryModel
                {
                    ItemsWithStock = Int(r, "ItemsWithStock"),
                    OperationalValue = Dec(r, "OperationalValue"),
                    DeferredValue = Dec(r, "DeferredValue"),
                    ItemsDeferring = Int(r, "ItemsDeferring"),
                    OpenLots = Int(r, "OpenLots"),
                    DeferredLots = Int(r, "DeferredLots"),
                    ItemsWithDrift = Int(r, "ItemsWithDrift"),
                    AuditFindings = Int(r, "AuditFindings"),
                };
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    res.Items.Add(new PoultryInventoryValuationModel
                    {
                        PoultryRawMaterialItemId = Int(r, "PoultryRawMaterialItemId"),
                        ItemName = StrN(r, "ItemName"),
                        Category = StrN(r, "Category"),
                        UnitOfMeasure = StrN(r, "UnitOfMeasure"),
                        UsageMethod = StrN(r, "UsageMethod"),
                        EffectiveMethod = StrN(r, "EffectiveMethod"),
                        CostRecognitionSource = StrN(r, "CostRecognitionSource"),
                        PhysicalQuantity = Dec(r, "PhysicalQuantity"),
                        CostLayerQuantity = Dec(r, "CostLayerQuantity"),
                        QuantityDrift = Dec(r, "QuantityDrift"),
                        OperationalValue = Dec(r, "OperationalValue"),
                        DeferredValue = Dec(r, "DeferredValue"),
                        OpenLots = Int(r, "OpenLots"),
                        DeferredLots = Int(r, "DeferredLots"),
                    });
                }
            }

            // Silent on a healthy farm, so an empty list here is the good case.
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    res.AuditFindings.Add(new PoultryCostLayerAuditModel
                    {
                        Finding = StrN(r, "Finding"),
                        Severity = StrN(r, "Severity"),
                        ItemId = IntN(r, "ItemId"),
                        ItemName = StrN(r, "ItemName"),
                        PurchaseId = IntN(r, "PurchaseId"),
                        Amount = DecN(r, "Amount"),
                        Detail = StrN(r, "Detail"),
                    });
                }
            }

            return res;
        }
    }
}
