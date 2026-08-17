// Poultry Staff + Attendance + Payroll services (port of the Water W6 module).
// Same NpgsqlConnection + SP pattern as PoultryCashServices.cs. Payroll item CRUD
// goes through spPoultryPayrollItem_Upsert so adding/changing a line rolls run
// totals atomically. The approve/mark-paid/reverse SPs handle the linked expense
// (dbo.Expense) and cash side-effects inside SQL Server.

using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Staff
    // ====================================================================
    public interface IPoultryStaffService
    {
        Task<List<PoultryStaffModel>> GetAllAsync(string farmId, string? role);
        Task<PoultryStaffModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryStaffModel m);
        Task       UpdateAsync(PoultryStaffModel m);
        Task       DeleteAsync(int id, string farmId);
    }

    public class PoultryStaffService : IPoultryStaffService
    {
        private readonly string _cs;
        public PoultryStaffService(string cs) => _cs = cs;

        public async Task<List<PoultryStaffModel>> GetAllAsync(string farmId, string? role)
        {
            var list = new List<PoultryStaffModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaff_getall(p_farmid => @FarmId::text, p_role => @Role::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Role", (object?)role ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryStaffModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaff_getbyid(p_poultrystaffid => @PoultryStaffId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(PoultryStaffModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaff_insert(p_farmid => @FarmId::text, p_firstname => @FirstName::text, p_lastname => @LastName::text, p_phonenumber => @PhoneNumber::text, p_email => @Email::text, p_role => @Role::text, p_salarytype => @SalaryType::text, p_basepay => @BasePay::numeric, p_commissionrate => @CommissionRate::numeric, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(PoultryStaffModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaff_update(p_poultrystaffid => @PoultryStaffId::int, p_farmid => @FarmId::text, p_firstname => @FirstName::text, p_lastname => @LastName::text, p_phonenumber => @PhoneNumber::text, p_email => @Email::text, p_role => @Role::text, p_salarytype => @SalaryType::text, p_basepay => @BasePay::numeric, p_commissionrate => @CommissionRate::numeric, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryStaffId", m.PoultryStaffId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName",  m.LastName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",       (object?)m.Email       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@CommissionRate", (object?)m.CommissionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaff_delete(p_poultrystaffid => @PoultryStaffId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryStaffId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryStaffModel Read(NpgsqlDataReader r) => new()
        {
            PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
            FarmId         = r.GetString(r.GetOrdinal("FarmId")),
            FirstName      = r.GetString(r.GetOrdinal("FirstName")),
            LastName       = r.GetString(r.GetOrdinal("LastName")),
            PhoneNumber    = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Email          = r.IsDBNull(r.GetOrdinal("Email"))       ? null : r.GetString(r.GetOrdinal("Email")),
            Role           = r.GetString(r.GetOrdinal("Role")),
            SalaryType     = r.GetString(r.GetOrdinal("SalaryType")),
            BasePay        = r.GetDecimal(r.GetOrdinal("BasePay")),
            CommissionRate = r.IsDBNull(r.GetOrdinal("CommissionRate")) ? null : r.GetDecimal(r.GetOrdinal("CommissionRate")),
            IsActive       = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted      = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes          = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt      = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt      = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public interface IPoultryStaffAttendanceService
    {
        Task<List<PoultryStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate);
        Task<PoultryStaffAttendanceModel?>      UpsertAsync(string farmId, PoultryStaffAttendanceUpsertRequest req, string? createdBy);
        Task                                     DeleteAsync(int id, string farmId);
    }

    public class PoultryStaffAttendanceService : IPoultryStaffAttendanceService
    {
        private readonly string _cs;
        public PoultryStaffAttendanceService(string cs) => _cs = cs;

        public async Task<List<PoultryStaffAttendanceModel>> GetAllAsync(string farmId, int? staffId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryStaffAttendanceModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaffattendance_getall(p_farmid => @FarmId::text, p_poultrystaffid => @PoultryStaffId::int, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryStaffId", (object?)staffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate",       (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",         (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryStaffAttendanceModel?> UpsertAsync(string farmId, PoultryStaffAttendanceUpsertRequest req, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaffattendance_upsert(p_farmid => @FarmId::text, p_poultrystaffid => @PoultryStaffId::int, p_attendancedate => @AttendanceDate::date, p_shift => @Shift::text, p_clockin => @ClockIn::timestamp, p_clockout => @ClockOut::timestamp, p_status => @Status::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryStaffId", req.PoultryStaffId);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystaffattendance_delete(p_poultrystaffattendanceid => @PoultryStaffAttendanceId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryStaffAttendanceId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryStaffAttendanceModel Read(NpgsqlDataReader r)
        {
            var m = new PoultryStaffAttendanceModel
            {
                PoultryStaffAttendanceId = r.GetInt32(r.GetOrdinal("PoultryStaffAttendanceId")),
                FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
                PoultryStaffId           = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
                AttendanceDate           = r.GetDateTime(r.GetOrdinal("AttendanceDate")),
                ClockIn                  = r.IsDBNull(r.GetOrdinal("ClockIn"))  ? null : r.GetDateTime(r.GetOrdinal("ClockIn")),
                ClockOut                 = r.IsDBNull(r.GetOrdinal("ClockOut")) ? null : r.GetDateTime(r.GetOrdinal("ClockOut")),
                Shift                    = r.IsDBNull(r.GetOrdinal("Shift"))    ? null : r.GetString(r.GetOrdinal("Shift")),
                Status                   = r.GetString(r.GetOrdinal("Status")),
                Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            };
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
    public interface IPoultryPayrollService
    {
        Task<List<PoultryPayrollRunModel>> GetRunsAsync(string farmId, string? status);
        Task<PoultryPayrollRunModel?>      GetRunAsync(int id, string farmId);
        Task<int>  CreateRunAsync(PoultryPayrollRunCreateRequest req, string? createdBy);
        Task<PoultryPayrollItemModel?> UpsertItemAsync(int runId, string farmId, PoultryPayrollItemUpsertRequest req);
        Task       DeleteItemAsync(int itemId, string farmId);
        Task       ApproveAsync(int runId, string farmId, string? approvedBy);
        Task       MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate);
        Task       CancelAsync(int runId, string farmId, string? cancelledBy, string? reason);
        Task       UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason);
        Task       DeleteRunAsync(int runId, string farmId, string? deletedBy);
        Task<PoultryPayrollRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId);
    }

    public class PoultryPayrollService : IPoultryPayrollService
    {
        private readonly string _cs;
        public PoultryPayrollService(string cs) => _cs = cs;

        public async Task<List<PoultryPayrollRunModel>> GetRunsAsync(string farmId, string? status)
        {
            var list = new List<PoultryPayrollRunModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRun(r));
            return list;
        }

        public async Task<PoultryPayrollRunModel?> GetRunAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_getbyid_rs1(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrypayrollrun_getbyid_rs2(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            PoultryPayrollRunModel? run = null;
            if (await r.ReadAsync()) run = ReadRun(r);
            if (run == null) return null;

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    run.Items.Add(ReadItem(r));
            return run;
        }

        public async Task<int> CreateRunAsync(PoultryPayrollRunCreateRequest req, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_insert(p_farmid => @FarmId::text, p_periodstart => @PeriodStart::date, p_periodend => @PeriodEnd::date, p_paydate => @PayDate::date, p_poultrycashaccountid => @PoultryCashAccountId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PeriodStart", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@PeriodEnd",   req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@PayDate",              (object?)req.PayDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)req.PoultryCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",            (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<PoultryPayrollItemModel?> UpsertItemAsync(int runId, string farmId, PoultryPayrollItemUpsertRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollitem_upsert(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_poultrystaffid => @PoultryStaffId::int, p_basicpay => @BasicPay::numeric, p_dailywage => @DailyWage::numeric, p_commission => @Commission::numeric, p_bonus => @Bonus::numeric, p_deductions => @Deductions::numeric, p_paymentmethod => @PaymentMethod::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryStaffId", req.PoultryStaffId);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollitem_delete(p_poultrypayrollitemid => @PoultryPayrollItemId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollItemId", itemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int runId, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_approve(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_markpaid(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_paidby => @PaidBy::text, p_paydate => @PayDate::date)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaidBy",  (object?)paidBy        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PayDate", (object?)payDate?.Date ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int runId, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_cancel(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_cancelledby => @CancelledBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",      (object?)reason      ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_unapprove(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_reopenedby => @ReopenedBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",     (object?)reason     ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteRunAsync(int runId, string farmId, string? deletedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_delete(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text, p_deletedby => @DeletedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DeletedBy", (object?)deletedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<PoultryPayrollRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrollrun_getdetailswithytd_rs1(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrypayrollrun_getdetailswithytd_rs2(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrypayrollrun_getdetailswithytd_rs3(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrypayrollrun_getdetailswithytd_rs4(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrypayrollrun_getdetailswithytd_rs5(p_poultrypayrollrunid => @PoultryPayrollRunId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            var result = new PoultryPayrollRunDetailsModel();

            if (await r.ReadAsync()) result.Run = ReadRun(r);
            if (result.Run == null) return null;

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    result.Run.Items.Add(ReadItem(r));

            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                result.YtdTotals = new PoultryPayrollYtdTotals
                {
                    Year             = r.GetInt32(r.GetOrdinal("Year")),
                    YtdGrossPaid     = r.GetDecimal(r.GetOrdinal("YtdGrossPaid")),
                    YtdDeductions    = r.GetDecimal(r.GetOrdinal("YtdDeductions")),
                    YtdNetPaid       = r.GetDecimal(r.GetOrdinal("YtdNetPaid")),
                    TotalPayrollRuns = r.GetInt32(r.GetOrdinal("TotalPayrollRuns")),
                    TotalStaffPaid   = r.GetInt32(r.GetOrdinal("TotalStaffPaid")),
                };
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    result.YtdByStaff.Add(new PoultryPayrollYtdStaffRow
                    {
                        PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
                        StaffName      = r.IsDBNull(r.GetOrdinal("StaffName")) ? null : r.GetString(r.GetOrdinal("StaffName")),
                        StaffRole      = r.IsDBNull(r.GetOrdinal("StaffRole")) ? null : r.GetString(r.GetOrdinal("StaffRole")),
                        YtdBasic       = r.GetDecimal(r.GetOrdinal("YtdBasic")),
                        YtdDaily       = r.GetDecimal(r.GetOrdinal("YtdDaily")),
                        YtdCommission  = r.GetDecimal(r.GetOrdinal("YtdCommission")),
                        YtdBonus       = r.GetDecimal(r.GetOrdinal("YtdBonus")),
                        YtdDeductions  = r.GetDecimal(r.GetOrdinal("YtdDeductions")),
                        YtdGross       = r.GetDecimal(r.GetOrdinal("YtdGross")),
                        YtdNet         = r.GetDecimal(r.GetOrdinal("YtdNet")),
                    });
                }
            }

            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                result.LinkedExpense = new PoultryPayrollLinkedExpense
                {
                    ExpenseId     = r.GetInt32(r.GetOrdinal("ExpenseId")),
                    FarmId        = r.IsDBNull(r.GetOrdinal("FarmId")) ? string.Empty : Convert.ToString(r.GetValue(r.GetOrdinal("FarmId")))!,
                    ExpenseDate   = r.GetDateTime(r.GetOrdinal("ExpenseDate")),
                    Category      = r.IsDBNull(r.GetOrdinal("Category"))      ? null : r.GetString(r.GetOrdinal("Category")),
                    Description   = r.IsDBNull(r.GetOrdinal("Description"))   ? null : r.GetString(r.GetOrdinal("Description")),
                    Amount        = r.GetDecimal(r.GetOrdinal("Amount")),
                    PaymentMethod = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
                    SourceType    = r.IsDBNull(r.GetOrdinal("SourceType"))    ? null : r.GetString(r.GetOrdinal("SourceType")),
                    SourceId      = r.IsDBNull(r.GetOrdinal("SourceId"))      ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                    CreatedDate   = r.GetDateTime(r.GetOrdinal("CreatedDate")),
                };
            }

            return result;
        }

        // ----- Readers
        private static bool HasCol(NpgsqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            return false;
        }

        private static PoultryPayrollRunModel ReadRun(NpgsqlDataReader r) => new()
        {
            PoultryPayrollRunId  = r.GetInt32(r.GetOrdinal("PoultryPayrollRunId")),
            FarmId               = r.GetString(r.GetOrdinal("FarmId")),
            PeriodStart          = r.GetDateTime(r.GetOrdinal("PeriodStart")),
            PeriodEnd            = r.GetDateTime(r.GetOrdinal("PeriodEnd")),
            PayDate              = r.IsDBNull(r.GetOrdinal("PayDate")) ? null : r.GetDateTime(r.GetOrdinal("PayDate")),
            TotalGrossPay        = r.GetDecimal(r.GetOrdinal("TotalGrossPay")),
            TotalDeductions      = r.GetDecimal(r.GetOrdinal("TotalDeductions")),
            TotalNetPay          = r.GetDecimal(r.GetOrdinal("TotalNetPay")),
            Status               = r.GetString(r.GetOrdinal("Status")),
            PoultryCashAccountId = r.IsDBNull(r.GetOrdinal("PoultryCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
            CashAccountName      = HasCol(r, "CashAccountName") && !r.IsDBNull(r.GetOrdinal("CashAccountName")) ? r.GetString(r.GetOrdinal("CashAccountName")) : null,
            Notes                = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy            = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy           = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt           = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            PaidBy               = r.IsDBNull(r.GetOrdinal("PaidBy")) ? null : r.GetString(r.GetOrdinal("PaidBy")),
            PaidAt               = r.IsDBNull(r.GetOrdinal("PaidAt")) ? null : r.GetDateTime(r.GetOrdinal("PaidAt")),
            ReopenedBy           = HasCol(r, "ReopenedBy")   && !r.IsDBNull(r.GetOrdinal("ReopenedBy"))   ? r.GetString(r.GetOrdinal("ReopenedBy"))   : null,
            ReopenedAt           = HasCol(r, "ReopenedAt")   && !r.IsDBNull(r.GetOrdinal("ReopenedAt"))   ? r.GetDateTime(r.GetOrdinal("ReopenedAt")) : (DateTime?)null,
            ReopenReason         = HasCol(r, "ReopenReason") && !r.IsDBNull(r.GetOrdinal("ReopenReason")) ? r.GetString(r.GetOrdinal("ReopenReason")) : null,
            ReapprovedBy         = HasCol(r, "ReapprovedBy") && !r.IsDBNull(r.GetOrdinal("ReapprovedBy")) ? r.GetString(r.GetOrdinal("ReapprovedBy")) : null,
            ReapprovedAt         = HasCol(r, "ReapprovedAt") && !r.IsDBNull(r.GetOrdinal("ReapprovedAt")) ? r.GetDateTime(r.GetOrdinal("ReapprovedAt")) : (DateTime?)null,
            CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt            = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static PoultryPayrollItemModel ReadItem(NpgsqlDataReader r)
        {
            var m = new PoultryPayrollItemModel
            {
                PoultryPayrollItemId = r.GetInt32(r.GetOrdinal("PoultryPayrollItemId")),
                PoultryPayrollRunId  = r.GetInt32(r.GetOrdinal("PoultryPayrollRunId")),
                PoultryStaffId       = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
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
                if (n.Equals("StaffName", StringComparison.OrdinalIgnoreCase))      m.StaffName = r.IsDBNull(i) ? null : r.GetString(i);
                else if (n.Equals("StaffRole", StringComparison.OrdinalIgnoreCase)) m.StaffRole = r.IsDBNull(i) ? null : r.GetString(i);
            }
            return m;
        }
    }
}
