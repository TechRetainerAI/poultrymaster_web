using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelCustomerService : IHotelCustomerService
    {
        private readonly string _cs;
        public HotelCustomerService(string connectionString) { _cs = connectionString; }

        private static string? StrN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetString(o); }
        private static string Str(NpgsqlDataReader r, string col) => r.GetString(r.GetOrdinal(col));
        private static int Int(NpgsqlDataReader r, string col) => r.GetInt32(r.GetOrdinal(col));
        private static int? IntN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetInt32(o); }
        private static long Long(NpgsqlDataReader r, string col) => r.GetInt64(r.GetOrdinal(col));
        private static decimal Dec(NpgsqlDataReader r, string col) => r.GetDecimal(r.GetOrdinal(col));
        private static bool Bool(NpgsqlDataReader r, string col) => r.GetBoolean(r.GetOrdinal(col));
        private static DateTime Dt(NpgsqlDataReader r, string col) => r.GetDateTime(r.GetOrdinal(col));
        private static DateTime? DtN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetDateTime(o); }

        private static HotelCustomerModel MapCustomer(NpgsqlDataReader r) => new()
        {
            HotelCustomerId = Int(r, "hotelcustomerid"),
            FarmId = Str(r, "farmid"),
            CustomerName = Str(r, "customername"),
            CustomerType = StrN(r, "customertype") ?? "Corporate",
            Phone = StrN(r, "phone"),
            Email = StrN(r, "email"),
            Address = StrN(r, "address"),
            City = StrN(r, "city"),
            PaymentTermDays = Int(r, "paymenttermdays"),
            CreditLimit = Dec(r, "creditlimit"),
            OpeningBalance = Dec(r, "openingbalance"),
            CurrentBalance = Dec(r, "currentbalance"),
            IsActive = Bool(r, "isactive"),
            Notes = StrN(r, "notes"),
            CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"),
            UpdatedAt = DtN(r, "updatedat"),
        };

        private static HotelCustomerLedgerEntryModel MapLedger(NpgsqlDataReader r) => new()
        {
            HotelCustomerLedgerId = Long(r, "hotelcustomerledgerid"),
            FarmId = Str(r, "farmid"),
            HotelCustomerId = Int(r, "hotelcustomerid"),
            TransactionDate = Dt(r, "transactiondate"),
            TransactionType = Str(r, "transactiontype"),
            InvoiceId = IntN(r, "invoiceid"),
            PaymentId = IntN(r, "paymentid"),
            DebitAmount = Dec(r, "debitamount"),
            CreditAmount = Dec(r, "creditamount"),
            BalanceAfterTransaction = Dec(r, "balanceaftertransaction"),
            Description = StrN(r, "description"),
            CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"),
        };

        private static HotelCustomerPaymentModel MapPayment(NpgsqlDataReader r) => new()
        {
            HotelCustomerPaymentId = Int(r, "hotelcustomerpaymentid"),
            FarmId = Str(r, "farmid"),
            HotelCustomerId = Int(r, "hotelcustomerid"),
            CustomerName = StrN(r, "customername"),
            PaymentDate = Dt(r, "paymentdate"),
            Amount = Dec(r, "amount"),
            PaymentMethod = Str(r, "paymentmethod"),
            HotelCashAccountId = IntN(r, "hotelcashaccountid"),
            Reference = StrN(r, "reference"),
            LinkedInvoiceId = IntN(r, "linkedinvoiceid"),
            Status = Str(r, "status"),
            Notes = StrN(r, "notes"),
            CreatedBy = StrN(r, "createdby"),
            ApprovedBy = StrN(r, "approvedby"),
            ApprovedAt = DtN(r, "approvedat"),
            CreatedAt = Dt(r, "createdat"),
            UpdatedAt = DtN(r, "updatedat"),
        };

        // ── Customers ────────────────────────────────────────────────────────

        public async Task<List<HotelCustomerModel>> GetAllAsync(string farmId)
        {
            var list = new List<HotelCustomerModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomer_getall(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapCustomer(r));
            return list;
        }

        public async Task<HotelCustomerModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomer_getbyid(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapCustomer(r) : null;
        }

        public async Task<int> InsertAsync(HotelCustomerModel m, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelcustomer_insert(@f, @name, @type, @phone, @email, @addr, @city, @terms, @limit, @opening, @notes, @by)", conn);
            cmd.Parameters.AddWithValue("@f", m.FarmId);
            cmd.Parameters.AddWithValue("@name", m.CustomerName);
            cmd.Parameters.AddWithValue("@type", m.CustomerType ?? "Corporate");
            cmd.Parameters.AddWithValue("@phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@addr", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@city", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@terms", m.PaymentTermDays);
            cmd.Parameters.AddWithValue("@limit", m.CreditLimit);
            cmd.Parameters.AddWithValue("@opening", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(HotelCustomerModel m)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelcustomer_update(@id, @f, @name, @type, @phone, @email, @addr, @city, @terms, @limit, @notes, @active)", conn);
            cmd.Parameters.AddWithValue("@id", m.HotelCustomerId);
            cmd.Parameters.AddWithValue("@f", m.FarmId);
            cmd.Parameters.AddWithValue("@name", m.CustomerName);
            cmd.Parameters.AddWithValue("@type", m.CustomerType ?? "Corporate");
            cmd.Parameters.AddWithValue("@phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@addr", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@city", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@terms", m.PaymentTermDays);
            cmd.Parameters.AddWithValue("@limit", m.CreditLimit);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@active", m.IsActive);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcustomer_delete(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelCustomerOwedRowModel>> GetOwedAsync(string farmId)
        {
            var list = new List<HotelCustomerOwedRowModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomer_getowedthem(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new HotelCustomerOwedRowModel
                {
                    HotelCustomerId = Int(r, "hotelcustomerid"),
                    FarmId = Str(r, "farmid"),
                    CustomerName = Str(r, "customername"),
                    CustomerType = StrN(r, "customertype"),
                    Phone = StrN(r, "phone"),
                    PaymentTermDays = Int(r, "paymenttermdays"),
                    CurrentBalance = Dec(r, "currentbalance"),
                });
            return list;
        }

        public async Task<HotelCustomerBalanceSummaryModel> GetBalanceSummaryAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomer_balancesummary(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
                return new HotelCustomerBalanceSummaryModel
                {
                    TotalCustomers = Int(r, "totalcustomers"),
                    CustomersOwing = Int(r, "customersowing"),
                    TotalBalance = Dec(r, "totalbalance"),
                    TotalOverdueCount = Int(r, "totaloverduecount"),
                };
            return new HotelCustomerBalanceSummaryModel();
        }

        // ── Ledger ────────────────────────────────────────────────────────────

        public async Task<List<HotelCustomerLedgerEntryModel>> GetLedgerAsync(int customerId, string farmId)
        {
            var list = new List<HotelCustomerLedgerEntryModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomerledger_getforcustomer(@cid, @f)", conn);
            cmd.Parameters.AddWithValue("@cid", customerId);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapLedger(r));
            return list;
        }

        public async Task PostInvoiceAsync(string farmId, int customerId, int invoiceId, decimal amount, string? description, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcustomer_postinvoice(@f, @cid, @inv, @amt, @desc, @by)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@cid", customerId);
            cmd.Parameters.AddWithValue("@inv", invoiceId);
            cmd.Parameters.AddWithValue("@amt", amount);
            cmd.Parameters.AddWithValue("@desc", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task PostAdjustmentAsync(string farmId, int customerId, decimal amount, string? description, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcustomer_postadjustment(@f, @cid, @amt, @desc, @by)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@cid", customerId);
            cmd.Parameters.AddWithValue("@amt", amount);
            cmd.Parameters.AddWithValue("@desc", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        // ── Payments ─────────────────────────────────────────────────────────

        public async Task<List<HotelCustomerPaymentModel>> GetPaymentsAsync(string farmId, string? status)
        {
            var list = new List<HotelCustomerPaymentModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomerpayment_getall(@f, @s)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@s", (object?)status ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapPayment(r));
            return list;
        }

        public async Task<HotelCustomerPaymentModel?> GetPaymentByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcustomerpayment_getbyid(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapPayment(r) : null;
        }

        public async Task<int> InsertPaymentAsync(HotelCustomerPaymentModel m, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelcustomerpayment_insert(@f, @cid, @amt, @method, @acct, @ref, @inv, @date, @notes, @by)", conn);
            cmd.Parameters.AddWithValue("@f", m.FarmId);
            cmd.Parameters.AddWithValue("@cid", m.HotelCustomerId);
            cmd.Parameters.AddWithValue("@amt", m.Amount);
            cmd.Parameters.AddWithValue("@method", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@acct", (object?)m.HotelCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ref", (object?)m.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@inv", (object?)m.LinkedInvoiceId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", m.PaymentDate == default ? DBNull.Value : (object)m.PaymentDate);
            cmd.Parameters.AddWithValue("@notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApprovePaymentAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcustomerpayment_approve(@id, @f, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@by", (object?)approvedBy ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelPaymentAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcustomerpayment_cancel(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
