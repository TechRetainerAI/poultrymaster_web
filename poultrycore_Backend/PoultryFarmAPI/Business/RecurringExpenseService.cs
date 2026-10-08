using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Recurring Expense Engine (migration 348). Module-neutral: everything is
    // keyed by farmId, and the module comes from the company's type inside the
    // database. Posting goes claim -> module adapter -> complete (or release),
    // so a repeated or concurrent Post can never create two expenses.
    // =========================================================================

    public interface IRecurringExpenseService
    {
        Task<List<RecurringExpenseTemplateModel>> GetTemplatesAsync(string farmId);
        Task<int> SaveTemplateAsync(int? templateId, RecurringExpenseTemplateRequest req, string? actor);
        Task<string> SetStatusAsync(int templateId, RecurringExpenseStatusRequest req, string? actor);
        Task DeleteTemplateAsync(string farmId, int templateId, string? actor);
        Task<List<RecurringExpenseEventModel>> GetHistoryAsync(string farmId, int templateId);

        Task<RecurringExpenseGenerateResult> GenerateAsync(string farmId, string? actor);
        Task<List<RecurringExpenseUpcomingModel>> GetUpcomingAsync(string farmId, int days);
        Task<List<RecurringExpenseOccurrenceModel>> GetOccurrencesAsync(string farmId, string? status, int? templateId);
        Task EditOccurrenceAsync(int occurrenceId, RecurringExpenseOccurrenceEditRequest req, string? actor);
        Task SkipAsync(string farmId, int occurrenceId, string reason, string? actor);
        Task RestoreAsync(string farmId, int occurrenceId, string? actor);
        Task<RecurringExpensePostResult> PostAsync(string farmId, int occurrenceId, string? actor);
        Task ReleaseAsync(string farmId, int occurrenceId, string? reason, string? actor);
        Task LinkExpenseAsync(string farmId, int occurrenceId, int expenseId, string? actor);
        /// <summary>Companies with at least one active template (for the scheduler).</summary>
        Task<List<string>> GetFarmsWithActiveTemplatesAsync();
    }

    public class RecurringExpenseService : IRecurringExpenseService
    {
        private readonly string _cs;
        private readonly Dictionary<string, IRecurringExpensePoster> _posters;

        public RecurringExpenseService(string cs, IEnumerable<IRecurringExpensePoster> posters)
        {
            _cs = cs;
            _posters = posters.ToDictionary(p => p.Module, StringComparer.OrdinalIgnoreCase);
        }

        private static string? Str(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static int? NInt(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetInt32(i); }
        private static DateTime? NDate(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }
        private static int Int(NpgsqlDataReader r, string c) => r.GetInt32(r.GetOrdinal(c));
        private static decimal Dec(NpgsqlDataReader r, string c) => r.GetDecimal(r.GetOrdinal(c));
        private static bool Bool(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private async Task<NpgsqlConnection> OpenAsync()
        {
            var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            return c;
        }

        // ------------------------------------------------------------ templates
        public async Task<List<RecurringExpenseTemplateModel>> GetTemplatesAsync(string farmId)
        {
            var list = new List<RecurringExpenseTemplateModel>();
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sprecurringexpense_gettemplates(p_farmid => @F::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new RecurringExpenseTemplateModel
                {
                    TemplateId = Int(r, "templateid"), Module = Str(r, "module") ?? "", Name = Str(r, "name") ?? "",
                    CategoryId = NInt(r, "categoryid"), CategoryName = Str(r, "categoryname"),
                    SupplierId = NInt(r, "supplierid"), PayeeName = Str(r, "payeename"), Amount = Dec(r, "amount"),
                    IsVariable = Bool(r, "isvariable"), Frequency = Str(r, "frequency") ?? "",
                    StartDate = r.GetDateTime(r.GetOrdinal("startdate")), EndDate = NDate(r, "enddate"),
                    GenerateFrom = r.GetDateTime(r.GetOrdinal("generatefrom")),
                    PaymentMethod = Str(r, "paymentmethod") ?? "Cash", CashAccountId = NInt(r, "cashaccountid"),
                    Description = Str(r, "description"), ApprovalMode = Str(r, "approvalmode") ?? "Draft",
                    Status = Str(r, "status") ?? "", NextDueDate = NDate(r, "nextduedate"),
                    Drafts = Int(r, "drafts"), Posted = Int(r, "posted"), Skipped = Int(r, "skipped"),
                    LastPostedAt = NDate(r, "lastpostedat"), CreatedBy = Str(r, "createdby"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")), EndedAt = NDate(r, "endedat"),
                    EndReason = Str(r, "endreason"),
                });
            return list;
        }

        public async Task<int> SaveTemplateAsync(int? templateId, RecurringExpenseTemplateRequest q, string? actor)
        {
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                SELECT sprecurringexpense_savetemplate(
                    p_farmid => @F::text, p_templateid => @Id::int, p_name => @Name::text,
                    p_categoryid => @CatId::int, p_categoryname => @Cat::text, p_supplierid => @Sup::int,
                    p_payeename => @Payee::text, p_amount => @Amount::numeric, p_isvariable => @Var::boolean,
                    p_frequency => @Freq::text, p_startdate => @Start::date, p_enddate => @End::date,
                    p_paymentmethod => @Method::text, p_cashaccountid => @Cash::int, p_description => @Desc::text,
                    p_approvalmode => @Mode::text, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@F", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", (object?)templateId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", q.Name);
            cmd.Parameters.AddWithValue("@CatId", (object?)q.CategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", (object?)q.CategoryName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Sup", (object?)q.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Payee", (object?)q.PayeeName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Var", q.IsVariable);
            cmd.Parameters.AddWithValue("@Freq", q.Frequency);
            cmd.Parameters.AddWithValue("@Start", q.StartDate.Date);
            cmd.Parameters.AddWithValue("@End", (object?)q.EndDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Method", q.PaymentMethod);
            cmd.Parameters.AddWithValue("@Cash", (object?)q.CashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Desc", (object?)q.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Mode", q.ApprovalMode);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<string> SetStatusAsync(int templateId, RecurringExpenseStatusRequest q, string? actor)
        {
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sprecurringexpense_setstatus(p_farmid => @F::text, p_templateid => @Id::int, p_action => @A::text, p_reason => @R::text, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@F", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", templateId);
            cmd.Parameters.AddWithValue("@A", q.Action);
            cmd.Parameters.AddWithValue("@R", (object?)q.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            return Convert.ToString(await cmd.ExecuteScalarAsync()) ?? "";
        }

        public async Task DeleteTemplateAsync(string farmId, int templateId, string? actor)
        {
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sprecurringexpense_deletetemplate(p_farmid => @F::text, p_templateid => @Id::int, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@Id", templateId);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<RecurringExpenseEventModel>> GetHistoryAsync(string farmId, int templateId)
        {
            var list = new List<RecurringExpenseEventModel>();
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sprecurringexpense_history(p_farmid => @F::text, p_templateid => @Id::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@Id", templateId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new RecurringExpenseEventModel
                {
                    EventId = r.GetInt64(r.GetOrdinal("eventid")), OccurrenceId = NInt(r, "occurrenceid"),
                    EventType = Str(r, "eventtype") ?? "",
                    Details = r.IsDBNull(r.GetOrdinal("details")) ? null : r.GetValue(r.GetOrdinal("details"))?.ToString(),
                    Actor = Str(r, "actor"),
                    AtUtc = r.GetFieldValue<DateTimeOffset>(r.GetOrdinal("atutc")).UtcDateTime,
                });
            return list;
        }

        // --------------------------------------------------------- occurrences
        public async Task<RecurringExpenseGenerateResult> GenerateAsync(string farmId, string? actor)
        {
            var result = new RecurringExpenseGenerateResult();
            var autoPost = new List<int>();
            using (var conn = await OpenAsync())
            using (var cmd = new NpgsqlCommand("SELECT * FROM sprecurringexpense_generate(p_farmid => @F::text, p_asof => NULL::date, p_actor => @Actor::text)", conn))
            {
                cmd.Parameters.AddWithValue("@F", farmId);
                cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    result.Generated++;
                    if (string.Equals(Str(r, "approvalmode"), "AutoPost", StringComparison.OrdinalIgnoreCase))
                        autoPost.Add(Int(r, "occurrenceid"));
                }
            }
            // AutoPost templates opted out of review: post through the module now.
            // A refusal (closed day, overdraft ...) leaves the draft for a person.
            foreach (var id in autoPost)
            {
                try { await PostAsync(farmId, id, actor); result.AutoPosted++; }
                catch (Exception ex) { result.AutoPostFailures.Add($"#{id}: {(ex as PostgresException)?.MessageText ?? ex.Message}"); }
            }
            return result;
        }

        public async Task<List<RecurringExpenseUpcomingModel>> GetUpcomingAsync(string farmId, int days)
        {
            var list = new List<RecurringExpenseUpcomingModel>();
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sprecurringexpense_upcoming(p_farmid => @F::text, p_days => @D::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@D", days);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new RecurringExpenseUpcomingModel
                {
                    TemplateId = Int(r, "templateid"), Name = Str(r, "name") ?? "", CategoryName = Str(r, "categoryname"),
                    Amount = Dec(r, "amount"), IsVariable = Bool(r, "isvariable"), Frequency = Str(r, "frequency") ?? "",
                    OccurrenceNo = Int(r, "occurrenceno"), ScheduledDate = r.GetDateTime(r.GetOrdinal("scheduleddate")),
                    DaysAway = Int(r, "daysaway"), Today = r.GetDateTime(r.GetOrdinal("today")),
                });
            return list;
        }

        public async Task<List<RecurringExpenseOccurrenceModel>> GetOccurrencesAsync(string farmId, string? status, int? templateId)
        {
            var list = new List<RecurringExpenseOccurrenceModel>();
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprecurringexpense_getoccurrences(p_farmid => @F::text, p_status => @S::text, p_templateid => @T::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@T", (object?)templateId ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new RecurringExpenseOccurrenceModel
                {
                    OccurrenceId = Int(r, "occurrenceid"), TemplateId = Int(r, "templateid"),
                    TemplateName = Str(r, "templatename") ?? "", Module = Str(r, "module") ?? "",
                    OccurrenceNo = Int(r, "occurrenceno"), ScheduledDate = r.GetDateTime(r.GetOrdinal("scheduleddate")),
                    Status = Str(r, "status") ?? "", Amount = Dec(r, "amount"), TemplateAmount = Dec(r, "templateamount"),
                    IsVariable = Bool(r, "isvariable"), ExpenseDate = r.GetDateTime(r.GetOrdinal("expensedate")),
                    PaymentMethod = Str(r, "paymentmethod") ?? "Cash", CashAccountId = NInt(r, "cashaccountid"),
                    SupplierId = NInt(r, "supplierid"), CategoryId = NInt(r, "categoryid"), CategoryName = Str(r, "categoryname"),
                    PayeeName = Str(r, "payeename"), Description = Str(r, "description"), Note = Str(r, "note"),
                    ExpenseId = NInt(r, "expenseid"), PostedBy = Str(r, "postedby"), PostedAt = NDate(r, "postedat"),
                    SkippedBy = Str(r, "skippedby"), SkippedAt = NDate(r, "skippedat"), SkipReason = Str(r, "skipreason"),
                    ClaimedBy = Str(r, "claimedby"), ClaimedAt = NDate(r, "claimedat"), IsInterrupted = Bool(r, "isinterrupted"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                });
            return list;
        }

        public async Task EditOccurrenceAsync(int occurrenceId, RecurringExpenseOccurrenceEditRequest q, string? actor)
        {
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                SELECT sprecurringexpense_editoccurrence(
                    p_farmid => @F::text, p_occurrenceid => @Id::int, p_amount => @Amount::numeric,
                    p_expensedate => @Date::date, p_paymentmethod => @Method::text, p_cashaccountid => @Cash::int,
                    p_supplierid => @Sup::int, p_description => @Desc::text, p_note => @Note::text, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@F", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", occurrenceId);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Date", q.ExpenseDate.Date);
            cmd.Parameters.AddWithValue("@Method", q.PaymentMethod);
            cmd.Parameters.AddWithValue("@Cash", (object?)q.CashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Sup", (object?)q.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Desc", (object?)q.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)q.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        private async Task ExecAsync(string sql, params (string, object?)[] ps)
        {
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (k, v) in ps) cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public Task SkipAsync(string farmId, int occurrenceId, string reason, string? actor) =>
            ExecAsync("SELECT sprecurringexpense_skip(p_farmid => @F::text, p_occurrenceid => @Id::int, p_reason => @R::text, p_actor => @A::text)",
                ("@F", farmId), ("@Id", occurrenceId), ("@R", reason), ("@A", actor));

        public Task RestoreAsync(string farmId, int occurrenceId, string? actor) =>
            ExecAsync("SELECT sprecurringexpense_restore(p_farmid => @F::text, p_occurrenceid => @Id::int, p_actor => @A::text)",
                ("@F", farmId), ("@Id", occurrenceId), ("@A", actor));

        public Task ReleaseAsync(string farmId, int occurrenceId, string? reason, string? actor) =>
            ExecAsync("SELECT sprecurringexpense_releaseclaim(p_farmid => @F::text, p_occurrenceid => @Id::int, p_claimtoken => NULL::uuid, p_reason => @R::text, p_actor => @A::text)",
                ("@F", farmId), ("@Id", occurrenceId), ("@R", reason), ("@A", actor));

        public Task LinkExpenseAsync(string farmId, int occurrenceId, int expenseId, string? actor) =>
            ExecAsync("SELECT sprecurringexpense_linkexpense(p_farmid => @F::text, p_occurrenceid => @Id::int, p_expenseid => @E::int, p_actor => @A::text)",
                ("@F", farmId), ("@Id", occurrenceId), ("@E", expenseId), ("@A", actor));

        public async Task<List<string>> GetFarmsWithActiveTemplatesAsync()
        {
            var list = new List<string>();
            using var conn = await OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT DISTINCT farmid FROM recurringexpensetemplates WHERE status = 'Active'", conn);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(r.GetString(0));
            return list;
        }

        // ------------------------------------------------------------- posting
        public async Task<RecurringExpensePostResult> PostAsync(string farmId, int occurrenceId, string? actor)
        {
            // 1. Claim: Draft -> Posting. A second Post (double click, two
            //    browsers, a retried request) is refused here.
            RecurringExpenseClaim claim;
            using (var conn = await OpenAsync())
            using (var cmd = new NpgsqlCommand("SELECT * FROM sprecurringexpense_claim(p_farmid => @F::text, p_occurrenceid => @Id::int, p_actor => @A::text)", conn))
            {
                cmd.Parameters.AddWithValue("@F", farmId);
                cmd.Parameters.AddWithValue("@Id", occurrenceId);
                cmd.Parameters.AddWithValue("@A", (object?)actor ?? DBNull.Value);
                using var r = await cmd.ExecuteReaderAsync();
                if (!await r.ReadAsync()) throw new InvalidOperationException("The occurrence could not be claimed.");
                claim = new RecurringExpenseClaim
                {
                    ClaimToken = r.GetGuid(r.GetOrdinal("claimtoken")), OccurrenceId = Int(r, "occurrenceid"),
                    TemplateId = Int(r, "templateid"), Module = Str(r, "module") ?? "", Amount = Dec(r, "amount"),
                    ExpenseDate = r.GetDateTime(r.GetOrdinal("expensedate")), PaymentMethod = Str(r, "paymentmethod") ?? "Cash",
                    CashAccountId = NInt(r, "cashaccountid"), SupplierId = NInt(r, "supplierid"),
                    CategoryId = NInt(r, "categoryid"), CategoryName = Str(r, "categoryname"),
                    PayeeName = Str(r, "payeename"), Description = Str(r, "description"), Note = Str(r, "note"),
                };
            }

            if (!_posters.TryGetValue(claim.Module, out var poster))
            {
                await ReleaseClaimAsync(farmId, claim, "No expense module for " + claim.Module, actor);
                throw new InvalidOperationException($"Recurring expenses cannot post to the {claim.Module} module.");
            }

            // A paid expense with no cash account is saved as paid but moves no
            // money (the module services accept it), so a recurring post refuses it.
            if (!claim.IsCredit && claim.CashAccountId is null)
            {
                await ReleaseClaimAsync(farmId, claim, "No cash account chosen", actor);
                throw new InvalidOperationException("Choose the cash account this is paid from before posting, or set the payment method to Credit.");
            }

            // 2. The module's own create path.
            int expenseId;
            try
            {
                expenseId = await poster.CreateExpenseAsync(farmId, claim, actor);
            }
            catch (Exception ex)
            {
                await ReleaseClaimAsync(farmId, claim, (ex as PostgresException)?.MessageText ?? ex.InnerException?.Message ?? ex.Message, actor);
                throw;
            }

            // 3. Complete: Posting -> Posted with the expense id.
            using (var conn = await OpenAsync())
            using (var cmd = new NpgsqlCommand(
                "SELECT sprecurringexpense_completepost(p_farmid => @F::text, p_occurrenceid => @Id::int, p_claimtoken => @T::uuid, p_expenseid => @E::int, p_actor => @A::text)", conn))
            {
                cmd.Parameters.AddWithValue("@F", farmId);
                cmd.Parameters.AddWithValue("@Id", occurrenceId);
                cmd.Parameters.AddWithValue("@T", claim.ClaimToken);
                cmd.Parameters.AddWithValue("@E", expenseId);
                cmd.Parameters.AddWithValue("@A", (object?)actor ?? DBNull.Value);
                await cmd.ExecuteNonQueryAsync();
            }

            return new RecurringExpensePostResult
            {
                OccurrenceId = occurrenceId,
                ExpenseId = expenseId,
                Module = claim.Module,
                AwaitingModuleApproval = poster.ModuleApproves,
                Message = poster.ModuleApproves
                    ? "Sent to Expenses as a draft. Cash moves when it is approved there."
                    : claim.IsCredit ? "Recorded as unpaid. It now appears on Supplier Balances." : "Expense recorded.",
            };
        }

        private async Task ReleaseClaimAsync(string farmId, RecurringExpenseClaim claim, string reason, string? actor)
        {
            try
            {
                await ExecAsync("SELECT sprecurringexpense_releaseclaim(p_farmid => @F::text, p_occurrenceid => @Id::int, p_claimtoken => @T::uuid, p_reason => @R::text, p_actor => @A::text)",
                    ("@F", farmId), ("@Id", claim.OccurrenceId), ("@T", claim.ClaimToken), ("@R", reason), ("@A", actor));
            }
            catch { /* the claim stays Posting and shows as interrupted after 10 minutes */ }
        }
    }
}
