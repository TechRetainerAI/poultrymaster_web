// Flock weigh-ins (migration 400). Every rule lives in the stored functions;
// this is the thin Npgsql wrapper. Refusals come back as PostgresException
// P0001 with a message written for the farm.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFlockWeighInService
    {
        Task<IReadOnlyList<FlockWeighIn>> ListAsync(string farmId, int? flockId);
        /// <summary>Create when weighInId is null, else edit. Returns the id.</summary>
        Task<int> SaveAsync(FlockWeighInSaveRequest req, string? by, int? weighInId);
        Task DeleteAsync(int weighInId, string farmId, string? by, string? reason);
    }

    public class FlockWeighInService : IFlockWeighInService
    {
        private readonly string _cs;
        public FlockWeighInService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<FlockWeighIn>> ListAsync(string farmId, int? flockId)
        {
            var list = new List<FlockWeighIn>();
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryweighin_list(p_farmid => @FarmId::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", (object?)flockId ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                decimal? Dec(string c) => r.IsDBNull(r.GetOrdinal(c)) ? null : r.GetDecimal(r.GetOrdinal(c));
                int? Int(string c) => r.IsDBNull(r.GetOrdinal(c)) ? null : r.GetInt32(r.GetOrdinal(c));
                string? Str(string c) => r.IsDBNull(r.GetOrdinal(c)) ? null : r.GetString(r.GetOrdinal(c));

                list.Add(new FlockWeighIn
                {
                    WeighInId = r.GetInt32(r.GetOrdinal("weighinid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str("flockname") ?? string.Empty,
                    FlockType = Str("flocktype") ?? "Layer",
                    Breed = Str("breed"),
                    FlockClosed = r.GetBoolean(r.GetOrdinal("flockclosed")),
                    WeighDate = r.GetDateTime(r.GetOrdinal("weighdate")),
                    AgeInDays = r.GetInt32(r.GetOrdinal("ageindays")),
                    SampleSize = r.GetInt32(r.GetOrdinal("samplesize")),
                    AvgWeightG = r.GetDecimal(r.GetOrdinal("avgweightg")),
                    MinWeightG = Dec("minweightg"),
                    MaxWeightG = Dec("maxweightg"),
                    UniformityPct = Dec("uniformitypct"),
                    CvPct = Dec("cvpct"),
                    WeightsG = r.IsDBNull(r.GetOrdinal("weightsg")) ? null : r.GetFieldValue<decimal[]>(r.GetOrdinal("weightsg")),
                    Notes = Str("notes"),
                    CreatedBy = Str("createdby"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                    PrevAvgWeightG = Dec("prevavgweightg"),
                    DaysSincePrev = Int("dayssinceprev"),
                    DailyGainG = Dec("dailygaing"),
                });
            }
            return list;
        }

        public async Task<int> SaveAsync(FlockWeighInSaveRequest req, string? by, int? weighInId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT sppoultryweighin_save(p_farmid => @FarmId::text, p_flockid => @FlockId::int, " +
                "p_weighdate => @WeighDate::date, p_samplesize => @SampleSize::int, p_avgweightg => @Avg::numeric, " +
                "p_weightsg => @Weights::numeric[], p_uniformitypct => @Uniformity::numeric, p_cvpct => @Cv::numeric, " +
                "p_minweightg => @Min::numeric, p_maxweightg => @Max::numeric, p_notes => @Notes::text, " +
                "p_by => @By::text, p_weighinid => @Id::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@FlockId", req.FlockId);
            cmd.Parameters.AddWithValue("@WeighDate", NpgsqlDbType.Date, req.WeighDate.Date);
            cmd.Parameters.AddWithValue("@SampleSize", (object?)req.SampleSize ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Avg", (object?)req.AvgWeightG ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@Weights", NpgsqlDbType.Array | NpgsqlDbType.Numeric)
            {
                Value = req.WeightsG is { Length: > 0 } w ? w : DBNull.Value,
            });
            cmd.Parameters.AddWithValue("@Uniformity", (object?)req.UniformityPct ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cv", (object?)req.CvPct ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Min", (object?)req.MinWeightG ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Max", (object?)req.MaxWeightG ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Id", (object?)weighInId ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteAsync(int weighInId, string farmId, string? by, string? reason)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT sppoultryweighin_delete(p_weighinid => @Id::int, p_farmid => @FarmId::text, p_by => @By::text, p_reason => @Reason::text)", conn);
            cmd.Parameters.AddWithValue("@Id", weighInId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
