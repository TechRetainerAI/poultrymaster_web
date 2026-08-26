using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // ==================== REQUEST MODELS ====================
    public class AddChargeRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public string ChargeType { get; set; } = "Room"; public string Description { get; set; } = ""; public int Quantity { get; set; } = 1; public decimal UnitPrice { get; set; } public decimal? TotalAmount { get; set; } }
    public class GenerateInvoiceRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } }
    public class RecordPaymentRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public int? HotelInvoiceId { get; set; } public decimal Amount { get; set; } public string PaymentMethod { get; set; } = "Cash"; public string? Reference { get; set; } public string? Notes { get; set; } }
    public class CreateExpenseRequest { public string FarmId { get; set; } = ""; public string Category { get; set; } = ""; public string Description { get; set; } = ""; public decimal Amount { get; set; } public string? ExpenseDate { get; set; } public string? Vendor { get; set; } public string? Notes { get; set; } }
    public class CreateCashAccountRequest { public string FarmId { get; set; } = ""; public string AccountName { get; set; } = ""; public string AccountType { get; set; } = "Cash"; public decimal OpeningBalance { get; set; } }

    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelFinanceController : ControllerBase
    {
        private readonly string _cs;
        public HotelFinanceController(IConfiguration config) => _cs = config.GetConnectionString("PoultryConn") ?? "";

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
        public async Task<IActionResult> ListPayments([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelpayments WHERE farmid=@f ORDER BY paymentdate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
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
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
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
        public async Task<IActionResult> ListExpenses([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelexpenses WHERE farmid=@f ORDER BY expensedate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
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
            using var cmd = new NpgsqlCommand("INSERT INTO hotelexpenses(farmid,category,description,amount,expensedate,vendor,notes) VALUES(@f,@c,@d,@a,@e::date,@v,@n) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@c", req.Category);
            cmd.Parameters.AddWithValue("@d", req.Description); cmd.Parameters.AddWithValue("@a", req.Amount);
            cmd.Parameters.AddWithValue("@e", date);
            cmd.Parameters.AddWithValue("@v", (object?)req.Vendor ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
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
            using var cmd = new NpgsqlCommand("INSERT INTO hotelcashaccounts(farmid,accountname,accounttype,openingbalance,currentbalance) VALUES(@f,@n,@t,@b,@b) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.AccountName);
            cmd.Parameters.AddWithValue("@t", req.AccountType); cmd.Parameters.AddWithValue("@b", req.OpeningBalance);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
