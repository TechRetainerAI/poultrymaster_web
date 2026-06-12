// Water Staff + Attendance + Payroll services (Phase W6).
// Same SqlConnection + SP pattern as WaterFinanceServices.cs. Payroll item
// CRUD goes through dbo.spWaterPayrollItem_Upsert so adding/changing a line
// also rolls the run totals atomically — the C# side is just a thin pass-through.

using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Staff
    // ====================================================================
    public interface IWaterStaffService
    {
        Task<List<WaterStaffModel>> GetAllAsync(string farmId, string? role);
        Task<WaterStaffModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(WaterStaffModel m);
        Task       UpdateAsync(WaterStaffModel m);
        Task       DeleteAsync(int id, string farmId);
    }

    public class WaterStaffService : IWaterStaffService
    {
        private readonly string _cs;
        public WaterStaffService(string cs) => _cs = cs;

        public async Task<List<WaterStaffModel>> GetAllAsync(string farmId, string? role)
        {
            var list = new List<WaterStaffModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaff_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Role", (object?)role ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterStaffModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaff_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterStaffModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaff_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedWaterVehicleId", (object?)m.AssignedWaterVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedWaterRouteId",   (object?)m.AssignedWaterRouteId   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterStaffModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaff_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterStaffId", m.WaterStaffId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedWaterVehicleId", (object?)m.AssignedWaterVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedWaterRouteId",   (object?)m.AssignedWaterRouteId   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaff_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterStaffModel Read(SqlDataReader r) => new()
        {
            WaterStaffId           = r.GetInt32(r.GetOrdinal("WaterStaffId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            FirstName              = r.GetString(r.GetOrdinal("FirstName")),
            LastName               = r.GetString(r.GetOrdinal("LastName")),
            PhoneNumber            = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Email                  = r.IsDBNull(r.GetOrdinal("Email"))       ? null : r.GetString(r.GetOrdinal("Email")),
            Role                   = r.GetString(r.GetOrdinal("Role")),
            SalaryType             = r.GetString(r.GetOrdinal("SalaryType")),
            BasePay                = r.GetDecimal(r.GetOrdinal("BasePay")),
            CommissionRate         = r.IsDBNull(r.GetOrdinal("CommissionRate")) ? null : r.GetDecimal(r.GetOrdinal("CommissionRate")),
            AssignedWaterVehicleId = r.IsDBNull(r.GetOrdinal("AssignedWaterVehicleId")) ? null : r.GetInt32(r.GetOrdinal("AssignedWaterVehicleId")),
            AssignedWaterRouteId   = r.IsDBNull(r.GetOrdinal("AssignedWaterRouteId"))   ? null : r.GetInt32(r.GetOrdinal("AssignedWaterRouteId")),
            IsActive               = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted              = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public interface IWaterStaffAttendanceService
    {
        Task<List<WaterStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate);
        Task<WaterStaffAttendanceModel?>      UpsertAsync(string farmId, WaterStaffAttendanceUpsertRequest req, string? createdBy);
        Task                                   DeleteAsync(int id, string farmId);
    }

    public class WaterStaffAttendanceService : IWaterStaffAttendanceService
    {
        private readonly string _cs;
        public WaterStaffAttendanceService(string cs) => _cs = cs;

        public async Task<List<WaterStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterStaffAttendanceModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaffAttendance_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterStaffId", (object?)staffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate",     (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",       (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterStaffAttendanceModel?> UpsertAsync(string farmId, WaterStaffAttendanceUpsertRequest req, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterStaffAttendance_Upsert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterStaffId", req.WaterStaffId);
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
            using var cmd = new SqlCommand("spWaterStaffAttendance_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterStaffAttendanceId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterStaffAttendanceModel Read(SqlDataReader r)
        {
            var m = new WaterStaffAttendanceModel
            {
                WaterStaffAttendanceId = r.GetInt32(r.GetOrdinal("WaterStaffAttendanceId")),
                FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
                WaterStaffId           = r.GetInt32(r.GetOrdinal("WaterStaffId")),
                AttendanceDate         = r.GetDateTime(r.GetOrdinal("AttendanceDate")),
                ClockIn                = r.IsDBNull(r.GetOrdinal("ClockIn"))  ? null : r.GetDateTime(r.GetOrdinal("ClockIn")),
                ClockOut               = r.IsDBNull(r.GetOrdinal("ClockOut")) ? null : r.GetDateTime(r.GetOrdinal("ClockOut")),
                Shift                  = r.IsDBNull(r.GetOrdinal("Shift"))    ? null : r.GetString(r.GetOrdinal("Shift")),
                Status                 = r.GetString(r.GetOrdinal("Status")),
                Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            };
            // StaffName only exists on GetAll, not on Upsert's return shape.
            for (int i = 0; i < r.FieldCount; i++)
            {
                if (r.GetName(i).Equals("StaffName", StringComparison.OrdinalIgnoreCase))
                {
                    m.StaffName = r.IsDBNull(i) ? null : r.GetString(i);
                    break;
                }
            }
            return m;
        }
    }

    // ====================================================================
    // Payroll
    // ====================================================================
    public interface IWaterPayrollService
    {
        Task<List<WaterPayrollRunModel>> GetRunsAsync(string farmId, string? status);
        Task<WaterPayrollRunModel?>      GetRunAsync(int id, string farmId);
        Task<int>  CreateRunAsync(WaterPayrollRunCreateRequest req, string? createdBy);
        Task<WaterPayrollItemModel?> UpsertItemAsync(int runId, string farmId, WaterPayrollItemUpsertRequest req);
        Task       DeleteItemAsync(int itemId, string farmId);
        Task       ApproveAsync(int runId, string farmId, string? approvedBy);
        Task       MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate);
        Task       CancelAsync(int runId, string farmId, string? cancelledBy, string? reason);
        // Migration 080
        Task       UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason);
        Task       DeleteRunAsync(int runId, string farmId, string? deletedBy);
        // Migration 082 — full Payroll Run Details with YTD totals + linked expense.
        Task<WaterPayrollRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId);
    }

    public class WaterPayrollService : IWaterPayrollService
    {
        private readonly string _cs;
        public WaterPayrollService(string cs) => _cs = cs;

        public async Task<List<WaterPayrollRunModel>> GetRunsAsync(string farmId, string? status)
        {
            var list = new List<WaterPayrollRunModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRun(r));
            return list;
        }

        public async Task<WaterPayrollRunModel?> GetRunAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            WaterPayrollRunModel? run = null;
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

        public async Task<int> CreateRunAsync(WaterPayrollRunCreateRequest req, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PeriodStart", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@PeriodEnd",   req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@PayDate",            (object?)req.PayDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)req.WaterCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",              (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",          (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<WaterPayrollItemModel?> UpsertItemAsync(int runId, string farmId, WaterPayrollItemUpsertRequest req)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollItem_Upsert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterStaffId", req.WaterStaffId);
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
            using var cmd = new SqlCommand("spWaterPayrollItem_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollItemId", itemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int runId, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_MarkPaid", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaidBy",  (object?)paidBy        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PayDate", (object?)payDate?.Date ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int runId, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",      (object?)reason      ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 080 — flip Approved/Paid → Reopened, reverse linked expense + cash.
        public async Task UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_Unapprove", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",     (object?)reason     ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 080 — hard delete a Draft / Pending / Reopened payroll run.
        public async Task DeleteRunAsync(int runId, string farmId, string? deletedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DeletedBy", (object?)deletedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 082 — one round-trip for the Payroll Run Details page.
        // SP returns 4 result sets: Run header, Items, YTD totals + YTD by staff
        // (concatenated by SQL Server into the same NextResult), Linked expense.
        public async Task<WaterPayrollRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterPayrollRun_GetDetailsWithYtd", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            var result = new WaterPayrollRunDetailsModel();

            // Set 1: Run header
            if (await r.ReadAsync()) result.Run = ReadRun(r);
            if (result.Run == null) return null;

            // Set 2: items
            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    result.Run.Items.Add(ReadItem(r));

            // Set 3a: YTD totals (single row)
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                result.YtdTotals = new WaterPayrollYtdTotals
                {
                    Year             = r.GetInt32(r.GetOrdinal("Year")),
                    YtdGrossPaid     = r.GetDecimal(r.GetOrdinal("YtdGrossPaid")),
                    YtdDeductions    = r.GetDecimal(r.GetOrdinal("YtdDeductions")),
                    YtdNetPaid       = r.GetDecimal(r.GetOrdinal("YtdNetPaid")),
                    TotalPayrollRuns = r.GetInt32(r.GetOrdinal("TotalPayrollRuns")),
                    TotalStaffPaid   = r.GetInt32(r.GetOrdinal("TotalStaffPaid")),
                };
            }

            // Set 3b: per-staff YTD
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    result.YtdByStaff.Add(new WaterPayrollYtdStaffRow
                    {
                        WaterStaffId  = r.GetInt32(r.GetOrdinal("WaterStaffId")),
                        StaffName     = r.IsDBNull(r.GetOrdinal("StaffName"))  ? null : r.GetString(r.GetOrdinal("StaffName")),
                        StaffRole     = r.IsDBNull(r.GetOrdinal("StaffRole"))  ? null : r.GetString(r.GetOrdinal("StaffRole")),
                        YtdBasic      = r.GetDecimal(r.GetOrdinal("YtdBasic")),
                        YtdDaily      = r.GetDecimal(r.GetOrdinal("YtdDaily")),
                        YtdCommission = r.GetDecimal(r.GetOrdinal("YtdCommission")),
                        YtdBonus      = r.GetDecimal(r.GetOrdinal("YtdBonus")),
                        YtdDeductions = r.GetDecimal(r.GetOrdinal("YtdDeductions")),
                        YtdGross      = r.GetDecimal(r.GetOrdinal("YtdGross")),
                        YtdNet        = r.GetDecimal(r.GetOrdinal("YtdNet")),
                    });
                }
            }

            // Set 4: linked expense (0 or 1 row)
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                result.LinkedExpense = new WaterPayrollLinkedExpense
                {
                    WaterExpenseId         = r.GetInt32(r.GetOrdinal("WaterExpenseId")),
                    FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
                    ExpenseDate            = r.GetDateTime(r.GetOrdinal("ExpenseDate")),
                    WaterExpenseCategoryId = r.GetInt32(r.GetOrdinal("WaterExpenseCategoryId")),
                    CategoryName           = r.IsDBNull(r.GetOrdinal("CategoryName"))    ? null : r.GetString(r.GetOrdinal("CategoryName")),
                    Description            = r.IsDBNull(r.GetOrdinal("Description"))     ? null : r.GetString(r.GetOrdinal("Description")),
                    Amount                 = r.GetDecimal(r.GetOrdinal("Amount")),
                    PaymentMethod          = r.IsDBNull(r.GetOrdinal("PaymentMethod"))   ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
                    WaterCashAccountId     = r.IsDBNull(r.GetOrdinal("WaterCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    CashAccountName        = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
                    Status                 = r.IsDBNull(r.GetOrdinal("Status"))          ? null : r.GetString(r.GetOrdinal("Status")),
                    Notes                  = r.IsDBNull(r.GetOrdinal("Notes"))           ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy"))       ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    ApprovedBy             = r.IsDBNull(r.GetOrdinal("ApprovedBy"))      ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    ApprovedAt             = r.IsDBNull(r.GetOrdinal("ApprovedAt"))      ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                    SourceType             = r.IsDBNull(r.GetOrdinal("SourceType"))      ? null : r.GetString(r.GetOrdinal("SourceType")),
                    SourceId               = r.IsDBNull(r.GetOrdinal("SourceId"))        ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                    CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt"))       ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                };
            }

            return result;
        }

        // ----- Readers
        private static WaterPayrollRunModel ReadRun(SqlDataReader r) => new()
        {
            WaterPayrollRunId = r.GetInt32(r.GetOrdinal("WaterPayrollRunId")),
            FarmId            = r.GetString(r.GetOrdinal("FarmId")),
            PeriodStart       = r.GetDateTime(r.GetOrdinal("PeriodStart")),
            PeriodEnd         = r.GetDateTime(r.GetOrdinal("PeriodEnd")),
            PayDate           = r.IsDBNull(r.GetOrdinal("PayDate")) ? null : r.GetDateTime(r.GetOrdinal("PayDate")),
            TotalGrossPay     = r.GetDecimal(r.GetOrdinal("TotalGrossPay")),
            TotalDeductions   = r.GetDecimal(r.GetOrdinal("TotalDeductions")),
            TotalNetPay       = r.GetDecimal(r.GetOrdinal("TotalNetPay")),
            Status            = r.GetString(r.GetOrdinal("Status")),
            WaterCashAccountId= r.IsDBNull(r.GetOrdinal("WaterCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
            CashAccountName   = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
            Notes             = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy         = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy        = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt        = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            PaidBy            = r.IsDBNull(r.GetOrdinal("PaidBy")) ? null : r.GetString(r.GetOrdinal("PaidBy")),
            PaidAt            = r.IsDBNull(r.GetOrdinal("PaidAt")) ? null : r.GetDateTime(r.GetOrdinal("PaidAt")),
            ReopenedBy        = HasCol(r, "ReopenedBy")   && !r.IsDBNull(r.GetOrdinal("ReopenedBy"))   ? r.GetString(r.GetOrdinal("ReopenedBy"))   : null,
            ReopenedAt        = HasCol(r, "ReopenedAt")   && !r.IsDBNull(r.GetOrdinal("ReopenedAt"))   ? r.GetDateTime(r.GetOrdinal("ReopenedAt")) : (DateTime?)null,
            ReopenReason      = HasCol(r, "ReopenReason") && !r.IsDBNull(r.GetOrdinal("ReopenReason")) ? r.GetString(r.GetOrdinal("ReopenReason")) : null,
            ReapprovedBy      = HasCol(r, "ReapprovedBy") && !r.IsDBNull(r.GetOrdinal("ReapprovedBy")) ? r.GetString(r.GetOrdinal("ReapprovedBy")) : null,
            ReapprovedAt      = HasCol(r, "ReapprovedAt") && !r.IsDBNull(r.GetOrdinal("ReapprovedAt")) ? r.GetDateTime(r.GetOrdinal("ReapprovedAt")) : (DateTime?)null,
            CreatedAt         = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt         = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static bool HasCol(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            return false;
        }

        private static WaterPayrollItemModel ReadItem(SqlDataReader r)
        {
            var m = new WaterPayrollItemModel
            {
                WaterPayrollItemId = r.GetInt32(r.GetOrdinal("WaterPayrollItemId")),
                WaterPayrollRunId  = r.GetInt32(r.GetOrdinal("WaterPayrollRunId")),
                WaterStaffId       = r.GetInt32(r.GetOrdinal("WaterStaffId")),
                BasicPay           = r.GetDecimal(r.GetOrdinal("BasicPay")),
                DailyWage          = r.GetDecimal(r.GetOrdinal("DailyWage")),
                Commission         = r.GetDecimal(r.GetOrdinal("Commission")),
                Bonus              = r.GetDecimal(r.GetOrdinal("Bonus")),
                Deductions         = r.GetDecimal(r.GetOrdinal("Deductions")),
                NetPay             = r.GetDecimal(r.GetOrdinal("NetPay")),
                PaymentMethod      = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
                Notes              = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                CreatedAt          = r.GetDateTime(r.GetOrdinal("CreatedAt")),
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
