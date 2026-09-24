using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using NpgsqlTypes;
using System.Text.Json;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ==================== REQUEST MODELS ====================
    public class CreatePayrollRunRequest { public string FarmId { get; set; } = ""; public string PeriodStart { get; set; } = ""; public string PeriodEnd { get; set; } = ""; public string? PayDate { get; set; } public int? HotelCashAccountId { get; set; } public string? Notes { get; set; } }
    /// <summary>
    /// One payroll line. Deductions is the "other" deductions the user types (tax,
    /// penalties, ...). Staff loan repayments go in LoanDeductions: null leaves the
    /// line's loan deductions as they are, a list replaces them (an empty list or
    /// an amount of 0 removes them).
    /// </summary>
    public class UpsertPayrollItemRequest { public string FarmId { get; set; } = ""; public int HotelPayrollRunId { get; set; } public int HotelStaffId { get; set; } public string? StaffName { get; set; } public string? StaffRole { get; set; } public decimal BasicPay { get; set; } public decimal DailyWage { get; set; } public decimal Commission { get; set; } public decimal Bonus { get; set; } public decimal Deductions { get; set; } public string? PaymentMethod { get; set; } public string? Notes { get; set; } public List<HotelPayrollLoanDeductionInput>? LoanDeductions { get; set; } }
    public class CancelPayrollRequest { public string FarmId { get; set; } = ""; public string? CancelReason { get; set; } }
    public class MarkPaidRequest { public string FarmId { get; set; } = ""; public string? PayDate { get; set; } }
    public class ReopenPayrollRequest { public string FarmId { get; set; } = ""; public string? Reason { get; set; } }

    // The money steps (save a line with its loan deductions, approve, reopen,
    // cancel, mark paid) run inside database functions from migration 325, so a
    // loan repayment and the payroll it came from can never disagree. Their
    // refusals come back as 400 with the database's sentence (HotelBusinessRuleFilter).
    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelPayrollController : ControllerBase
    {
        private readonly string _cs;
        private readonly IHotelEmployeeLoanService _loans;
        public HotelPayrollController(IConfiguration config, IHotelEmployeeLoanService loans) { _cs = config.GetConnectionString("PoultryConn") ?? ""; _loans = loans; }

        [HttpGet("payroll-runs")]
        public async Task<IActionResult> ListPayrollRuns([FromQuery] string farmId, [FromQuery] string? status = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            var sql = "SELECT * FROM hotelpayrollruns WHERE farmid=@f";
            if (!string.IsNullOrEmpty(status)) sql += " AND status=@s";
            sql += " ORDER BY createdat DESC";
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            if (!string.IsNullOrEmpty(status)) cmd.Parameters.AddWithValue("@s", status);
            return Ok(await ReadAll(cmd));
        }

        [HttpGet("payroll-runs/{id}")]
        public async Task<IActionResult> GetPayrollRun(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            Dictionary<string, object?>? run = null;
            using (var cmd = new NpgsqlCommand("SELECT * FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn))
            {
                cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync()) run = ReadRow(r); else return NotFound(new { message = "Payroll run not found." });
            }
            List<Dictionary<string, object?>> items;
            using (var cmd = new NpgsqlCommand("SELECT * FROM hotelpayrollitems WHERE hotelpayrollrunid=@id ORDER BY createdat", conn))
            {
                cmd.Parameters.AddWithValue("@id", id);
                items = await ReadAll(cmd);
            }
            // Staff loan deductions on this run, one row per loan per line.
            var deductions = await _loans.GetPayrollDeductionsAsync(farmId, id);
            return Ok(new { run, items, deductions });
        }

        [HttpPost("payroll-runs")]
        public async Task<IActionResult> CreatePayrollRun([FromBody] CreatePayrollRunRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidateRequiredString(req.PeriodStart, "Period start"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidateRequiredString(req.PeriodEnd, "Period end"); if (v2 != null) return v2;

            string payDate = string.IsNullOrEmpty(req.PayDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.PayDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            var sql = "INSERT INTO hotelpayrollruns(farmid,periodstart,periodend,paydate,totalgrosspay,totaldeductions,totalnetpay,status,hotelcashaccountid,cashaccountname,notes,createdby) VALUES(@f,@ps::date,@pe::date,@pd::date,0,0,0,'Draft',@ca,@cn,@n,@cb) RETURNING *";
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@ps", req.PeriodStart); cmd.Parameters.AddWithValue("@pe", req.PeriodEnd);
            cmd.Parameters.AddWithValue("@pd", payDate);
            cmd.Parameters.AddWithValue("@ca", req.HotelCashAccountId.HasValue ? req.HotelCashAccountId.Value : DBNull.Value);
            // Resolve cash account name if provided
            string? accountName = null;
            if (req.HotelCashAccountId.HasValue)
            {
                using var acmd = new NpgsqlCommand("SELECT accountname FROM hotelcashaccounts WHERE hotelcashaccountid=@id AND farmid=@f", conn);
                acmd.Parameters.AddWithValue("@id", req.HotelCashAccountId.Value); acmd.Parameters.AddWithValue("@f", req.FarmId);
                var result = await acmd.ExecuteScalarAsync();
                accountName = result?.ToString();
            }
            cmd.Parameters.AddWithValue("@cn", (object?)accountName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPost("payroll-runs/{runId}/items")]
        public async Task<IActionResult> UpsertPayrollItem(int runId, [FromBody] UpsertPayrollItemRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            if (req.HotelPayrollRunId != runId) return BadRequest(new { message = "Run ID mismatch." });

            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // Updates the line in place (so its loan deductions survive), checks every
            // loan deduction against what the staff member still owes, and recalculates
            // the line and the run -- one transaction, inside the function.
            int itemId;
            using (var cmd = new NpgsqlCommand(
                "SELECT sphotelpayrollitem_save(@f, @r, @s, @sn, @sr, @bp, @dw, @co, @bo, @od, @pm, @n, @ld, @by)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId);
                cmd.Parameters.AddWithValue("@r", runId);
                cmd.Parameters.AddWithValue("@s", req.HotelStaffId);
                cmd.Parameters.AddWithValue("@sn", (object?)req.StaffName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@sr", (object?)req.StaffRole ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@bp", req.BasicPay); cmd.Parameters.AddWithValue("@dw", req.DailyWage);
                cmd.Parameters.AddWithValue("@co", req.Commission); cmd.Parameters.AddWithValue("@bo", req.Bonus);
                cmd.Parameters.AddWithValue("@od", req.Deductions);
                cmd.Parameters.AddWithValue("@pm", (object?)req.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
                cmd.Parameters.Add(new NpgsqlParameter("@ld", NpgsqlDbType.Jsonb)
                {
                    Value = req.LoanDeductions == null
                        ? DBNull.Value
                        : JsonSerializer.Serialize(req.LoanDeductions.Select(d => new { loanId = d.LoanId, amount = d.Amount })),
                });
                cmd.Parameters.AddWithValue("@by", HotelAuthHelper.GetUserName(User));
                itemId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }

            using var sel = new NpgsqlCommand("SELECT * FROM hotelpayrollitems WHERE hotelpayrollitemid=@id", conn);
            sel.Parameters.AddWithValue("@id", itemId);
            using var rd = await sel.ExecuteReaderAsync();
            return await rd.ReadAsync() ? Ok(ReadRow(rd)) : StatusCode(500);
        }

        [HttpDelete("payroll-runs/items/{itemId}")]
        public async Task<IActionResult> DeletePayrollItem(int itemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelpayrollitem_delete(@f, @id)", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@id", itemId);
            await cmd.ExecuteNonQueryAsync();
            return Ok(new { message = "Item deleted and totals recalculated." });
        }

        /// <summary>Draft -> Approved. Each staff loan deduction becomes a repayment.</summary>
        [HttpPost("payroll-runs/{id}/approve")]
        public async Task<IActionResult> ApprovePayrollRun(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int posted;
            using (var cmd = new NpgsqlCommand("SELECT sphotelpayrollrun_approve(@f, @id, @u)", conn))
            {
                cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
                posted = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
            var run = await ReadRun(conn, id, farmId);
            return Ok(new { run, loanRepaymentsPosted = posted });
        }

        /// <summary>Approved -> Draft, to correct a run before it is paid. Its loan repayments are reversed.</summary>
        [HttpPost("payroll-runs/{id}/reopen")]
        public async Task<IActionResult> ReopenPayrollRun(int id, [FromBody] ReopenPayrollRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using (var cmd = new NpgsqlCommand("SELECT sphotelpayrollrun_unapprove(@f, @id, @reason, @u)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.AddWithValue("@reason", (object?)req.Reason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
                await cmd.ExecuteNonQueryAsync();
            }
            return Ok(await ReadRun(conn, id, req.FarmId));
        }

        /// <summary>
        /// Approved -> Paid. Net pay leaves the run's cash account (or the hotel's
        /// Payroll account), in the same transaction as the status change. Before
        /// 325 this posted nothing: it read a "totalamount" column the run does not
        /// have, in a fire-and-forget task that swallowed the error.
        /// </summary>
        [HttpPost("payroll-runs/{id}/mark-paid")]
        public async Task<IActionResult> MarkPaid(int id, [FromBody] MarkPaidRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using (var cmd = new NpgsqlCommand("SELECT sphotelpayrollrun_markpaid(@f, @id, @pd, @u)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.Add(new NpgsqlParameter("@pd", NpgsqlDbType.Date)
                {
                    Value = string.IsNullOrEmpty(req.PayDate) ? DBNull.Value : DateTime.Parse(req.PayDate).Date,
                });
                cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
                await cmd.ExecuteNonQueryAsync();
            }
            return Ok(await ReadRun(conn, id, req.FarmId));
        }

        /// <summary>Draft or Approved -> Cancelled. Any loan repayments are reversed.</summary>
        [HttpPost("payroll-runs/{id}/cancel")]
        public async Task<IActionResult> CancelPayrollRun(int id, [FromBody] CancelPayrollRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using (var cmd = new NpgsqlCommand("SELECT sphotelpayrollrun_cancel(@f, @id, @cr, @u)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.AddWithValue("@cr", (object?)req.CancelReason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
                await cmd.ExecuteNonQueryAsync();
            }
            return Ok(await ReadRun(conn, id, req.FarmId));
        }

        [HttpDelete("payroll-runs/{id}")]
        public async Task<IActionResult> DeletePayrollRun(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                // Verify status is Draft or Cancelled
                using (var vc = new NpgsqlCommand("SELECT status FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn, txn))
                {
                    vc.Parameters.AddWithValue("@id", id); vc.Parameters.AddWithValue("@f", farmId);
                    var st = await vc.ExecuteScalarAsync();
                    if (st == null) { await txn.RollbackAsync(); return NotFound(new { message = "Payroll run not found." }); }
                    if (st.ToString() != "Draft" && st.ToString() != "Cancelled") { await txn.RollbackAsync(); return BadRequest(new { message = "Can only delete Draft or Cancelled runs." }); }
                }

                // Delete items first, then run. Draft loan deductions go with their
                // items (ON DELETE CASCADE); a cancelled run's deductions are already
                // Reversed, and its reversed repayments stay on the loan's history.
                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollitems WHERE hotelpayrollrunid=@id", conn, txn))
                { dc.Parameters.AddWithValue("@id", id); await dc.ExecuteNonQueryAsync(); }
                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn, txn))
                { dc.Parameters.AddWithValue("@id", id); dc.Parameters.AddWithValue("@f", farmId); await dc.ExecuteNonQueryAsync(); }

                await txn.CommitAsync();
                return Ok(new { message = "Payroll run deleted." });
            }
            catch { await txn.RollbackAsync(); throw; }
        }

        private static async Task<Dictionary<string, object?>?> ReadRun(NpgsqlConnection conn, int id, string farmId)
        {
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadRow(r) : null;
        }

        [HttpGet("payroll-diag")]
        public async Task<IActionResult> PayrollDiag([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            var info = new Dictionary<string, object?>();
            using (var c1 = new NpgsqlCommand("SELECT current_database(), current_schema(), current_user", conn))
            using (var r1 = await c1.ExecuteReaderAsync()) { if (await r1.ReadAsync()) { info["database"] = r1.GetString(0); info["schema"] = r1.GetString(1); info["user"] = r1.GetString(2); } }
            using (var c2 = new NpgsqlCommand("SHOW search_path", conn))
            { info["search_path"] = (await c2.ExecuteScalarAsync())?.ToString(); }
            using (var c3 = new NpgsqlCommand("SELECT schemaname, tablename FROM pg_tables WHERE tablename='hotelpayrollruns'", conn))
            using (var r3 = await c3.ExecuteReaderAsync()) { var tables = new List<string>(); while (await r3.ReadAsync()) tables.Add($"{r3.GetString(0)}.{r3.GetString(1)}"); info["payroll_tables"] = tables; }
            using (var c4 = new NpgsqlCommand("SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hotel%'", conn))
            { info["hotel_table_count"] = (await c4.ExecuteScalarAsync()); }
            // Try the actual query
            try {
                using var c5 = new NpgsqlCommand("SELECT count(*) FROM hotelpayrollruns", conn);
                info["payrollruns_count"] = await c5.ExecuteScalarAsync();
                info["payrollruns_accessible"] = true;
            } catch (Exception ex) { info["payrollruns_accessible"] = false; info["payrollruns_error"] = ex.Message; }
            return Ok(info);
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
