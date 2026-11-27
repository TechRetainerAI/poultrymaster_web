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
        Task UpdateAsync(int loanId, GenericLoanUpdateRequest r);
        Task CancelAsync(int loanId, string farmId, string reason, string? by);
        /// <summary>509: Draft -> Active; the money received posts here.</summary>
        Task ApproveAsync(int loanId, string farmId, string? by);
        /// <summary>509: an approved loan with no posted repayments goes back to Draft.</summary>
        Task ReverseAsync(int loanId, string farmId, string reason, string? by);
        /// <summary>loanId null = every repayment of the company (reversed ones included).</summary>
        Task<List<GenericLoanPaymentModel>> ListPaymentsAsync(int? loanId, string farmId);
        Task<int> RepayAsync(int loanId, GenericLoanRepayRequest r);
        Task ReversePaymentAsync(int paymentId, string farmId, string reason, string? by);
    }

    // 455: every cash move goes through fngenericcash_move inside these SPs, and
    // the SPs raise P0001 for the user-facing rules (controller returns 400).
    public class GenericLoanService : IGenericLoanService
    {
        private readonly string _cs; public GenericLoanService(string cs) => _cs = cs;

        private static object N(object? v) => v ?? DBNull.Value;

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
                LoanNumber = r.StrN("LoanNumber"),
                LenderName = r.StrN("LenderName") ?? "", LenderType = r.StrN("LenderType"),
                AccountNumber = r.StrN("AccountNumber"),
                OriginalPrincipal = r.Dec("OriginalPrincipal"),
                AmountReceived = r.Dec("AmountReceived"), InterestRate = r.Dec("InterestRate"),
                InterestType = r.StrN("InterestType"), TermMonths = r.IntN("TermMonths"),
                PaymentFrequency = r.StrN("PaymentFrequency"),
                TotalInterestPaid = r.Dec("TotalInterestPaid"), TotalFeesPaid = r.Dec("TotalFeesPaid"),
                TotalPrincipalPaid = r.Dec("TotalPrincipalPaid"), OutstandingBalance = r.Dec("OutstandingBalance"),
                LoanDate = r.Date("LoanDate"), StartDate = r.DateN("StartDate"), DueDate = r.DateN("DueDate"),
                NextPaymentDate = r.DateN("NextPaymentDate"),
                GenericCashAccountId = r.IntN("GenericCashAccountId"), AccountName = r.StrN("AccountName"),
                PaymentCount = r.Int("PaymentCount"), IsOverdue = r.Bool("IsOverdue"),
                PaidOffDate = r.DateN("PaidOffDate"), CancelReason = r.StrN("CancelReason"),
                Status = r.Str("Status"), Notes = r.StrN("Notes"), CreatedAt = r.Date("CreatedAt"),
                ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"),
                ReversedAt = r.DateN("ReversedAt"), ReversalReason = r.StrN("ReversalReason"),
            });
            return list;
        }

        public async Task<int> CreateAsync(GenericLoanCreateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            const string call =
                "spgenericloan_create(" +
                "p_farmid=>@FarmId::text, p_lendername=>@Lender::text, p_originalprincipal=>@Principal::numeric, " +
                "p_amountreceived=>@Received::numeric, p_interestrate=>@Rate::numeric, " +
                "p_loandate=>@LoanDate::timestamp, p_startdate=>@StartDate::timestamp, p_duedate=>@DueDate::timestamp, " +
                "p_cashaccountid=>@AccountId::int, p_notes=>@Notes::text, p_createdby=>@CreatedBy::text, " +
                "p_lendertype=>@LenderType::text, p_accountnumber=>@AccountNumber::text, p_interesttype=>@InterestType::text, " +
                "p_termmonths=>@Term::int, p_paymentfrequency=>@Frequency::text, p_nextpaymentdate=>@Next::date, " +
                "p_approve=>@Approve::boolean)";
            // Projects & Contracts: the loan and its project are saved in one statement.
            using var cmd = new NpgsqlCommand(GenericProjectAttach.Has(m.Projects)
                ? GenericProjectAttach.WrapInsert(call, "Loan")
                : "SELECT " + call, c);
            if (GenericProjectAttach.Has(m.Projects)) GenericProjectAttach.AddParams(cmd, m.FarmId, m.Projects, m.CreatedBy);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Lender", m.LenderName ?? "");
            cmd.Parameters.AddWithValue("@Principal", m.OriginalPrincipal);
            cmd.Parameters.AddWithValue("@Received", m.AmountReceived);
            cmd.Parameters.AddWithValue("@Rate", N(m.InterestRate));
            cmd.Parameters.AddWithValue("@LoanDate", N(m.LoanDate ?? m.StartDate));
            cmd.Parameters.AddWithValue("@StartDate", N(m.StartDate));
            cmd.Parameters.AddWithValue("@DueDate", N(m.DueDate));
            cmd.Parameters.AddWithValue("@AccountId", N(m.GenericCashAccountId));
            cmd.Parameters.AddWithValue("@Notes", N(m.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", N(m.CreatedBy));
            cmd.Parameters.AddWithValue("@LenderType", N(m.LenderType));
            cmd.Parameters.AddWithValue("@AccountNumber", N(m.AccountNumber));
            cmd.Parameters.AddWithValue("@InterestType", N(m.InterestType));
            cmd.Parameters.AddWithValue("@Term", N(m.TermMonths));
            cmd.Parameters.AddWithValue("@Frequency", N(m.PaymentFrequency));
            cmd.Parameters.AddWithValue("@Next", N(m.NextPaymentDate?.Date));
            cmd.Parameters.AddWithValue("@Approve", m.Approve ?? true);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int loanId, GenericLoanUpdateRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            const string call =
                "spgenericloan_update(p_genericloanid=>@Id::int, p_farmid=>@FarmId::text, " +
                "p_lendername=>@Lender::text, p_lendertype=>@LenderType::text, p_accountnumber=>@AccountNumber::text, " +
                "p_interestrate=>@Rate::numeric, p_interesttype=>@InterestType::text, p_termmonths=>@Term::int, " +
                "p_paymentfrequency=>@Frequency::text, p_duedate=>@Due::date, p_nextpaymentdate=>@Next::date, " +
                "p_notes=>@Notes::text, p_updatedby=>@By::text, " +
                "p_originalprincipal=>@Principal::numeric, p_amountreceived=>@Received::numeric, " +
                "p_cashaccountid=>@AccountId::int, p_loandate=>@LoanDate::date)";
            // Projects & Contracts: a changed project is saved with the terms in one statement.
            using var cmd = new NpgsqlCommand(GenericProjectAttach.Has(m.Projects)
                ? GenericProjectAttach.WrapUpdate(call, "Loan")
                : "SELECT " + call, c);
            if (GenericProjectAttach.Has(m.Projects)) GenericProjectAttach.AddParams(cmd, m.FarmId, m.Projects, m.UpdatedBy, loanId);
            cmd.Parameters.AddWithValue("@Id", loanId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Lender", N(m.LenderName));
            cmd.Parameters.AddWithValue("@LenderType", N(m.LenderType));
            cmd.Parameters.AddWithValue("@AccountNumber", N(m.AccountNumber));
            cmd.Parameters.AddWithValue("@Rate", N(m.InterestRate));
            cmd.Parameters.AddWithValue("@InterestType", N(m.InterestType));
            cmd.Parameters.AddWithValue("@Term", N(m.TermMonths));
            cmd.Parameters.AddWithValue("@Frequency", N(m.PaymentFrequency));
            cmd.Parameters.AddWithValue("@Due", N(m.DueDate?.Date));
            cmd.Parameters.AddWithValue("@Next", N(m.NextPaymentDate?.Date));
            cmd.Parameters.AddWithValue("@Notes", N(m.Notes));
            cmd.Parameters.AddWithValue("@By", N(m.UpdatedBy));
            cmd.Parameters.AddWithValue("@Principal", N(m.OriginalPrincipal));
            cmd.Parameters.AddWithValue("@Received", N(m.AmountReceived));
            cmd.Parameters.AddWithValue("@AccountId", N(m.GenericCashAccountId));
            cmd.Parameters.AddWithValue("@LoanDate", N(m.LoanDate?.Date));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int loanId, string farmId, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT spgenericloan_approve(@Id::int, @FarmId::text, @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", loanId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@By", N(by));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int loanId, string farmId, string reason, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericloan_reverse(@Id::int, @FarmId::text, @Reason::text, @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", loanId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason ?? "");
            cmd.Parameters.AddWithValue("@By", N(by));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int loanId, string farmId, string reason, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericloan_cancel(@Id::int, @FarmId::text, @Reason::text, @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", loanId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason ?? "");
            cmd.Parameters.AddWithValue("@By", N(by));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericLoanPaymentModel>> ListPaymentsAsync(int? loanId, string farmId)
        {
            var list = new List<GenericLoanPaymentModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericloan_payments(@LoanId::int, @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@LoanId", N(loanId));
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericLoanPaymentModel
            {
                GenericLoanPaymentId = r.Int("GenericLoanPaymentId"),
                GenericLoanId = r.Int("GenericLoanId"),
                LoanNumber = r.StrN("LoanNumber"),
                PaymentNumber = r.StrN("PaymentNumber"),
                PaymentDate = r.Date("PaymentDate"),
                PrincipalAmount = r.Dec("PrincipalAmount"),
                InterestAmount = r.Dec("InterestAmount"),
                FeeAmount = r.Dec("FeeAmount"),
                OtherAmount = r.Dec("OtherAmount"),
                TotalPayment = r.Dec("TotalPayment"),
                GenericCashAccountId = r.IntN("GenericCashAccountId"),
                AccountName = r.StrN("AccountName"),
                PaymentMethod = r.StrN("PaymentMethod"),
                ReferenceNumber = r.StrN("ReferenceNumber"),
                Notes = r.StrN("Notes"),
                IsReversed = r.Bool("IsReversed"),
                Status = r.Str("Status"),
                ReversedAt = r.DateN("ReversedAt"),
                ReversalReason = r.StrN("ReversalReason"),
                CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> RepayAsync(int loanId, GenericLoanRepayRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericloan_repay(" +
                "p_genericloanid=>@LoanId::int, p_farmid=>@FarmId::text, " +
                "p_principalamount=>@Principal::numeric, p_interestamount=>@Interest::numeric, " +
                "p_feeamount=>@Fee::numeric, p_paymentdate=>@PaymentDate::timestamp, " +
                "p_cashaccountid=>@AccountId::int, p_notes=>@Notes::text, p_createdby=>@CreatedBy::text, " +
                "p_otheramount=>@Other::numeric, p_paymentmethod=>@Method::text, p_referencenumber=>@Ref::text, " +
                "p_nextpaymentdate=>@Next::date)", c);
            cmd.Parameters.AddWithValue("@LoanId", loanId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Principal", m.PrincipalAmount);
            cmd.Parameters.AddWithValue("@Interest", m.InterestAmount);
            cmd.Parameters.AddWithValue("@Fee", m.FeeAmount);
            cmd.Parameters.AddWithValue("@PaymentDate", N(m.PaymentDate));
            cmd.Parameters.AddWithValue("@AccountId", N(m.GenericCashAccountId));
            cmd.Parameters.AddWithValue("@Notes", N(m.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", N(m.CreatedBy));
            cmd.Parameters.AddWithValue("@Other", m.OtherAmount);
            cmd.Parameters.AddWithValue("@Method", N(m.PaymentMethod));
            cmd.Parameters.AddWithValue("@Ref", N(m.ReferenceNumber));
            cmd.Parameters.AddWithValue("@Next", N(m.NextPaymentDate?.Date));
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReversePaymentAsync(int paymentId, string farmId, string reason, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericloanpayment_reverse(@Id::int, @FarmId::text, @Reason::text, @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", paymentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason ?? "");
            cmd.Parameters.AddWithValue("@By", N(by));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
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
        Task<bool> DepreciateAsync(int assetId, string farmId, decimal amount);
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

        public async Task<bool> DepreciateAsync(int assetId, string farmId, decimal amount)
        {
            using var connection = new NpgsqlConnection(_cs);
            await connection.OpenAsync();
            using var transaction = await connection.BeginTransactionAsync(System.Data.IsolationLevel.RepeatableRead);

            // The register stores only cumulative depreciation. Record each new charge
            // as a dated non-cash expense in the same transaction as the register update.
            using var lookup = new NpgsqlCommand("""
                SELECT "AssetName" FROM spgenericasset_list(@farm)
                WHERE "GenericAssetId" = @id AND "Status" = 'Active' AND "CurrentValue" >= @amount
                """, connection, transaction);
            lookup.Parameters.AddWithValue("farm", farmId);
            lookup.Parameters.AddWithValue("id", assetId);
            lookup.Parameters.AddWithValue("amount", amount);
            if (await lookup.ExecuteScalarAsync() is not string name) return false;

            using var post = new NpgsqlCommand("""
                SELECT spgenericasset_depreciate(@id, @farm, @amount);
                WITH category AS (
                    INSERT INTO genericexpensecategories (farmid, name) VALUES (@farm, 'Depreciation')
                    ON CONFLICT (farmid, name) DO UPDATE SET name = excluded.name
                    RETURNING genericexpensecategoryid
                )
                INSERT INTO genericexpenses
                    (farmid, expensedate, genericexpensecategoryid, description, amount, amountpaid,
                     paymentmethod, status, approvedat, sourcetype)
                SELECT @farm, now() AT TIME ZONE 'UTC', genericexpensecategoryid, @description,
                       @amount, @amount, 'NonCash', 'Approved', now() AT TIME ZONE 'UTC', 'AssetDepreciation'
                FROM category
                """, connection, transaction);
            post.Parameters.AddWithValue("id", assetId);
            post.Parameters.AddWithValue("farm", farmId);
            post.Parameters.AddWithValue("amount", amount);
            post.Parameters.AddWithValue("description", $"Depreciation for {name} (asset #{assetId})");
            await post.ExecuteNonQueryAsync();
            await transaction.CommitAsync();
            return true;
        }
    }
}
