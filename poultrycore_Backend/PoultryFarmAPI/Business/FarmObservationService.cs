using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Free-text weekly notes per farm. Backed by dbo.FarmObservations and
    /// spFarmObservation_Upsert / _GetByWeek / _GetAll (migration 018).
    /// </summary>
    public class FarmObservationService : IFarmObservationService
    {
        private readonly string _connectionString;

        public FarmObservationService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static FarmObservationModel Read(NpgsqlDataReader r) => new()
        {
            Id = r.GetInt32(r.GetOrdinal("Id")),
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            UserId = r.IsDBNull(r.GetOrdinal("UserId")) ? null : r.GetString(r.GetOrdinal("UserId")),
            WeekStartDate = r.GetDateTime(r.GetOrdinal("WeekStartDate")),
            Notes = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? (DateTime?)null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        public async Task<FarmObservationModel?> GetByWeek(string farmId, DateTime weekStartDate)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfarmobservation_getbyweek(p_farmid => @FarmId::text, p_weekstartdate => @WeekStartDate::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WeekStartDate", weekStartDate.Date);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? Read(reader) : null;
        }

        public async Task<List<FarmObservationModel>> GetAll(string farmId)
        {
            var list = new List<FarmObservationModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfarmobservation_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader));
            return list;
        }

        public async Task<FarmObservationModel?> Upsert(FarmObservationModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfarmobservation_upsert(p_farmid => @FarmId::text, p_userid => @UserId::text, p_weekstartdate => @WeekStartDate::date, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)model.UserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WeekStartDate", model.WeekStartDate.Date);
            cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? Read(reader) : null;
        }
    }
}
