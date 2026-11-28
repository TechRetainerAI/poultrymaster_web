using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Poultry sale approval (migration 527).
    ///
    /// <para>
    /// A sale entered by someone who is neither the owner nor holds
    /// <c>poultry.sales.approve</c> is not posted: the request, exactly as the
    /// form sent it, waits in <c>poultrypendingsales</c>. Approving it runs the
    /// ordinary posting code (<see cref="ISaleService.Insert"/> /
    /// <see cref="ISaleService.CreateGroup"/>) as the person who entered it, so a
    /// waiting sale never touches stock, cash or any report until it is approved.
    /// </para>
    /// </summary>
    public interface IPoultrySaleApprovalService
    {
        /// <summary>Must a sale this person enters for this company wait for approval?</summary>
        Task<bool> MustWaitAsync(string userId, string farmId);
        Task<PoultrySaleApprovalInfo> GetInfoAsync(string userId, string farmId);
        Task<bool> IsApproverAsync(string userId, string farmId);
        Task<bool> IsOwnerAsync(string userId, string farmId);
        Task SetNeedApprovalAsync(string farmId, bool needApproval, string by);

        Task<int> SubmitSingleAsync(SaleModel model, string by);
        Task<int> SubmitGroupAsync(SaleGroupRequest request, string by);
        Task UpdateSingleAsync(int pendingSaleId, SaleModel model, string by);
        Task UpdateGroupAsync(int pendingSaleId, SaleGroupRequest request, string by);

        Task<List<PoultryPendingSaleRow>> ListAsync(string farmId, string? status);
        Task<PoultryPendingSaleRow?> GetAsync(int pendingSaleId, string farmId);
        Task<PoultryPendingSaleApproved> ApproveAsync(int pendingSaleId, string farmId, string approverId);
        Task RejectAsync(int pendingSaleId, string farmId, string reason, string by);
        Task WithdrawAsync(int pendingSaleId, string farmId, string by);
    }

    public class PoultrySaleApprovalService : IPoultrySaleApprovalService
    {
        public const string ApproveKey = "poultry.sales.approve";

        private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

        private readonly string _connectionString;
        private readonly IIamService _iam;
        private readonly ISaleService _sales;

        public PoultrySaleApprovalService(string connectionString, IIamService iam, ISaleService sales)
        {
            _connectionString = connectionString;
            _iam = iam;
            _sales = sales;
        }

        // ------------------------------------------------------------ who ----

        public async Task<bool> IsOwnerAsync(string userId, string farmId) =>
            await _iam.GetMembershipAsync(userId, farmId) == "owner";

        public async Task<bool> IsApproverAsync(string userId, string farmId) =>
            await IsOwnerAsync(userId, farmId) || await _iam.HasPermissionAsync(userId, farmId, ApproveKey);

        public async Task<bool> MustWaitAsync(string userId, string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(farmId)) return false;
            // Poultry only: the Sale controller is shared, but only poultry has this step.
            if (!string.Equals(await _iam.GetModuleForFarmAsync(farmId), "poultry", StringComparison.OrdinalIgnoreCase)) return false;
            // Before per-company page access (506/507) nobody can be given the
            // approve right, so nobody would be able to approve: post as before.
            if (!await _iam.HasPageAccessModelAsync()) return false;
            if (!await NeedApprovalAsync(farmId)) return false;
            return !await IsApproverAsync(userId, farmId);
        }

        public async Task<PoultrySaleApprovalInfo> GetInfoAsync(string userId, string farmId)
        {
            var need = await NeedApprovalAsync(farmId);
            var owner = await IsOwnerAsync(userId, farmId);
            var approver = owner || await _iam.HasPermissionAsync(userId, farmId, ApproveKey);
            var live = await _iam.HasPageAccessModelAsync();
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var waiting = 0;
            if (await TableExistsAsync(conn))
            {
                await using var cmd = new NpgsqlCommand(
                    "SELECT count(*)::int FROM poultrypendingsales WHERE farmid = @F AND status IN ('Waiting','Approving')", conn);
                cmd.Parameters.AddWithValue("@F", farmId);
                waiting = (int)(await cmd.ExecuteScalarAsync() ?? 0);
            }
            return new PoultrySaleApprovalInfo
            {
                NeedApproval = need,
                Active = need && live,
                IsApprover = approver,
                IsOwner = owner,
                MySalesWait = need && live && !approver,
                WaitingCount = waiting,
            };
        }

        public async Task SetNeedApprovalAsync(string farmId, bool needApproval, string by)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand("SELECT sppoultrysalessettings_set(@F, @N, @B)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@N", needApproval);
            cmd.Parameters.AddWithValue("@B", by);
            await cmd.ExecuteScalarAsync();
        }

        private async Task<bool> NeedApprovalAsync(string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            // Deployed ahead of 527: no approval step.
            await using var probe = new NpgsqlCommand("SELECT to_regproc('public.fnpoultrysales_needapproval') IS NOT NULL", conn);
            if (await probe.ExecuteScalarAsync() is not true) return false;
            await using var cmd = new NpgsqlCommand("SELECT fnpoultrysales_needapproval(@F)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            return await cmd.ExecuteScalarAsync() is true;
        }

        private static async Task<bool> TableExistsAsync(NpgsqlConnection conn)
        {
            await using var probe = new NpgsqlCommand("SELECT to_regclass('public.poultrypendingsales') IS NOT NULL", conn);
            return await probe.ExecuteScalarAsync() is true;
        }

        // ---------------------------------------------------- submit / edit ----

        private static (DateTime date, string? customer, string summary, decimal total, int lines) Describe(SaleModel m) =>
            (m.SaleDate, m.CustomerName, $"{m.Product} × {m.Quantity:0.##}", m.TotalAmount, 1);

        private static (DateTime date, string? customer, string summary, decimal total, int lines) Describe(SaleGroupRequest r) =>
            (r.SaleDate, r.CustomerName,
             string.Join(", ", r.Lines.Select(l => $"{l.Product} × {l.Quantity:0.##}")),
             r.Lines.Sum(l => l.TotalAmount), Math.Max(1, r.Lines.Count));

        public Task<int> SubmitSingleAsync(SaleModel model, string by) =>
            SubmitAsync(model.FarmId, "single", JsonSerializer.Serialize(model, Json), Describe(model), by);

        public Task<int> SubmitGroupAsync(SaleGroupRequest request, string by)
        {
            // The group path is idempotent on its request key; give every
            // waiting sale one so a repeated approval cannot post it twice.
            if (string.IsNullOrWhiteSpace(request.RequestKey)) request.RequestKey = Guid.NewGuid().ToString();
            return SubmitAsync(request.FarmId, "group", JsonSerializer.Serialize(request, Json), Describe(request), by);
        }

        private async Task<int> SubmitAsync(string farmId, string kind, string payload,
            (DateTime date, string? customer, string summary, decimal total, int lines) d, string by)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT sppoultrypendingsale_submit(@F, @K, @P::jsonb, @D, @C, @S, @T, @L, @B)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@K", kind);
            cmd.Parameters.AddWithValue("@P", payload);
            cmd.Parameters.AddWithValue("@D", d.date);
            cmd.Parameters.AddWithValue("@C", (object?)d.customer ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@S", d.summary);
            cmd.Parameters.AddWithValue("@T", d.total);
            cmd.Parameters.AddWithValue("@L", d.lines);
            cmd.Parameters.AddWithValue("@B", by);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task UpdateSingleAsync(int pendingSaleId, SaleModel model, string by) =>
            UpdateAsync(pendingSaleId, model.FarmId, "single", JsonSerializer.Serialize(model, Json), Describe(model), by);

        public Task UpdateGroupAsync(int pendingSaleId, SaleGroupRequest request, string by)
        {
            if (string.IsNullOrWhiteSpace(request.RequestKey)) request.RequestKey = Guid.NewGuid().ToString();
            return UpdateAsync(pendingSaleId, request.FarmId, "group", JsonSerializer.Serialize(request, Json), Describe(request), by);
        }

        private async Task UpdateAsync(int id, string farmId, string kind, string payload,
            (DateTime date, string? customer, string summary, decimal total, int lines) d, string by)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT sppoultrypendingsale_update(@Id, @F, @K, @P::jsonb, @D, @C, @S, @T, @L, @B)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@K", kind);
            cmd.Parameters.AddWithValue("@P", payload);
            cmd.Parameters.AddWithValue("@D", d.date);
            cmd.Parameters.AddWithValue("@C", (object?)d.customer ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@S", d.summary);
            cmd.Parameters.AddWithValue("@T", d.total);
            cmd.Parameters.AddWithValue("@L", d.lines);
            cmd.Parameters.AddWithValue("@B", by);
            await cmd.ExecuteNonQueryAsync();
        }

        // ------------------------------------------------------------ read ----

        public async Task<List<PoultryPendingSaleRow>> ListAsync(string farmId, string? status)
        {
            var rows = new List<PoultryPendingSaleRow>();
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            if (!await TableExistsAsync(conn)) return rows;
            await using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypendingsale_list(@F, @S)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) rows.Add(Read(r));
            return rows;
        }

        public async Task<PoultryPendingSaleRow?> GetAsync(int pendingSaleId, string farmId) =>
            (await ListAsync(farmId, null)).FirstOrDefault(x => x.PendingSaleId == pendingSaleId);

        private static PoultryPendingSaleRow Read(NpgsqlDataReader r)
        {
            string? S(string c) => r[c] is DBNull ? null : r[c].ToString();
            DateTime? D(string c) => r[c] is DBNull ? null : (DateTime)r[c];
            return new PoultryPendingSaleRow
            {
                PendingSaleId = (int)r["pendingsaleid"],
                Kind = S("kind") ?? "single",
                Payload = JsonDocument.Parse(S("payload") ?? "{}").RootElement.Clone(),
                SaleDate = D("saledate"),
                CustomerName = S("customername"),
                Summary = S("summary"),
                TotalAmount = r["totalamount"] is DBNull ? 0 : Convert.ToDecimal(r["totalamount"]),
                LineCount = (int)r["linecount"],
                Status = S("status") ?? "Waiting",
                SubmittedBy = S("submittedby") ?? "",
                SubmittedByName = S("submittedbyname"),
                SubmittedAt = (DateTime)r["submittedat"],
                UpdatedAt = D("updatedat"),
                DecidedBy = S("decidedby"),
                DecidedByName = S("decidedbyname"),
                DecidedAt = D("decidedat"),
                RejectionReason = S("rejectionreason"),
                LastError = S("lasterror"),
                PostedSaleId = r["postedsaleid"] is DBNull ? null : (int)r["postedsaleid"],
                PostedSaleLabel = S("postedsalelabel"),
            };
        }

        // --------------------------------------------------------- decide ----

        public async Task<PoultryPendingSaleApproved> ApproveAsync(int pendingSaleId, string farmId, string approverId)
        {
            string kind, payload, submittedBy;
            await using (var conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand("SELECT kind, payload::text, submittedby FROM sppoultrypendingsale_claim(@Id, @F, @B)", conn);
                cmd.Parameters.AddWithValue("@Id", pendingSaleId);
                cmd.Parameters.AddWithValue("@F", farmId);
                cmd.Parameters.AddWithValue("@B", approverId);
                try
                {
                    await using var r = await cmd.ExecuteReaderAsync();
                    if (!await r.ReadAsync()) throw new SaleRuleException("This sale is no longer waiting for approval.");
                    kind = r.GetString(0); payload = r.GetString(1); submittedBy = r.GetString(2);
                }
                catch (PostgresException ex) when (ex.SqlState == "P0001")
                {
                    throw new SaleRuleException(ex.MessageText, ex);
                }
            }

            try
            {
                int saleId; string label;
                if (kind == "group")
                {
                    var req = JsonSerializer.Deserialize<SaleGroupRequest>(payload, Json)
                              ?? throw new SaleRuleException("The waiting sale could not be read.");
                    // Posted as the person who entered it, in the company it was entered for.
                    req.UserId = submittedBy;
                    req.FarmId = farmId;
                    SaleGroupResult res;
                    try { res = await _sales.CreateGroup(req); }
                    catch (PostgresException ex) when (ex.SqlState == "P0001") { throw new SaleRuleException(ex.MessageText, ex); }
                    saleId = res.SaleId;
                    label = string.IsNullOrWhiteSpace(res.SaleGroupNo) ? $"S{saleId}" : res.SaleGroupNo;
                }
                else
                {
                    var model = JsonSerializer.Deserialize<SaleModel>(payload, Json)
                                ?? throw new SaleRuleException("The waiting sale could not be read.");
                    model.UserId = submittedBy;
                    model.FarmId = farmId;
                    model.SaleId = 0;
                    saleId = await _sales.Insert(model);
                    label = $"S{saleId}";
                }

                await using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                await using var mark = new NpgsqlCommand("SELECT sppoultrypendingsale_markapproved(@Id, @F, @S, @L, @B)", conn);
                mark.Parameters.AddWithValue("@Id", pendingSaleId);
                mark.Parameters.AddWithValue("@F", farmId);
                mark.Parameters.AddWithValue("@S", saleId);
                mark.Parameters.AddWithValue("@L", label);
                mark.Parameters.AddWithValue("@B", approverId);
                await mark.ExecuteNonQueryAsync();
                return new PoultryPendingSaleApproved { PendingSaleId = pendingSaleId, SaleId = saleId, SaleLabel = label };
            }
            catch (Exception ex)
            {
                // Not posted: back to Waiting, with the reason on the row.
                var message = ex is SaleRuleException ? ex.Message : "The sale could not be posted. Try again.";
                await using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                await using var rel = new NpgsqlCommand("SELECT sppoultrypendingsale_release(@Id, @F, @E)", conn);
                rel.Parameters.AddWithValue("@Id", pendingSaleId);
                rel.Parameters.AddWithValue("@F", farmId);
                rel.Parameters.AddWithValue("@E", message);
                await rel.ExecuteNonQueryAsync();
                if (ex is SaleRuleException) throw;
                throw new Exception("Error approving the waiting sale.", ex);
            }
        }

        public Task RejectAsync(int pendingSaleId, string farmId, string reason, string by) =>
            RunAsync("SELECT sppoultrypendingsale_reject(@Id, @F, @R, @B)", pendingSaleId, farmId, by, reason);

        public Task WithdrawAsync(int pendingSaleId, string farmId, string by) =>
            RunAsync("SELECT sppoultrypendingsale_withdraw(@Id, @F, @B)", pendingSaleId, farmId, by, null);

        private async Task RunAsync(string sql, int id, string farmId, string by, string? reason)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@B", by);
            if (reason is not null) cmd.Parameters.AddWithValue("@R", reason);
            try { await cmd.ExecuteNonQueryAsync(); }
            catch (PostgresException ex) when (ex.SqlState == "P0001") { throw new SaleRuleException(ex.MessageText, ex); }
        }
    }
}
