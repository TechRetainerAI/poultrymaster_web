using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IAnnouncementService
    {
        Task<List<AnnouncementModel>> ListForUserAsync(string userId, string? orgOwnerUserId, bool isAdmin, string? farmId);
        Task<List<AnnouncementModel>> ListManageAsync(string orgOwnerUserId);
        Task<int> CreateAsync(CreateAnnouncementRequest r);
        Task SetReceiptAsync(int announcementId, string userId, string action);
        Task DeleteAsync(int announcementId, string orgOwnerUserId);
    }

    public class AnnouncementService : IAnnouncementService
    {
        private readonly string _cs;
        public AnnouncementService(string cs) => _cs = cs;

        public async Task<List<AnnouncementModel>> ListForUserAsync(string userId, string? orgOwnerUserId, bool isAdmin, string? farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spannouncement_listforuser(p_userid => @UserId::text, p_orgowneruserid => @OrgOwnerUserId::text, p_isadmin => @IsAdmin::boolean, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OrgOwnerUserId", (object?)orgOwnerUserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsAdmin", isAdmin);
            cmd.Parameters.AddWithValue("@FarmId", (object?)farmId ?? DBNull.Value);
            return await ReadList(cmd, conn);
        }

        public async Task<List<AnnouncementModel>> ListManageAsync(string orgOwnerUserId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spannouncement_listmanage(p_orgowneruserid => @OrgOwnerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@OrgOwnerUserId", (object?)orgOwnerUserId ?? DBNull.Value);
            return await ReadList(cmd, conn);
        }

        public async Task<int> CreateAsync(CreateAnnouncementRequest r)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spannouncement_create(p_orgowneruserid => @OrgOwnerUserId::text, p_title => @Title::text, p_message => @Message::text, p_type => @Type::text, p_priority => @Priority::int, p_audiencerole => @AudienceRole::text, p_targetfarmid => @TargetFarmId::text, p_startdate => @StartDate::timestamp, p_enddate => @EndDate::timestamp, p_isdismissible => @IsDismissible::boolean, p_requiresack => @RequiresAck::boolean, p_actionlabel => @ActionLabel::text, p_actionurl => @ActionUrl::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@OrgOwnerUserId", (object?)r.OrgOwnerUserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Title", r.Title);
            cmd.Parameters.AddWithValue("@Message", (object?)r.Message ?? string.Empty);
            cmd.Parameters.AddWithValue("@Type", (object?)r.Type ?? "Info");
            cmd.Parameters.AddWithValue("@Priority", r.Priority);
            cmd.Parameters.AddWithValue("@AudienceRole", (object?)r.AudienceRole ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TargetFarmId", (object?)r.TargetFarmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartDate", (object?)r.StartDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndDate", (object?)r.EndDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsDismissible", r.IsDismissible);
            cmd.Parameters.AddWithValue("@RequiresAck", r.RequiresAck);
            cmd.Parameters.AddWithValue("@ActionLabel", (object?)r.ActionLabel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ActionUrl", (object?)r.ActionUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)r.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task SetReceiptAsync(int announcementId, string userId, string action)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spannouncement_setreceipt(p_announcementid => @AnnouncementId::int, p_userid => @UserId::text, p_action => @Action::text)", conn);
            cmd.Parameters.AddWithValue("@AnnouncementId", announcementId);
            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Action", action);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int announcementId, string orgOwnerUserId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spannouncement_delete(p_announcementid => @AnnouncementId::int, p_orgowneruserid => @OrgOwnerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@AnnouncementId", announcementId);
            cmd.Parameters.AddWithValue("@OrgOwnerUserId", (object?)orgOwnerUserId ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static async Task<List<AnnouncementModel>> ReadList(NpgsqlCommand cmd, NpgsqlConnection conn)
        {
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<AnnouncementModel>();
            string? S(string c) => r.IsDBNull(r.GetOrdinal(c)) ? null : r.GetString(r.GetOrdinal(c));
            DateTime? D(string c) => r.IsDBNull(r.GetOrdinal(c)) ? (DateTime?)null : r.GetDateTime(r.GetOrdinal(c));
            while (await r.ReadAsync())
            {
                list.Add(new AnnouncementModel
                {
                    AnnouncementId = r.GetInt32(r.GetOrdinal("AnnouncementId")),
                    OrgOwnerUserId = S("OrgOwnerUserId"),
                    Title = r.GetString(r.GetOrdinal("Title")),
                    Message = r.IsDBNull(r.GetOrdinal("Message")) ? "" : r.GetString(r.GetOrdinal("Message")),
                    Type = r.IsDBNull(r.GetOrdinal("Type")) ? "Info" : r.GetString(r.GetOrdinal("Type")),
                    Priority = r.GetInt32(r.GetOrdinal("Priority")),
                    AudienceRole = S("AudienceRole"),
                    TargetFarmId = S("TargetFarmId"),
                    StartDate = D("StartDate"),
                    EndDate = D("EndDate"),
                    IsDismissible = r.GetBoolean(r.GetOrdinal("IsDismissible")),
                    RequiresAck = r.GetBoolean(r.GetOrdinal("RequiresAck")),
                    ActionLabel = S("ActionLabel"),
                    ActionUrl = S("ActionUrl"),
                    CreatedBy = S("CreatedBy"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    ReadAt = D("ReadAt"),
                    DismissedAt = D("DismissedAt"),
                    AcknowledgedAt = D("AcknowledgedAt"),
                });
            }
            return list;
        }
    }
}
