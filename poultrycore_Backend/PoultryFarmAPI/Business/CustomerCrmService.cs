// PROMPT 5: Customer Success CRM — the data behind Organization 360 and
// Company 360: a combined significant-event timeline, internal notes/contact
// history/follow-ups, product feedback, structured cancellation reasons,
// vertical-specific company summaries (adapter registry, not a giant if/else)
// and the organization activity rollup.
//
// Security: everything here is internal-only, served through the
// SystemAdmin/PlatformOwner gate. Nothing in these queries touches passwords,
// tokens or payment credentials — identifiers and aggregates only.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>Pure merge/sort/cap for timeline assembly (unit-tested).</summary>
    public static class TimelineBuilder
    {
        public static List<TimelineEventDto> Merge(int limit, params IEnumerable<TimelineEventDto>[] sources)
        {
            return sources.SelectMany(s => s)
                .OrderByDescending(e => e.AtUtc)
                .Take(Math.Clamp(limit, 1, 500))
                .ToList();
        }

        /// <summary>Health history rows → transition events only (first row and changes).</summary>
        public static List<TimelineEventDto> HealthTransitions(
            IEnumerable<(DateTime AtUtc, string Health, string? SubjectName, string? CompanyId)> ordered)
        {
            var result = new List<TimelineEventDto>();
            var last = new Dictionary<string, string>();
            foreach (var row in ordered.OrderBy(r => r.AtUtc))
            {
                var key = row.CompanyId ?? row.SubjectName ?? "";
                if (last.TryGetValue(key, out var prev) && prev == row.Health) continue;
                result.Add(new TimelineEventDto
                {
                    AtUtc = row.AtUtc,
                    Kind = "HealthChanged",
                    Title = last.ContainsKey(key)
                        ? $"Health changed to {row.Health}"
                        : $"Health recorded as {row.Health}",
                    Detail = row.SubjectName,
                    CompanyId = row.CompanyId,
                    CompanyName = row.SubjectName,
                });
                last[key] = row.Health;
            }
            return result;
        }
    }

    public interface ICustomerCrmService
    {
        Task<List<TimelineEventDto>> GetTimelineAsync(string organizationId, string? companyId, int limit);
        Task<List<CrmNoteDto>> GetNotesAsync(string? organizationId, string? companyId, string? category,
            string? assignee, string? contactType, DateTime? followUpFrom, DateTime? followUpTo);
        Task<CrmNoteDto> AddNoteAsync(CrmNoteRequest req, string actor);
        Task<CrmNoteDto?> SetNoteOutcomeAsync(long id, string outcome, string actor);
        Task<List<ProductFeedbackDto>> GetFeedbackAsync(string? organizationId, string? status);
        Task<ProductFeedbackDto> AddFeedbackAsync(ProductFeedbackRequest req, string actor);
        Task<ProductFeedbackDto?> SetFeedbackStatusAsync(long id, string status);
        Task<List<CancellationReasonDto>> GetCancellationReasonsAsync(string? organizationId);
        Task<CancellationReasonDto> AddCancellationReasonAsync(CancellationReasonRequest req, string actor);
        Task<VerticalSummaryDto> GetVerticalSummaryAsync(string companyId);
        Task<OrgActivitySummaryDto> GetOrgActivitySummaryAsync(string organizationId);
    }

    public class CustomerCrmService : ICustomerCrmService
    {
        private readonly string _cs;

        public CustomerCrmService(string connectionString) => _cs = connectionString;

        private static readonly string[] NoteCategories =
            { "Support", "Sales", "Onboarding", "Billing", "Product Feedback", "General" };
        private static readonly string[] ContactTypes =
            { "Called", "Emailed", "WhatsApp", "Meeting", "Demo", "Training" };
        private static readonly string[] CancellationCodes =
            { "TooExpensive", "MissingFeature", "HardToUse", "BusinessClosed", "TemporaryPause", "Competitor", "SupportIssue", "Other" };

        // ------------------------------------------------------------------
        // Timeline
        // ------------------------------------------------------------------
        public async Task<List<TimelineEventDto>> GetTimelineAsync(string organizationId, string? companyId, int limit)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            var registrations = new List<TimelineEventDto>();
            var firsts = new List<TimelineEventDto>();
            var billing = new List<TimelineEventDto>();
            var health = new List<(DateTime, string, string?, string?)>();
            var attention = new List<TimelineEventDto>();
            var notes = new List<TimelineEventDto>();

            // Companies created (+ org registered = earliest).
            await using (var cmd = Cmd(conn, @"
                SELECT farmid, coalesce(name, ''), createdat FROM farms
                WHERE owneruserid = @Org AND coalesce(isdeleted, false) = false
                  AND type IS DISTINCT FROM 'System'
                  AND (@Company::text IS NULL OR farmid = @Company)
                ORDER BY createdat", organizationId, companyId))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var first = true;
                while (await r.ReadAsync())
                {
                    if (r.IsDBNull(2)) continue;
                    var at = r.GetDateTime(2);
                    if (first && companyId is null)
                    {
                        registrations.Add(new TimelineEventDto { AtUtc = at, Kind = "Registered", Title = "Organization registered" });
                        first = false;
                    }
                    registrations.Add(new TimelineEventDto
                    {
                        AtUtc = at, Kind = "CompanyCreated",
                        Title = $"Company created: {r.GetString(1)}",
                        CompanyId = r.GetString(0), CompanyName = r.GetString(1),
                    });
                }
            }

            // First meaningful activity + first sale per company.
            await using (var cmd = Cmd(conn, @"
                SELECT e.companyid, max(coalesce(f.name, '')),
                       min(e.occurredatutc),
                       min(e.occurredatutc) FILTER (WHERE e.activitycategory = 'SALES')
                FROM platformactivityevents e
                LEFT JOIN farms f ON f.farmid = e.companyid
                WHERE e.organizationid = @Org AND e.ismeaningful AND e.companyid IS NOT NULL
                  AND (@Company::text IS NULL OR e.companyid = @Company)
                GROUP BY e.companyid", organizationId, companyId))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var cid = r.GetString(0);
                    var cname = r.GetString(1);
                    if (!r.IsDBNull(2))
                        firsts.Add(new TimelineEventDto
                        {
                            AtUtc = r.GetDateTime(2), Kind = "FirstMeaningful",
                            Title = $"First meaningful activity — {cname}",
                            CompanyId = cid, CompanyName = cname,
                        });
                    if (!r.IsDBNull(3))
                        firsts.Add(new TimelineEventDto
                        {
                            AtUtc = r.GetDateTime(3), Kind = "FirstSale",
                            Title = $"First sale — {cname}",
                            CompanyId = cid, CompanyName = cname,
                        });
                }
            }

            // Billing: account events, payments, trial end.
            await using (var cmd = Cmd(conn, @"
                SELECT b.eventtype, b.reason, b.actoruserid, b.createdatutc
                FROM billingevents b
                JOIN organizationbillingaccounts a ON a.id = b.accountid
                WHERE a.owneruserid = @Org
                ORDER BY b.createdatutc DESC LIMIT 50", organizationId, null))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    billing.Add(new TimelineEventDto
                    {
                        AtUtc = r.GetDateTime(3), Kind = "Billing",
                        Title = Pretty(r.GetString(0)),
                        Detail = r.IsDBNull(1) ? null : r.GetString(1),
                        Actor = r.IsDBNull(2) ? null : r.GetString(2),
                    });
            }
            await using (var cmd = Cmd(conn, @"
                SELECT p.status, p.amount, p.currencycode, coalesce(p.paymentdateutc, p.createdatutc)
                FROM platformpayments p
                JOIN organizationbillingaccounts a ON a.id = p.accountid
                WHERE a.owneruserid = @Org
                ORDER BY coalesce(p.paymentdateutc, p.createdatutc) DESC LIMIT 50", organizationId, null))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var ok = r.GetString(0) == "Succeeded";
                    billing.Add(new TimelineEventDto
                    {
                        AtUtc = r.GetDateTime(3),
                        Kind = ok ? "InvoicePaid" : "PaymentFailed",
                        Title = ok
                            ? $"Invoice paid — {r.GetString(2)} {r.GetDecimal(1)}"
                            : $"Payment failed — {r.GetString(2)} {r.GetDecimal(1)}",
                    });
                }
            }
            await using (var cmd = Cmd(conn, @"
                SELECT trialendutc, status FROM organizationbillingaccounts
                WHERE owneruserid = @Org LIMIT 1", organizationId, null))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync() && !r.IsDBNull(0))
                {
                    var te = r.GetDateTime(0);
                    billing.Add(new TimelineEventDto
                    {
                        AtUtc = te, Kind = "TrialEnds",
                        Title = te > DateTime.UtcNow ? "Trial ends" : "Trial ended",
                        Detail = r.IsDBNull(1) ? null : $"Account status: {r.GetString(1)}",
                    });
                }
            }

            // Health transitions (org + company scope).
            await using (var cmd = Cmd(conn, @"
                SELECT h.recordedatutc, h.health, h.subjectid, f.name, h.scope
                FROM customerhealthhistory h
                LEFT JOIN farms f ON f.farmid = h.subjectid
                WHERE (h.scope = 'Organization' AND h.subjectid = @Org AND @Company::text IS NULL)
                   OR (h.scope = 'Company' AND h.subjectid IN (
                        SELECT farmid FROM farms WHERE owneruserid = @Org
                          AND (@Company::text IS NULL OR farmid = @Company)))
                ORDER BY h.recordedatutc", organizationId, companyId))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var isOrg = r.GetString(4) == "Organization";
                    health.Add((r.GetDateTime(0), r.GetString(1),
                        isOrg ? "Organization" : (r.IsDBNull(3) ? r.GetString(2) : r.GetString(3)),
                        isOrg ? null : r.GetString(2)));
                }
            }

            // Attention items: significant conditions + reactivations.
            await using (var cmd = Cmd(conn, @"
                SELECT i.title, i.detectedatutc, i.companyid, f.name, i.resolutionnote, i.resolvedatutc
                FROM customerattentionitems i
                LEFT JOIN farms f ON f.farmid = i.companyid
                WHERE i.organizationid = @Org
                  AND (@Company::text IS NULL OR i.companyid = @Company)
                ORDER BY i.detectedatutc DESC LIMIT 50", organizationId, companyId))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    attention.Add(new TimelineEventDto
                    {
                        AtUtc = r.GetDateTime(1), Kind = "Attention",
                        Title = $"Attention: {r.GetString(0)}",
                        CompanyId = r.IsDBNull(2) ? null : r.GetString(2),
                        CompanyName = r.IsDBNull(3) ? null : r.GetString(3),
                    });
                    if (!r.IsDBNull(4) && !r.IsDBNull(5) && r.GetString(4).Contains("Reactivated"))
                        attention.Add(new TimelineEventDto
                        {
                            AtUtc = r.GetDateTime(5), Kind = "Reactivated",
                            Title = "Customer reactivated",
                            CompanyId = r.IsDBNull(2) ? null : r.GetString(2),
                            CompanyName = r.IsDBNull(3) ? null : r.GetString(3),
                        });
                }
            }

            // Internal notes / contacts.
            await using (var cmd = Cmd(conn, @"
                SELECT n.createdatutc, n.category, n.contacttype, n.note, n.createdby, n.companyid, f.name
                FROM customercrmnotes n
                LEFT JOIN farms f ON f.farmid = n.companyid
                WHERE n.organizationid = @Org
                  AND (@Company::text IS NULL OR n.companyid = @Company)
                ORDER BY n.createdatutc DESC LIMIT 50", organizationId, companyId))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    notes.Add(new TimelineEventDto
                    {
                        AtUtc = r.GetDateTime(0),
                        Kind = r.IsDBNull(2) ? "Note" : "Contacted",
                        Title = r.IsDBNull(2)
                            ? $"Internal note ({r.GetString(1)})"
                            : $"Customer contacted — {r.GetString(2)}",
                        Detail = Truncate(r.GetString(3), 160),
                        Actor = r.GetString(4),
                        CompanyId = r.IsDBNull(5) ? null : r.GetString(5),
                        CompanyName = r.IsDBNull(6) ? null : r.GetString(6),
                    });
            }

            return TimelineBuilder.Merge(limit, registrations, firsts, billing,
                TimelineBuilder.HealthTransitions(health), attention, notes);
        }

        private static NpgsqlCommand Cmd(NpgsqlConnection conn, string sql, string org, string? company)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Org", org);
            if (sql.Contains("@Company"))
                cmd.Parameters.AddWithValue("@Company", (object?)company ?? DBNull.Value);
            return cmd;
        }

        private static string Pretty(string eventType) =>
            System.Text.RegularExpressions.Regex.Replace(eventType, "([a-z0-9])([A-Z])", "$1 $2");

        private static string Truncate(string s, int n) => s.Length <= n ? s : s[..n] + "…";

        // ------------------------------------------------------------------
        // Internal notes / contact history / follow-ups
        // ------------------------------------------------------------------
        public async Task<List<CrmNoteDto>> GetNotesAsync(string? organizationId, string? companyId,
            string? category, string? assignee, string? contactType, DateTime? followUpFrom, DateTime? followUpTo)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<CrmNoteDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT n.id, n.organizationid, n.companyid, f.name, n.category, n.contacttype, n.note,
                       n.followupatutc, n.assignedtoname, n.outcome, n.attentionitemid, n.createdby, n.createdatutc
                FROM customercrmnotes n
                LEFT JOIN farms f ON f.farmid = n.companyid
                WHERE (@Org::text IS NULL OR n.organizationid = @Org)
                  AND (@Company::text IS NULL OR n.companyid = @Company)
                  AND (@Cat::text IS NULL OR n.category = @Cat)
                  AND (@Assignee::text IS NULL OR n.assignedtoname ILIKE '%' || @Assignee || '%')
                  AND (@Contact::text IS NULL OR n.contacttype = @Contact)
                  AND (@FuFrom::timestamptz IS NULL OR n.followupatutc >= @FuFrom)
                  AND (@FuTo::timestamptz IS NULL OR n.followupatutc <= @FuTo)
                ORDER BY n.createdatutc DESC LIMIT 500", conn);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Company", (object?)companyId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", (object?)category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Assignee", (object?)assignee ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Contact", (object?)contactType ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@FuFrom", NpgsqlDbType.TimestampTz) { Value = (object?)followUpFrom ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("@FuTo", NpgsqlDbType.TimestampTz) { Value = (object?)followUpTo ?? DBNull.Value });
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadNote(r));
            return list;
        }

        private static CrmNoteDto ReadNote(NpgsqlDataReader r) => new()
        {
            Id = r.GetInt64(0),
            OrganizationId = r.GetString(1),
            CompanyId = r.IsDBNull(2) ? null : r.GetString(2),
            CompanyName = r.IsDBNull(3) ? null : r.GetString(3),
            Category = r.GetString(4),
            ContactType = r.IsDBNull(5) ? null : r.GetString(5),
            Note = r.GetString(6),
            FollowUpAtUtc = r.IsDBNull(7) ? null : r.GetDateTime(7),
            AssignedToName = r.IsDBNull(8) ? null : r.GetString(8),
            Outcome = r.IsDBNull(9) ? null : r.GetString(9),
            AttentionItemId = r.IsDBNull(10) ? null : r.GetInt64(10),
            CreatedBy = r.GetString(11),
            CreatedAtUtc = r.GetDateTime(12),
        };

        public async Task<CrmNoteDto> AddNoteAsync(CrmNoteRequest req, string actor)
        {
            if (string.IsNullOrWhiteSpace(req.OrganizationId)) throw new ArgumentException("organizationId is required");
            if (string.IsNullOrWhiteSpace(req.Note)) throw new ArgumentException("note is required");
            var category = NoteCategories.FirstOrDefault(c =>
                string.Equals(c, req.Category, StringComparison.OrdinalIgnoreCase)) ?? "General";
            string? contact = null;
            if (!string.IsNullOrWhiteSpace(req.ContactType))
            {
                contact = ContactTypes.FirstOrDefault(c =>
                    string.Equals(c, req.ContactType, StringComparison.OrdinalIgnoreCase))
                    ?? throw new ArgumentException($"Unknown contact type '{req.ContactType}'");
            }

            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(@"
                INSERT INTO customercrmnotes
                    (organizationid, companyid, category, contacttype, note, followupatutc,
                     assignedtoname, outcome, attentionitemid, createdby)
                VALUES (@Org, @Company, @Cat, @Contact, @Note, @Fu, @Assignee, @Outcome, @Item, @By)
                RETURNING id, createdatutc", conn);
            cmd.Parameters.AddWithValue("@Org", req.OrganizationId);
            cmd.Parameters.AddWithValue("@Company", (object?)Clean(req.CompanyId) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", category);
            cmd.Parameters.AddWithValue("@Contact", (object?)contact ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", req.Note.Trim());
            cmd.Parameters.Add(new NpgsqlParameter("@Fu", NpgsqlDbType.TimestampTz) { Value = (object?)req.FollowUpAtUtc ?? DBNull.Value });
            cmd.Parameters.AddWithValue("@Assignee", (object?)Clean(req.AssignedToName) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Outcome", (object?)Clean(req.Outcome) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Item", (object?)req.AttentionItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", actor);
            await using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new CrmNoteDto
            {
                Id = r.GetInt64(0),
                OrganizationId = req.OrganizationId,
                CompanyId = Clean(req.CompanyId),
                Category = category,
                ContactType = contact,
                Note = req.Note.Trim(),
                FollowUpAtUtc = req.FollowUpAtUtc,
                AssignedToName = Clean(req.AssignedToName),
                Outcome = Clean(req.Outcome),
                AttentionItemId = req.AttentionItemId,
                CreatedBy = actor,
                CreatedAtUtc = r.GetDateTime(1),
            };
        }

        public async Task<CrmNoteDto?> SetNoteOutcomeAsync(long id, string outcome, string actor)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using (var cmd = new NpgsqlCommand(@"
                UPDATE customercrmnotes
                   SET outcome = @Outcome, updatedatutc = now()
                 WHERE id = @Id", conn))
            {
                cmd.Parameters.AddWithValue("@Id", id);
                cmd.Parameters.AddWithValue("@Outcome", $"{outcome.Trim()} — {actor}");
                if (await cmd.ExecuteNonQueryAsync() == 0) return null;
            }
            var all = await GetNotesAsync(null, null, null, null, null, null, null);
            return all.FirstOrDefault(n => n.Id == id);
        }

        private static string? Clean(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();

        // ------------------------------------------------------------------
        // Product feedback
        // ------------------------------------------------------------------
        public async Task<List<ProductFeedbackDto>> GetFeedbackAsync(string? organizationId, string? status)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<ProductFeedbackDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT x.id, x.organizationid, x.companyid, f.name, x.companyfamily, x.category,
                       x.module, x.severity, x.title, x.detail, x.status, x.createdby, x.createdatutc
                FROM customerproductfeedback x
                LEFT JOIN farms f ON f.farmid = x.companyid
                WHERE (@Org::text IS NULL OR x.organizationid = @Org)
                  AND (@Status::text IS NULL OR x.status = @Status)
                ORDER BY x.createdatutc DESC LIMIT 500", conn);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new ProductFeedbackDto
                {
                    Id = r.GetInt64(0),
                    OrganizationId = r.GetString(1),
                    CompanyId = r.IsDBNull(2) ? null : r.GetString(2),
                    CompanyName = r.IsDBNull(3) ? null : r.GetString(3),
                    CompanyFamily = r.IsDBNull(4) ? null : r.GetString(4),
                    Category = r.GetString(5),
                    Module = r.IsDBNull(6) ? null : r.GetString(6),
                    Severity = r.GetString(7),
                    Title = r.GetString(8),
                    Detail = r.IsDBNull(9) ? null : r.GetString(9),
                    Status = r.GetString(10),
                    CreatedBy = r.GetString(11),
                    CreatedAtUtc = r.GetDateTime(12),
                });
            return list;
        }

        public async Task<ProductFeedbackDto> AddFeedbackAsync(ProductFeedbackRequest req, string actor)
        {
            if (string.IsNullOrWhiteSpace(req.OrganizationId)) throw new ArgumentException("organizationId is required");
            if (string.IsNullOrWhiteSpace(req.Title)) throw new ArgumentException("title is required");
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(@"
                INSERT INTO customerproductfeedback
                    (organizationid, companyid, companyfamily, category, module, severity, title, detail, createdby)
                VALUES (@Org, @Company, @Family, @Cat, @Module, @Sev, @Title, @Detail, @By)
                RETURNING id, createdatutc", conn);
            cmd.Parameters.AddWithValue("@Org", req.OrganizationId);
            cmd.Parameters.AddWithValue("@Company", (object?)Clean(req.CompanyId) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Family", (object?)Clean(req.CompanyFamily) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", Clean(req.Category) ?? "FeatureRequest");
            cmd.Parameters.AddWithValue("@Module", (object?)Clean(req.Module) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Sev", Clean(req.Severity) ?? "Medium");
            cmd.Parameters.AddWithValue("@Title", req.Title.Trim());
            cmd.Parameters.AddWithValue("@Detail", (object?)Clean(req.Detail) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", actor);
            await using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new ProductFeedbackDto
            {
                Id = r.GetInt64(0),
                OrganizationId = req.OrganizationId,
                CompanyId = Clean(req.CompanyId),
                CompanyFamily = Clean(req.CompanyFamily),
                Category = Clean(req.Category) ?? "FeatureRequest",
                Module = Clean(req.Module),
                Severity = Clean(req.Severity) ?? "Medium",
                Title = req.Title.Trim(),
                Detail = Clean(req.Detail),
                Status = "Open",
                CreatedBy = actor,
                CreatedAtUtc = r.GetDateTime(1),
            };
        }

        public async Task<ProductFeedbackDto?> SetFeedbackStatusAsync(long id, string status)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "UPDATE customerproductfeedback SET status = @S WHERE id = @Id", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@S", status);
            if (await cmd.ExecuteNonQueryAsync() == 0) return null;
            return (await GetFeedbackAsync(null, null)).FirstOrDefault(f => f.Id == id);
        }

        // ------------------------------------------------------------------
        // Cancellation reasons
        // ------------------------------------------------------------------
        public async Task<List<CancellationReasonDto>> GetCancellationReasonsAsync(string? organizationId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<CancellationReasonDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT id, organizationid, reasoncode, note, createdby, createdatutc
                FROM subscriptioncancellationreasons
                WHERE (@Org::text IS NULL OR organizationid = @Org)
                ORDER BY createdatutc DESC LIMIT 200", conn);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new CancellationReasonDto
                {
                    Id = r.GetInt64(0),
                    OrganizationId = r.GetString(1),
                    ReasonCode = r.GetString(2),
                    Note = r.IsDBNull(3) ? null : r.GetString(3),
                    CreatedBy = r.GetString(4),
                    CreatedAtUtc = r.GetDateTime(5),
                });
            return list;
        }

        public async Task<CancellationReasonDto> AddCancellationReasonAsync(CancellationReasonRequest req, string actor)
        {
            if (string.IsNullOrWhiteSpace(req.OrganizationId)) throw new ArgumentException("organizationId is required");
            var code = CancellationCodes.FirstOrDefault(c =>
                string.Equals(c, req.ReasonCode, StringComparison.OrdinalIgnoreCase))
                ?? throw new ArgumentException($"Unknown cancellation reason '{req.ReasonCode}'");
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(@"
                INSERT INTO subscriptioncancellationreasons (organizationid, accountid, reasoncode, note, createdby)
                VALUES (@Org,
                        (SELECT id FROM organizationbillingaccounts WHERE owneruserid = @Org LIMIT 1),
                        @Code, @Note, @By)
                RETURNING id, createdatutc", conn);
            cmd.Parameters.AddWithValue("@Org", req.OrganizationId);
            cmd.Parameters.AddWithValue("@Code", code);
            cmd.Parameters.AddWithValue("@Note", (object?)Clean(req.Note) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", actor);
            await using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new CancellationReasonDto
            {
                Id = r.GetInt64(0),
                OrganizationId = req.OrganizationId,
                ReasonCode = code,
                Note = Clean(req.Note),
                CreatedBy = actor,
                CreatedAtUtc = r.GetDateTime(1),
            };
        }

        // ------------------------------------------------------------------
        // Vertical-specific company summaries — adapter registry, no giant if/else
        // ------------------------------------------------------------------
        private delegate Task FillSummary(NpgsqlConnection conn, string companyId, List<VerticalSummaryItemDto> items);

        private static readonly Dictionary<string, FillSummary> SummaryProviders =
            new(StringComparer.OrdinalIgnoreCase)
            {
                ["Poultry"] = FillPoultryAsync,
                ["Water"] = FillWaterAsync,
                ["Hotel"] = FillHotelAsync,
                ["Restaurant"] = FillRestaurantAsync,
                ["Generic"] = FillGenericAsync,
            };

        /// <summary>Families that have a vertical summary adapter (testable registry).</summary>
        public static IReadOnlyCollection<string> SupportedSummaryFamilies => SummaryProviders.Keys;

        public async Task<VerticalSummaryDto> GetVerticalSummaryAsync(string companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            string? family = null;
            await using (var cmd = new NpgsqlCommand(
                "SELECT type FROM farms WHERE farmid = @C LIMIT 1", conn))
            {
                cmd.Parameters.AddWithValue("@C", companyId);
                family = (await cmd.ExecuteScalarAsync())?.ToString();
            }
            var dto = new VerticalSummaryDto { CompanyId = companyId, CompanyFamily = family };
            if (family != null && SummaryProviders.TryGetValue(family, out var fill))
                await fill(conn, companyId, dto.Items);
            return dto;
        }

        private static async Task<string> OneAsync(NpgsqlConnection conn, string sql, string companyId)
        {
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@C", companyId);
            var v = await cmd.ExecuteScalarAsync();
            if (v is null || v is DBNull) return "—";
            if (v is DateTime dt) return dt.ToString("yyyy-MM-dd");
            return v.ToString() ?? "—";
        }

        private static async Task FillPoultryAsync(NpgsqlConnection conn, string c, List<VerticalSummaryItemDto> items)
        {
            items.Add(new() { Label = "Active flocks", Value = await OneAsync(conn, "SELECT count(*) FROM flock WHERE farmid = @C AND active AND coalesce(isdeleted,false)=false", c) });
            items.Add(new() { Label = "Active birds", Value = await OneAsync(conn, "SELECT coalesce(sum(quantity),0) FROM flock WHERE farmid = @C AND active AND coalesce(isdeleted,false)=false", c) });
            items.Add(new() { Label = "Last production", Value = await OneAsync(conn, "SELECT greatest(max(p.date), (SELECT max(e.productiondate) FROM eggproduction e WHERE e.farmid = @C))::date FROM productionrecords p WHERE p.farmid = @C", c) });
            items.Add(new() { Label = "Production days (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM companyusagedaily WHERE companyid = @C AND productioncount > 0 AND businessdate > current_date - 30", c) });
            items.Add(new() { Label = "Last sale", Value = await OneAsync(conn, "SELECT max(saledate)::date FROM sale WHERE farmid = @C", c) });
            items.Add(new() { Label = "Daily closings (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM poultrydailyclosings WHERE farmid = @C AND closingdate > current_date - 30", c) });
        }

        private static async Task FillWaterAsync(NpgsqlConnection conn, string c, List<VerticalSummaryItemDto> items)
        {
            items.Add(new() { Label = "Production lines", Value = await OneAsync(conn, "SELECT count(*) FROM waterproductionlines WHERE farmid = @C", c) });
            items.Add(new() { Label = "Last production", Value = await OneAsync(conn, "SELECT max(productiondate)::date FROM waterdailyproductions WHERE farmid = @C AND coalesce(isdeleted,false)=false", c) });
            items.Add(new() { Label = "Driver returns (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM waterdriverreturns WHERE farmid = @C AND returndate > current_date - 30", c) });
            items.Add(new() { Label = "Last sale", Value = await OneAsync(conn, "SELECT max(saledate)::date FROM watersales WHERE farmid = @C", c) });
            items.Add(new() { Label = "Daily closings (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM waterdailyclosings WHERE farmid = @C AND closingdate > current_date - 30", c) });
        }

        private static async Task FillHotelAsync(NpgsqlConnection conn, string c, List<VerticalSummaryItemDto> items)
        {
            items.Add(new() { Label = "Active rooms", Value = await OneAsync(conn, "SELECT count(*) FROM hotelrooms WHERE farmid = @C AND coalesce(isactive, true)", c) });
            items.Add(new() { Label = "Bookings (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM hotelbookings WHERE farmid = @C AND createdat > now() - interval '30 days'", c) });
            items.Add(new() { Label = "Check-ins (7d)", Value = await OneAsync(conn, "SELECT count(*) FROM hotelcheckins WHERE farmid = @C AND checkintime > now() - interval '7 days'", c) });
            items.Add(new() { Label = "Last closing", Value = await OneAsync(conn, "SELECT max(closingdate)::date FROM hoteldailyclosings WHERE farmid = @C", c) });
        }

        private static async Task FillRestaurantAsync(NpgsqlConnection conn, string c, List<VerticalSummaryItemDto> items)
        {
            items.Add(new() { Label = "Menu items", Value = await OneAsync(conn, "SELECT count(*) FROM restaurantmenuitems WHERE farmid = @C", c) });
            items.Add(new() { Label = "Orders (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM restaurantorders WHERE farmid = @C AND createdat > now() - interval '30 days'", c) });
            items.Add(new() { Label = "Last order", Value = await OneAsync(conn, "SELECT max(createdat)::date FROM restaurantorders WHERE farmid = @C", c) });
            items.Add(new() { Label = "Daily closings (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM restaurantdailyclosings WHERE farmid = @C AND closingdate > current_date - 30", c) });
        }

        private static async Task FillGenericAsync(NpgsqlConnection conn, string c, List<VerticalSummaryItemDto> items)
        {
            items.Add(new() { Label = "Customers", Value = await OneAsync(conn, "SELECT count(*) FROM genericcustomers WHERE farmid = @C", c) });
            items.Add(new() { Label = "Sales (30d)", Value = await OneAsync(conn, "SELECT count(*) FROM genericsales WHERE farmid = @C AND coalesce(isdeleted,false)=false AND saledate > current_date - 30", c) });
            items.Add(new() { Label = "Last sale", Value = await OneAsync(conn, "SELECT max(saledate)::date FROM genericsales WHERE farmid = @C AND coalesce(isdeleted,false)=false", c) });
            items.Add(new() { Label = "Last customer payment", Value = await OneAsync(conn, "SELECT max(paymentdate)::date FROM genericcustomerpayments WHERE farmid = @C", c) });
            items.Add(new() { Label = "Subscriptions", Value = await OneAsync(conn, "SELECT count(*) FROM genericsubscriptions WHERE farmid = @C", c) });
        }

        // ------------------------------------------------------------------
        // Organization activity summary (7/30/90)
        // ------------------------------------------------------------------
        public async Task<OrgActivitySummaryDto> GetOrgActivitySummaryAsync(string organizationId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var dto = new OrgActivitySummaryDto();

            foreach (var days in new[] { 7, 30, 90 })
            {
                await using var cmd = new NpgsqlCommand(@"
                    SELECT coalesce(sum(d.meaningfulactivitycount), 0),
                           count(DISTINCT d.businessdate) FILTER (WHERE d.meaningfulactivitycount > 0),
                           (SELECT count(DISTINCT u.userid)
                              FROM companyusagedailyusers u
                              JOIN farms uf ON uf.farmid = u.companyid
                             WHERE uf.owneruserid = @Org AND u.businessdate > current_date - @D)
                    FROM companyusagedaily d
                    JOIN farms f ON f.farmid = d.companyid
                    WHERE f.owneruserid = @Org AND d.businessdate > current_date - @D", conn);
                cmd.Parameters.AddWithValue("@Org", organizationId);
                cmd.Parameters.AddWithValue("@D", days);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                    dto.Windows.Add(new OrgActivityWindowDto
                    {
                        Days = days,
                        MeaningfulCount = Convert.ToInt64(r.GetValue(0)),
                        ActiveDays = Convert.ToInt32(r.GetValue(1)),
                        ActiveUsers = Convert.ToInt32(r.GetValue(2)),
                    });
            }

            await using (var cmd = new NpgsqlCommand(@"
                SELECT activitycategory, count(*) FILTER (WHERE ismeaningful), count(*)
                FROM platformactivityevents
                WHERE organizationid = @Org AND occurredatutc > now() - interval '90 days'
                GROUP BY activitycategory ORDER BY 2 DESC LIMIT 8", conn))
            {
                cmd.Parameters.AddWithValue("@Org", organizationId);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    dto.TopCategories.Add(new CategoryCountDto
                    {
                        Key = r.GetString(0),
                        MeaningfulCount = r.GetInt64(1),
                        TotalCount = r.GetInt64(2),
                    });
            }

            await using (var cmd = new NpgsqlCommand(@"
                SELECT currentperiodend FROM organizationbillingaccounts
                WHERE owneruserid = @Org LIMIT 1", conn))
            {
                cmd.Parameters.AddWithValue("@Org", organizationId);
                var v = await cmd.ExecuteScalarAsync();
                if (v is DateTime d) dto.NextBillingUtc = d;
            }
            return dto;
        }
    }
}
