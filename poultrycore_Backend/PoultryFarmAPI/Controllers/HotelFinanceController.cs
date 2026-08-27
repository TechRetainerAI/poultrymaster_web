using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // ==================== REQUEST MODELS ====================
    public class AddChargeRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public string ChargeType { get; set; } = "Room"; public string Description { get; set; } = ""; public int Quantity { get; set; } = 1; public decimal UnitPrice { get; set; } public decimal? TotalAmount { get; set; } }
    public class GenerateInvoiceRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } }
    public class RecordPaymentRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public int? HotelInvoiceId { get; set; } public decimal Amount { get; set; } public string PaymentMethod { get; set; } = "Cash"; public string? Reference { get; set; } public string? Notes { get; set; } }
    public class CreateExpenseRequest { public string FarmId { get; set; } = ""; public string Category { get; set; } = ""; public string Description { get; set; } = ""; public decimal Amount { get; set; } public string? ExpenseDate { get; set; } public string? Vendor { get; set; } public string? Notes { get; set; } public string PaymentMethod { get; set; } = "Cash"; public int? HotelCashAccountId { get; set; } public string? PaidTo { get; set; } public int? HotelExpenseCategoryId { get; set; } }
    public class CreateCashAccountRequest { public string FarmId { get; set; } = ""; public string AccountName { get; set; } = ""; public string AccountType { get; set; } = "Cash"; public decimal OpeningBalance { get; set; } public string? Purpose { get; set; } }
    public class CreateExpenseCategoryRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; }
    public class UpdatePurposeRequest { public string FarmId { get; set; } = ""; public string? Purpose { get; set; } }
    public class ExpenseActionRequest { public string FarmId { get; set; } = ""; public string? Reason { get; set; } }

    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelFinanceController : ControllerBase
    {
        private readonly string _cs;
        private readonly IHotelEmailService _hotelEmail;
        private readonly IHotelCashLedgerService _cashLedger;
        public HotelFinanceController(IConfiguration config, IHotelEmailService hotelEmail, IHotelCashLedgerService cashLedger) { _cs = config.GetConnectionString("PoultryConn") ?? ""; _hotelEmail = hotelEmail; _cashLedger = cashLedger; }

        private static (int offset, int limit, bool paginate) ParsePagination(int? page, int? pageSize)
        {
            if (page == null || page <= 0) return (0, 0, false);
            int ps = Math.Clamp(pageSize ?? 20, 1, 100);
            return ((page.Value - 1) * ps, ps, true);
        }

        private async Task<IActionResult> PaginatedList(string table, string where, string orderBy, NpgsqlParameter[] parms, int? page, int? pageSize)
        {
            var (offset, limit, paginate) = ParsePagination(page, pageSize);
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            if (!paginate)
            {
                using var cmd = new NpgsqlCommand($"SELECT * FROM {table} WHERE {where} ORDER BY {orderBy}", conn);
                foreach (var p in parms) cmd.Parameters.Add(new NpgsqlParameter(p.ParameterName, p.Value));
                return Ok(await ReadAll(cmd));
            }
            int total;
            using (var cnt = new NpgsqlCommand($"SELECT COUNT(*) FROM {table} WHERE {where}", conn))
            {
                foreach (var p in parms) cnt.Parameters.Add(new NpgsqlParameter(p.ParameterName, p.Value));
                total = Convert.ToInt32(await cnt.ExecuteScalarAsync());
            }
            using var dataCmd = new NpgsqlCommand($"SELECT * FROM {table} WHERE {where} ORDER BY {orderBy} LIMIT @_limit OFFSET @_offset", conn);
            foreach (var p in parms) dataCmd.Parameters.Add(new NpgsqlParameter(p.ParameterName, p.Value));
            dataCmd.Parameters.AddWithValue("@_limit", limit); dataCmd.Parameters.AddWithValue("@_offset", offset);
            var data = await ReadAll(dataCmd);
            return Ok(new { data, total, page = page!.Value, pageSize = limit });
        }

        [HttpGet("billing/charges")]
        public async Task<IActionResult> ListCharges([FromQuery] string farmId, [FromQuery] int bookingId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelstaycharges WHERE farmid=@f AND hotelbookingid=@b ORDER BY chargedate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@b", bookingId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("billing/charges")]
        public async Task<IActionResult> AddCharge([FromBody] AddChargeRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveAmount(req.UnitPrice, "Unit price"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidatePositiveInt(req.Quantity, "Quantity"); if (v2 != null) return v2;
            var v3 = HotelValidation.ValidateRequiredString(req.Description, "Description"); if (v3 != null) return v3;

            decimal total = req.TotalAmount ?? req.Quantity * req.UnitPrice;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelstaycharges(farmid,hotelbookingid,chargetype,description,quantity,unitprice,totalamount,postedby) VALUES(@f,@b,@t,@d,@q,@u,@tot,@pb) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@b", req.HotelBookingId);
            cmd.Parameters.AddWithValue("@t", req.ChargeType); cmd.Parameters.AddWithValue("@d", req.Description);
            cmd.Parameters.AddWithValue("@q", req.Quantity); cmd.Parameters.AddWithValue("@u", req.UnitPrice);
            cmd.Parameters.AddWithValue("@tot", total);
            cmd.Parameters.AddWithValue("@pb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpGet("billing/invoices")]
        public async Task<IActionResult> ListInvoices([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelinvoices WHERE farmid=@f ORDER BY createdat DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("billing/invoices/generate")]
        public async Task<IActionResult> GenerateInvoice([FromBody] GenerateInvoiceRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveInt(req.HotelBookingId, "Booking ID"); if (v1 != null) return v1;

            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                decimal subtotal = 0; int guestId = 0;
                using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(totalamount),0) FROM hotelstaycharges WHERE farmid=@f AND hotelbookingid=@b", conn, txn)) { c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@b", req.HotelBookingId); subtotal = Convert.ToDecimal(await c.ExecuteScalarAsync()); }
                using (var c = new NpgsqlCommand("SELECT hotelguestid FROM hotelbookings WHERE hotelbookingid=@b AND farmid=@f", conn, txn))
                {
                    c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@b", req.HotelBookingId);
                    var result = await c.ExecuteScalarAsync();
                    if (result == null || result == DBNull.Value) { await txn.RollbackAsync(); return NotFound(new { message = "Booking not found." }); }
                    guestId = Convert.ToInt32(result);
                }
                if (subtotal == 0) { using var c2 = new NpgsqlCommand("SELECT totalamount FROM hotelbookings WHERE hotelbookingid=@b AND farmid=@f", conn, txn); c2.Parameters.AddWithValue("@f", req.FarmId); c2.Parameters.AddWithValue("@b", req.HotelBookingId); subtotal = Convert.ToDecimal(await c2.ExecuteScalarAsync() ?? 0); }
                string invNum = $"INV-{DateTime.UtcNow:yyyyMMdd}-{req.HotelBookingId:D3}";
                using var ins = new NpgsqlCommand("INSERT INTO hotelinvoices(farmid,hotelbookingid,hotelguestid,invoicenumber,subtotal,totalamount,balance,status) VALUES(@f,@b,@g,@n,@s,@s,@s,'Issued') RETURNING *", conn, txn);
                ins.Parameters.AddWithValue("@f", req.FarmId); ins.Parameters.AddWithValue("@b", req.HotelBookingId); ins.Parameters.AddWithValue("@g", guestId);
                ins.Parameters.AddWithValue("@n", invNum); ins.Parameters.AddWithValue("@s", subtotal);
                using var r = await ins.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    var row = ReadRow(r);
                    await r.CloseAsync();
                    await txn.CommitAsync();
                    return Ok(row);
                }
                await txn.RollbackAsync();
                return StatusCode(500, new { message = "Failed to generate invoice." });
            }
            catch
            {
                await txn.RollbackAsync();
                throw;
            }
        }

        [HttpGet("billing/payments")]
        public async Task<IActionResult> ListPayments([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return await PaginatedList("hotelpayments", "farmid=@f", "paymentdate DESC",
                new[] { new NpgsqlParameter("@f", farmId) }, page, pageSize);
        }

        [HttpPost("billing/payments")]
        public async Task<IActionResult> RecordPayment([FromBody] RecordPaymentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveAmount(req.Amount, "Payment amount"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidateRequiredString(req.PaymentMethod, "Payment method"); if (v2 != null) return v2;

            string payRef = $"PAY-{DateTime.UtcNow:yyyyMMddHHmmss}-{req.HotelBookingId}";
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelpayments(farmid,hotelbookingid,amount,paymentmethod,reference,notes,receivedby) VALUES(@f,@b,@a,@m,@r,@n,@rb) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@b", req.HotelBookingId);
            cmd.Parameters.AddWithValue("@a", req.Amount); cmd.Parameters.AddWithValue("@m", req.PaymentMethod);
            cmd.Parameters.AddWithValue("@r", string.IsNullOrEmpty(req.Reference) ? payRef : req.Reference);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@rb", HotelAuthHelper.GetUserName(User));
            string refUsed = string.IsNullOrEmpty(req.Reference) ? payRef : req.Reference;
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return StatusCode(500);
            var row = ReadRow(r);
            int paymentId = Convert.ToInt32(row.GetValueOrDefault("hotelpaymentid", 0));
            _ = Task.Run(async () => { try { await _hotelEmail.SendPaymentReceiptAsync(req.FarmId, req.HotelBookingId, req.Amount, req.PaymentMethod, refUsed); } catch { } });
            _ = Task.Run(async () => { try { await _cashLedger.PostAsync(req.FarmId, "FrontDesk", "Credit", req.Amount, $"Guest payment ({req.PaymentMethod}) - {refUsed}", refUsed, "Payment", paymentId, HotelAuthHelper.GetUserName(User)); } catch { } });
            return Ok(row);
        }

        [HttpGet("billing/balance/{bookingId}")]
        public async Task<IActionResult> GetBookingBalance(int bookingId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            decimal totalBill = 0, totalPaid = 0;
            using (var c = new NpgsqlCommand("SELECT COALESCE(totalamount,0) FROM hotelbookings WHERE hotelbookingid=@b AND farmid=@f", conn)) { c.Parameters.AddWithValue("@b", bookingId); c.Parameters.AddWithValue("@f", farmId); totalBill = Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }
            using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(amount),0) FROM hotelpayments WHERE hotelbookingid=@b AND farmid=@f", conn)) { c.Parameters.AddWithValue("@b", bookingId); c.Parameters.AddWithValue("@f", farmId); totalPaid = Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }
            decimal charges = 0;
            using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(totalamount),0) FROM hotelstaycharges WHERE hotelbookingid=@b AND farmid=@f", conn)) { c.Parameters.AddWithValue("@b", bookingId); c.Parameters.AddWithValue("@f", farmId); charges = Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }
            decimal grandTotal = totalBill + charges;
            return Ok(new { totalBill, additionalCharges = charges, grandTotal, totalPaid, balance = grandTotal - totalPaid, isPaid = totalPaid >= grandTotal });
        }

        [HttpGet("finance/expenses")]
        public async Task<IActionResult> ListExpenses([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return await PaginatedList("hotelexpenses", "farmid=@f", "expensedate DESC",
                new[] { new NpgsqlParameter("@f", farmId) }, page, pageSize);
        }

        [HttpPost("finance/expenses")]
        public async Task<IActionResult> CreateExpense([FromBody] CreateExpenseRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveAmount(req.Amount, "Expense amount"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidateRequiredString(req.Category, "Category"); if (v2 != null) return v2;
            var v3 = HotelValidation.ValidateRequiredString(req.Description, "Description"); if (v3 != null) return v3;

            string date = string.IsNullOrEmpty(req.ExpenseDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.ExpenseDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "INSERT INTO hotelexpenses(farmid,category,description,amount,expensedate,vendor,notes,paymentmethod,hotelcashaccountid,paidto,hotelexpensecategoryid,status) " +
                "VALUES(@f,@c,@d,@a,@e::date,@v,@n,@pm,@ca,@pt,@eci,'Draft') RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@c", req.Category);
            cmd.Parameters.AddWithValue("@d", req.Description); cmd.Parameters.AddWithValue("@a", req.Amount);
            cmd.Parameters.AddWithValue("@e", date);
            cmd.Parameters.AddWithValue("@v", (object?)req.Vendor ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pm", req.PaymentMethod ?? "Cash");
            cmd.Parameters.AddWithValue("@ca", (object?)req.HotelCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pt", (object?)req.PaidTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@eci", (object?)req.HotelExpenseCategoryId ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return StatusCode(500);
            var row = ReadRow(r);
            return Ok(row);
        }

        // ======================= EXPENSE CATEGORIES =======================
        [HttpGet("finance/expense-categories")]
        public async Task<IActionResult> ListExpenseCategories([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelexpensecategories WHERE farmid=@f ORDER BY name", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("finance/expense-categories")]
        public async Task<IActionResult> CreateExpenseCategory([FromBody] CreateExpenseCategoryRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v = HotelValidation.ValidateRequiredString(req.Name, "Name"); if (v != null) return v;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelexpensecategories(farmid,name) VALUES(@f,@n) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.Name);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        // ======================= EXPENSE STATUS WORKFLOW =======================
        [HttpPost("finance/expenses/{id}/submit")]
        public async Task<IActionResult> SubmitExpense(int id, [FromBody] ExpenseActionRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelexpenses SET status='Submitted', submittedby=@u, submittedat=NOW(), updatedat=NOW() WHERE hotelexpenseid=@id AND farmid=@f AND status='Draft' RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Expense not found or not in Draft status." });
        }

        [HttpPost("finance/expenses/{id}/approve")]
        public async Task<IActionResult> ApproveExpense(int id, [FromBody] ExpenseActionRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelexpenses SET status='Approved', approvedby=@u, approvedat=NOW(), updatedat=NOW() WHERE hotelexpenseid=@id AND farmid=@f AND status IN ('Draft','Submitted') RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@u", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return NotFound(new { message = "Expense not found or already approved/cancelled." });
            var row = ReadRow(r);
            decimal amount = Convert.ToDecimal(row.GetValueOrDefault("amount", 0m));
            string desc = $"{row.GetValueOrDefault("category", "")}: {row.GetValueOrDefault("description", "")}";
            int expenseId = Convert.ToInt32(row.GetValueOrDefault("hotelexpenseid", 0));
            _ = Task.Run(async () => { try { await _cashLedger.PostAsync(req.FarmId, "Expenses", "Debit", amount, desc, null, "Expense", expenseId, HotelAuthHelper.GetUserName(User)); } catch { } });
            return Ok(row);
        }

        [HttpPost("finance/expenses/{id}/cancel")]
        public async Task<IActionResult> CancelExpense(int id, [FromBody] ExpenseActionRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelexpenses SET status='Cancelled', cancelreason=@r, updatedat=NOW() WHERE hotelexpenseid=@id AND farmid=@f AND status NOT IN ('Cancelled') RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@r", (object?)req.Reason ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Expense not found or already cancelled." });
        }

        [HttpGet("finance/cash-accounts")]
        public async Task<IActionResult> ListCashAccounts([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelcashaccounts WHERE farmid=@f ORDER BY accountname", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("finance/cash-accounts")]
        public async Task<IActionResult> CreateCashAccount([FromBody] CreateCashAccountRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidateRequiredString(req.AccountName, "Account name"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidateAmount(req.OpeningBalance, "Opening balance"); if (v2 != null) return v2;

            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelcashaccounts(farmid,accountname,accounttype,openingbalance,currentbalance,purpose) VALUES(@f,@n,@t,@b,@b,@p) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.AccountName);
            cmd.Parameters.AddWithValue("@t", req.AccountType); cmd.Parameters.AddWithValue("@b", req.OpeningBalance);
            cmd.Parameters.AddWithValue("@p", (object?)req.Purpose ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpDelete("finance/cash-accounts/{id}")]
        public async Task<IActionResult> DeleteCashAccount(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // Check for existing transactions
            int txnCount;
            using (var cnt = new NpgsqlCommand("SELECT COUNT(*) FROM hotelcashtransactions WHERE hotelcashaccountid=@id AND farmid=@f", conn))
            { cnt.Parameters.AddWithValue("@id", id); cnt.Parameters.AddWithValue("@f", farmId); txnCount = Convert.ToInt32(await cnt.ExecuteScalarAsync()); }
            if (txnCount > 0) return BadRequest(new { message = $"Cannot delete — this account has {txnCount} transaction(s). Deactivate it instead." });
            using var cmd = new NpgsqlCommand("DELETE FROM hotelcashaccounts WHERE hotelcashaccountid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            var rows = await cmd.ExecuteNonQueryAsync();
            return rows > 0 ? Ok(new { message = "Account deleted" }) : NotFound(new { message = "Account not found" });
        }

        [HttpPatch("finance/cash-accounts/{id}/purpose")]
        public async Task<IActionResult> UpdateCashAccountPurpose(int id, [FromBody] UpdatePurposeRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // If setting a purpose, clear it from any other account that had it (one account per purpose)
            if (!string.IsNullOrEmpty(req.Purpose))
            {
                using var clear = new NpgsqlCommand("UPDATE hotelcashaccounts SET purpose=NULL, updatedat=NOW() WHERE farmid=@f AND purpose=@p AND hotelcashaccountid!=@id", conn);
                clear.Parameters.AddWithValue("@f", req.FarmId); clear.Parameters.AddWithValue("@p", req.Purpose); clear.Parameters.AddWithValue("@id", id);
                await clear.ExecuteNonQueryAsync();
            }
            using var cmd = new NpgsqlCommand("UPDATE hotelcashaccounts SET purpose=@p, updatedat=NOW() WHERE hotelcashaccountid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@p", string.IsNullOrEmpty(req.Purpose) ? DBNull.Value : req.Purpose);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Account not found" });
        }

        [HttpGet("finance/cash-transactions")]
        public async Task<IActionResult> ListCashTransactions([FromQuery] string farmId, [FromQuery] int? accountId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            string where = accountId.HasValue && accountId > 0
                ? "t.farmid=@f AND t.hotelcashaccountid=@acct"
                : "t.farmid=@f";
            string sql = $"SELECT t.*, a.accountname FROM hotelcashtransactions t JOIN hotelcashaccounts a ON t.hotelcashaccountid=a.hotelcashaccountid WHERE {where} ORDER BY t.txndate DESC";

            var (offset, limit, paginate) = ParsePagination(page, pageSize);
            if (!paginate)
            {
                using var cmd = new NpgsqlCommand(sql + " LIMIT 500", conn);
                cmd.Parameters.AddWithValue("@f", farmId);
                if (accountId.HasValue && accountId > 0) cmd.Parameters.AddWithValue("@acct", accountId.Value);
                return Ok(await ReadAll(cmd));
            }
            int total;
            string countWhere = accountId.HasValue && accountId > 0
                ? "farmid=@f AND hotelcashaccountid=@acct"
                : "farmid=@f";
            using (var cnt = new NpgsqlCommand($"SELECT COUNT(*) FROM hotelcashtransactions WHERE {countWhere}", conn))
            {
                cnt.Parameters.AddWithValue("@f", farmId);
                if (accountId.HasValue && accountId > 0) cnt.Parameters.AddWithValue("@acct", accountId.Value);
                total = Convert.ToInt32(await cnt.ExecuteScalarAsync());
            }
            using var dataCmd = new NpgsqlCommand(sql + " LIMIT @_limit OFFSET @_offset", conn);
            dataCmd.Parameters.AddWithValue("@f", farmId);
            if (accountId.HasValue && accountId > 0) dataCmd.Parameters.AddWithValue("@acct", accountId.Value);
            dataCmd.Parameters.AddWithValue("@_limit", limit); dataCmd.Parameters.AddWithValue("@_offset", offset);
            var data = await ReadAll(dataCmd);
            return Ok(new { data, total, page = page!.Value, pageSize = limit });
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
