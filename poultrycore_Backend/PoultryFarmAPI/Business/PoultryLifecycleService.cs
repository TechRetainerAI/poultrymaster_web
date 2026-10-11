using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Flock Lifecycle Assistant (migration 347). Thin, like every service here:
    // the scheduling calculation lives in fnpoultrylifecycle_schedule so the
    // page, Business Office and the tests all read ONE answer.
    // =========================================================================

    public interface IPoultryLifecycleService
    {
        Task<List<LifecycleTaskModel>> GetTasksAsync(string farmId, string? view, int? flockId);
        Task<LifecycleSummaryModel> GetSummaryAsync(string farmId);
        Task<List<LifecycleTaskEventModel>> GetHistoryAsync(string farmId, int flockId, int? milestoneId);
        Task<int> SetTaskStatusAsync(LifecycleTaskStatusRequest req, string? actor);

        Task<List<LifecycleTemplateModel>> GetTemplatesAsync(string farmId);
        Task<LifecycleTemplateModel?> GetTemplateAsync(string farmId, int templateId);
        Task<int> SaveTemplateAsync(int? templateId, LifecycleTemplateSaveRequest req, string? actor);
        Task<string> DeleteTemplateAsync(string farmId, int templateId, string? actor);

        Task<List<LifecycleAssignmentModel>> GetAssignmentsAsync(string farmId);
        Task<int> AssignAsync(LifecycleAssignRequest req, string? actor);
        Task UnassignAsync(string farmId, int assignmentId, string? actor);
    }

    public class PoultryLifecycleService : IPoultryLifecycleService
    {
        private readonly string _cs;
        public PoultryLifecycleService(string cs) => _cs = cs;

        private static string? Str(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static int? NInt(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetInt32(i); }
        private static DateTime? NDate(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }
        private static int Int(NpgsqlDataReader r, string c) => r.GetInt32(r.GetOrdinal(c));
        private static bool Bool(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private static LifecycleTaskModel MapTask(NpgsqlDataReader r) => new()
        {
            FlockId = Int(r, "flockid"),
            FlockName = Str(r, "flockname") ?? string.Empty,
            BatchId = NInt(r, "batchid"),
            BatchCode = Str(r, "batchcode"),
            HouseId = NInt(r, "houseid"),
            Breed = Str(r, "breed"),
            FlockStartDate = r.GetDateTime(r.GetOrdinal("flockstartdate")),
            FlockActive = Bool(r, "flockactive"),
            IsEstimated = Bool(r, "isestimated"),
            AssignmentId = Int(r, "assignmentid"),
            AssignedVia = Str(r, "assignedvia") ?? string.Empty,
            TemplateId = Int(r, "templateid"),
            TemplateName = Str(r, "templatename") ?? string.Empty,
            TemplateBreed = Str(r, "templatebreed"),
            AgeAtStartDays = Int(r, "ageatstartdays"),
            CurrentAgeDays = Int(r, "currentagedays"),
            MilestoneId = Int(r, "milestoneid"),
            Title = Str(r, "title") ?? string.Empty,
            Description = Str(r, "description"),
            Category = Str(r, "category"),
            AgeUnit = Str(r, "ageunit") ?? string.Empty,
            AgeValue = Int(r, "agevalue"),
            AgeDays = Int(r, "agedays"),
            LeadTimeDays = Int(r, "leadtimedays"),
            ActionType = Str(r, "actiontype"),
            DueDate = r.GetDateTime(r.GetOrdinal("duedate")),
            DueWindowEnd = r.GetDateTime(r.GetOrdinal("duewindowend")),
            VisibleFrom = r.GetDateTime(r.GetOrdinal("visiblefrom")),
            DaysUntilDue = Int(r, "daysuntildue"),
            TaskId = NInt(r, "taskid"),
            Status = Str(r, "status") ?? string.Empty,
            Note = Str(r, "note"),
            ActedBy = Str(r, "actedby"),
            ActedAt = NDate(r, "actedat"),
            Today = r.GetDateTime(r.GetOrdinal("today")),
        };

        public async Task<List<LifecycleTaskModel>> GetTasksAsync(string farmId, string? view, int? flockId)
        {
            var list = new List<LifecycleTaskModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrylifecycle_tasks(p_farmid => @FarmId::text, p_view => @View::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@View", string.IsNullOrWhiteSpace(view) ? "Open" : view);
            cmd.Parameters.AddWithValue("@FlockId", (object?)flockId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapTask(r));
            return list;
        }

        public async Task<LifecycleSummaryModel> GetSummaryAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylifecycle_summary(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new LifecycleSummaryModel();
            return new LifecycleSummaryModel
            {
                Upcoming = Int(r, "upcoming"), Due = Int(r, "due"), Overdue = Int(r, "overdue"),
                CompletedLast30 = Int(r, "completedlast30"), SkippedLast30 = Int(r, "skippedlast30"),
                EstimatedFlocks = Int(r, "estimatedflocks"), AssignedFlocks = Int(r, "assignedflocks"),
                Today = r.GetDateTime(r.GetOrdinal("today")),
            };
        }

        public async Task<List<LifecycleTaskEventModel>> GetHistoryAsync(string farmId, int flockId, int? milestoneId)
        {
            var list = new List<LifecycleTaskEventModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrylifecycle_taskhistory(p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_milestoneid => @MilestoneId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            cmd.Parameters.AddWithValue("@MilestoneId", (object?)milestoneId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new LifecycleTaskEventModel
                {
                    EventId = r.GetInt64(r.GetOrdinal("eventid")),
                    FlockId = Int(r, "flockid"),
                    MilestoneId = Int(r, "milestoneid"),
                    Title = Str(r, "title") ?? string.Empty,
                    FromStatus = Str(r, "fromstatus") ?? string.Empty,
                    ToStatus = Str(r, "tostatus") ?? string.Empty,
                    Note = Str(r, "note"),
                    Actor = Str(r, "actor"),
                    AtUtc = r.GetFieldValue<DateTimeOffset>(r.GetOrdinal("atutc")).UtcDateTime,
                });
            return list;
        }

        public async Task<int> SetTaskStatusAsync(LifecycleTaskStatusRequest req, string? actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(@"
                SELECT sppoultrylifecycle_settaskstatus(
                    p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_milestoneid => @MilestoneId::int,
                    p_status => @Status::text, p_note => @Note::text, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@FlockId", req.FlockId);
            cmd.Parameters.AddWithValue("@MilestoneId", req.MilestoneId);
            cmd.Parameters.AddWithValue("@Status", req.Status);
            cmd.Parameters.AddWithValue("@Note", (object?)req.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<LifecycleTemplateModel>> GetTemplatesAsync(string farmId)
        {
            var list = new List<LifecycleTemplateModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylifecycletemplate_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new LifecycleTemplateModel
                {
                    TemplateId = Int(r, "templateid"),
                    Name = Str(r, "name") ?? string.Empty,
                    Breed = Str(r, "breed"),
                    Description = Str(r, "description"),
                    IsActive = Bool(r, "isactive"),
                    MilestoneCount = Int(r, "milestonecount"),
                    AssignedBatches = Int(r, "assignedbatches"),
                    AssignedFlocks = Int(r, "assignedflocks"),
                    CreatedBy = Str(r, "createdby"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                    UpdatedBy = Str(r, "updatedby"),
                    UpdatedAt = NDate(r, "updatedat"),
                });
            return list;
        }

        public async Task<LifecycleTemplateModel?> GetTemplateAsync(string farmId, int templateId)
        {
            var template = (await GetTemplatesAsync(farmId)).FirstOrDefault(t => t.TemplateId == templateId);
            if (template is null) return null;
            template.Milestones = new List<LifecycleMilestoneModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrylifecyclemilestone_getall(p_farmid => @FarmId::text, p_templateid => @Id::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", templateId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                template.Milestones.Add(new LifecycleMilestoneModel
                {
                    MilestoneId = Int(r, "milestoneid"),
                    AgeUnit = Str(r, "ageunit") ?? "Week",
                    AgeValue = Int(r, "agevalue"),
                    AgeDays = Int(r, "agedays"),
                    Title = Str(r, "title") ?? string.Empty,
                    Description = Str(r, "description"),
                    Category = Str(r, "category"),
                    LeadTimeDays = Int(r, "leadtimedays"),
                    ActionType = Str(r, "actiontype"),
                    SortOrder = Int(r, "sortorder"),
                });
            return template;
        }

        public async Task<int> SaveTemplateAsync(int? templateId, LifecycleTemplateSaveRequest req, string? actor)
        {
            // Lowercase keys: the function reads them with ->>, which is case-sensitive.
            var milestones = JsonSerializer.Serialize(req.Milestones.Select(m => new Dictionary<string, object?>
            {
                ["milestoneid"] = m.MilestoneId,
                ["ageunit"] = m.AgeUnit,
                ["agevalue"] = m.AgeValue,
                ["title"] = m.Title,
                ["description"] = m.Description,
                ["category"] = m.Category,
                ["leadtimedays"] = m.LeadTimeDays,
                ["actiontype"] = string.IsNullOrWhiteSpace(m.ActionType) ? null : m.ActionType,
            }));
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(@"
                SELECT sppoultrylifecycletemplate_save(
                    p_farmid => @FarmId::text, p_templateid => @Id::int, p_name => @Name::text,
                    p_breed => @Breed::text, p_description => @Description::text, p_isactive => @IsActive::boolean,
                    p_milestones => @Milestones::jsonb, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", (object?)templateId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", req.Name);
            cmd.Parameters.AddWithValue("@Breed", (object?)req.Breed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", req.IsActive);
            cmd.Parameters.AddWithValue("@Milestones", milestones);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<string> DeleteTemplateAsync(string farmId, int templateId, string? actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrylifecycletemplate_delete(p_farmid => @FarmId::text, p_templateid => @Id::int, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", templateId);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToString(await cmd.ExecuteScalarAsync()) ?? "Deleted";
        }

        public async Task<List<LifecycleAssignmentModel>> GetAssignmentsAsync(string farmId)
        {
            var list = new List<LifecycleAssignmentModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylifecycleassignment_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new LifecycleAssignmentModel
                {
                    AssignmentId = Int(r, "assignmentid"),
                    TemplateId = Int(r, "templateid"),
                    TemplateName = Str(r, "templatename") ?? string.Empty,
                    TemplateBreed = Str(r, "templatebreed"),
                    BatchId = NInt(r, "batchid"),
                    BatchCode = Str(r, "batchcode"),
                    BatchName = Str(r, "batchname"),
                    FlockId = NInt(r, "flockid"),
                    FlockName = Str(r, "flockname"),
                    TargetBreed = Str(r, "targetbreed"),
                    AgeAtStartDays = Int(r, "ageatstartdays"),
                    FlockCount = Int(r, "flockcount"),
                    BreedMismatch = Bool(r, "breedmismatch"),
                    AssignedBy = Str(r, "assignedby"),
                    AssignedAt = r.GetDateTime(r.GetOrdinal("assignedat")),
                });
            return list;
        }

        public async Task<int> AssignAsync(LifecycleAssignRequest req, string? actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(@"
                SELECT sppoultrylifecycle_assign(
                    p_farmid => @FarmId::text, p_templateid => @TemplateId::int, p_batchid => @BatchId::int,
                    p_flockid => @FlockId::int, p_ageatstartdays => @Age::int, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@TemplateId", req.TemplateId);
            cmd.Parameters.AddWithValue("@BatchId", (object?)req.BatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FlockId", (object?)req.FlockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Age", req.AgeAtStartDays);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UnassignAsync(string farmId, int assignmentId, string? actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrylifecycle_unassign(p_farmid => @FarmId::text, p_assignmentid => @Id::int, p_actor => @Actor::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", assignmentId);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
