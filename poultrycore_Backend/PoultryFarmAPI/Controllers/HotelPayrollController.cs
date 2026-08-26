using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // ==================== REQUEST MODELS ====================
    public class CreatePayrollRunRequest { public string FarmId { get; set; } = ""; public string PeriodStart { get; set; } = ""; public string PeriodEnd { get; set; } = ""; public string? PayDate { get; set; } public int? HotelCashAccountId { get; set; } public string? Notes { get; set; } }
    public class UpsertPayrollItemRequest { public string FarmId { get; set; } = ""; public int HotelPayrollRunId { get; set; } public int HotelStaffId { get; set; } public string? StaffName { get; set; } public string? StaffRole { get; set; } public decimal BasicPay { get; set; } public decimal DailyWage { get; set; } public decimal Commission { get; set; } public decimal Bonus { get; set; } public decimal Deductions { get; set; } public string? PaymentMethod { get; set; } public string? Notes { get; set; } }
    public class CancelPayrollRequest { public string FarmId { get; set; } = ""; public string? CancelReason { get; set; } }
    public class MarkPaidRequest { public string FarmId { get; set; } = ""; public string? PayDate { get; set; } }

    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelPayrollController : ControllerBase
    {
        private readonly string _cs;
        public HotelPayrollController(IConfiguration config) => _cs = config.GetConnectionString("PoultryConn") ?? "";

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
            using (var cmd = new NpgsqlCommand("SELECT * FROM hotelpayrollitems WHERE hotelpayrollrunid=@id ORDER BY createdat", conn))
            {
                cmd.Parameters.AddWithValue("@id", id);
                var items = await ReadAll(cmd);
                return Ok(new { run, items });
            }
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

            decimal netPay = req.BasicPay + req.DailyWage + req.Commission + req.Bonus - req.Deductions;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                // Verify run exists, belongs to farm, and is Draft
                using (var vc = new NpgsqlCommand("SELECT status FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn, txn))
                {
                    vc.Parameters.AddWithValue("@id", runId); vc.Parameters.AddWithValue("@f", req.FarmId);
                    var st = await vc.ExecuteScalarAsync();
                    if (st == null) { await txn.RollbackAsync(); return NotFound(new { message = "Payroll run not found." }); }
                    if (st.ToString() != "Draft") { await txn.RollbackAsync(); return BadRequest(new { message = "Can only add items to Draft runs." }); }
                }

                // Delete existing item for same staff in same run
                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollitems WHERE hotelpayrollrunid=@r AND hotelstaffid=@s", conn, txn))
                {
                    dc.Parameters.AddWithValue("@r", runId); dc.Parameters.AddWithValue("@s", req.HotelStaffId);
                    await dc.ExecuteNonQueryAsync();
                }

                // Insert new item
                using var ins = new NpgsqlCommand("INSERT INTO hotelpayrollitems(hotelpayrollrunid,hotelstaffid,staffname,staffrole,basicpay,dailywage,commission,bonus,deductions,netpay,paymentmethod,notes) VALUES(@r,@s,@sn,@sr,@bp,@dw,@co,@bo,@de,@np,@pm,@n) RETURNING *", conn, txn);
                ins.Parameters.AddWithValue("@r", runId); ins.Parameters.AddWithValue("@s", req.HotelStaffId);
                ins.Parameters.AddWithValue("@sn", (object?)req.StaffName ?? DBNull.Value);
                ins.Parameters.AddWithValue("@sr", (object?)req.StaffRole ?? DBNull.Value);
                ins.Parameters.AddWithValue("@bp", req.BasicPay); ins.Parameters.AddWithValue("@dw", req.DailyWage);
                ins.Parameters.AddWithValue("@co", req.Commission); ins.Parameters.AddWithValue("@bo", req.Bonus);
                ins.Parameters.AddWithValue("@de", req.Deductions); ins.Parameters.AddWithValue("@np", netPay);
                ins.Parameters.AddWithValue("@pm", (object?)req.PaymentMethod ?? DBNull.Value);
                ins.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
                using var r = await ins.ExecuteReaderAsync();
                Dictionary<string, object?>? item = null;
                if (await r.ReadAsync()) item = ReadRow(r);
                await r.CloseAsync();

                // Recalculate run totals
                await RecalcRunTotals(conn, txn, runId);
                await txn.CommitAsync();
                return item != null ? Ok(item) : StatusCode(500);
            }
            catch { await txn.RollbackAsync(); throw; }
        }

        [HttpDelete("payroll-runs/items/{itemId}")]
        public async Task<IActionResult> DeletePayrollItem(int itemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                // Get run id and verify farm ownership + Draft status
                int runId = 0;
                using (var c = new NpgsqlCommand("SELECT i.hotelpayrollrunid FROM hotelpayrollitems i JOIN hotelpayrollruns r ON r.hotelpayrollrunid=i.hotelpayrollrunid WHERE i.hotelpayrollitemid=@id AND r.farmid=@f AND r.status='Draft'", conn, txn))
                {
                    c.Parameters.AddWithValue("@id", itemId); c.Parameters.AddWithValue("@f", farmId);
                    var result = await c.ExecuteScalarAsync();
                    if (result == null) { await txn.RollbackAsync(); return NotFound(new { message = "Item not found or run is not in Draft status." }); }
                    runId = Convert.ToInt32(result);
                }

                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollitems WHERE hotelpayrollitemid=@id", conn, txn))
                {
                    dc.Parameters.AddWithValue("@id", itemId); await dc.ExecuteNonQueryAsync();
                }

                await RecalcRunTotals(conn, txn, runId);
                await txn.CommitAsync();
                return Ok(new { message = "Item deleted and totals recalculated." });
            }
            catch { await txn.RollbackAsync(); throw; }
        }

        [HttpPost("payroll-runs/{id}/approve")]
        public async Task<IActionResult> ApprovePayrollRun(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelpayrollruns SET status='Approved', approvedby=@u, approvedat=NOW(), updatedat=NOW() WHERE hotelpayrollrunid=@id AND farmid=@f AND status='Draft' RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Run not found or not in Draft status." });
        }

        [HttpPost("payroll-runs/{id}/mark-paid")]
        public async Task<IActionResult> MarkPaid(int id, [FromBody] MarkPaidRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            string payDate = string.IsNullOrEmpty(req.PayDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.PayDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelpayrollruns SET status='Paid', paidby=@u, paidat=NOW(), paydate=@pd::date, updatedat=NOW() WHERE hotelpayrollrunid=@id AND farmid=@f AND status='Approved' RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
            cmd.Parameters.AddWithValue("@pd", payDate);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Run not found or not in Approved status." });
        }

        [HttpPost("payroll-runs/{id}/cancel")]
        public async Task<IActionResult> CancelPayrollRun(int id, [FromBody] CancelPayrollRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelpayrollruns SET status='Cancelled', cancelledby=@u, cancelreason=@cr, updatedat=NOW() WHERE hotelpayrollrunid=@id AND farmid=@f AND status IN ('Draft','Approved') RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
            cmd.Parameters.AddWithValue("@cr", (object?)req.CancelReason ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Run not found or cannot be cancelled (only Draft/Approved)." });
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

                // Delete items first, then run
                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollitems WHERE hotelpayrollrunid=@id", conn, txn))
                { dc.Parameters.AddWithValue("@id", id); await dc.ExecuteNonQueryAsync(); }
                using (var dc = new NpgsqlCommand("DELETE FROM hotelpayrollruns WHERE hotelpayrollrunid=@id AND farmid=@f", conn, txn))
                { dc.Parameters.AddWithValue("@id", id); dc.Parameters.AddWithValue("@f", farmId); await dc.ExecuteNonQueryAsync(); }

                await txn.CommitAsync();
                return Ok(new { message = "Payroll run deleted." });
            }
            catch { await txn.RollbackAsync(); throw; }
        }

        private static async Task RecalcRunTotals(NpgsqlConnection conn, NpgsqlTransaction txn, int runId)
        {
            using var cmd = new NpgsqlCommand(@"UPDATE hotelpayrollruns SET totalgrosspay = COALESCE((SELECT SUM(basicpay+dailywage+commission+bonus) FROM hotelpayrollitems WHERE hotelpayrollrunid=@id),0), totaldeductions = COALESCE((SELECT SUM(deductions) FROM hotelpayrollitems WHERE hotelpayrollrunid=@id),0), totalnetpay = COALESCE((SELECT SUM(basicpay+dailywage+commission+bonus) FROM hotelpayrollitems WHERE hotelpayrollrunid=@id),0) - COALESCE((SELECT SUM(deductions) FROM hotelpayrollitems WHERE hotelpayrollrunid=@id),0), updatedat=NOW() WHERE hotelpayrollrunid=@id", conn, txn);
            cmd.Parameters.AddWithValue("@id", runId);
            await cmd.ExecuteNonQueryAsync();
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
