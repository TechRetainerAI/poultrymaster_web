using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericCustomerService : IGenericCustomerService
    {
        private readonly string _connectionString;
        public GenericCustomerService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Customers
        // ====================================================================
        public async Task<List<GenericCustomerModel>> GetAllAsync(string farmId)
        {
            var list = new List<GenericCustomerModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadCustomer(reader));
            return list;
        }

        public async Task<GenericCustomerModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_getbyid(p_genericcustomerid => @GenericCustomerId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadCustomer(reader) : null;
        }

        public async Task<int> InsertAsync(GenericCustomerModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_insert(p_farmid => @FarmId::text, p_customername => @CustomerName::text, p_customertype => @CustomerType::text, p_phonenumber => @PhoneNumber::text, p_email => @Email::text, p_location => @Location::text, p_address => @Address::text, p_creditlimit => @CreditLimit::numeric, p_paymenttermsdays => @PaymentTermsDays::int, p_openingbalance => @OpeningBalance::numeric, p_assignedstaffid => @AssignedStaffId::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@CustomerName", m.CustomerName);
            cmd.Parameters.AddWithValue("@CustomerType", m.CustomerType);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreditLimit", m.CreditLimit);
            cmd.Parameters.AddWithValue("@PaymentTermsDays", m.PaymentTermsDays);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@AssignedStaffId", (object?)m.AssignedStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(GenericCustomerModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_update(p_genericcustomerid => @GenericCustomerId::int, p_farmid => @FarmId::text, p_customername => @CustomerName::text, p_customertype => @CustomerType::text, p_phonenumber => @PhoneNumber::text, p_email => @Email::text, p_location => @Location::text, p_address => @Address::text, p_creditlimit => @CreditLimit::numeric, p_paymenttermsdays => @PaymentTermsDays::int, p_assignedstaffid => @AssignedStaffId::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerId", m.GenericCustomerId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@CustomerName", m.CustomerName);
            cmd.Parameters.AddWithValue("@CustomerType", m.CustomerType);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreditLimit", m.CreditLimit);
            cmd.Parameters.AddWithValue("@PaymentTermsDays", m.PaymentTermsDays);
            cmd.Parameters.AddWithValue("@AssignedStaffId", (object?)m.AssignedStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_delete(p_genericcustomerid => @GenericCustomerId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericCustomerOwingRowModel>> GetOwingMoneyAsync(string farmId)
        {
            var list = new List<GenericCustomerOwingRowModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomer_getowingmoney(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCustomerOwingRowModel
                {
                    GenericCustomerId = reader.GetInt32(reader.GetOrdinal("GenericCustomerId")),
                    FarmId            = reader.GetString(reader.GetOrdinal("FarmId")),
                    CustomerName      = reader.GetString(reader.GetOrdinal("CustomerName")),
                    CustomerType      = reader.IsDBNull(reader.GetOrdinal("CustomerType")) ? null : reader.GetString(reader.GetOrdinal("CustomerType")),
                    PhoneNumber       = reader.IsDBNull(reader.GetOrdinal("PhoneNumber")) ? null : reader.GetString(reader.GetOrdinal("PhoneNumber")),
                    CreditLimit       = reader.GetDecimal(reader.GetOrdinal("CreditLimit")),
                    CurrentBalance    = reader.GetDecimal(reader.GetOrdinal("CurrentBalance")),
                    IsOverLimit       = reader.GetInt32(reader.GetOrdinal("IsOverLimit")) == 1,
                });
            }
            return list;
        }

        // ====================================================================
        // Ledger
        // ====================================================================
        public async Task<List<GenericCustomerLedgerEntryModel>> GetLedgerAsync(int customerId, string farmId)
        {
            var list = new List<GenericCustomerLedgerEntryModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerledger_getforcustomer(p_genericcustomerid => @GenericCustomerId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerId", customerId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCustomerLedgerEntryModel
                {
                    GenericCustomerLedgerId = reader.GetInt64(reader.GetOrdinal("GenericCustomerLedgerId")),
                    FarmId                  = reader.GetString(reader.GetOrdinal("FarmId")),
                    GenericCustomerId       = reader.GetInt32(reader.GetOrdinal("GenericCustomerId")),
                    TransactionDate         = reader.GetDateTime(reader.GetOrdinal("TransactionDate")),
                    TransactionType         = reader.GetString(reader.GetOrdinal("TransactionType")),
                    SaleId                  = reader.IsDBNull(reader.GetOrdinal("SaleId")) ? null : reader.GetInt32(reader.GetOrdinal("SaleId")),
                    PaymentId               = reader.IsDBNull(reader.GetOrdinal("PaymentId")) ? null : reader.GetInt32(reader.GetOrdinal("PaymentId")),
                    DebitAmount             = reader.GetDecimal(reader.GetOrdinal("DebitAmount")),
                    CreditAmount            = reader.GetDecimal(reader.GetOrdinal("CreditAmount")),
                    BalanceAfterTransaction = reader.GetDecimal(reader.GetOrdinal("BalanceAfterTransaction")),
                    Description             = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                    CreatedBy               = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetString(reader.GetOrdinal("CreatedBy")),
                    CreatedAt               = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        // ====================================================================
        // Customer payments
        // ====================================================================
        public async Task<List<GenericCustomerPaymentModel>> GetPaymentsAsync(string farmId, string? status)
        {
            var list = new List<GenericCustomerPaymentModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerpayment_getall(p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadPayment(reader));
            return list;
        }

        public async Task<GenericCustomerPaymentModel?> GetPaymentByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerpayment_getbyid(p_genericcustomerpaymentid => @GenericCustomerPaymentId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadPayment(reader) : null;
        }

        public async Task<int> InsertPaymentAsync(GenericCustomerPaymentModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerpayment_insert(p_farmid => @FarmId::text, p_genericcustomerid => @GenericCustomerId::int, p_amount => @Amount::numeric, p_paymentmethod => @PaymentMethod::text, p_genericcashaccountid => @GenericCashAccountId::int, p_receivedbystaffid => @ReceivedByStaffId::int, p_linkedsaleid => @LinkedSaleId::int, p_paymentdate => @PaymentDate::timestamp, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericCustomerId", m.GenericCustomerId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceivedByStaffId", (object?)m.ReceivedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedSaleId", (object?)m.LinkedSaleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate",
                m.PaymentDate == default ? (object)DBNull.Value : m.PaymentDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApprovePaymentAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerpayment_approve(p_genericcustomerpaymentid => @GenericCustomerPaymentId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelPaymentAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcustomerpayment_cancel(p_genericcustomerpaymentid => @GenericCustomerPaymentId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCustomerPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericCustomerModel ReadCustomer(NpgsqlDataReader r) => new()
        {
            GenericCustomerId = r.GetInt32(r.GetOrdinal("GenericCustomerId")),
            FarmId            = r.GetString(r.GetOrdinal("FarmId")),
            CustomerName      = r.GetString(r.GetOrdinal("CustomerName")),
            CustomerType      = r.GetString(r.GetOrdinal("CustomerType")),
            PhoneNumber       = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Email             = r.IsDBNull(r.GetOrdinal("Email")) ? null : r.GetString(r.GetOrdinal("Email")),
            Location          = r.IsDBNull(r.GetOrdinal("Location")) ? null : r.GetString(r.GetOrdinal("Location")),
            Address           = r.IsDBNull(r.GetOrdinal("Address")) ? null : r.GetString(r.GetOrdinal("Address")),
            CreditLimit       = r.GetDecimal(r.GetOrdinal("CreditLimit")),
            PaymentTermsDays  = r.GetInt32(r.GetOrdinal("PaymentTermsDays")),
            OpeningBalance    = r.GetDecimal(r.GetOrdinal("OpeningBalance")),
            CurrentBalance    = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
            AssignedStaffId   = r.IsDBNull(r.GetOrdinal("AssignedStaffId")) ? null : r.GetInt32(r.GetOrdinal("AssignedStaffId")),
            IsActive          = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted         = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes             = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt         = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt         = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericCustomerPaymentModel ReadPayment(NpgsqlDataReader r) => new()
        {
            GenericCustomerPaymentId = r.GetInt32(r.GetOrdinal("GenericCustomerPaymentId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            GenericCustomerId        = r.GetInt32(r.GetOrdinal("GenericCustomerId")),
            CustomerName             = r.IsDBNull(r.GetOrdinal("CustomerName")) ? null : r.GetString(r.GetOrdinal("CustomerName")),
            PaymentDate              = r.GetDateTime(r.GetOrdinal("PaymentDate")),
            Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
            PaymentMethod            = r.GetString(r.GetOrdinal("PaymentMethod")),
            GenericCashAccountId     = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            ReceivedByStaffId        = r.IsDBNull(r.GetOrdinal("ReceivedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("ReceivedByStaffId")),
            LinkedSaleId             = r.IsDBNull(r.GetOrdinal("LinkedSaleId")) ? null : r.GetInt32(r.GetOrdinal("LinkedSaleId")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
