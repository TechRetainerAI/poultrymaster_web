using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Customer Credits
    // =========================================================================
    public interface IGenericCustomerCreditService
    {
        Task<List<GenericCustomerCreditModel>> ListAsync(string farmId);
        Task<int> CreateAsync(GenericCustomerCreditCreateRequest r);
    }

    public class GenericCustomerCreditService : IGenericCustomerCreditService
    {
        private readonly string _cs; public GenericCustomerCreditService(string cs) => _cs = cs;

        public async Task<List<GenericCustomerCreditModel>> ListAsync(string farmId)
        {
            var list = new List<GenericCustomerCreditModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomercredit_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericCustomerCreditModel
            {
                GenericCustomerCreditId = r.Int("GenericCustomerCreditId"),
                FarmId = r.Str("FarmId"), GenericCustomerId = r.Int("GenericCustomerId"),
                CustomerName = r.StrN("CustomerName"), CreditType = r.Str("CreditType"),
                Amount = r.Dec("Amount"), RemainingBalance = r.Dec("RemainingBalance"),
                CreditDate = r.Date("CreditDate"), Notes = r.StrN("Notes"),
                Status = r.Str("Status"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericCustomerCreditCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericcustomercredit_create(" +
                "p_farmid=>@FarmId::text, p_customerid=>@CustomerId::int, p_credittype=>@CreditType::varchar, " +
                "p_amount=>@Amount::numeric, p_creditdate=>@CreditDate::timestamp, " +
                "p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", m.GenericCustomerId);
            cmd.Parameters.AddWithValue("@CreditType", m.CreditType);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@CreditDate", (object?)m.CreditDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    // =========================================================================
    // Supplier Credits
    // =========================================================================
    public interface IGenericSupplierCreditService
    {
        Task<List<GenericSupplierCreditModel>> ListAsync(string farmId);
        Task<int> CreateAsync(GenericSupplierCreditCreateRequest r);
    }

    public class GenericSupplierCreditService : IGenericSupplierCreditService
    {
        private readonly string _cs; public GenericSupplierCreditService(string cs) => _cs = cs;

        public async Task<List<GenericSupplierCreditModel>> ListAsync(string farmId)
        {
            var list = new List<GenericSupplierCreditModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericsuppliercredit_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericSupplierCreditModel
            {
                GenericSupplierCreditId = r.Int("GenericSupplierCreditId"),
                FarmId = r.Str("FarmId"), GenericSupplierId = r.Int("GenericSupplierId"),
                SupplierName = r.StrN("SupplierName"), CreditType = r.Str("CreditType"),
                Amount = r.Dec("Amount"), RemainingBalance = r.Dec("RemainingBalance"),
                CreditDate = r.Date("CreditDate"), Notes = r.StrN("Notes"),
                Status = r.Str("Status"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericSupplierCreditCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericsuppliercredit_create(" +
                "p_farmid=>@FarmId::text, p_supplierid=>@SupplierId::int, p_credittype=>@CreditType::varchar, " +
                "p_amount=>@Amount::numeric, p_creditdate=>@CreditDate::timestamp, " +
                "p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierId", m.GenericSupplierId);
            cmd.Parameters.AddWithValue("@CreditType", m.CreditType);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@CreditDate", (object?)m.CreditDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    // =========================================================================
    // Deferred Inventory Cost (read-only report)
    // =========================================================================
    public interface IGenericDeferredCostService
    {
        Task<List<GenericDeferredCostRow>> ListAsync(string farmId);
    }

    public class GenericDeferredCostService : IGenericDeferredCostService
    {
        private readonly string _cs; public GenericDeferredCostService(string cs) => _cs = cs;

        public async Task<List<GenericDeferredCostRow>> ListAsync(string farmId)
        {
            var list = new List<GenericDeferredCostRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdeferredcost_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericDeferredCostRow
            {
                GenericProductId = r.Int("GenericProductId"),
                ProductName = r.Str("ProductName"),
                TotalPurchased = r.Dec("TotalPurchased"),
                TotalSoldCost = r.Dec("TotalSoldCost"),
                DeferredBalance = r.Dec("DeferredBalance"),
                CurrentStock = r.Dec("CurrentStock"),
            });
            return list;
        }
    }
}
