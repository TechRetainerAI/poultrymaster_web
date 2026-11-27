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
                ReferenceType = r.StrN("ReferenceType"),
                ReferenceId = r.IsDBNull(r.GetOrdinal("ReferenceId")) ? null : r.GetInt32(r.GetOrdinal("ReferenceId")),
                Status = r.Str("Status"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericCustomerCreditCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            // 501: the project split (if any) is saved in the same statement.
            const string createCall = "spgenericcustomercredit_create(" +
                "p_farmid=>@FarmId::text, p_customerid=>@CustomerId::int, p_credittype=>@CreditType::varchar, " +
                "p_amount=>@Amount::numeric, p_creditdate=>@CreditDate::timestamp, " +
                "p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)";
            var withProject = GenericProjectAttach.Has(m.Projects);
            using var cmd = new NpgsqlCommand(withProject
                ? GenericProjectAttach.WrapInsert(createCall, "CustomerCredit")
                : "SELECT * FROM " + createCall, c);
            if (withProject) GenericProjectAttach.AddParams(cmd, m.FarmId, m.Projects, m.CreatedBy);
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
    // Credit Applications (Phase A — read-only, written by spgenericsale_approve)
    // =========================================================================
    public interface IGenericCustomerCreditApplicationService
    {
        Task<List<GenericCustomerCreditApplicationModel>> ListAsync(string farmId);
    }

    public class GenericCustomerCreditApplicationService : IGenericCustomerCreditApplicationService
    {
        private readonly string _cs; public GenericCustomerCreditApplicationService(string cs) => _cs = cs;

        public async Task<List<GenericCustomerCreditApplicationModel>> ListAsync(string farmId)
        {
            var list = new List<GenericCustomerCreditApplicationModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomercreditapplication_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericCustomerCreditApplicationModel
            {
                GenericCustomerCreditApplicationId = r.Int("GenericCustomerCreditApplicationId"),
                FarmId = r.Str("FarmId"), GenericCustomerId = r.Int("GenericCustomerId"),
                CustomerName = r.StrN("CustomerName"), GenericSaleId = r.Int("GenericSaleId"),
                ReceiptNumber = r.StrN("ReceiptNumber"), AmountApplied = r.Dec("AmountApplied"),
                ApplicationDate = r.Date("ApplicationDate"), Description = r.StrN("Description"),
                CreatedBy = r.StrN("CreatedBy"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }
    }

    // =========================================================================
    // Bulk Payment (Phase B)
    // =========================================================================
    public interface IGenericBulkPaymentService
    {
        Task<Guid> BulkInsertAsync(GenericBulkPaymentRequest req);
    }

    public class GenericBulkPaymentService : IGenericBulkPaymentService
    {
        private readonly string _cs; public GenericBulkPaymentService(string cs) => _cs = cs;

        public async Task<Guid> BulkInsertAsync(GenericBulkPaymentRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericcustomerpayment_bulkinsert(" +
                "p_farmid=>@FarmId::text, p_genericcustomerid=>@CustomerId::int, " +
                "p_paymentmethod=>@PaymentMethod::text, p_genericcashaccountid=>@CashAccountId::int, " +
                "p_receivedbystaffid=>@StaffId::int, p_paymentdate=>@PaymentDate::timestamp, " +
                "p_notes=>@Notes::text, p_createdby=>@CreatedBy::text, p_allocations=>@Allocations::jsonb)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", req.GenericCustomerId);
            cmd.Parameters.AddWithValue("@PaymentMethod", req.PaymentMethod);
            cmd.Parameters.AddWithValue("@CashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StaffId", (object?)req.ReceivedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate", (object?)req.PaymentDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);

            var allocJson = System.Text.Json.JsonSerializer.Serialize(
                req.Allocations.Select(a => new { saleid = a.SaleId, amount = a.Amount }));
            cmd.Parameters.Add(new NpgsqlParameter("@Allocations", NpgsqlTypes.NpgsqlDbType.Jsonb) { Value = allocJson });

            await c.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is Guid g ? g : Guid.Parse(result!.ToString()!);
        }
    }

    // =========================================================================
    // Credit Refunds (Phase C)
    // =========================================================================
    public interface IGenericCustomerCreditRefundService
    {
        Task<List<GenericCustomerCreditRefundModel>> ListAsync(string farmId);
        Task<int> CreateAsync(GenericCustomerCreditRefundRequest req);
    }

    public class GenericCustomerCreditRefundService : IGenericCustomerCreditRefundService
    {
        private readonly string _cs; public GenericCustomerCreditRefundService(string cs) => _cs = cs;

        public async Task<List<GenericCustomerCreditRefundModel>> ListAsync(string farmId)
        {
            var list = new List<GenericCustomerCreditRefundModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomercreditrefund_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericCustomerCreditRefundModel
            {
                GenericCustomerCreditRefundId = r.Int("GenericCustomerCreditRefundId"),
                FarmId = r.Str("FarmId"), GenericCustomerId = r.Int("GenericCustomerId"),
                CustomerName = r.StrN("CustomerName"), Amount = r.Dec("Amount"),
                RefundMethod = r.Str("RefundMethod"),
                GenericCashAccountId = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.Int("GenericCashAccountId"),
                AccountName = r.StrN("AccountName"),
                RefundDate = r.Date("RefundDate"), Reason = r.StrN("Reason"),
                Status = r.Str("Status"), CreatedBy = r.StrN("CreatedBy"),
                ApprovedBy = r.StrN("ApprovedBy"), CreatedAt = r.Date("CreatedAt"),
                ApprovedAt = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.Date("ApprovedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericCustomerCreditRefundRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericcustomercreditrefund_create(" +
                "p_farmid=>@FarmId::text, p_genericcustomerid=>@CustomerId::int, " +
                "p_amount=>@Amount::numeric, p_refundmethod=>@RefundMethod::text, " +
                "p_genericcashaccountid=>@CashAccountId::int, p_reason=>@Reason::text, " +
                "p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", req.GenericCustomerId);
            cmd.Parameters.AddWithValue("@Amount", req.Amount);
            cmd.Parameters.AddWithValue("@RefundMethod", req.RefundMethod);
            cmd.Parameters.AddWithValue("@CashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)req.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
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
