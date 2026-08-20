using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryDeliveryService
    {
        Task<List<PoultryDeliveryModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<int> LoadAsync(PoultryDeliveryLoadRequest r);
        Task ReconcileAsync(int id, PoultryDeliveryReconcileRequest r);
        Task ReverseAsync(int id, string farmId);
        Task CancelAsync(int id, string farmId);
    }

    public class PoultryDeliveryService : IPoultryDeliveryService
    {
        private readonly string _cs; public PoultryDeliveryService(string cs) => _cs = cs;

        public async Task<List<PoultryDeliveryModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDeliveryModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydelivery_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryDeliveryModel
            {
                PoultryDeliveryId = r.Int("PoultryDeliveryId"), FarmId = r.Str("FarmId"), DeliveryDate = r.Date("DeliveryDate"),
                DriverName = r.StrN("DriverName"), VehicleName = r.StrN("VehicleName"), Route = r.StrN("Route"),
                PoultryProductId = r.Int("PoultryProductId"), ProductName = r.StrN("ProductName"),
                QuantityLoaded = r.Dec("QuantityLoaded"), Unit = r.StrN("Unit"), UnitPrice = r.Dec("UnitPrice"),
                QuantitySold = r.Dec("QuantitySold"), QuantityReturned = r.Dec("QuantityReturned"), QuantityBroken = r.Dec("QuantityBroken"), QuantityShort = r.Dec("QuantityShort"),
                CashCollected = r.Dec("CashCollected"), CreditSales = r.Dec("CreditSales"), DeliveryExpenses = r.Dec("DeliveryExpenses"),
                TotalSales = r.Has("TotalSales") ? r.Dec("TotalSales") : 0, CashVariance = r.Has("CashVariance") ? r.Dec("CashVariance") : 0,
                Status = r.Str("Status"), Notes = r.StrN("Notes"), CreatedAt = r.Date("CreatedAt"), ReconciledAt = r.DateN("ReconciledAt"),
            });
            return list;
        }

        public async Task<int> LoadAsync(PoultryDeliveryLoadRequest m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydelivery_load(p_farmid => @FarmId::text, p_deliverydate => @DeliveryDate::timestamp, p_drivername => @DriverName::text, p_vehiclename => @VehicleName::text, p_route => @Route::text, p_poultryproductid => @PoultryProductId::int, p_quantityloaded => @QuantityLoaded::numeric, p_unit => @Unit::text, p_unitprice => @UnitPrice::numeric, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DeliveryDate", (object?)m.DeliveryDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DriverName", (object?)m.DriverName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@VehicleName", (object?)m.VehicleName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Route", (object?)m.Route ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId);
            cmd.Parameters.AddWithValue("@QuantityLoaded", m.QuantityLoaded);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReconcileAsync(int id, PoultryDeliveryReconcileRequest m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydelivery_reconcile(p_poultrydeliveryid => @PoultryDeliveryId::int, p_farmid => @FarmId::text, p_quantitysold => @QuantitySold::numeric, p_quantityreturned => @QuantityReturned::numeric, p_quantitybroken => @QuantityBroken::numeric, p_quantityshort => @QuantityShort::numeric, p_cashcollected => @CashCollected::numeric, p_creditsales => @CreditSales::numeric, p_deliveryexpenses => @DeliveryExpenses::numeric, p_paymentmethod => @PaymentMethod::text, p_reconciledby => @ReconciledBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDeliveryId", id);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@QuantitySold", m.QuantitySold);
            cmd.Parameters.AddWithValue("@QuantityReturned", m.QuantityReturned);
            cmd.Parameters.AddWithValue("@QuantityBroken", m.QuantityBroken);
            cmd.Parameters.AddWithValue("@QuantityShort", m.QuantityShort);
            cmd.Parameters.AddWithValue("@CashCollected", m.CashCollected);
            cmd.Parameters.AddWithValue("@CreditSales", m.CreditSales);
            cmd.Parameters.AddWithValue("@DeliveryExpenses", m.DeliveryExpenses);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? "Cash");
            cmd.Parameters.AddWithValue("@ReconciledBy", (object?)m.ReconciledBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydelivery_reverse(p_poultrydeliveryid => @PoultryDeliveryId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDeliveryId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydelivery_cancel(p_poultrydeliveryid => @PoultryDeliveryId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDeliveryId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }
}
