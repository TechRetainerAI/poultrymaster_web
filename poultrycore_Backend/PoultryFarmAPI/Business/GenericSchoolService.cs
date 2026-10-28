using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericSchoolService : IGenericSchoolService
    {
        private readonly string _connectionString;
        public GenericSchoolService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Classes
        // ====================================================================
        public async Task<List<GenericClassModel>> GetClassesAsync(string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM spgenericclass_list(@p)";
            cmd.Parameters.AddWithValue("p", farmId);
            var list = new List<GenericClassModel>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new GenericClassModel
                {
                    GenericClassId = r.GetInt32(r.GetOrdinal("genericclassid")),
                    FarmId = r.GetString(r.GetOrdinal("farmid")),
                    ClassName = r.GetString(r.GetOrdinal("classname")),
                    ClassLevel = r.IsDBNull(r.GetOrdinal("classlevel")) ? null : r.GetInt32(r.GetOrdinal("classlevel")),
                    ClassTeacher = r.IsDBNull(r.GetOrdinal("classteacher")) ? null : r.GetString(r.GetOrdinal("classteacher")),
                    Capacity = r.IsDBNull(r.GetOrdinal("capacity")) ? null : r.GetInt32(r.GetOrdinal("capacity")),
                    Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                    IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                    StudentCount = r.GetInt64(r.GetOrdinal("studentcount")),
                });
            }
            return list;
        }

        public async Task<int> UpsertClassAsync(string farmId, GenericClassModel m)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericclass_upsert(@farmid, @id, @name, @level, @teacher, @cap, @desc, @active)";
            cmd.Parameters.AddWithValue("farmid", farmId);
            cmd.Parameters.Add(new NpgsqlParameter("id", NpgsqlTypes.NpgsqlDbType.Integer) { Value = m.GenericClassId > 0 ? m.GenericClassId : DBNull.Value });
            cmd.Parameters.AddWithValue("name", m.ClassName);
            cmd.Parameters.Add(new NpgsqlParameter("level", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)m.ClassLevel ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("teacher", NpgsqlTypes.NpgsqlDbType.Varchar) { Value = (object?)m.ClassTeacher ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("cap", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)m.Capacity ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("desc", NpgsqlTypes.NpgsqlDbType.Varchar) { Value = (object?)m.Description ?? DBNull.Value });
            cmd.Parameters.AddWithValue("active", m.IsActive);
            return (int)(await cmd.ExecuteScalarAsync())!;
        }

        public async Task DeleteClassAsync(int id, string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericclass_delete(@id, @farmid)";
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("farmid", farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Academic Terms
        // ====================================================================
        public async Task<List<GenericAcademicTermModel>> GetTermsAsync(string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM spgenericacademicterm_list(@p)";
            cmd.Parameters.AddWithValue("p", farmId);
            var list = new List<GenericAcademicTermModel>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new GenericAcademicTermModel
                {
                    GenericAcademicTermId = r.GetInt32(r.GetOrdinal("genericacademictermid")),
                    FarmId = r.GetString(r.GetOrdinal("farmid")),
                    TermName = r.GetString(r.GetOrdinal("termname")),
                    StartDate = r.GetDateTime(r.GetOrdinal("startdate")),
                    EndDate = r.GetDateTime(r.GetOrdinal("enddate")),
                    IsCurrent = r.GetBoolean(r.GetOrdinal("iscurrent")),
                    IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                });
            }
            return list;
        }

        public async Task<int> UpsertTermAsync(string farmId, GenericAcademicTermModel m)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericacademicterm_upsert(@farmid, @id, @name, @start, @end, @current, @active)";
            cmd.Parameters.AddWithValue("farmid", farmId);
            cmd.Parameters.Add(new NpgsqlParameter("id", NpgsqlTypes.NpgsqlDbType.Integer) { Value = m.GenericAcademicTermId > 0 ? m.GenericAcademicTermId : DBNull.Value });
            cmd.Parameters.AddWithValue("name", m.TermName);
            cmd.Parameters.Add(new NpgsqlParameter("start", NpgsqlTypes.NpgsqlDbType.Date) { Value = m.StartDate });
            cmd.Parameters.Add(new NpgsqlParameter("end", NpgsqlTypes.NpgsqlDbType.Date) { Value = m.EndDate });
            cmd.Parameters.AddWithValue("current", m.IsCurrent);
            cmd.Parameters.AddWithValue("active", m.IsActive);
            return (int)(await cmd.ExecuteScalarAsync())!;
        }

        public async Task DeleteTermAsync(int id, string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericacademicterm_delete(@id, @farmid)";
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("farmid", farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Customer/Student Attendance (migration 367)
        // ====================================================================
        public async Task<List<GenericCustomerAttendanceModel>> GetCustomerAttendanceAsync(string farmId, DateTime? date, int? classId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM spgenericcustomerattendance_list(@p, @d, @c)";
            cmd.Parameters.AddWithValue("p", farmId);
            cmd.Parameters.Add(new NpgsqlParameter("d", NpgsqlTypes.NpgsqlDbType.Date) { Value = (object?)date ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("c", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)classId ?? DBNull.Value });
            var list = new List<GenericCustomerAttendanceModel>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new GenericCustomerAttendanceModel
                {
                    GenericCustomerAttendanceId = r.GetInt32(r.GetOrdinal("genericcustomerattendanceid")),
                    FarmId = r.GetString(r.GetOrdinal("farmid")),
                    GenericCustomerId = r.GetInt32(r.GetOrdinal("genericcustomerid")),
                    CustomerName = r.IsDBNull(r.GetOrdinal("customername")) ? null : r.GetString(r.GetOrdinal("customername")),
                    ClassOrGrade = r.IsDBNull(r.GetOrdinal("classorgrade")) ? null : r.GetString(r.GetOrdinal("classorgrade")),
                    AttendanceDate = r.GetDateTime(r.GetOrdinal("attendancedate")),
                    Status = r.GetString(r.GetOrdinal("status")),
                    GenericClassId = r.IsDBNull(r.GetOrdinal("genericclassid")) ? null : r.GetInt32(r.GetOrdinal("genericclassid")),
                    GenericAcademicTermId = r.IsDBNull(r.GetOrdinal("genericacademictermid")) ? null : r.GetInt32(r.GetOrdinal("genericacademictermid")),
                    Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                    CreatedBy = r.IsDBNull(r.GetOrdinal("createdby")) ? null : r.GetString(r.GetOrdinal("createdby")),
                });
            }
            return list;
        }

        public async Task<int> UpsertCustomerAttendanceAsync(string farmId, GenericCustomerAttendanceModel m)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericcustomerattendance_upsert(@farmid, @custid, @date, @status, @classid, @termid, @notes, @by)";
            cmd.Parameters.AddWithValue("farmid", farmId);
            cmd.Parameters.AddWithValue("custid", m.GenericCustomerId);
            cmd.Parameters.Add(new NpgsqlParameter("date", NpgsqlTypes.NpgsqlDbType.Date) { Value = m.AttendanceDate });
            cmd.Parameters.AddWithValue("status", m.Status);
            cmd.Parameters.Add(new NpgsqlParameter("classid", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)m.GenericClassId ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("termid", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)m.GenericAcademicTermId ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("notes", NpgsqlTypes.NpgsqlDbType.Varchar) { Value = (object?)m.Notes ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("by", NpgsqlTypes.NpgsqlDbType.Varchar) { Value = (object?)m.CreatedBy ?? DBNull.Value });
            return (int)(await cmd.ExecuteScalarAsync())!;
        }

        public async Task DeleteCustomerAttendanceAsync(int id, string farmId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT spgenericcustomerattendance_delete(@id, @farmid)";
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("farmid", farmId);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
