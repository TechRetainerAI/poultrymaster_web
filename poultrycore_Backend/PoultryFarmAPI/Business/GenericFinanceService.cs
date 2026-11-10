using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Loans
    // =========================================================================
    public interface IGenericLoanService
    {
        Task<List<GenericLoanModel>> ListAsync(string farmId);
        Task<int> CreateAsync(GenericLoanCreateRequest r);
        Task<List<GenericLoanPaymentModel>> ListPaymentsAsync(int loanId, string farmId);
        Task<int> RepayAsync(int loanId, GenericLoanRepayRequest r);
    }

    public class GenericLoanService : IGenericLoanService
    {
        private readonly string _cs; public GenericLoanService(string cs) => _cs = cs;

        public async Task<List<GenericLoanModel>> ListAsync(string farmId)
        {
            var list = new List<GenericLoanModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericloan_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericLoanModel
            {
                GenericLoanId = r.Int("GenericLoanId"), FarmId = r.Str("FarmId"),
                LenderName = r.Str("LenderName"), OriginalPrincipal = r.Dec("OriginalPrincipal"),
                AmountReceived = r.Dec("AmountReceived"), InterestRate = r.Dec("InterestRate"),
                TotalInterestPaid = r.Dec("TotalInterestPaid"), TotalFeesPaid = r.Dec("TotalFeesPaid"),
                TotalPrincipalPaid = r.Dec("TotalPrincipalPaid"), OutstandingBalance = r.Dec("OutstandingBalance"),
                LoanDate = r.Date("LoanDate"), StartDate = r.DateN("StartDate"), DueDate = r.DateN("DueDate"),
                Status = r.Str("Status"), Notes = r.StrN("Notes"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericLoanCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericloan_create(" +
                "p_farmid=>@FarmId::text, p_lendername=>@Lender::text, p_originalprincipal=>@Principal::numeric, " +
                "p_amountreceived=>@Received::numeric, p_interestrate=>@Rate::numeric, " +
                "p_loandate=>@LoanDate::timestamp, p_startdate=>@StartDate::timestamp, p_duedate=>@DueDate::timestamp, " +
                "p_cashaccountid=>@AccountId::int, p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Lender", m.LenderName);
            cmd.Parameters.AddWithValue("@Principal", m.OriginalPrincipal);
            cmd.Parameters.AddWithValue("@Received", m.AmountReceived);
            cmd.Parameters.AddWithValue("@Rate", m.InterestRate);
            cmd.Parameters.AddWithValue("@LoanDate", (object?)m.LoanDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartDate", (object?)m.StartDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DueDate", (object?)m.DueDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<GenericLoanPaymentModel>> ListPaymentsAsync(int loanId, string farmId)
        {
            var list = new List<GenericLoanPaymentModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericloan_payments(@LoanId::int, @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@LoanId", loanId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericLoanPaymentModel
            {
                GenericLoanPaymentId = r.Int("GenericLoanPaymentId"),
                GenericLoanId = r.Int("GenericLoanId"),
                PaymentDate = r.Date("PaymentDate"),
                PrincipalAmount = r.Dec("PrincipalAmount"),
                InterestAmount = r.Dec("InterestAmount"),
                FeeAmount = r.Dec("FeeAmount"),
                TotalPayment = r.Dec("TotalPayment"),
                Notes = r.StrN("Notes"),
                IsReversed = r.GetBoolean(r.GetOrdinal("IsReversed")),
                CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> RepayAsync(int loanId, GenericLoanRepayRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericloan_repay(" +
                "p_genericloanid=>@LoanId::int, p_farmid=>@FarmId::text, " +
                "p_principalamount=>@Principal::numeric, p_interestamount=>@Interest::numeric, " +
                "p_feeamount=>@Fee::numeric, p_paymentdate=>@PaymentDate::timestamp, " +
                "p_cashaccountid=>@AccountId::int, p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@LoanId", loanId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Principal", m.PrincipalAmount);
            cmd.Parameters.AddWithValue("@Interest", m.InterestAmount);
            cmd.Parameters.AddWithValue("@Fee", m.FeeAmount);
            cmd.Parameters.AddWithValue("@PaymentDate", (object?)m.PaymentDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    // =========================================================================
    // Assets
    // =========================================================================
    public interface IGenericAssetService
    {
        Task<List<GenericAssetModel>> ListAsync(string farmId);
        Task<int> CreateAsync(GenericAssetCreateRequest r);
        Task DisposeAsync(int assetId, GenericAssetDisposeRequest r);
        Task DepreciateAsync(int assetId, string farmId, decimal amount);
    }

    public class GenericAssetService : IGenericAssetService
    {
        private readonly string _cs; public GenericAssetService(string cs) => _cs = cs;

        public async Task<List<GenericAssetModel>> ListAsync(string farmId)
        {
            var list = new List<GenericAssetModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericasset_list(@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericAssetModel
            {
                GenericAssetId = r.Int("GenericAssetId"), FarmId = r.Str("FarmId"),
                AssetName = r.Str("AssetName"), Category = r.StrN("Category"),
                PurchaseDate = r.Date("PurchaseDate"), PurchaseCost = r.Dec("PurchaseCost"),
                CurrentValue = r.Dec("CurrentValue"), TotalDepreciation = r.Dec("TotalDepreciation"),
                UsefulLifeMonths = r.Has("UsefulLifeMonths") && !r.IsDBNull(r.GetOrdinal("UsefulLifeMonths")) ? r.GetInt32(r.GetOrdinal("UsefulLifeMonths")) : null,
                DepreciationMethod = r.StrN("DepreciationMethod"), Status = r.Str("Status"),
                DisposalDate = r.DateN("DisposalDate"),
                DisposalAmount = r.Has("DisposalAmount") && !r.IsDBNull(r.GetOrdinal("DisposalAmount")) ? r.Dec("DisposalAmount") : null,
                Location = r.StrN("Location"), SerialNumber = r.StrN("SerialNumber"),
                Notes = r.StrN("Notes"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericAssetCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericasset_create(" +
                "p_farmid=>@FarmId::text, p_assetname=>@Name::text, p_category=>@Category::varchar, " +
                "p_purchasedate=>@PurchaseDate::timestamp, p_purchasecost=>@Cost::numeric, " +
                "p_usefullifemonths=>@LifeMonths::int, p_depreciationmethod=>@DepMethod::varchar, " +
                "p_location=>@Location::text, p_serialnumber=>@Serial::text, " +
                "p_notes=>@Notes::text, p_createdby=>@CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.AssetName);
            cmd.Parameters.AddWithValue("@Category", (object?)m.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)m.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cost", m.PurchaseCost);
            cmd.Parameters.AddWithValue("@LifeMonths", (object?)m.UsefulLifeMonths ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DepMethod", (object?)m.DepreciationMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Serial", (object?)m.SerialNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DisposeAsync(int assetId, GenericAssetDisposeRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericasset_dispose(@AssetId::int, @FarmId::text, @DisposalDate::timestamp, @Amount::numeric)", c);
            cmd.Parameters.AddWithValue("@AssetId", assetId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DisposalDate", (object?)m.DisposalDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", m.DisposalAmount);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DepreciateAsync(int assetId, string farmId, decimal amount)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericasset_depreciate(@AssetId::int, @FarmId::text, @Amount::numeric)", c);
            cmd.Parameters.AddWithValue("@AssetId", assetId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }
}
