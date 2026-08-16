using PoultryFarmAPIWeb.Models;
using System.Data;
using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    public class HealthRecordService : IHealthRecordService
    {
        private readonly string _connectionString;

        public HealthRecordService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(HealthRecordModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_houseid => @HouseId::int, p_itemid => @ItemId::int, p_recorddate => @RecordDate::timestamp, p_vaccination => @Vaccination::text, p_medication => @Medication::text, p_waterconsumption => @WaterConsumption::numeric, p_notes => @Notes::text, p_attachmentimage => @AttachmentImage::bytea, p_attachmentcontenttype => @AttachmentContentType::text)", conn);

            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", (object?)model.FarmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HouseId", (object?)model.HouseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemId", (object?)model.ItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RecordDate", model.RecordDate);
            cmd.Parameters.AddWithValue("@Vaccination", (object?)model.Vaccination ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Medication", (object?)model.Medication ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterConsumption", (object?)model.WaterConsumption ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@AttachmentImage", NpgsqlDbType.Bytea, -1)
            {
                Value = (object?)model.AttachmentImage ?? DBNull.Value
            });
            cmd.Parameters.Add(new NpgsqlParameter("@AttachmentContentType", NpgsqlDbType.Text, 64)
            {
                Value = (object?)model.AttachmentContentType ?? DBNull.Value
            });

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task Update(HealthRecordModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_update(p_id => @Id::int, p_userid => @UserId::text, p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_houseid => @HouseId::int, p_itemid => @ItemId::int, p_recorddate => @RecordDate::timestamp, p_vaccination => @Vaccination::text, p_medication => @Medication::text, p_waterconsumption => @WaterConsumption::numeric, p_notes => @Notes::text, p_attachmentimageset => @AttachmentImageSet::boolean, p_attachmentimage => @AttachmentImage::bytea, p_attachmentcontenttype => @AttachmentContentType::text)", conn);

            cmd.Parameters.AddWithValue("@Id", model.Id);
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", (object?)model.FarmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HouseId", (object?)model.HouseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemId", (object?)model.ItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RecordDate", model.RecordDate);
            cmd.Parameters.AddWithValue("@Vaccination", (object?)model.Vaccination ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Medication", (object?)model.Medication ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterConsumption", (object?)model.WaterConsumption ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@AttachmentImage", NpgsqlDbType.Bytea, -1)
            {
                Value = (object?)model.AttachmentImage ?? DBNull.Value
            });
            cmd.Parameters.Add(new NpgsqlParameter("@AttachmentContentType", NpgsqlDbType.Text, 64)
            {
                Value = (object?)model.AttachmentContentType ?? DBNull.Value
            });
            cmd.Parameters.AddWithValue("@AttachmentImageSet", model.SetAttachmentImage);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<HealthRecordModel?> GetById(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_getbyid(p_id => @Id::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);

            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return null;

            return MapHealthRecord(reader);
        }

        public async Task<List<HealthRecordModel>> GetAll(string userId, string farmId, int? flockId = null, int? houseId = null, int? itemId = null)
        {
            var list = new List<HealthRecordModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_getall(p_userid => @UserId::text, p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_houseid => @HouseId::int, p_itemid => @ItemId::int)", conn);

            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", (object?)flockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HouseId", (object?)houseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemId", (object?)itemId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(MapHealthRecord(reader));
            }

            return list;
        }

        public async Task Delete(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_delete(p_id => @Id::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);

            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<(byte[] Body, string ContentType)?> GetAttachment(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphealth_getattachment(p_id => @Id::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);

            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync(CommandBehavior.SequentialAccess);
            if (!await reader.ReadAsync()) return null;

            var ordImg = reader.GetOrdinal("AttachmentImage");
            var ordCt = reader.GetOrdinal("AttachmentContentType");
            if (reader.IsDBNull(ordImg)) return null;

            var len = reader.GetBytes(ordImg, 0, null, 0, 0);
            if (len <= 0) return null;

            var buf = new byte[len];
            reader.GetBytes(ordImg, 0, buf, 0, (int)len);
            var ct = reader.IsDBNull(ordCt) ? "application/octet-stream" : reader.GetString(ordCt);
            return (buf, ct);
        }

        private static HealthRecordModel MapHealthRecord(NpgsqlDataReader reader)
        {
            var hasOrd = TryGetOrdinal(reader, "HasAttachmentImage", out var hasAttOrd);
            return new HealthRecordModel
            {
                Id = reader.GetInt32(reader.GetOrdinal("Id")),
                UserId = reader.GetNullableString("UserId") ?? string.Empty,
                FarmId = reader.GetNullableString("FarmId"),
                FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                HouseId = reader.IsDBNull(reader.GetOrdinal("HouseId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("HouseId")),
                ItemId = reader.IsDBNull(reader.GetOrdinal("ItemId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("ItemId")),
                RecordDate = reader.GetDateTime(reader.GetOrdinal("RecordDate")),
                Vaccination = reader.GetNullableString("Vaccination"),
                Medication = reader.GetNullableString("Medication"),
                WaterConsumption = reader.IsDBNull(reader.GetOrdinal("WaterConsumption")) ? (decimal?)null : reader.GetDecimal(reader.GetOrdinal("WaterConsumption")),
                Notes = reader.GetNullableString("Notes"),
                CreatedDate = reader.GetNullableDateTime("CreatedDate"),
                HasAttachmentImage = hasOrd && !reader.IsDBNull(hasAttOrd) && reader.GetBoolean(hasAttOrd)
            };
        }

        private static bool TryGetOrdinal(NpgsqlDataReader reader, string name, out int ordinal)
        {
            try
            {
                ordinal = reader.GetOrdinal(name);
                return true;
            }
            catch (IndexOutOfRangeException)
            {
                ordinal = -1;
                return false;
            }
        }
    }
}
