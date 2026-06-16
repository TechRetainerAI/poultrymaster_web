// Generic Company Staff + Attendance + Payroll services (spec §13, §14).
// Same SqlConnection + SP pattern as WaterStaffPayrollServices.cs / the other
// Generic*Service files. Payroll item CRUD routes through
// dbo.spGenericPayrollItem_Upsert so adding/changing a line rolls the run
// totals atomically — the C# side is a thin pass-through.

using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Staff
    // ====================================================================
    public interface IGenericStaffService
    {
        Task<List<GenericStaffModel>> GetAllAsync(string farmId, string? role);
        Task<GenericStaffModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(GenericStaffModel m);
        Task       UpdateAsync(GenericStaffModel m);
        Task       DeleteAsync(int id, string farmId);
    }

    public class GenericStaffService : IGenericStaffService
    {
        private readonly string _cs;
        public GenericStaffService(string cs) => _cs = cs;

        public async Task<List<GenericStaffModel>> GetAllAsync(string farmId, string? role)
        {
            var list = new List<GenericStaffModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaff_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Role", (object?)role ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<GenericStaffModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaff_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(GenericStaffModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaff_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)m.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(GenericStaffModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaff_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStaffId", m.GenericStaffId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)m.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaff_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericStaffModel Read(SqlDataReader r) => new()
        {
            GenericStaffId  = r.GetInt32(r.GetOrdinal("GenericStaffId")),
            FarmId          = r.GetString(r.GetOrdinal("FarmId")),
            FirstName       = r.GetString(r.GetOrdinal("FirstName")),
            LastName        = r.GetString(r.GetOrdinal("LastName")),
            PhoneNumber     = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Email           = r.IsDBNull(r.GetOrdinal("Email"))       ? null : r.GetString(r.GetOrdinal("Email")),
            Role            = r.GetString(r.GetOrdinal("Role")),
            SalaryType      = r.GetString(r.GetOrdinal("SalaryType")),
            BasePay         = r.GetDecimal(r.GetOrdinal("BasePay")),
            CommissionRate  = r.IsDBNull(r.GetOrdinal("CommissionRate")) ? null : r.GetDecimal(r.GetOrdinal("CommissionRate")),
            BranchId        = r.IsDBNull(r.GetOrdinal("BranchId")) ? null : r.GetInt32(r.GetOrdinal("BranchId")),
            IsActive        = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted       = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes           = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public interface IGenericStaffAttendanceService
    {
        Task<List<GenericStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate);
        Task<GenericStaffAttendanceModel?>      UpsertAsync(string farmId, GenericStaffAttendanceUpsertRequest req, string? createdBy);
        Task                                     DeleteAsync(int id, string farmId);
    }

    public class GenericStaffAttendanceService : IGenericStaffAttendanceService
    {
        private readonly string _cs;
        public GenericStaffAttendanceService(string cs) => _cs = cs;

        public async Task<List<GenericStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericStaffAttendanceModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaffAttendance_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericStaffId", (object?)staffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate",       (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",         (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<GenericStaffAttendanceModel?> UpsertAsync(string farmId, GenericStaffAttendanceUpsertRequest req, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaffAttendance_Upsert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericStaffId", req.GenericStaffId);
            cmd.Parameters.AddWithValue("@AttendanceDate", req.AttendanceDate.Date);
            cmd.Parameters.AddWithValue("@Shift",    (object?)req.Shift    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClockIn",  (object?)req.ClockIn  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClockOut", (object?)req.ClockOut ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status",   req.Status);
            cmd.Parameters.AddWithValue("@Notes",    (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericStaffAttendance_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStaffAttendanceId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericStaffAttendanceModel Read(SqlDataReader r)
        {
            var m = new GenericStaffAttendanceModel
            {
                GenericStaffAttendanceId = r.GetInt32(r.GetOrdinal("GenericStaffAttendanceId")),
                FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
                GenericStaffId           = r.GetInt32(r.GetOrdinal("GenericStaffId")),
                AttendanceDate           = r.GetDateTime(r.GetOrdinal("AttendanceDate")),
                ClockIn                  = r.IsDBNull(r.GetOrdinal("ClockIn"))  ? null : r.GetDateTime(r.GetOrdinal("ClockIn")),
                ClockOut                 = r.IsDBNull(r.GetOrdinal("ClockOut")) ? null : r.GetDateTime(r.GetOrdinal("ClockOut")),
                Shift                    = r.IsDBNull(r.GetOrdinal("Shift"))    ? null : r.GetString(r.GetOrdinal("Shift")),
                Status                   = r.GetString(r.GetOrdinal("Status")),
                Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            };
            // StaffName / StaffRole only exist on GetAll, not on Upsert's return shape.
            for (int i = 0; i < r.FieldCount; i++)
            {
                var n = r.GetName(i);
                if (n.Equals("StaffName", StringComparison.OrdinalIgnoreCase))      m.StaffName = r.IsDBNull(i) ? null : r.GetString(i);
                else if (n.Equals("StaffRole", StringComparison.OrdinalIgnoreCase)) m.StaffRole = r.IsDBNull(i) ? null : r.GetString(i);
            }
            return m;
        }
    }

    // ====================================================================
    // Payroll
    // ====================================================================
    public interface IGenericPayrollService
    {
        Task<List<GenericPayrollRunModel>> GetRunsAsync(string farmId, string? status);
        Task<GenericPayrollRunModel?>      GetRunAsync(int id, string farmId);
        Task<int>  CreateRunAsync(GenericPayrollRunCreateRequest req, string? createdBy);
        Task       UpdateRunAsync(int runId, string farmId, GenericPayrollRunUpdateRequest req);
        Task<GenericPayrollItemModel?> UpsertItemAsync(int runId, string farmId, GenericPayrollItemUpsertRequest req);
        Task       DeleteItemAsync(int itemId, string farmId);
        Task       ApproveAsync(int runId, string farmId, string? approvedBy);
        Task       MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate);
        Task       CancelAsync(int runId, string farmId, string? cancelledBy, string? reason);
    }

    public class GenericPayrollService : IGenericPayrollService
    {
        private readonly string _cs;
        public GenericPayrollService(string cs) => _cs = cs;

        public async Task<List<GenericPayrollRunModel>> GetRunsAsync(string farmId, string? status)
        {
            var list = new List<GenericPayrollRunModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRun(r));
            return list;
        }

        public async Task<GenericPayrollRunModel?> GetRunAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            GenericPayrollRunModel? run = null;
            if (await r.ReadAsync()) run = ReadRun(r);
            if (run == null) return null;

            // Second result set: items
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                    run.Items.Add(ReadItem(r));
            }
            return run;
        }

        public async Task<int> CreateRunAsync(GenericPayrollRunCreateRequest req, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PeriodStart", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@PeriodEnd",   req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@PayDate",              (object?)req.PayDate?.Date         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes                  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",            (object?)createdBy                  ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateRunAsync(int runId, string farmId, GenericPayrollRunUpdateRequest req)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PeriodStart", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@PeriodEnd",   req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@PayDate",              (object?)req.PayDate?.Date        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes                 ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<GenericPayrollItemModel?> UpsertItemAsync(int runId, string farmId, GenericPayrollItemUpsertRequest req)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollItem_Upsert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericStaffId", req.GenericStaffId);
            cmd.Parameters.AddWithValue("@BasicPay",   req.BasicPay);
            cmd.Parameters.AddWithValue("@DailyWage",  req.DailyWage);
            cmd.Parameters.AddWithValue("@Commission", req.Commission);
            cmd.Parameters.AddWithValue("@Bonus",      req.Bonus);
            cmd.Parameters.AddWithValue("@Deductions", req.Deductions);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)req.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",         (object?)req.Notes         ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadItem(r) : null;
        }

        public async Task DeleteItemAsync(int itemId, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollItem_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollItemId", itemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int runId, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_MarkPaid", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaidBy",  (object?)paidBy        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PayDate", (object?)payDate?.Date ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int runId, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spGenericPayrollRun_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",      (object?)reason      ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ----- Readers
        private static GenericPayrollRunModel ReadRun(SqlDataReader r) => new()
        {
            GenericPayrollRunId  = r.GetInt32(r.GetOrdinal("GenericPayrollRunId")),
            FarmId               = r.GetString(r.GetOrdinal("FarmId")),
            PeriodStart          = r.GetDateTime(r.GetOrdinal("PeriodStart")),
            PeriodEnd            = r.GetDateTime(r.GetOrdinal("PeriodEnd")),
            PayDate              = r.IsDBNull(r.GetOrdinal("PayDate")) ? null : r.GetDateTime(r.GetOrdinal("PayDate")),
            TotalGrossPay        = r.GetDecimal(r.GetOrdinal("TotalGrossPay")),
            TotalDeductions      = r.GetDecimal(r.GetOrdinal("TotalDeductions")),
            TotalNetPay          = r.GetDecimal(r.GetOrdinal("TotalNetPay")),
            Status               = r.GetString(r.GetOrdinal("Status")),
            GenericCashAccountId = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            CashAccountName      = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
            Notes                = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy            = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy           = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt           = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            PaidBy               = r.IsDBNull(r.GetOrdinal("PaidBy")) ? null : r.GetString(r.GetOrdinal("PaidBy")),
            PaidAt               = r.IsDBNull(r.GetOrdinal("PaidAt")) ? null : r.GetDateTime(r.GetOrdinal("PaidAt")),
            CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt            = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericPayrollItemModel ReadItem(SqlDataReader r)
        {
            var m = new GenericPayrollItemModel
            {
                GenericPayrollItemId = r.GetInt32(r.GetOrdinal("GenericPayrollItemId")),
                GenericPayrollRunId  = r.GetInt32(r.GetOrdinal("GenericPayrollRunId")),
                GenericStaffId       = r.GetInt32(r.GetOrdinal("GenericStaffId")),
                BasicPay             = r.GetDecimal(r.GetOrdinal("BasicPay")),
                DailyWage            = r.GetDecimal(r.GetOrdinal("DailyWage")),
                Commission           = r.GetDecimal(r.GetOrdinal("Commission")),
                Bonus                = r.GetDecimal(r.GetOrdinal("Bonus")),
                Deductions           = r.GetDecimal(r.GetOrdinal("Deductions")),
                NetPay               = r.GetDecimal(r.GetOrdinal("NetPay")),
                PaymentMethod        = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
                Notes                = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            };
            for (int i = 0; i < r.FieldCount; i++)
            {
                var n = r.GetName(i);
                if (n.Equals("StaffName", StringComparison.OrdinalIgnoreCase))      m.StaffName  = r.IsDBNull(i) ? null : r.GetString(i);
                else if (n.Equals("StaffRole", StringComparison.OrdinalIgnoreCase)) m.StaffRole  = r.IsDBNull(i) ? null : r.GetString(i);
            }
            return m;
        }
    }
}
