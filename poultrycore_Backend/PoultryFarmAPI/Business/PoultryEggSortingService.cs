// Egg Sorting Workspace (migrations 341-343). Orchestration only: availability,
// the Unsorted -> size transformation, locking, reversal rules and the ledger
// rows all live in the database functions. This file sends parameters and maps
// rows.

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryEggSortingService
    {
        Task<EggSortingSettings> GetSettingsAsync(string farmId);
        Task SaveSettingsAsync(EggSortingSettingsRequest req, string? by);
        /// <summary>Unsorted + sizes with stock on hand. Seeds the default sizes on first use when asked.</summary>
        Task<IReadOnlyList<EggClass>> GetClassesAsync(string farmId, bool includeInactive, bool ensureSizes, string? by);
        Task<int> SaveSizeAsync(EggSizeSaveRequest req, string? by);
        Task<IReadOnlyList<EggSortingPick>> GetPicksAsync(string farmId, DateTime? from, DateTime? to, int? flockId, int[]? recordIds);
        Task<EggSortingSummary?> GetSummaryAsync(string farmId, DateTime? date);
        Task<IReadOnlyList<EggSortingSession>> GetSessionsAsync(string farmId, DateTime? from, DateTime? to, string? status, int? recordId, int? sessionId);
        /// <summary>Save a draft (and post it in the same transaction when req.Post). Throws PostgresException P0003 / P0001.</summary>
        Task<int> SaveAsync(EggSortingSaveRequest req, int? sessionId, string by);
        Task DiscardAsync(string farmId, int sessionId, string? by);
        /// <summary>Throws PostgresException P0006 when sized eggs were already sold or used.</summary>
        Task ReverseAsync(string farmId, int sessionId, string reason, string by);
        Task<IReadOnlyList<EggCompositionRow>> GetCompositionAsync(string farmId, DateTime from, DateTime to, string groupBy, int? flockId);
        Task<IReadOnlyList<EggCarryoverRow>> GetCarryoverAsync(string farmId, DateTime from, DateTime to, int? flockId);
        Task<IReadOnlyList<EggLedgerRow>> GetLedgerAsync(string farmId, DateTime? from, DateTime? to, int? productId);
        Task<IReadOnlyList<ProductionDuplicateGroup>> GetDuplicatesAsync(string farmId);
        Task SetSizePriceAsync(string farmId, int eggSizeId, decimal? pricePerCrate, string? by);
        /// <summary>Throws PostgresException P0003 when the class would go below zero.</summary>
        Task<int> AdjustClassAsync(EggClassAdjustRequest req, string by);
        Task<IReadOnlyList<EggSortingAuditRow>> GetAuditAsync(string farmId, string? entity, int? entityId, int limit);
        /// <summary>The farm's eggs per crate (344), 30 when not set or before 344.</summary>
        Task<int> GetEggsPerCrateAsync(string farmId);
    }

    public class PoultryEggSortingService : IPoultryEggSortingService
    {
        private readonly string _cs;
        public PoultryEggSortingService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

        public async Task<EggSortingSettings> GetSettingsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryeggsortingsettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new EggSortingSettings { FarmId = farmId };
            return new EggSortingSettings
            {
                FarmId = farmId,
                EnableEggSorting = r.GetBoolean(r.GetOrdinal("enableeggsorting")),
                ClosingPolicy = Str(r, "closingpolicy") ?? "Warning",
                IsCustomised = r.GetBoolean(r.GetOrdinal("iscustomised")),
                UpdatedBy = Str(r, "updatedby"),
                UpdatedAtUtc = Date(r, "updatedatutc"),
                // 344 columns; absent on a database that has only 341-343.
                EggsPerCrate = Has(r, "eggspercrate") ? Int(r, "eggspercrate") ?? 30 : 30,
                UnsortedPricePerCrate = Has(r, "unsortedpricepercrate") ? Dec(r, "unsortedpricepercrate") : null,
            };
        }

        public async Task SaveSettingsAsync(EggSortingSettingsRequest req, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            if (await FunctionExistsAsync(c, "sppoultryeggsortingsettings_save"))
            {
                using var save = new NpgsqlCommand(
                    "SELECT sppoultryeggsortingsettings_save(p_farmid => @FarmId::text, p_enableeggsorting => @On::boolean, "
                    + "p_closingpolicy => @Policy::text, p_eggspercrate => @Crate::int, p_unsortedpricepercrate => @Price::numeric, "
                    + "p_by => @By::text)", c);
                save.Parameters.AddWithValue("@FarmId", req.FarmId);
                save.Parameters.AddWithValue("@On", req.EnableEggSorting);
                save.Parameters.AddWithValue("@Policy", string.IsNullOrWhiteSpace(req.ClosingPolicy) ? "Warning" : req.ClosingPolicy);
                save.Parameters.AddWithValue("@Crate", req.EggsPerCrate <= 0 ? 30 : req.EggsPerCrate);
                save.Parameters.AddWithValue("@Price", (object?)req.UnsortedPricePerCrate ?? DBNull.Value);
                save.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
                await save.ExecuteNonQueryAsync();
                return;
            }
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryeggsortingsettings_set(p_farmid => @FarmId::text, p_enableeggsorting => @On::boolean, "
                + "p_closingpolicy => @Policy::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@On", req.EnableEggSorting);
            cmd.Parameters.AddWithValue("@Policy", string.IsNullOrWhiteSpace(req.ClosingPolicy) ? "Warning" : req.ClosingPolicy);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<EggClass>> GetClassesAsync(string farmId, bool includeInactive, bool ensureSizes, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            if (ensureSizes)
            {
                using var seed = new NpgsqlCommand("SELECT sppoultryeggsizes_ensure(p_farmid => @FarmId::text, p_by => @By::text)", c);
                seed.Parameters.AddWithValue("@FarmId", farmId);
                seed.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
                await seed.ExecuteNonQueryAsync();
            }
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggclasses_get(p_farmid => @FarmId::text, p_includeinactive => @All::boolean)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@All", includeInactive);
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggClass>();
            while (await r.ReadAsync())
            {
                list.Add(new EggClass
                {
                    PoultryProductId = r.GetInt32(r.GetOrdinal("poultryproductid")),
                    EggSizeId = Int(r, "eggsizeid"),
                    Name = Str(r, "name") ?? string.Empty,
                    ClassKind = Str(r, "classkind") ?? "Unsorted",
                    SortOrder = Int(r, "sortorder") ?? 0,
                    IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                    OnHand = Dec(r, "onhand") ?? 0,
                    PricePerCrate = Has(r, "pricepercrate") ? Dec(r, "pricepercrate") : null,
                });
            }
            return list;
        }

        public async Task<int> SaveSizeAsync(EggSizeSaveRequest req, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryeggsize_save(p_farmid => @FarmId::text, p_eggsizeid => @Id::int, p_name => @Name::text, "
                + "p_sortorder => @Sort::int, p_isactive => @Active::boolean, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", (object?)req.EggSizeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", req.Name ?? string.Empty);
            cmd.Parameters.AddWithValue("@Sort", (object?)req.SortOrder ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Active", req.IsActive);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<IReadOnlyList<EggSortingPick>> GetPicksAsync(string farmId, DateTime? from, DateTime? to, int? flockId, int[]? recordIds)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_picks(p_farmid => @FarmId::text, p_fromdate => @From::date, "
                + "p_todate => @To::date, p_flockid => @Flock::int, p_recordids => @Ids)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Flock", (object?)flockId ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@Ids", NpgsqlDbType.Array | NpgsqlDbType.Integer)
            {
                Value = recordIds is { Length: > 0 } ? recordIds : DBNull.Value,
            });
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggSortingPick>();
            while (await r.ReadAsync())
            {
                list.Add(new EggSortingPick
                {
                    ProductionRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    BatchName = Str(r, "batchname"),
                    HouseName = Str(r, "housename"),
                    ProductionDate = r.GetDateTime(r.GetOrdinal("productiondate")),
                    PickNumber = r.GetInt32(r.GetOrdinal("picknumber")),
                    PickGross = Int(r, "pickgross") ?? 0,
                    PickSorted = Int(r, "picksorted") ?? 0,
                    PickLeft = Int(r, "pickleft") ?? 0,
                    Available = Int(r, "available") ?? 0,
                    RecordGross = Int(r, "recordgross") ?? 0,
                    RecordCollectionLoss = Int(r, "recordcollectionloss") ?? 0,
                    RecordSaleable = Int(r, "recordsaleable") ?? 0,
                    RecordSorted = Int(r, "recordsorted") ?? 0,
                    RecordLeft = Int(r, "recordleft") ?? 0,
                    ByPickSorted = Int(r, "bypicksorted") ?? 0,
                });
            }
            return list;
        }

        public async Task<EggSortingSummary?> GetSummaryAsync(string farmId, DateTime? date)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_summary(p_farmid => @FarmId::text, p_date => @Date::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", date.HasValue ? date.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new EggSortingSummary
            {
                BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                UnsortedOnHand = Dec(r, "unsortedonhand") ?? 0,
                SizedOnHand = Dec(r, "sizedonhand") ?? 0,
                SortedToday = Int(r, "sortedtoday") ?? 0,
                SizedCreatedToday = Int(r, "sizedcreatedtoday") ?? 0,
                LossToday = Int(r, "losstoday") ?? 0,
                SessionsToday = Int(r, "sessionstoday") ?? 0,
                ProductionLeft = Int(r, "productionleft") ?? 0,
                RecordsWithLeft = Int(r, "recordswithleft") ?? 0,
                OldestLeftDate = Date(r, "oldestleftdate"),
            };
        }

        public async Task<IReadOnlyList<EggSortingSession>> GetSessionsAsync(string farmId, DateTime? from, DateTime? to, string? status, int? recordId, int? sessionId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_sessions(p_farmid => @FarmId::text, p_fromdate => @From::date, "
                + "p_todate => @To::date, p_status => @Status::text, p_recordid => @Record::int, p_sessionid => @Id::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status);
            cmd.Parameters.AddWithValue("@Record", (object?)recordId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Id", (object?)sessionId ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggSortingSession>();
            while (await r.ReadAsync())
            {
                var s = new EggSortingSession
                {
                    SessionId = r.GetInt32(r.GetOrdinal("sessionid")),
                    SessionNo = Str(r, "sessionno") ?? string.Empty,
                    SortingMode = Str(r, "sortingmode") ?? "ByPick",
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = Int(r, "productionrecordid"),
                    PickNumber = Int(r, "picknumber"),
                    ScopeRecordIds = r.IsDBNull(r.GetOrdinal("scoperecordids")) ? Array.Empty<int>() : r.GetFieldValue<int[]>(r.GetOrdinal("scoperecordids")),
                    SortingDate = r.GetDateTime(r.GetOrdinal("sortingdate")),
                    Status = Str(r, "status") ?? "Draft",
                    InputQuantity = Int(r, "inputquantity") ?? 0,
                    OutputQuantity = Int(r, "outputquantity") ?? 0,
                    LossQuantity = Int(r, "lossquantity") ?? 0,
                    Notes = Str(r, "notes"),
                    CreatedBy = Str(r, "createdby"),
                    CreatedAtUtc = Date(r, "createdatutc") ?? DateTime.MinValue,
                    PostedBy = Str(r, "postedby"),
                    PostedAtUtc = Date(r, "postedatutc"),
                    ReversedBy = Str(r, "reversedby"),
                    ReversedAtUtc = Date(r, "reversedatutc"),
                    ReversalReason = Str(r, "reversalreason"),
                    FirstProductionDate = Date(r, "firstproductiondate"),
                    LastProductionDate = Date(r, "lastproductiondate"),
                };
                var lines = Str(r, "linesjson");
                if (!string.IsNullOrWhiteSpace(lines))
                    s.Lines = JsonSerializer.Deserialize<List<EggSortingLine>>(lines, Json) ?? new();
                var sources = Str(r, "sourcesjson");
                if (!string.IsNullOrWhiteSpace(sources))
                    s.Sources = JsonSerializer.Deserialize<List<EggSortingSource>>(sources, Json) ?? new();
                list.Add(s);
            }
            return list;
        }

        public async Task<int> SaveAsync(EggSortingSaveRequest req, int? sessionId, string by)
        {
            var lines = JsonSerializer.Serialize(req.Lines.Select(l => new
            {
                lineType = l.LineType,
                eggSizeId = l.EggSizeId,
                quantity = l.Quantity,
                notes = l.Notes,
            }));

            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            // Save and post succeed or fail together: a refused post leaves no
            // half-saved draft behind the user's back.
            await using var tx = await c.BeginTransactionAsync();

            using var save = new NpgsqlCommand(
                "SELECT sppoultryeggsorting_save(p_farmid => @FarmId::text, p_sessionid => @Id::int, p_mode => @Mode::text, "
                + "p_sortingdate => @Date::date, p_recordids => @Records, p_picknumber => @Pick::int, "
                + "p_linesjson => @Lines::text, p_notes => @Notes::text, p_clientrequestid => @Req::uuid, p_by => @By::text)", c, tx);
            save.Parameters.AddWithValue("@FarmId", req.FarmId);
            save.Parameters.AddWithValue("@Id", (object?)sessionId ?? DBNull.Value);
            save.Parameters.AddWithValue("@Mode", req.SortingMode);
            save.Parameters.AddWithValue("@Date", req.SortingDate.Date);
            save.Parameters.Add(new NpgsqlParameter("@Records", NpgsqlDbType.Array | NpgsqlDbType.Integer) { Value = req.ProductionRecordIds ?? Array.Empty<int>() });
            save.Parameters.AddWithValue("@Pick", (object?)req.PickNumber ?? DBNull.Value);
            save.Parameters.AddWithValue("@Lines", lines);
            save.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            save.Parameters.AddWithValue("@Req", (object?)req.ClientRequestId ?? DBNull.Value);
            save.Parameters.AddWithValue("@By", by);
            var id = Convert.ToInt32(await save.ExecuteScalarAsync());

            if (req.Post)
            {
                using var post = new NpgsqlCommand(
                    "SELECT sppoultryeggsorting_post(p_farmid => @FarmId::text, p_sessionid => @Id::int, p_by => @By::text)", c, tx);
                post.Parameters.AddWithValue("@FarmId", req.FarmId);
                post.Parameters.AddWithValue("@Id", id);
                post.Parameters.AddWithValue("@By", by);
                await post.ExecuteNonQueryAsync();
            }

            await tx.CommitAsync();
            return id;
        }

        public async Task DiscardAsync(string farmId, int sessionId, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            // 344 adds p_by (who discarded, for the audit trail).
            var withBy = await FunctionHasArgAsync(c, "sppoultryeggsorting_discard", "p_by");
            using var cmd = new NpgsqlCommand(withBy
                ? "SELECT sppoultryeggsorting_discard(p_farmid => @FarmId::text, p_sessionid => @Id::int, p_by => @By::text)"
                : "SELECT sppoultryeggsorting_discard(p_farmid => @FarmId::text, p_sessionid => @Id::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", sessionId);
            if (withBy) cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task SetSizePriceAsync(string farmId, int eggSizeId, decimal? pricePerCrate, string? by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryeggsize_setprice(p_farmid => @FarmId::text, p_eggsizeid => @Id::int, "
                + "p_pricepercrate => @Price::numeric, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", eggSizeId);
            cmd.Parameters.AddWithValue("@Price", (object?)pricePerCrate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> AdjustClassAsync(EggClassAdjustRequest req, string by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryeggclass_adjust(p_farmid => @FarmId::text, p_poultryproductid => @Product::int, "
                + "p_kind => @Kind::text, p_quantity => @Qty::int, p_reason => @Reason::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Product", req.PoultryProductId);
            cmd.Parameters.AddWithValue("@Kind", req.Kind ?? string.Empty);
            cmd.Parameters.AddWithValue("@Qty", req.Quantity);
            cmd.Parameters.AddWithValue("@Reason", req.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", by);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<IReadOnlyList<EggSortingAuditRow>> GetAuditAsync(string farmId, string? entity, int? entityId, int limit)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_audit(p_farmid => @FarmId::text, p_entity => @Entity::text, "
                + "p_entityid => @Id::int, p_limit => @Limit::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Entity", string.IsNullOrWhiteSpace(entity) ? DBNull.Value : entity);
            cmd.Parameters.AddWithValue("@Id", (object?)entityId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Limit", limit);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggSortingAuditRow>();
            while (await r.ReadAsync())
            {
                list.Add(new EggSortingAuditRow
                {
                    AuditId = Long(r, "auditid"),
                    Entity = Str(r, "entity") ?? string.Empty,
                    EntityId = Int(r, "entityid"),
                    Action = Str(r, "action") ?? string.Empty,
                    Actor = Str(r, "actor"),
                    Details = Str(r, "details"),
                    AtUtc = Date(r, "atutc") ?? DateTime.MinValue,
                });
            }
            return list;
        }

        public async Task<int> GetEggsPerCrateAsync(string farmId)
        {
            try
            {
                using var c = new NpgsqlConnection(_cs);
                using var cmd = new NpgsqlCommand("SELECT fnpoultry_eggspercrate(@FarmId::text)", c);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await c.OpenAsync();
                var v = await cmd.ExecuteScalarAsync();
                return v is null || v is DBNull ? 30 : Convert.ToInt32(v);
            }
            catch (PostgresException)
            {
                return 30;   // before 344
            }
        }

        private static async Task<bool> FunctionExistsAsync(NpgsqlConnection c, string name)
        {
            using var probe = new NpgsqlCommand(
                "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                + "WHERE n.nspname = 'public' AND p.proname = @Name LIMIT 1", c);
            probe.Parameters.AddWithValue("@Name", name);
            return await probe.ExecuteScalarAsync() is not null;
        }

        private static async Task<bool> FunctionHasArgAsync(NpgsqlConnection c, string name, string arg)
        {
            using var probe = new NpgsqlCommand(
                "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                + "WHERE n.nspname = 'public' AND p.proname = @Name AND @Arg = ANY(p.proargnames) LIMIT 1", c);
            probe.Parameters.AddWithValue("@Name", name);
            probe.Parameters.AddWithValue("@Arg", arg);
            return await probe.ExecuteScalarAsync() is not null;
        }

        private static bool Has(NpgsqlDataReader r, string col)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public async Task ReverseAsync(string farmId, int sessionId, string reason, string by)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryeggsorting_reverse(p_farmid => @FarmId::text, p_sessionid => @Id::int, "
                + "p_reason => @Reason::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", sessionId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", by);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<EggCompositionRow>> GetCompositionAsync(string farmId, DateTime from, DateTime to, string groupBy, int? flockId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_composition(p_farmid => @FarmId::text, p_fromdate => @From::date, "
                + "p_todate => @To::date, p_groupby => @By::text, p_flockid => @Flock::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.Date);
            cmd.Parameters.AddWithValue("@To", to.Date);
            cmd.Parameters.AddWithValue("@By", string.IsNullOrWhiteSpace(groupBy) ? "productiondate" : groupBy);
            cmd.Parameters.AddWithValue("@Flock", (object?)flockId ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggCompositionRow>();
            while (await r.ReadAsync())
            {
                list.Add(new EggCompositionRow
                {
                    GroupKey = Str(r, "groupkey") ?? string.Empty,
                    GroupLabel = Str(r, "grouplabel") ?? string.Empty,
                    GroupSort = Str(r, "groupsort") ?? string.Empty,
                    LineType = Str(r, "linetype") ?? string.Empty,
                    EggSizeId = Int(r, "eggsizeid"),
                    SizeName = Str(r, "sizename"),
                    SizeSort = Int(r, "sizesort") ?? 0,
                    Quantity = Dec(r, "quantity") ?? 0,
                    Sessions = Int(r, "sessions") ?? 0,
                    CombinedSessions = Int(r, "combinedsessions") ?? 0,
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<EggCarryoverRow>> GetCarryoverAsync(string farmId, DateTime from, DateTime to, int? flockId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggsorting_carryover(p_farmid => @FarmId::text, p_fromdate => @From::date, "
                + "p_todate => @To::date, p_flockid => @Flock::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.Date);
            cmd.Parameters.AddWithValue("@To", to.Date);
            cmd.Parameters.AddWithValue("@Flock", (object?)flockId ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggCarryoverRow>();
            while (await r.ReadAsync())
            {
                list.Add(new EggCarryoverRow
                {
                    ProductionDate = r.GetDateTime(r.GetOrdinal("productiondate")),
                    Records = Int(r, "records") ?? 0,
                    Gross = Long(r, "gross"),
                    CollectionLoss = Long(r, "collectionloss"),
                    Saleable = Long(r, "saleable"),
                    Sorted = Long(r, "sorted"),
                    LeftUnsorted = Long(r, "leftunsorted"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<EggLedgerRow>> GetLedgerAsync(string farmId, DateTime? from, DateTime? to, int? productId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryeggledger(p_farmid => @FarmId::text, p_fromdate => @From::date, "
                + "p_todate => @To::date, p_poultryproductid => @Product::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Product", (object?)productId ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<EggLedgerRow>();
            while (await r.ReadAsync())
            {
                list.Add(new EggLedgerRow
                {
                    TransactionId = r.GetInt32(r.GetOrdinal("transactionid")),
                    CreatedAtUtc = r.GetDateTime(r.GetOrdinal("createdatutc")),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    TxnType = Str(r, "txntype") ?? string.Empty,
                    PoultryProductId = r.GetInt32(r.GetOrdinal("poultryproductid")),
                    ClassName = Str(r, "classname") ?? string.Empty,
                    ClassKind = Str(r, "classkind") ?? string.Empty,
                    QuantityIn = Dec(r, "quantityin") ?? 0,
                    QuantityOut = Dec(r, "quantityout") ?? 0,
                    RunningBalance = Dec(r, "runningbalance") ?? 0,
                    RelatedId = Int(r, "relatedid"),
                    Note = Str(r, "note"),
                    CreatedBy = Str(r, "createdby"),
                    FlockId = Int(r, "flockid"),
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = Int(r, "productionrecordid"),
                    PickNumbers = Str(r, "picknumbers"),
                    SortingSessionNo = Str(r, "sortingsessionno"),
                    SaleId = Int(r, "saleid"),
                    CustomerName = Str(r, "customername"),
                    SaleGroupNo = Str(r, "salegroupno"),
                    Reference = Str(r, "reference"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<ProductionDuplicateGroup>> GetDuplicatesAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduction_duplicates(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<ProductionDuplicateGroup>();
            while (await r.ReadAsync())
            {
                list.Add(new ProductionDuplicateGroup
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    ProductionDate = r.GetDateTime(r.GetOrdinal("productiondate")),
                    RecordCount = Int(r, "recordcount") ?? 0,
                    RecordIds = r.IsDBNull(r.GetOrdinal("recordids")) ? Array.Empty<int>() : r.GetFieldValue<int[]>(r.GetOrdinal("recordids")),
                    TotalEggs = Long(r, "totaleggs"),
                    Grades = Str(r, "grades"),
                });
            }
            return list;
        }

        // ---- row helpers -----------------------------------------------------
        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToString(r.GetValue(i));
        }

        private static int? Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static long Long(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0 : Convert.ToInt64(r.GetValue(i));
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
        }

        private static DateTime? Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            if (r.IsDBNull(i)) return null;
            var v = r.GetValue(i);
            return v switch
            {
                DateTime dt => dt,
                DateTimeOffset dto => dto.UtcDateTime,
                DateOnly d => d.ToDateTime(TimeOnly.MinValue),
                _ => Convert.ToDateTime(v),
            };
        }
    }
}
