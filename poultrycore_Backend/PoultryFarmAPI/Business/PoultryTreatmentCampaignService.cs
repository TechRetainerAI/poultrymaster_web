// Treatment Campaigns (migration 339). Orchestration only: every stock
// movement, lot draw, cost and consumption expense happens inside the database
// through spproductionrecord_update -- the same path as adding a medication
// line to a flock's production record by hand. This file sends parameters and
// maps rows.

using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryTreatmentCampaignService
    {
        Task<IReadOnlyList<MedicationProduct>> GetProductsAsync(string farmId);
        Task SetProductSettingsAsync(int itemId, MedicationProductSettingsRequest req, string? updatedBy);
        Task<IReadOnlyList<TreatmentFlockOption>> GetFlockOptionsAsync(string farmId);
        Task<IReadOnlyList<TreatmentCampaign>> GetAllAsync(string farmId, int? id = null);
        /// <summary>Throws PostgresException P0004 (a flock cannot be on it), P0001 (other refusal).</summary>
        Task<int> CreateAsync(TreatmentCampaignCreateRequest req, string createdBy);
        Task CompleteAsync(int id, string farmId, string by);
        Task CancelAsync(int id, string farmId, string reason, string by);
        Task<IReadOnlyList<TreatmentCampaignFlock>> GetFlocksAsync(int id, string farmId);
        Task<IReadOnlyList<TreatmentDayRow>> GetDayGridAsync(int id, string farmId, DateTime date);
        /// <summary>Throws P0003 (not enough stock), P0004 (flock cannot be dosed), P0006 (day already posted), P0001.</summary>
        Task<int> PostDayAsync(int id, TreatmentDayPostRequest req, string postedBy);
        /// <summary>Throws P0005 when a record was edited after posting, P0001 otherwise.</summary>
        Task ReverseDayAsync(int postId, string farmId, string reason, string reversedBy);
        Task<IReadOnlyList<TreatmentDayPosting>> GetDaysAsync(int id, string farmId);
        Task<IReadOnlyList<TreatmentDayLine>> GetDayLinesAsync(int postId, string farmId);
        Task<IReadOnlyList<FlockTreatmentHistoryRow>> GetFlockHistoryAsync(string farmId, int flockId);
    }

    public class PoultryTreatmentCampaignService : IPoultryTreatmentCampaignService
    {
        private readonly string _cs;
        public PoultryTreatmentCampaignService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<MedicationProduct>> GetProductsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrymedication_products(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<MedicationProduct>();
            while (await r.ReadAsync())
            {
                list.Add(new MedicationProduct
                {
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
                    ItemName = Str(r, "itemname") ?? string.Empty,
                    Category = Str(r, "category"),
                    UnitOfMeasure = Str(r, "unitofmeasure"),
                    UsageMethod = Str(r, "usagemethod") ?? "FIFO",
                    IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                    AvailableQuantity = Dec(r, "availablequantity") ?? 0,
                    LotCount = Int(r, "lotcount") ?? 0,
                    CostRecognitionMethod = Str(r, "costrecognitionmethod"),
                    DoseQuantity = Dec(r, "dosequantity"),
                    DoseBasis = Str(r, "dosebasis"),
                    EggWithdrawalDays = Int(r, "eggwithdrawaldays"),
                    MeatWithdrawalDays = Int(r, "meatwithdrawaldays"),
                    WithdrawalNotes = Str(r, "withdrawalnotes"),
                });
            }
            return list;
        }

        public async Task SetProductSettingsAsync(int itemId, MedicationProductSettingsRequest req, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await SetProductSettingsCore(c, null, req.FarmId, itemId, req.DoseQuantity, req.DoseBasis,
                req.EggWithdrawalDays, req.MeatWithdrawalDays, req.WithdrawalNotes, updatedBy);
        }

        private static async Task SetProductSettingsCore(NpgsqlConnection c, NpgsqlTransaction? tx, string farmId, int itemId,
            decimal? dose, string? basis, int? eggDays, int? meatDays, string? notes, string? by)
        {
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrymedication_setproductsettings(p_farmid => @FarmId::text, p_itemid => @ItemId::int, "
                + "p_dosequantity => @Dose::numeric, p_dosebasis => @Basis::text, p_eggwithdrawaldays => @Egg::int, "
                + "p_meatwithdrawaldays => @Meat::int, p_withdrawalnotes => @Notes::text, p_updatedby => @By::text)", c, tx);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ItemId", itemId);
            cmd.Parameters.AddWithValue("@Dose", dose.HasValue ? dose.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Basis", (object?)basis ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Egg", eggDays.HasValue ? eggDays.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Meat", meatDays.HasValue ? meatDays.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<TreatmentFlockOption>> GetFlockOptionsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrytreatmentcampaign_flockoptions(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentFlockOption>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentFlockOption
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    BatchName = Str(r, "batchname"),
                    HouseName = Str(r, "housename"),
                    Birds = Int(r, "birds"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<TreatmentCampaign>> GetAllAsync(string farmId, int? id = null)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_getall(p_farmid => @FarmId::text, p_id => @Id::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", id.HasValue ? id.Value : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentCampaign>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentCampaign
                {
                    PoultryTreatmentCampaignId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignid")),
                    Name = Str(r, "name") ?? string.Empty,
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
                    ItemName = Str(r, "itemname"),
                    UnitOfMeasure = Str(r, "unitofmeasure"),
                    Reason = Str(r, "reason"),
                    StartDate = r.GetDateTime(r.GetOrdinal("startdate")),
                    EndDate = r.GetDateTime(r.GetOrdinal("enddate")),
                    PlannedDays = Int(r, "planneddays") ?? 0,
                    DoseInstructions = Str(r, "doseinstructions"),
                    DoseQuantity = Dec(r, "dosequantity"),
                    DoseBasis = Str(r, "dosebasis"),
                    DoseSource = Str(r, "dosesource") ?? "None",
                    EggWithdrawalDays = Int(r, "eggwithdrawaldays"),
                    MeatWithdrawalDays = Int(r, "meatwithdrawaldays"),
                    WithdrawalNotes = Str(r, "withdrawalnotes"),
                    Notes = Str(r, "notes"),
                    Lifecycle = Str(r, "lifecycle") ?? "Open",
                    Status = Str(r, "status") ?? "Scheduled",
                    CompanyToday = r.GetDateTime(r.GetOrdinal("companytoday")),
                    FlockCount = Int(r, "flockcount") ?? 0,
                    PostedDays = Int(r, "posteddays") ?? 0,
                    TotalQuantity = Dec(r, "totalquantity") ?? 0,
                    TotalCost = Dec(r, "totalcost"),
                    LastPostedDate = Date(r, "lastposteddate"),
                    EggWithdrawalUntil = Date(r, "eggwithdrawaluntil"),
                    MeatWithdrawalUntil = Date(r, "meatwithdrawaluntil"),
                    CreatedBy = Str(r, "createdby"),
                    CreatedAtUtc = Utc(r, "createdatutc") ?? DateTime.UtcNow,
                    CompletedBy = Str(r, "completedby"),
                    CompletedAtUtc = Utc(r, "completedatutc"),
                    CancelledBy = Str(r, "cancelledby"),
                    CancelledAtUtc = Utc(r, "cancelledatutc"),
                    CancelReason = Str(r, "cancelreason"),
                });
            }
            return list;
        }

        public async Task<int> CreateAsync(TreatmentCampaignCreateRequest req, string createdBy)
        {
            var flocks = JsonSerializer.Serialize(req.Flocks.Select(f => new
            {
                flockId = f.FlockId,
                doseQuantity = f.DoseQuantity,
                notes = f.Notes,
            }));

            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            // One transaction: saving the product's defaults and creating the
            // campaign succeed or fail together.
            await using var tx = await c.BeginTransactionAsync();

            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrytreatmentcampaign_create(p_farmid => @FarmId::text, p_name => @Name::text, "
                + "p_itemid => @ItemId::int, p_reason => @Reason::text, p_startdate => @Start::date, p_enddate => @End::date, "
                + "p_doseinstructions => @Instr::text, p_dosequantity => @Dose::numeric, p_dosebasis => @Basis::text, "
                + "p_dosesource => @Source::text, p_eggwithdrawaldays => @Egg::int, p_meatwithdrawaldays => @Meat::int, "
                + "p_withdrawalnotes => @WNotes::text, p_notes => @Notes::text, p_flocksjson => @Flocks::text, "
                + "p_createdby => @By::text)", c, tx);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Name", req.Name ?? string.Empty);
            cmd.Parameters.AddWithValue("@ItemId", req.ItemId);
            cmd.Parameters.AddWithValue("@Reason", (object?)req.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Start", req.StartDate.Date);
            cmd.Parameters.AddWithValue("@End", req.EndDate.Date);
            cmd.Parameters.AddWithValue("@Instr", (object?)req.DoseInstructions ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Dose", req.DoseQuantity.HasValue ? req.DoseQuantity.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Basis", (object?)req.DoseBasis ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Source", (object?)req.DoseSource ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Egg", req.EggWithdrawalDays.HasValue ? req.EggWithdrawalDays.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Meat", req.MeatWithdrawalDays.HasValue ? req.MeatWithdrawalDays.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@WNotes", (object?)req.WithdrawalNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Flocks", flocks);
            cmd.Parameters.AddWithValue("@By", createdBy);
            var id = Convert.ToInt32(await cmd.ExecuteScalarAsync());

            if (req.SaveAsProductDefault)
                await SetProductSettingsCore(c, tx, req.FarmId, req.ItemId, req.DoseQuantity, req.DoseBasis,
                    req.EggWithdrawalDays, req.MeatWithdrawalDays, req.WithdrawalNotes, createdBy);

            await tx.CommitAsync();
            return id;
        }

        public Task CompleteAsync(int id, string farmId, string by)
            => Exec("SELECT sppoultrytreatmentcampaign_complete(p_id => @Id::int, p_farmid => @FarmId::text, p_by => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@By", by));

        public Task CancelAsync(int id, string farmId, string reason, string by)
            => Exec("SELECT sppoultrytreatmentcampaign_cancel(p_id => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_by => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@Reason", reason), ("@By", by));

        public async Task<IReadOnlyList<TreatmentCampaignFlock>> GetFlocksAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_flocks(p_id => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentCampaignFlock>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentCampaignFlock
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    HouseName = Str(r, "housename"),
                    BirdsAtCreation = Int(r, "birdsatcreation"),
                    DoseQuantity = Dec(r, "dosequantity"),
                    Notes = Str(r, "notes"),
                    IsClosed = Bool(r, "isclosed"),
                    PostedDays = Int(r, "posteddays") ?? 0,
                    TotalQuantity = Dec(r, "totalquantity") ?? 0,
                    LastPostedDate = Date(r, "lastposteddate"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<TreatmentDayRow>> GetDayGridAsync(int id, string farmId, DateTime date)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_daygrid(p_id => @Id::int, p_farmid => @FarmId::text, p_date => @Date::date)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", date.Date);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentDayRow>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentDayRow
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    HouseName = Str(r, "housename"),
                    IsClosed = Bool(r, "isclosed"),
                    RecordCount = Int(r, "recordcount") ?? 0,
                    ProductionRecordId = Int(r, "productionrecordid"),
                    Birds = Int(r, "birds"),
                    DoseQuantity = Dec(r, "dosequantity"),
                    DoseBasis = Str(r, "dosebasis"),
                    SuggestedQuantity = Dec(r, "suggestedquantity"),
                    ThisItemQuantity = Dec(r, "thisitemquantity") ?? 0,
                    PostedQuantity = Dec(r, "postedquantity"),
                    Notes = Str(r, "notes"),
                });
            }
            return list;
        }

        public async Task<int> PostDayAsync(int id, TreatmentDayPostRequest req, string postedBy)
        {
            var lines = JsonSerializer.Serialize(req.Lines.Select(l => new
            {
                flockId = l.FlockId,
                actualQuantity = l.ActualQuantity,
                suggestedQuantity = l.SuggestedQuantity,
                notes = l.Notes,
            }));
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrytreatmentcampaign_post(p_id => @Id::int, p_farmid => @FarmId::text, "
                + "p_businessdate => @Date::date, p_notes => @Notes::text, p_linesjson => @Lines::text, p_postedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Date", req.BusinessDate.Date);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Lines", lines);
            cmd.Parameters.AddWithValue("@By", postedBy);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task ReverseDayAsync(int postId, string farmId, string reason, string reversedBy)
            => Exec("SELECT sppoultrytreatmentcampaign_reverse(p_postid => @Id::int, p_farmid => @FarmId::text, "
                    + "p_reason => @Reason::text, p_reversedby => @By::text)",
                ("@Id", postId), ("@FarmId", farmId), ("@Reason", reason), ("@By", reversedBy));

        public async Task<IReadOnlyList<TreatmentDayPosting>> GetDaysAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_posts(p_id => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentDayPosting>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentDayPosting
                {
                    PoultryTreatmentCampaignPostId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignpostid")),
                    PoultryTreatmentCampaignId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignid")),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    FlockCount = Int(r, "flockcount") ?? 0,
                    TotalQuantity = Dec(r, "totalquantity") ?? 0,
                    TotalCost = Dec(r, "totalcost"),
                    Status = Str(r, "status") ?? "Posted",
                    Notes = Str(r, "notes"),
                    PostedBy = Str(r, "postedby"),
                    PostedAtUtc = Utc(r, "postedatutc") ?? DateTime.UtcNow,
                    ReversedBy = Str(r, "reversedby"),
                    ReversedAtUtc = Utc(r, "reversedatutc"),
                    ReversalReason = Str(r, "reversalreason"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<TreatmentDayLine>> GetDayLinesAsync(int postId, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_postlines(p_postid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", postId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<TreatmentDayLine>();
            while (await r.ReadAsync())
            {
                list.Add(new TreatmentDayLine
                {
                    PoultryTreatmentCampaignPostLineId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignpostlineid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    Birds = Int(r, "birds"),
                    DoseQuantity = Dec(r, "dosequantity"),
                    DoseBasis = Str(r, "dosebasis"),
                    SuggestedQuantity = Dec(r, "suggestedquantity"),
                    ActualQuantity = Dec(r, "actualquantity") ?? 0,
                    UnitCost = Dec(r, "unitcost"),
                    TotalCost = Dec(r, "totalcost"),
                    Notes = Str(r, "notes"),
                    ReversalNote = Str(r, "reversalnote"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FlockTreatmentHistoryRow>> GetFlockHistoryAsync(string farmId, int flockId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrytreatmentcampaign_flockhistory(p_farmid => @FarmId::text, p_flockid => @FlockId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockTreatmentHistoryRow>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockTreatmentHistoryRow
                {
                    PoultryTreatmentCampaignPostLineId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignpostlineid")),
                    PoultryTreatmentCampaignPostId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignpostid")),
                    PoultryTreatmentCampaignId = r.GetInt32(r.GetOrdinal("poultrytreatmentcampaignid")),
                    CampaignName = Str(r, "campaignname") ?? string.Empty,
                    Reason = Str(r, "reason"),
                    ItemName = Str(r, "itemname"),
                    UnitOfMeasure = Str(r, "unitofmeasure"),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    ProductionRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    Birds = Int(r, "birds"),
                    ActualQuantity = Dec(r, "actualquantity") ?? 0,
                    TotalCost = Dec(r, "totalcost"),
                    PostStatus = Str(r, "poststatus") ?? "Posted",
                    EggWithdrawalUntil = Date(r, "eggwithdrawaluntil"),
                    MeatWithdrawalUntil = Date(r, "meatwithdrawaluntil"),
                    Notes = Str(r, "notes"),
                });
            }
            return list;
        }

        private async Task Exec(string sql, params (string Name, object Value)[] ps)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(sql, c);
            foreach (var (name, value) in ps) cmd.Parameters.AddWithValue(name, value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
        }

        private static int? Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
        }

        private static bool Bool(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return !r.IsDBNull(i) && r.GetBoolean(i);
        }

        private static DateTime? Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static DateTime? Utc(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            if (r.IsDBNull(i)) return null;
            var d = r.GetDateTime(i);
            return d.Kind == DateTimeKind.Utc ? d : DateTime.SpecifyKind(d.ToUniversalTime(), DateTimeKind.Utc);
        }
    }
}
