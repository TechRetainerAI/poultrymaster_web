using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericDeliveryService
    {
        Task<List<GenericDeliveryModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<int> LoadAsync(GenericDeliveryLoadRequest r);
        Task ReconcileAsync(int id, GenericDeliveryReconcileRequest r);
        Task ReverseAsync(int id, string farmId);
        Task CancelAsync(int id, string farmId);
        Task DispatchAsync(int id, string farmId);
        Task MarkDeliveredAsync(int id, string farmId);
    }

    public class GenericDeliveryService : IGenericDeliveryService
    {
        private readonly string _cs; public GenericDeliveryService(string cs) => _cs = cs;

        public async Task<List<GenericDeliveryModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericDeliveryModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericDeliveryModel
            {
                GenericDeliveryId = r.Int("GenericDeliveryId"),
                FarmId = r.Str("FarmId"),
                DeliveryDate = r.Date("DeliveryDate"),
                DriverName = r.StrN("DriverName"),
                VehicleName = r.StrN("VehicleName"),
                Route = r.StrN("Route"),
                GenericProductId = r.Int("GenericProductId"),
                ProductName = r.StrN("ProductName"),
                QuantityLoaded = r.Dec("QuantityLoaded"),
                Unit = r.StrN("Unit"),
                UnitPrice = r.Dec("UnitPrice"),
                QuantitySold = r.Dec("QuantitySold"),
                QuantityReturned = r.Dec("QuantityReturned"),
                QuantityDamaged = r.Dec("QuantityDamaged"),
                QuantityShort = r.Dec("QuantityShort"),
                CashCollected = r.Dec("CashCollected"),
                CreditSales = r.Dec("CreditSales"),
                DeliveryExpenses = r.Dec("DeliveryExpenses"),
                TotalSales = r.Dec("TotalSales"),
                CustomerName = r.StrN("CustomerName"),
                Destination = r.StrN("Destination"),
                Status = r.Str("Status"),
                Notes = r.StrN("Notes"),
                CreatedAt = r.Date("CreatedAt"),
                ReconciledAt = r.DateN("ReconciledAt"),
                DeliveredAt = r.DateN("DeliveredAt"),
                DeliveredBy = r.StrN("DeliveredBy"),
            });
            return list;
        }

        public async Task<int> LoadAsync(GenericDeliveryLoadRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_load(" +
                "p_farmid => @FarmId::text, p_deliverydate => @DeliveryDate::timestamp, " +
                "p_drivername => @DriverName::text, p_vehiclename => @VehicleName::text, " +
                "p_route => @Route::text, p_genericproductid => @GenericProductId::int, " +
                "p_quantityloaded => @QuantityLoaded::numeric, p_unit => @Unit::text, " +
                "p_unitprice => @UnitPrice::numeric, p_notes => @Notes::text, " +
                "p_createdby => @CreatedBy::text, p_customername => @CustomerName::text, " +
                "p_destination => @Destination::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DeliveryDate", (object?)m.DeliveryDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DriverName", (object?)m.DriverName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@VehicleName", (object?)m.VehicleName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Route", (object?)m.Route ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericProductId", m.GenericProductId);
            cmd.Parameters.AddWithValue("@QuantityLoaded", m.QuantityLoaded);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CustomerName", (object?)m.CustomerName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Destination", (object?)m.Destination ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReconcileAsync(int id, GenericDeliveryReconcileRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_reconcile(" +
                "p_genericdeliveryid => @Id::int, p_farmid => @FarmId::text, " +
                "p_quantitysold => @QuantitySold::numeric, p_quantityreturned => @QuantityReturned::numeric, " +
                "p_quantitydamaged => @QuantityDamaged::numeric, p_quantityshort => @QuantityShort::numeric, " +
                "p_cashcollected => @CashCollected::numeric, p_creditsales => @CreditSales::numeric, " +
                "p_deliveryexpenses => @DeliveryExpenses::numeric, p_reconciledby => @ReconciledBy::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@QuantitySold", m.QuantitySold);
            cmd.Parameters.AddWithValue("@QuantityReturned", m.QuantityReturned);
            cmd.Parameters.AddWithValue("@QuantityDamaged", m.QuantityDamaged);
            cmd.Parameters.AddWithValue("@QuantityShort", m.QuantityShort);
            cmd.Parameters.AddWithValue("@CashCollected", m.CashCollected);
            cmd.Parameters.AddWithValue("@CreditSales", m.CreditSales);
            cmd.Parameters.AddWithValue("@DeliveryExpenses", m.DeliveryExpenses);
            cmd.Parameters.AddWithValue("@ReconciledBy", (object?)m.ReconciledBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_reverse(p_genericdeliveryid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_cancel(p_genericdeliveryid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DispatchAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_dispatch(p_genericdeliveryid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task MarkDeliveredAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdelivery_markdelivered(p_genericdeliveryid => @Id::int, p_farmid => @FarmId::text, p_deliveredby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@By", DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
