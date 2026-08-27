using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // WaterInternalUsageService (migration 212)
    //
    // Thin ADO.NET wrapper over spwaterinternalusage_*, following
    // WaterDailyProductionService. Two things to know:
    //  * Items travel as a JSON array. The SP computes UnitsPerEntryUnit and
    //    StockQuantity from waterproducts.sachetsperbag, so a client cannot post
    //    a quantity that disagrees with the conversion.
    //  * Post/Reverse use ExecuteNonQueryAsync; the SPs return void and any
    //    RAISE EXCEPTION surfaces through GlobalExceptionMiddleware as
    //    structured JSON the frontend can toast verbatim.
    // =========================================================================
    public interface IWaterInternalUsageService
    {
        Task<List<WaterInternalUsageModel>> GetAllAsync(string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate);
        Task<WaterInternalUsageModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(WaterInternalUsageModel m);
        Task       UpdateAsync(WaterInternalUsageModel m);
        Task       DeleteAsync(int id, string farmId, string? userId);
        Task       PostAsync(int id, string farmId, string? postedBy);
        Task       ReverseAsync(int id, string farmId, string? reason, string? reversedBy);
        Task<decimal> GetSuggestedCostAsync(string farmId, int waterProductId, string? entryUnit);
    }

    public class WaterInternalUsageService : IWaterInternalUsageService
    {
        private readonly string _cs;
        public WaterInternalUsageService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        };

        // ---------------------------------------------------------------- read
        public async Task<List<WaterInternalUsageModel>> GetAllAsync(
            string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterInternalUsageModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterinternalusage_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_category => @Category::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Category", (object?)category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }

        public async Task<WaterInternalUsageModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterinternalusage_getbyid(p_waterinternalusageid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Map(r) : null;
        }

        // Unit-aware: a bag is priced as a bag, not as thirty sachets, because
        // bulk pricing means bagPrice is rarely 30 x sachetPrice (migration 218).
        public async Task<decimal> GetSuggestedCostAsync(string farmId, int waterProductId, string? entryUnit)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.fnwaterproductentrycost(@FarmId::text, @WaterProductId::int, @EntryUnit::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductId", waterProductId);
            cmd.Parameters.AddWithValue("@EntryUnit", (object?)entryUnit ?? DBNull.Value);
            await conn.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            return v is null || v == DBNull.Value ? 0m : Convert.ToDecimal(v);
        }

        // --------------------------------------------------------------- write
        public async Task<int> InsertAsync(WaterInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spwaterinternalusage_insert(p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_createdby => @CreatedBy::text)", conn);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            var id = await cmd.ExecuteScalarAsync();
            return id is null || id == DBNull.Value ? 0 : Convert.ToInt32(id);
        }

        public async Task UpdateAsync(WaterInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spwaterinternalusage_update(p_waterinternalusageid => @Id::int, p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.WaterInternalUsageId);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spwaterinternalusage_delete(p_waterinternalusageid => @Id::int, p_farmid => @FarmId::text, p_userid => @UserId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task PostAsync(int id, string farmId, string? postedBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spwaterinternalusage_post(p_waterinternalusageid => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PostedBy", (object?)postedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId, string? reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spwaterinternalusage_reverse(p_waterinternalusageid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)reversedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // -------------------------------------------------------------- helpers
        private static void AddHeaderParams(NpgsqlCommand cmd, WaterInternalUsageModel m)
        {
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@UsageDate", m.UsageDate);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RecipientName", (object?)m.RecipientName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StaffCount", (object?)m.StaffCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", BuildItemsJson(m.Items));
        }

        // Only the fields the SP reads. UnitsPerEntryUnit, StockQuantity, UnitCost
        // and TotalCost are deliberately NOT sent: the SP derives them, so the
        // stored conversion and costing can never disagree with the product's
        // configuration or with what the user typed.
        private static string BuildItemsJson(List<WaterInternalUsageItemModel>? items)
        {
            if (items is null || items.Count == 0) return "[]";
            return JsonSerializer.Serialize(
                items.Where(x => x.WaterProductId > 0 && x.EntryQuantity > 0)
                     .Select(x => new
                     {
                         waterProductId   = x.WaterProductId,
                         entryQuantity    = x.EntryQuantity,
                         entryUnit        = x.EntryUnit,
                         quantityPerStaff = x.QuantityPerStaff,
                         entryUnitCost    = x.EntryUnitCost,
                         itemNotes        = x.ItemNotes,
                     }));
        }

        private static WaterInternalUsageModel Map(NpgsqlDataReader r) => new()
        {
            WaterInternalUsageId = GetInt(r, "waterinternalusageid"),
            FarmId             = GetString(r, "farmid") ?? string.Empty,
            UsageDate          = GetDate(r, "usagedate") ?? DateTime.UtcNow,
            ReferenceNo        = GetString(r, "referenceno"),
            Category           = GetString(r, "category") ?? string.Empty,
            Reason             = GetString(r, "reason"),
            RecipientName      = GetString(r, "recipientname"),
            ResponsibleStaffId = GetNullableInt(r, "responsiblestaffid"),
            StaffCount         = GetNullableInt(r, "staffcount"),
            Status             = GetString(r, "status") ?? InternalUseStatus.Draft,
            TotalCostValue     = GetDecimal(r, "totalcostvalue"),
            Notes              = GetString(r, "notes"),
            PostedBy           = GetString(r, "postedby"),
            PostedAt           = GetDate(r, "postedat"),
            ReversedBy         = GetString(r, "reversedby"),
            ReversedAt         = GetDate(r, "reversedat"),
            ReversalReason     = GetString(r, "reversalreason"),
            CreatedBy          = GetString(r, "createdby"),
            CreatedAt          = GetDate(r, "createdat") ?? DateTime.UtcNow,
            UpdatedAt          = GetDate(r, "updatedat"),
            Items              = DeserializeItems(GetString(r, "itemsjson")),
        };

        // json_agg yields NULL, not "[]", when the sub-select is empty — guard it.
        private static List<WaterInternalUsageItemModel> DeserializeItems(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new();
            try { return JsonSerializer.Deserialize<List<WaterInternalUsageItemModel>>(json, JsonOpts) ?? new(); }
            catch { return new(); }
        }

        private static int Ordinal(NpgsqlDataReader r, string col)
        {
            try { return r.GetOrdinal(col); } catch { return -1; }
        }
        private static string? GetString(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : r.GetValue(i)?.ToString();
        }
        private static int GetInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }
        private static int? GetNullableInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }
        private static decimal GetDecimal(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0m : Convert.ToDecimal(r.GetValue(i));
        }
        private static DateTime? GetDate(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToDateTime(r.GetValue(i));
        }
    }

    // =========================================================================
    // PoultryInternalUsageService (migration 216)
    //
    // Clone of the water service against sppoultryinternalusage_*. The only
    // shape difference is EggsPerCrate on the item, which the SP feeds to
    // fnpoultrycrateunits to work out the crate -> egg multiplier.
    // =========================================================================
    public interface IPoultryInternalUsageService
    {
        Task<List<PoultryInternalUsageModel>> GetAllAsync(string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate);
        Task<PoultryInternalUsageModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryInternalUsageModel m);
        Task       UpdateAsync(PoultryInternalUsageModel m);
        Task       DeleteAsync(int id, string farmId, string? userId);
        Task       PostAsync(int id, string farmId, string? postedBy);
        Task       ReverseAsync(int id, string farmId, string? reason, string? reversedBy);
        Task<decimal> GetSuggestedCostAsync(string farmId, int poultryProductId, string? entryUnit);
    }

    public class PoultryInternalUsageService : IPoultryInternalUsageService
    {
        private readonly string _cs;
        public PoultryInternalUsageService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        };

        public async Task<List<PoultryInternalUsageModel>> GetAllAsync(
            string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryInternalUsageModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryinternalusage_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_category => @Category::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Category", (object?)category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }

        public async Task<PoultryInternalUsageModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryinternalusage_getbyid(p_poultryinternalusageid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Map(r) : null;
        }

        public async Task<decimal> GetSuggestedCostAsync(string farmId, int poultryProductId, string? entryUnit)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.fnpoultryproductentrycost(@FarmId::text, @PoultryProductId::int, @EntryUnit::text, 30)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryProductId", poultryProductId);
            cmd.Parameters.AddWithValue("@EntryUnit", (object?)entryUnit ?? DBNull.Value);
            await conn.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            return v is null || v == DBNull.Value ? 0m : Convert.ToDecimal(v);
        }

        public async Task<int> InsertAsync(PoultryInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.sppoultryinternalusage_insert(p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_createdby => @CreatedBy::text)", conn);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            var id = await cmd.ExecuteScalarAsync();
            return id is null || id == DBNull.Value ? 0 : Convert.ToInt32(id);
        }

        public async Task UpdateAsync(PoultryInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.sppoultryinternalusage_update(p_poultryinternalusageid => @Id::int, p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.PoultryInternalUsageId);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? userId)
            => await ExecAsync("SELECT public.sppoultryinternalusage_delete(p_poultryinternalusageid => @Id::int, p_farmid => @FarmId::text, p_userid => @UserId::text)",
                               id, farmId, ("@UserId", userId));

        public async Task PostAsync(int id, string farmId, string? postedBy)
            => await ExecAsync("SELECT public.sppoultryinternalusage_post(p_poultryinternalusageid => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text)",
                               id, farmId, ("@PostedBy", postedBy));

        public async Task ReverseAsync(int id, string farmId, string? reason, string? reversedBy)
            => await ExecAsync("SELECT public.sppoultryinternalusage_reverse(p_poultryinternalusageid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)",
                               id, farmId, ("@Reason", reason), ("@ReversedBy", reversedBy));

        private async Task ExecAsync(string sql, int id, string farmId, params (string Name, object? Value)[] extra)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            foreach (var (name, value) in extra) cmd.Parameters.AddWithValue(name, value ?? (object)DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static void AddHeaderParams(NpgsqlCommand cmd, PoultryInternalUsageModel m)
        {
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@UsageDate", m.UsageDate);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RecipientName", (object?)m.RecipientName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StaffCount", (object?)m.StaffCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", BuildItemsJson(m.Items));
        }

        // camelCase keys, matched by the quoted identifiers in the SP's
        // json_to_recordset (see migration 214 for why that matters).
        private static string BuildItemsJson(List<PoultryInternalUsageItemModel>? items)
        {
            if (items is null || items.Count == 0) return "[]";
            return JsonSerializer.Serialize(
                items.Where(x => x.PoultryProductId > 0 && x.EntryQuantity > 0)
                     .Select(x => new
                     {
                         poultryProductId = x.PoultryProductId,
                         entryQuantity    = x.EntryQuantity,
                         entryUnit        = x.EntryUnit,
                         quantityPerStaff = x.QuantityPerStaff,
                         entryUnitCost    = x.EntryUnitCost,
                         eggsPerCrate     = x.EggsPerCrate,
                         itemNotes        = x.ItemNotes,
                     }));
        }

        private static PoultryInternalUsageModel Map(NpgsqlDataReader r) => new()
        {
            PoultryInternalUsageId = GetInt(r, "poultryinternalusageid"),
            FarmId             = GetString(r, "farmid") ?? string.Empty,
            UsageDate          = GetDate(r, "usagedate") ?? DateTime.UtcNow,
            ReferenceNo        = GetString(r, "referenceno"),
            Category           = GetString(r, "category") ?? string.Empty,
            Reason             = GetString(r, "reason"),
            RecipientName      = GetString(r, "recipientname"),
            ResponsibleStaffId = GetNullableInt(r, "responsiblestaffid"),
            StaffCount         = GetNullableInt(r, "staffcount"),
            Status             = GetString(r, "status") ?? InternalUseStatus.Draft,
            TotalCostValue     = GetDecimal(r, "totalcostvalue"),
            Notes              = GetString(r, "notes"),
            PostedBy           = GetString(r, "postedby"),
            PostedAt           = GetDate(r, "postedat"),
            ReversedBy         = GetString(r, "reversedby"),
            ReversedAt         = GetDate(r, "reversedat"),
            ReversalReason     = GetString(r, "reversalreason"),
            CreatedBy          = GetString(r, "createdby"),
            CreatedAt          = GetDate(r, "createdat") ?? DateTime.UtcNow,
            UpdatedAt          = GetDate(r, "updatedat"),
            Items              = DeserializeItems(GetString(r, "itemsjson")),
        };

        private static List<PoultryInternalUsageItemModel> DeserializeItems(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new();
            try { return JsonSerializer.Deserialize<List<PoultryInternalUsageItemModel>>(json, JsonOpts) ?? new(); }
            catch { return new(); }
        }

        private static int Ordinal(NpgsqlDataReader r, string col)
        {
            try { return r.GetOrdinal(col); } catch { return -1; }
        }
        private static string? GetString(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : r.GetValue(i)?.ToString();
        }
        private static int GetInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }
        private static int? GetNullableInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }
        private static decimal GetDecimal(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0m : Convert.ToDecimal(r.GetValue(i));
        }
        private static DateTime? GetDate(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToDateTime(r.GetValue(i));
        }
    }

    // =========================================================================
    // GenericInternalUsageService (migration 217)
    //
    // Clone of the water service against spgenericinternalusage_*. Generic has
    // no unit conversion, so there is no per-line factor to send; the SP still
    // maintains genericproducts.currentstock alongside the movement ledger.
    // =========================================================================
    public interface IGenericInternalUsageService
    {
        Task<List<GenericInternalUsageModel>> GetAllAsync(string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate);
        Task<GenericInternalUsageModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(GenericInternalUsageModel m);
        Task       UpdateAsync(GenericInternalUsageModel m);
        Task       DeleteAsync(int id, string farmId, string? userId);
        Task       PostAsync(int id, string farmId, string? postedBy);
        Task       ReverseAsync(int id, string farmId, string? reason, string? reversedBy);
        Task<decimal> GetSuggestedCostAsync(string farmId, int genericProductId, string? entryUnit);
    }

    public class GenericInternalUsageService : IGenericInternalUsageService
    {
        private readonly string _cs;
        public GenericInternalUsageService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        };

        public async Task<List<GenericInternalUsageModel>> GetAllAsync(
            string farmId, string? status, string? category, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericInternalUsageModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericinternalusage_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_category => @Category::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Category", (object?)category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }

        public async Task<GenericInternalUsageModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericinternalusage_getbyid(p_genericinternalusageid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Map(r) : null;
        }

        // entryUnit is accepted for signature parity; generic has no conversion.
        public async Task<decimal> GetSuggestedCostAsync(string farmId, int genericProductId, string? entryUnit)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.fngenericproductentrycost(@FarmId::text, @GenericProductId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericProductId", genericProductId);
            await conn.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            return v is null || v == DBNull.Value ? 0m : Convert.ToDecimal(v);
        }

        public async Task<int> InsertAsync(GenericInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spgenericinternalusage_insert(p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_createdby => @CreatedBy::text)", conn);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            var id = await cmd.ExecuteScalarAsync();
            return id is null || id == DBNull.Value ? 0 : Convert.ToInt32(id);
        }

        public async Task UpdateAsync(GenericInternalUsageModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT public.spgenericinternalusage_update(p_genericinternalusageid => @Id::int, p_farmid => @FarmId::text, p_usagedate => @UsageDate::timestamp, p_category => @Category::text, p_reason => @Reason::text, p_recipientname => @RecipientName::text, p_responsiblestaffid => @ResponsibleStaffId::int, p_staffcount => @StaffCount::int, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.GenericInternalUsageId);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? userId)
            => await ExecAsync("SELECT public.spgenericinternalusage_delete(p_genericinternalusageid => @Id::int, p_farmid => @FarmId::text, p_userid => @UserId::text)",
                               id, farmId, ("@UserId", userId));

        public async Task PostAsync(int id, string farmId, string? postedBy)
            => await ExecAsync("SELECT public.spgenericinternalusage_post(p_genericinternalusageid => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text)",
                               id, farmId, ("@PostedBy", postedBy));

        public async Task ReverseAsync(int id, string farmId, string? reason, string? reversedBy)
            => await ExecAsync("SELECT public.spgenericinternalusage_reverse(p_genericinternalusageid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)",
                               id, farmId, ("@Reason", reason), ("@ReversedBy", reversedBy));

        private async Task ExecAsync(string sql, int id, string farmId, params (string Name, object? Value)[] extra)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            foreach (var (name, value) in extra) cmd.Parameters.AddWithValue(name, value ?? (object)DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static void AddHeaderParams(NpgsqlCommand cmd, GenericInternalUsageModel m)
        {
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@UsageDate", m.UsageDate);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RecipientName", (object?)m.RecipientName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StaffCount", (object?)m.StaffCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", BuildItemsJson(m.Items));
        }

        // camelCase keys, matched by the quoted identifiers in the SP's
        // json_to_recordset (see migration 214 for why that matters).
        private static string BuildItemsJson(List<GenericInternalUsageItemModel>? items)
        {
            if (items is null || items.Count == 0) return "[]";
            return JsonSerializer.Serialize(
                items.Where(x => x.GenericProductId > 0 && x.EntryQuantity > 0)
                     .Select(x => new
                     {
                         genericProductId = x.GenericProductId,
                         entryQuantity    = x.EntryQuantity,
                         entryUnit        = x.EntryUnit,
                         quantityPerStaff = x.QuantityPerStaff,
                         entryUnitCost    = x.EntryUnitCost,
                         itemNotes        = x.ItemNotes,
                     }));
        }

        private static GenericInternalUsageModel Map(NpgsqlDataReader r) => new()
        {
            GenericInternalUsageId = GetInt(r, "genericinternalusageid"),
            FarmId             = GetString(r, "farmid") ?? string.Empty,
            UsageDate          = GetDate(r, "usagedate") ?? DateTime.UtcNow,
            ReferenceNo        = GetString(r, "referenceno"),
            Category           = GetString(r, "category") ?? string.Empty,
            Reason             = GetString(r, "reason"),
            RecipientName      = GetString(r, "recipientname"),
            ResponsibleStaffId = GetNullableInt(r, "responsiblestaffid"),
            StaffCount         = GetNullableInt(r, "staffcount"),
            Status             = GetString(r, "status") ?? InternalUseStatus.Draft,
            TotalCostValue     = GetDecimal(r, "totalcostvalue"),
            Notes              = GetString(r, "notes"),
            PostedBy           = GetString(r, "postedby"),
            PostedAt           = GetDate(r, "postedat"),
            ReversedBy         = GetString(r, "reversedby"),
            ReversedAt         = GetDate(r, "reversedat"),
            ReversalReason     = GetString(r, "reversalreason"),
            CreatedBy          = GetString(r, "createdby"),
            CreatedAt          = GetDate(r, "createdat") ?? DateTime.UtcNow,
            UpdatedAt          = GetDate(r, "updatedat"),
            Items              = DeserializeItems(GetString(r, "itemsjson")),
        };

        private static List<GenericInternalUsageItemModel> DeserializeItems(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new();
            try { return JsonSerializer.Deserialize<List<GenericInternalUsageItemModel>>(json, JsonOpts) ?? new(); }
            catch { return new(); }
        }

        private static int Ordinal(NpgsqlDataReader r, string col)
        {
            try { return r.GetOrdinal(col); } catch { return -1; }
        }
        private static string? GetString(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : r.GetValue(i)?.ToString();
        }
        private static int GetInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }
        private static int? GetNullableInt(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }
        private static decimal GetDecimal(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? 0m : Convert.ToDecimal(r.GetValue(i));
        }
        private static DateTime? GetDate(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i < 0 || r.IsDBNull(i) ? null : Convert.ToDateTime(r.GetValue(i));
        }
    }
}
