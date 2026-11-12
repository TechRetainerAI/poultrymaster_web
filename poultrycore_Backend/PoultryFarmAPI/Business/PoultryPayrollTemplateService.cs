// 428. Payroll templates. Thin wrapper over the sppoultrypayrolltemplate_* functions;
// all rules (unique name, staff on this farm, no overlapping runs) live in SQL.

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryPayrollTemplateService
    {
        Task<List<PoultryPayrollTemplateModel>> GetAllAsync(string farmId, bool includeInactive);
        Task<PoultryPayrollTemplateModel?> GetAsync(int id, string farmId);
        Task<int> SaveAsync(int? id, PoultryPayrollTemplateSaveRequest req);
        Task SetActiveAsync(int id, PoultryPayrollTemplateSetActiveRequest req);
        Task<int> CreateRunAsync(int id, PoultryPayrollTemplateCreateRunRequest req);
    }

    public class PoultryPayrollTemplateService : IPoultryPayrollTemplateService
    {
        private readonly string _cs;
        public PoultryPayrollTemplateService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions Camel = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

        private static string? Str(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : r.GetValue(o)?.ToString(); }
        private static decimal Dec(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? 0m : Convert.ToDecimal(r.GetValue(o)); }
        private static int Int(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? 0 : Convert.ToInt32(r.GetValue(o)); }
        private static int? NInt(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : Convert.ToInt32(r.GetValue(o)); }
        private static DateTime? NDate(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return r.IsDBNull(o) ? null : Convert.ToDateTime(r.GetValue(o)); }
        private static bool Bool(NpgsqlDataReader r, string c) { var o = r.GetOrdinal(c); return !r.IsDBNull(o) && r.GetBoolean(o); }

        private static PoultryPayrollTemplateModel ReadTemplate(NpgsqlDataReader r) => new()
        {
            PoultryPayrollTemplateId = Int(r, "poultrypayrolltemplateid"),
            Name                 = Str(r, "name") ?? "",
            Frequency            = Str(r, "frequency") ?? "Monthly",
            PoultryCashAccountId = NInt(r, "poultrycashaccountid"),
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

        public async Task<List<PoultryPayrollTemplateModel>> GetAllAsync(string farmId, bool includeInactive)
        {
            var list = new List<PoultryPayrollTemplateModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrolltemplate_getall(p_farmid => @FarmId::text, p_includeinactive => @Inc::boolean)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Inc", includeInactive);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadTemplate(r));
            return list;
        }

        public async Task<PoultryPayrollTemplateModel?> GetAsync(int id, string farmId)
        {
            var t = (await GetAllAsync(farmId, includeInactive: true)).FirstOrDefault(x => x.PoultryPayrollTemplateId == id);
            if (t is null) return null;

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayrolltemplate_getlines(p_farmid => @FarmId::text, p_templateid => @Id::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", id);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                t.Lines.Add(new PoultryPayrollTemplateLineModel
                {
                    PoultryPayrollTemplateLineId = Int(r, "poultrypayrolltemplatelineid"),
                    PoultryStaffId = Int(r, "poultrystaffid"),
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

        public async Task<int> SaveAsync(int? id, PoultryPayrollTemplateSaveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sppoultrypayrolltemplate_save(p_farmid => @FarmId::text, p_templateid => @Id::int, p_name => @Name::text, p_frequency => @Freq::text, p_poultrycashaccountid => @Acct::int, p_notes => @Notes::text, p_lines => @Lines, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", (object?)id ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", req.Name ?? "");
            cmd.Parameters.AddWithValue("@Freq", req.Frequency ?? "Monthly");
            cmd.Parameters.AddWithValue("@Acct", (object?)req.PoultryCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@Lines", NpgsqlDbType.Jsonb) { Value = JsonSerializer.Serialize(req.Lines ?? new(), Camel) });
            cmd.Parameters.AddWithValue("@By", (object?)req.SavedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task SetActiveAsync(int id, PoultryPayrollTemplateSetActiveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sppoultrypayrolltemplate_setactive(p_farmid => @FarmId::text, p_templateid => @Id::int, p_active => @Active::boolean, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Active", req.IsActive);
            cmd.Parameters.AddWithValue("@By", (object?)req.By ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> CreateRunAsync(int id, PoultryPayrollTemplateCreateRunRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sppoultrypayrolltemplate_createrun(p_farmid => @FarmId::text, p_templateid => @Id::int, p_periodstart => @Start::date, p_periodend => @End::date, p_paydate => @Pay::date, p_poultrycashaccountid => @Acct::int, p_notes => @Notes::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Start", req.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@End", req.PeriodEnd.Date);
            cmd.Parameters.AddWithValue("@Pay", (object?)req.PayDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Acct", (object?)req.PoultryCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)req.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }
}
