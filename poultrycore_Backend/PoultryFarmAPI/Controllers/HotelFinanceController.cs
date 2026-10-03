using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // ==================== REQUEST MODELS ====================
    public class AddChargeRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public string ChargeType { get; set; } = "Room"; public string Description { get; set; } = ""; public int Quantity { get; set; } = 1; public decimal UnitPrice { get; set; } public decimal? TotalAmount { get; set; } }
    public class GenerateInvoiceRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } }
    public class HotelRecordPaymentRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public int? HotelInvoiceId { get; set; } public decimal Amount { get; set; } public string PaymentMethod { get; set; } = "Cash"; public string? Reference { get; set; } public string? Notes { get; set; } public int? HotelCashAccountId { get; set; } }
    public class CreateExpenseRequest { public string FarmId { get; set; } = ""; public string Category { get; set; } = ""; public string Description { get; set; } = ""; public decimal Amount { get; set; } public string? ExpenseDate { get; set; } public string? Vendor { get; set; } public string? Notes { get; set; } public string PaymentMethod { get; set; } = "Cash"; public int? HotelCashAccountId { get; set; } public string? PaidTo { get; set; } public int? HotelExpenseCategoryId { get; set; } public int? HotelSupplierId { get; set; } public string? DueDate { get; set; } }
    public class CreateCashAccountRequest { public string FarmId { get; set; } = ""; public string AccountName { get; set; } = ""; public string AccountType { get; set; } = "Cash"; public decimal OpeningBalance { get; set; } public string? Purpose { get; set; } public bool AllowNegativeBalance { get; set; } public string? Notes { get; set; } }
    public class CreateExpenseCategoryRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; }
    public class UpdatePurposeRequest { public string FarmId { get; set; } = ""; public string? Purpose { get; set; } }
    public class ExpenseActionRequest { public string FarmId { get; set; } = ""; public string? Reason { get; set; } }

    // Money moves only through the Postgres posting functions of migration 327
    // (sphotelpayment_record, sphotelexpense_approve/_cancel, sphotelinvoice_generate),
    // each in one transaction with its ledger row. Their refusals are P0001 and come
    // back as 400 with the sentence (HotelBusinessRuleFilter) -- never swallowed.
    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelFinanceController : ControllerBase
    {
        private readonly string _cs;
        private readonly IHotelEmailService _hotelEmail;
        public HotelFinanceController(IConfiguration config, IHotelEmailService hotelEmail) { _cs = config.GetConnectionString("PoultryConn") ?? ""; _hotelEmail = hotelEmail; }

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

            // Priced from the whole bill (booking total + folio charges); a booking that
            // already has an open invoice gets it refreshed, not a duplicate (327).
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int invoiceId;
            using (var c = new NpgsqlCommand("SELECT sphotelinvoice_generate(p_farmid => @f::text, p_bookingid => @b::int, p_by => @by::text)", conn))
            {
                c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@b", req.HotelBookingId);
                c.Parameters.AddWithValue("@by", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
                invoiceId = Convert.ToInt32(await c.ExecuteScalarAsync());
            }
            using var get = new NpgsqlCommand("SELECT * FROM hotelinvoices WHERE hotelinvoiceid=@id AND farmid=@f", conn);
            get.Parameters.AddWithValue("@id", invoiceId); get.Parameters.AddWithValue("@f", req.FarmId);
            using var r = await get.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500, new { message = "Failed to generate invoice." });
        }

        [HttpGet("billing/payments")]
        public async Task<IActionResult> ListPayments([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return await PaginatedList("hotelpayments", "farmid=@f", "paymentdate DESC",
                new[] { new NpgsqlParameter("@f", farmId) }, page, pageSize);
        }

        [HttpPost("billing/payments")]
        public async Task<IActionResult> RecordPayment([FromBody] HotelRecordPaymentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveAmount(req.Amount, "Payment amount"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidateRequiredString(req.PaymentMethod, "Payment method"); if (v2 != null) return v2;

            // Payment row + ledger row + invoice recompute in one transaction (327).
            // If the posting fails, the payment is not recorded and the caller sees why.
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int paymentId;
            using (var cmd = new NpgsqlCommand(
                "SELECT sphotelpayment_record(p_farmid => @f::text, p_bookingid => @b::int, p_amount => @a::numeric, " +
                "p_paymentmethod => @m::text, p_reference => @r::text, p_notes => @n::text, p_invoiceid => @i::int, " +
                "p_cashaccountid => @ca::int, p_by => @by::text)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@b", req.HotelBookingId);
                cmd.Parameters.AddWithValue("@a", req.Amount); cmd.Parameters.AddWithValue("@m", req.PaymentMethod);
                cmd.Parameters.AddWithValue("@r", string.IsNullOrWhiteSpace(req.Reference) ? DBNull.Value : req.Reference);
                cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@i", (object?)req.HotelInvoiceId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ca", (object?)req.HotelCashAccountId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@by", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
                paymentId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
            Dictionary<string, object?> row;
            using (var get = new NpgsqlCommand("SELECT * FROM hotelpayments WHERE hotelpaymentid=@id AND farmid=@f", conn))
            {
                get.Parameters.AddWithValue("@id", paymentId); get.Parameters.AddWithValue("@f", req.FarmId);
                using var r = await get.ExecuteReaderAsync();
                if (!await r.ReadAsync()) return StatusCode(500);
                row = ReadRow(r);
            }
            string refUsed = row.GetValueOrDefault("reference")?.ToString() ?? "";
            // The receipt email is a courtesy, not money, so it may still run in the background.
            _ = Task.Run(async () => { try { await _hotelEmail.SendPaymentReceiptAsync(req.FarmId, req.HotelBookingId, req.Amount, req.PaymentMethod, refUsed); } catch { } });
            return Ok(row);
        }

        [HttpGet("billing/balance/{bookingId}")]
        public async Task<IActionResult> GetBookingBalance(int bookingId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            decimal totalBill = 0, totalPaid = 0;
            using (var c = new NpgsqlCommand("SELECT COALESCE(totalamount,0) FROM hotelbookings WHERE hotelbookingid=@b AND farmid=@f", conn)) { c.Parameters.AddWithValue("@b", bookingId); c.Parameters.AddWithValue("@f", farmId); totalBill = Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }
            using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(amount),0) FROM hotelpayments WHERE hotelbookingid=@b AND farmid=@f AND status<>'Void'", conn)) { c.Parameters.AddWithValue("@b", bookingId); c.Parameters.AddWithValue("@f", farmId); totalPaid = Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }
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
            // 332: a supplier named on the expense must be this hotel's; a Credit expense to it is a bill on Supplier Balances.
            if (req.HotelSupplierId != null)
            {
                using var chk = new NpgsqlConnection(_cs); await chk.OpenAsync();
                using var c = new NpgsqlCommand("SELECT 1 FROM hotelsuppliers WHERE hotelsupplierid=@s AND farmid=@f AND NOT isdeleted", chk);
                c.Parameters.AddWithValue("@s", req.HotelSupplierId.Value); c.Parameters.AddWithValue("@f", req.FarmId);
                if (await c.ExecuteScalarAsync() == null) return BadRequest(new { message = "Supplier does not belong to this company." });
            }
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "INSERT INTO hotelexpenses(farmid,category,description,amount,expensedate,vendor,notes,paymentmethod,hotelcashaccountid,paidto,hotelexpensecategoryid,status,hotelsupplierid,duedate) " +
                "VALUES(@f,@c,@d,@a,@e::date,@v,@n,@pm,@ca,@pt,@eci,'Draft',@sid,@due::date) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@sid", (object?)req.HotelSupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@due", string.IsNullOrEmpty(req.DueDate) ? DBNull.Value : req.DueDate);
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
            // Status + ledger row in one transaction; the money leaves the account the
            // expense chose (327). A refusal is a 400 with the reason.
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using (var cmd = new NpgsqlCommand("SELECT sphotelexpense_approve(p_farmid => @f::text, p_expenseid => @id::int, p_by => @u::text)", conn))
            {
                cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
                cmd.Parameters.AddWithValue("@u", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
                await cmd.ExecuteNonQueryAsync();
            }
            return await ExpenseRow(conn, id, req.FarmId);
        }

        [HttpPost("finance/expenses/{id}/cancel")]
        public async Task<IActionResult> CancelExpense(int id, [FromBody] ExpenseActionRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            // An approved expense's money comes back to its account as a reversal row (327).
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using (var cmd = new NpgsqlCommand("SELECT sphotelexpense_cancel(p_farmid => @f::text, p_expenseid => @id::int, p_reason => @r::text, p_by => @u::text)", conn))
            {
                cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
                cmd.Parameters.AddWithValue("@r", (object?)req.Reason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@u", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
                await cmd.ExecuteNonQueryAsync();
            }
            return await ExpenseRow(conn, id, req.FarmId);
        }

        private async Task<IActionResult> ExpenseRow(NpgsqlConnection conn, int id, string farmId)
        {
            using var get = new NpgsqlCommand("SELECT * FROM hotelexpenses WHERE hotelexpenseid=@id AND farmid=@f", conn);
            get.Parameters.AddWithValue("@id", id); get.Parameters.AddWithValue("@f", farmId);
            using var r = await get.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound(new { message = "Expense not found." });
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
            // 331: allownegativebalance / notes (Poultry's account form). The purpose
            // stays one-account-per-purpose, as the PATCH below keeps it.
            if (!string.IsNullOrEmpty(req.Purpose))
            {
                using var clear = new NpgsqlCommand("UPDATE hotelcashaccounts SET purpose=NULL, updatedat=NOW() WHERE farmid=@f AND purpose=@p", conn);
                clear.Parameters.AddWithValue("@f", req.FarmId); clear.Parameters.AddWithValue("@p", req.Purpose);
                await clear.ExecuteNonQueryAsync();
            }
            using var cmd = new NpgsqlCommand("INSERT INTO hotelcashaccounts(farmid,accountname,accounttype,openingbalance,currentbalance,purpose,allownegativebalance,notes) VALUES(@f,@n,@t,@b,@b,@p,@neg,@notes) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.AccountName);
            cmd.Parameters.AddWithValue("@t", req.AccountType); cmd.Parameters.AddWithValue("@b", req.OpeningBalance);
            cmd.Parameters.AddWithValue("@p", (object?)req.Purpose ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@neg", req.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@notes", string.IsNullOrWhiteSpace(req.Notes) ? DBNull.Value : req.Notes.Trim());
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
