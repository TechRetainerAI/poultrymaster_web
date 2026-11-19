// 451. Generic payroll, the Poultry way. Ported from PoultryStaffPayrollServices
// (payroll part), PoultryPayrollTemplateService and the deduction part of
// PoultryEmployeeLoanService. Every rule lives in the spgeneric* SQL functions.

using System.Data;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericPayRunService
    {
        Task<List<GenericPayRunModel>> GetRunsAsync(string farmId, string? status);
        Task<GenericPayRunModel?>      GetRunAsync(int id, string farmId);
        Task<int>  CreateRunAsync(GenericPayRunCreateRequest req, string? createdBy);
        Task<GenericPayItemModel?> UpsertItemAsync(int runId, string farmId, GenericPayItemUpsertRequest req);
        Task       DeleteItemAsync(int itemId, string farmId);
        Task       ApproveAsync(int runId, string farmId, string? approvedBy);
        Task       MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate);
        Task       CancelAsync(int runId, string farmId, string? cancelledBy, string? reason);
        Task       UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason);
        Task       DeleteRunAsync(int runId, string farmId, string? deletedBy);
        Task<GenericPayRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId);
    }

    public class GenericPayRunService : IGenericPayRunService
    {
        private readonly string _cs;
        public GenericPayRunService(string cs) => _cs = cs;

        public async Task<List<GenericPayRunModel>> GetRunsAsync(string farmId, string? status)
        {
            var list = new List<GenericPayRunModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRun(r));
            return list;
        }

        public async Task<GenericPayRunModel?> GetRunAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_getbyid_rs1(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpayrollrun_getbyid_rs2(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            GenericPayRunModel? run = null;
            if (await r.ReadAsync()) run = ReadRun(r);
            if (run == null) return null;

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    run.Items.Add(ReadItem(r));
            return run;
        }

        public async Task<int> CreateRunAsync(GenericPayRunCreateRequest req, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_insert(p_farmid => @FarmId::text, p_periodstart => @PeriodStart::date, p_periodend => @PeriodEnd::date, p_paydate => @PayDate::date, p_genericcashaccountid => @GenericCashAccountId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PeriodStart", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@PeriodEnd",   req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@PayDate",              (object?)req.PayDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",            (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<GenericPayItemModel?> UpsertItemAsync(int runId, string farmId, GenericPayItemUpsertRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollitem_upsert(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_genericstaffid => @GenericStaffId::int, p_basicpay => @BasicPay::numeric, p_dailywage => @DailyWage::numeric, p_commission => @Commission::numeric, p_bonus => @Bonus::numeric, p_deductions => @Deductions::numeric, p_paymentmethod => @PaymentMethod::text, p_notes => @Notes::text, p_otherdeductions => @OtherDeductions::numeric, p_employeecredit => @EmployeeCredit::numeric)", c);
            cmd.Parameters.AddWithValue("@OtherDeductions", (object?)req.OtherDeductions ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EmployeeCredit",  (object?)req.EmployeeCredit  ?? DBNull.Value);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollitem_delete(p_genericpayrollitemid => @GenericPayrollItemId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollItemId", itemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int runId, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_approve(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task MarkPaidAsync(int runId, string farmId, string? paidBy, DateTime? payDate)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_markpaid(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_paidby => @PaidBy::text, p_paydate => @PayDate::date)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaidBy",  (object?)paidBy        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PayDate", (object?)payDate?.Date ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int runId, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_cancel(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_cancelledby => @CancelledBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",      (object?)reason      ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UnapproveAsync(int runId, string farmId, string? reopenedBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_unapprove(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_reopenedby => @ReopenedBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",     (object?)reason     ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteRunAsync(int runId, string farmId, string? deletedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_delete(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text, p_deletedby => @DeletedBy::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DeletedBy", (object?)deletedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<GenericPayRunDetailsModel?> GetDetailsWithYtdAsync(int runId, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrollrun_getdetailswithytd_rs1(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpayrollrun_getdetailswithytd_rs2(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpayrollrun_getdetailswithytd_rs3(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpayrollrun_getdetailswithytd_rs4(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpayrollrun_getdetailswithytd_rs5(p_genericpayrollrunid => @GenericPayrollRunId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@GenericPayrollRunId", runId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            var result = new GenericPayRunDetailsModel();

            if (await r.ReadAsync()) result.Run = ReadRun(r);
            if (result.Run == null) return null;

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    result.Run.Items.Add(ReadItem(r));

            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                result.YtdTotals = new GenericPayYtdTotals
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
                    result.YtdByStaff.Add(new GenericPayYtdStaffRow
                    {
                        GenericStaffId = r.GetInt32(r.GetOrdinal("GenericStaffId")),
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
                result.LinkedExpense = new GenericPayLinkedExpense
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

        private static GenericPayRunModel ReadRun(NpgsqlDataReader r) => new()
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

        private static GenericPayItemModel ReadItem(NpgsqlDataReader r)
        {
            var m = new GenericPayItemModel
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
                if (n.Equals("StaffName", StringComparison.OrdinalIgnoreCase))      m.StaffName = r.IsDBNull(i) ? null : r.GetString(i);
                else if (n.Equals("StaffRole", StringComparison.OrdinalIgnoreCase)) m.StaffRole = r.IsDBNull(i) ? null : r.GetString(i);
            }
            return m;
        }
    }

    public interface IGenericPayrollTemplateService
    {
        Task<List<GenericPayrollTemplateModel>> GetAllAsync(string farmId, bool includeInactive);
        Task<GenericPayrollTemplateModel?> GetAsync(int id, string farmId);
        Task<int> SaveAsync(int? id, GenericPayrollTemplateSaveRequest req);
        Task SetActiveAsync(int id, GenericPayrollTemplateSetActiveRequest req);
        Task<int> CreateRunAsync(int id, GenericPayrollTemplateCreateRunRequest req);
    }

    public class GenericPayrollTemplateService : IGenericPayrollTemplateService
    {
        private readonly string _cs;
        public GenericPayrollTemplateService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions Camel = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

        private static string? Str(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : r.GetValue(o)?.ToString(); }
        private static decimal Dec(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? 0m : Convert.ToDecimal(r.GetValue(o)); }
        private static int Int(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? 0 : Convert.ToInt32(r.GetValue(o)); }
        private static int? NInt(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : Convert.ToInt32(r.GetValue(o)); }
        private static DateTime? NDate(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : Convert.ToDateTime(r.GetValue(o)); }
        private static bool Bool(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return !r.IsDBNull(o) && r.GetBoolean(o); }

        private static GenericPayrollTemplateModel ReadTemplate(NpgsqlDataReader r) => new()
        {
            GenericPayrollTemplateId = Int(r, "genericpayrolltemplateid"),
            Name                 = Str(r, "name") ?? "",
            Frequency            = Str(r, "frequency") ?? "Monthly",
            GenericCashAccountId = NInt(r, "genericcashaccountid"),
            CashAccountName      = Str(r, "cashaccountname"),
            Notes                = Str(r, "notes"),
            IsActive             = Bool(r, "isactive"),
            LineCount            = Int(r, "linecount"),
            StaffInactiveCount   = Int(r, "staffinactivecount"),
            TotalGross           = Dec(r, "totalgross"),
            TotalDeductions      = Dec(r, "totaldeductions"),
            TotalNet             = Dec(r, "totalnet"),
            RunCount             = Int(r, "runcount"),
            LastPeriodStart      = NDate(r, "lastperiodstart"),
            LastPeriodEnd        = NDate(r, "lastperiodend"),
            CreatedBy            = Str(r, "createdby"),
            CreatedAt            = NDate(r, "createdat") ?? DateTime.MinValue,
            UpdatedBy            = Str(r, "updatedby"),
            UpdatedAt            = NDate(r, "updatedat"),
        };

        public async Task<List<GenericPayrollTemplateModel>> GetAllAsync(string farmId, bool includeInactive)
        {
            var list = new List<GenericPayrollTemplateModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrolltemplate_getall(p_farmid => @FarmId::text, p_includeinactive => @Inc::boolean)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Inc", includeInactive);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadTemplate(r));
            return list;
        }

        public async Task<GenericPayrollTemplateModel?> GetAsync(int id, string farmId)
        {
            var t = (await GetAllAsync(farmId, includeInactive: true)).FirstOrDefault(x => x.GenericPayrollTemplateId == id);
            if (t is null) return null;

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpayrolltemplate_getlines(p_farmid => @FarmId::text, p_templateid => @Id::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", id);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                t.Lines.Add(new GenericPayrollTemplateLineModel
                {
                    GenericPayrollTemplateLineId = Int(r, "genericpayrolltemplatelineid"),
                    GenericStaffId = Int(r, "genericstaffid"),
                    StaffName      = Str(r, "staffname"),
                    StaffRole      = Str(r, "staffrole"),
                    StaffIsActive  = Bool(r, "staffisactive"),
                    BasicPay       = Dec(r, "basicpay"),
                    DailyWage      = Dec(r, "dailywage"),
                    Commission     = Dec(r, "commission"),
                    Bonus          = Dec(r, "bonus"),
                    Deductions     = Dec(r, "deductions"),
                    NetPay         = Dec(r, "netpay"),
                    PaymentMethod  = Str(r, "paymentmethod"),
                    Notes          = Str(r, "notes"),
                });
            }
            return t;
        }

        public async Task<int> SaveAsync(int? id, GenericPayrollTemplateSaveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT spgenericpayrolltemplate_save(p_farmid => @FarmId::text, p_templateid => @Id::int, p_name => @Name::text, p_frequency => @Freq::text, p_genericcashaccountid => @Acct::int, p_notes => @Notes::text, p_lines => @Lines, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", (object?)id ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", req.Name ?? "");
            cmd.Parameters.AddWithValue("@Freq", req.Frequency ?? "Monthly");
            cmd.Parameters.AddWithValue("@Acct", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@Lines", NpgsqlDbType.Jsonb) { Value = JsonSerializer.Serialize(req.Lines ?? new(), Camel) });
            cmd.Parameters.AddWithValue("@By", (object?)req.SavedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task SetActiveAsync(int id, GenericPayrollTemplateSetActiveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT spgenericpayrolltemplate_setactive(p_farmid => @FarmId::text, p_templateid => @Id::int, p_active => @Active::boolean, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Active", req.IsActive);
            cmd.Parameters.AddWithValue("@By", (object?)req.By ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> CreateRunAsync(int id, GenericPayrollTemplateCreateRunRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT spgenericpayrolltemplate_createrun(p_farmid => @FarmId::text, p_templateid => @Id::int, p_periodstart => @Start::date, p_periodend => @End::date, p_paydate => @Pay::date, p_genericcashaccountid => @Acct::int, p_notes => @Notes::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Start", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@End", req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@Pay", (object?)req.PayDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Acct", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)req.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    public interface IGenericPayrollDeductionService
    {
        Task<List<GenericPayrollDeductionModel>> GetDeductionsAsync(string farmId, int payrollItemId);
        Task<List<GenericPayrollDeductionRunRow>> GetRunDeductionsAsync(string farmId, int runId);
        Task<int> SaveDeductionAsync(GenericPayrollDeductionSaveRequest r);
        Task DeleteDeductionAsync(int deductionId, string farmId, string? deletedBy);
    }

    public class GenericPayrollDeductionService : IGenericPayrollDeductionService
    {
        private readonly string _cs;
        public GenericPayrollDeductionService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : (object)DBNull.Value;

        private static string? Str(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i)); }
        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDecimal(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }
        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        // ==================================================================
        // Structured payroll deductions (306)
        // ==================================================================
        public async Task<List<GenericPayrollDeductionModel>> GetDeductionsAsync(
            string farmId, int payrollItemId)
        {
            var list = new List<GenericPayrollDeductionModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericpayrollitemdeduction_getall(" +
                "p_farmid => @FarmId::text, p_genericpayrollitemid => @ItemId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ItemId", payrollItemId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new GenericPayrollDeductionModel
                {
                    GenericPayrollItemDeductionId = IntN(r, "GenericPayrollItemDeductionId"),
                    GenericPayrollItemId = r.GetInt32(r.GetOrdinal("GenericPayrollItemId")),
                    GenericStaffId = r.GetInt32(r.GetOrdinal("GenericStaffId")),
                    DeductionType = Str(r, "DeductionType") ?? "OtherDeduction",
                    Amount = r.GetDecimal(r.GetOrdinal("Amount")),
                    GenericEmployeeLoanId = IntN(r, "GenericEmployeeLoanId"),
                    LoanNumber = Str(r, "LoanNumber"),
                    LoanType = Str(r, "LoanType"),
                    LoanOutstanding = DecN(r, "LoanOutstanding"),
                    GenericEmployeeLoanRepaymentId = IntN(r, "GenericEmployeeLoanRepaymentId"),
                    Description = Str(r, "Description"),
                    Reference = Str(r, "Reference"),
                    Status = Str(r, "Status") ?? "Draft",
                    IsLegacy = Bool(r, "IsLegacy"),
                    CreatedBy = Str(r, "CreatedBy"),
                    CreatedAt = DateN(r, "CreatedAt"),
                });
            return list;
        }

        public async Task<List<GenericPayrollDeductionRunRow>> GetRunDeductionsAsync(
            string farmId, int runId)
        {
            var list = new List<GenericPayrollDeductionRunRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericpayrollitemdeduction_getforrun(" +
                "p_farmid => @FarmId::text, p_genericpayrollrunid => @RunId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RunId", runId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new GenericPayrollDeductionRunRow
                {
                    GenericPayrollItemId = r.GetInt32(r.GetOrdinal("GenericPayrollItemId")),
                    GenericStaffId = r.GetInt32(r.GetOrdinal("GenericStaffId")),
                    StaffName = Str(r, "StaffName"),
                    Deductions = r.GetDecimal(r.GetOrdinal("Deductions")),
                    LegacyDeductions = r.GetDecimal(r.GetOrdinal("LegacyDeductions")),
                    StructuredTotal = r.GetDecimal(r.GetOrdinal("StructuredTotal")),
                    StructuredCount = Convert.ToInt32(r.GetValue(r.GetOrdinal("StructuredCount"))),
                    LoanRepaymentTotal = r.GetDecimal(r.GetOrdinal("LoanRepaymentTotal")),
                    ActiveLoanCount = Convert.ToInt32(r.GetValue(r.GetOrdinal("ActiveLoanCount"))),
                    ActiveLoanOutstanding = r.GetDecimal(r.GetOrdinal("ActiveLoanOutstanding")),
                    SuggestedDeduction = r.GetDecimal(r.GetOrdinal("SuggestedDeduction")),
                });
            return list;
        }

        public async Task<int> SaveDeductionAsync(GenericPayrollDeductionSaveRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericpayrollitemdeduction_save(" +
                "p_farmid => @FarmId::text, p_genericpayrollitemid => @ItemId::int, " +
                "p_deductiontype => @Type::text, p_amount => @Amount::numeric, " +
                "p_genericemployeeloanid => @LoanId::int, p_description => @Description::text, " +
                "p_reference => @Reference::text, " +
                "p_genericpayrollitemdeductionid => @Id::int, p_savedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@ItemId", q.GenericPayrollItemId);
            cmd.Parameters.AddWithValue("@Type", q.DeductionType);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@LoanId", Db(q.GenericEmployeeLoanId));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Reference", Db(q.Reference));
            cmd.Parameters.AddWithValue("@Id", Db(q.GenericPayrollItemDeductionId));
            cmd.Parameters.AddWithValue("@By", Db(q.SavedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteDeductionAsync(int deductionId, string farmId, string? deletedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericpayrollitemdeduction_delete(" +
                "p_farmid => @FarmId::text, p_genericpayrollitemdeductionid => @Id::int, " +
                "p_deletedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", deductionId);
            cmd.Parameters.AddWithValue("@By", Db(deletedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
