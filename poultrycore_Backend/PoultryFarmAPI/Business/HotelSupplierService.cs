using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelSupplierService : IHotelSupplierService
    {
        private readonly string _cs;
        public HotelSupplierService(string connectionString) { _cs = connectionString; }

        private static string? StrN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetString(o); }
        private static string Str(NpgsqlDataReader r, string col) => r.GetString(r.GetOrdinal(col));
        private static int Int(NpgsqlDataReader r, string col) => r.GetInt32(r.GetOrdinal(col));
        private static int? IntN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetInt32(o); }
        private static long Long(NpgsqlDataReader r, string col) => r.GetInt64(r.GetOrdinal(col));
        private static decimal Dec(NpgsqlDataReader r, string col) => r.GetDecimal(r.GetOrdinal(col));
        private static bool Bool(NpgsqlDataReader r, string col) => r.GetBoolean(r.GetOrdinal(col));
        private static DateTime Dt(NpgsqlDataReader r, string col) => r.GetDateTime(r.GetOrdinal(col));
        private static DateTime? DtN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetDateTime(o); }

        private static HotelSupplierModel MapSupplier(NpgsqlDataReader r) => new()
        {
            HotelSupplierId = Int(r, "hotelsupplierid"), FarmId = Str(r, "farmid"),
            SupplierName = Str(r, "suppliername"), SupplierType = StrN(r, "suppliertype") ?? "ProductSupplier",
            Phone = StrN(r, "phone"), Email = StrN(r, "email"), Location = StrN(r, "location"),
            Address = StrN(r, "address"), PaymentTermDays = Int(r, "paymenttermdays"),
            OpeningBalance = Dec(r, "openingbalance"), CurrentBalance = Dec(r, "currentbalance"),
            IsActive = Bool(r, "isactive"), Notes = StrN(r, "notes"), CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"), UpdatedAt = DtN(r, "updatedat"),
        };

        private static HotelSupplierLedgerEntryModel MapLedger(NpgsqlDataReader r) => new()
        {
            HotelSupplierLedgerId = Long(r, "hotelsupplierledgerid"), FarmId = Str(r, "farmid"),
            HotelSupplierId = Int(r, "hotelsupplierid"), TransactionDate = Dt(r, "transactiondate"),
            TransactionType = Str(r, "transactiontype"), ExpenseId = IntN(r, "expenseid"),
            PaymentId = IntN(r, "paymentid"), DebitAmount = Dec(r, "debitamount"),
            CreditAmount = Dec(r, "creditamount"), BalanceAfterTransaction = Dec(r, "balanceaftertransaction"),
            Description = StrN(r, "description"), CreatedBy = StrN(r, "createdby"), CreatedAt = Dt(r, "createdat"),
        };

        private static HotelSupplierPaymentModel MapPayment(NpgsqlDataReader r) => new()
        {
            HotelSupplierPaymentId = Int(r, "hotelsupplierpaymentid"), FarmId = Str(r, "farmid"),
            HotelSupplierId = Int(r, "hotelsupplierid"), SupplierName = StrN(r, "suppliername"),
            PaymentDate = Dt(r, "paymentdate"), Amount = Dec(r, "amount"), PaymentMethod = Str(r, "paymentmethod"),
            HotelCashAccountId = IntN(r, "hotelcashaccountid"), Reference = StrN(r, "reference"),
            LinkedExpenseId = IntN(r, "linkedexpenseid"), Status = Str(r, "status"), Notes = StrN(r, "notes"),
            CreatedBy = StrN(r, "createdby"), ApprovedBy = StrN(r, "approvedby"),
            ApprovedAt = DtN(r, "approvedat"), CreatedAt = Dt(r, "createdat"), UpdatedAt = DtN(r, "updatedat"),
        };

        public async Task<List<HotelSupplierModel>> GetAllAsync(string farmId)
        {
            var list = new List<HotelSupplierModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplier_getall(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapSupplier(r));
            return list;
        }

        public async Task<HotelSupplierModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplier_getbyid(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapSupplier(r) : null;
        }

        public async Task<int> InsertAsync(HotelSupplierModel m, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplier_insert(@f,@n,@t,@ph,@em,@loc,@addr,@terms,@open,@notes,@by)", conn);
            cmd.Parameters.AddWithValue("@f", m.FarmId); cmd.Parameters.AddWithValue("@n", m.SupplierName);
            cmd.Parameters.AddWithValue("@t", m.SupplierType ?? "ProductSupplier");
            cmd.Parameters.AddWithValue("@ph", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@em", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@loc", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@addr", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@terms", m.PaymentTermDays);
            cmd.Parameters.AddWithValue("@open", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(HotelSupplierModel m)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplier_update(@id,@f,@n,@t,@ph,@em,@loc,@addr,@terms,@notes,@active)", conn);
            cmd.Parameters.AddWithValue("@id", m.HotelSupplierId); cmd.Parameters.AddWithValue("@f", m.FarmId);
            cmd.Parameters.AddWithValue("@n", m.SupplierName); cmd.Parameters.AddWithValue("@t", m.SupplierType ?? "ProductSupplier");
            cmd.Parameters.AddWithValue("@ph", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@em", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@loc", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@addr", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@terms", m.PaymentTermDays);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@active", m.IsActive);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplier_delete(@id,@f)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelSupplierModel>> GetOwedAsync(string farmId)
        {
            var list = new List<HotelSupplierModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplier_getowedtothem(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new HotelSupplierModel { HotelSupplierId = Int(r,"hotelsupplierid"), FarmId = Str(r,"farmid"), SupplierName = Str(r,"suppliername"), SupplierType = StrN(r,"suppliertype") ?? "", Phone = StrN(r,"phone"), PaymentTermDays = Int(r,"paymenttermdays"), CurrentBalance = Dec(r,"currentbalance") });
            return list;
        }

        public async Task<HotelSupplierBalanceSummaryModel> GetBalanceSummaryAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplier_balancesummary(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new HotelSupplierBalanceSummaryModel { TotalSuppliers = Int(r,"totalsuppliers"), SuppliersOwed = Int(r,"suppliersowed"), TotalBalance = Dec(r,"totalbalance") };
            return new HotelSupplierBalanceSummaryModel();
        }

        public async Task<List<HotelSupplierLedgerEntryModel>> GetLedgerAsync(int supplierId, string farmId)
        {
            var list = new List<HotelSupplierLedgerEntryModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplierledger_getforsupplier(@sid,@f)", conn);
            cmd.Parameters.AddWithValue("@sid", supplierId); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapLedger(r));
            return list;
        }

        public async Task PostExpenseAsync(string farmId, int supplierId, int expenseId, decimal amount, string? description, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplier_postexpense(@f,@sid,@eid,@amt,@desc,@by)", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@sid", supplierId);
            cmd.Parameters.AddWithValue("@eid", expenseId); cmd.Parameters.AddWithValue("@amt", amount);
            cmd.Parameters.AddWithValue("@desc", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task PostAdjustmentAsync(string farmId, int supplierId, decimal amount, string? description, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplier_postadjustment(@f,@sid,@amt,@desc,@by)", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@sid", supplierId);
            cmd.Parameters.AddWithValue("@amt", amount);
            cmd.Parameters.AddWithValue("@desc", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelSupplierPaymentModel>> GetPaymentsAsync(string farmId, string? status)
        {
            var list = new List<HotelSupplierPaymentModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelsupplierpayment_getall(@f,@s)", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@s", (object?)status ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapPayment(r));
            return list;
        }

        public async Task<int> InsertPaymentAsync(HotelSupplierPaymentModel m, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplierpayment_insert(@f,@sid,@amt,@meth,@acct,@ref,@exp,@date,@notes,@by)", conn);
            cmd.Parameters.AddWithValue("@f", m.FarmId); cmd.Parameters.AddWithValue("@sid", m.HotelSupplierId);
            cmd.Parameters.AddWithValue("@amt", m.Amount); cmd.Parameters.AddWithValue("@meth", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@acct", (object?)m.HotelCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ref", (object?)m.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@exp", (object?)m.LinkedExpenseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", m.PaymentDate == default ? DBNull.Value : (object)m.PaymentDate);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApprovePaymentAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplierpayment_approve(@id,@f,@by)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@by", (object?)approvedBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelPaymentAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelsupplierpayment_cancel(@id,@f)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
