using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelEmailService : IHotelEmailService
    {
        private readonly IEmailService _email;
        private readonly string _cs;
        private readonly ILogger<HotelEmailService> _logger;

        public HotelEmailService(IEmailService email, IConfiguration config, ILogger<HotelEmailService> logger)
        {
            _email = email;
            _cs = config.GetConnectionString("PoultryConn") ?? "";
            _logger = logger;
        }

        public async Task SendBookingConfirmationAsync(string farmId, int bookingId)
        {
            try
            {
                var (guestEmail, guestName, hotelName, booking) = await GetBookingContext(farmId, bookingId);
                if (string.IsNullOrWhiteSpace(guestEmail)) return;

                var subject = $"Booking Confirmation — {booking["bookingref"]} | {hotelName}";
                var body = BuildHtml(hotelName, $@"
                    <h2 style='color:#7c3aed;margin:0 0 16px'>Booking Confirmed</h2>
                    <p>Dear {guestName},</p>
                    <p>Your reservation has been confirmed. Here are your booking details:</p>
                    <table style='width:100%;border-collapse:collapse;margin:16px 0'>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Booking Ref</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking["bookingref"]}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Check-in</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{FormatDate(booking["checkindate"])}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Check-out</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{FormatDate(booking["checkoutdate"])}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Room Type</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking.GetValueOrDefault("roomtypename", "—")}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Guests</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking["numberofguests"]}</td></tr>
                        <tr><td style='padding:8px;color:#64748b'>Total Amount</td><td style='padding:8px;font-weight:700;font-size:18px;color:#7c3aed'>{FormatAmount(booking["totalamount"])}</td></tr>
                    </table>
                    {(booking.ContainsKey("specialrequests") && booking["specialrequests"] != null ? $"<p style='background:#f8fafc;padding:12px;border-radius:8px;color:#64748b'><strong>Special Requests:</strong> {booking["specialrequests"]}</p>" : "")}
                    <p>We look forward to welcoming you!</p>");

                await _email.SendAsync(new[] { guestEmail }, subject, body);
                _logger.LogInformation("Booking confirmation email sent for booking {BookingId}", bookingId);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send booking confirmation email for booking {BookingId}", bookingId); }
        }

        public async Task SendCheckInConfirmationAsync(string farmId, int bookingId)
        {
            try
            {
                var (guestEmail, guestName, hotelName, booking) = await GetBookingContext(farmId, bookingId);
                if (string.IsNullOrWhiteSpace(guestEmail)) return;

                var subject = $"Welcome to {hotelName} — Check-In Confirmation";
                var body = BuildHtml(hotelName, $@"
                    <h2 style='color:#7c3aed;margin:0 0 16px'>Welcome!</h2>
                    <p>Dear {guestName},</p>
                    <p>You have been successfully checked in. We hope you enjoy your stay!</p>
                    <table style='width:100%;border-collapse:collapse;margin:16px 0'>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Booking Ref</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking["bookingref"]}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Room</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking.GetValueOrDefault("roomnumber", "—")}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Check-in</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{DateTime.UtcNow:MMMM dd, yyyy}</td></tr>
                        <tr><td style='padding:8px;color:#64748b'>Check-out</td><td style='padding:8px;font-weight:600'>{FormatDate(booking["checkoutdate"])}</td></tr>
                    </table>
                    <p>If you need anything during your stay, please don't hesitate to contact the front desk.</p>");

                await _email.SendAsync(new[] { guestEmail }, subject, body);
                _logger.LogInformation("Check-in confirmation email sent for booking {BookingId}", bookingId);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send check-in email for booking {BookingId}", bookingId); }
        }

        public async Task SendCheckOutReceiptAsync(string farmId, int bookingId, decimal totalBill, decimal totalPaid)
        {
            try
            {
                var (guestEmail, guestName, hotelName, booking) = await GetBookingContext(farmId, bookingId);
                if (string.IsNullOrWhiteSpace(guestEmail)) return;

                decimal balance = totalBill - totalPaid;
                var subject = $"Check-Out Receipt — {booking["bookingref"]} | {hotelName}";
                var body = BuildHtml(hotelName, $@"
                    <h2 style='color:#7c3aed;margin:0 0 16px'>Check-Out Receipt</h2>
                    <p>Dear {guestName},</p>
                    <p>Thank you for staying with us. Here is your bill summary:</p>
                    <table style='width:100%;border-collapse:collapse;margin:16px 0'>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Booking Ref</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking["bookingref"]}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Check-in</td><td style='padding:8px;border-bottom:1px solid #e2e8f0'>{FormatDate(booking["checkindate"])}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Check-out</td><td style='padding:8px;border-bottom:1px solid #e2e8f0'>{DateTime.UtcNow:MMMM dd, yyyy}</td></tr>
                        <tr><td style='padding:12px;border-bottom:1px solid #e2e8f0;color:#64748b;font-weight:600'>Total Bill</td><td style='padding:12px;border-bottom:1px solid #e2e8f0;font-weight:700;font-size:16px'>{FormatAmount(totalBill)}</td></tr>
                        <tr><td style='padding:12px;border-bottom:1px solid #e2e8f0;color:#64748b;font-weight:600'>Total Paid</td><td style='padding:12px;border-bottom:1px solid #e2e8f0;font-weight:700;font-size:16px;color:#059669'>{FormatAmount(totalPaid)}</td></tr>
                        <tr><td style='padding:12px;color:#64748b;font-weight:600'>Balance</td><td style='padding:12px;font-weight:700;font-size:18px;color:{(balance <= 0 ? "#059669" : "#dc2626")}'>{FormatAmount(balance)}</td></tr>
                    </table>
                    <p>We hope you had a wonderful stay and look forward to welcoming you again!</p>");

                await _email.SendAsync(new[] { guestEmail }, subject, body);
                _logger.LogInformation("Check-out receipt email sent for booking {BookingId}", bookingId);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send check-out email for booking {BookingId}", bookingId); }
        }

        public async Task SendPaymentReceiptAsync(string farmId, int bookingId, decimal amount, string paymentMethod, string reference)
        {
            try
            {
                var (guestEmail, guestName, hotelName, booking) = await GetBookingContext(farmId, bookingId);
                if (string.IsNullOrWhiteSpace(guestEmail)) return;

                var subject = $"Payment Receipt — {reference} | {hotelName}";
                var body = BuildHtml(hotelName, $@"
                    <h2 style='color:#7c3aed;margin:0 0 16px'>Payment Receipt</h2>
                    <p>Dear {guestName},</p>
                    <p>We have received your payment. Here are the details:</p>
                    <table style='width:100%;border-collapse:collapse;margin:16px 0'>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Reference</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600;font-family:monospace'>{reference}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Booking</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{booking["bookingref"]}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Method</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{paymentMethod}</td></tr>
                        <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Date</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{DateTime.UtcNow:MMMM dd, yyyy}</td></tr>
                        <tr><td style='padding:12px;color:#64748b;font-weight:600'>Amount Paid</td><td style='padding:12px;font-weight:700;font-size:20px;color:#059669'>{FormatAmount(amount)}</td></tr>
                    </table>
                    <p>Thank you for your payment.</p>");

                await _email.SendAsync(new[] { guestEmail }, subject, body);
                _logger.LogInformation("Payment receipt email sent for booking {BookingId}, amount {Amount}", bookingId, amount);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send payment receipt email for booking {BookingId}", bookingId); }
        }

        // ---- Helpers ----

        private async Task<(string? email, string name, string hotelName, Dictionary<string, object?> booking)> GetBookingContext(string farmId, int bookingId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            // Get booking with guest join
            var booking = new Dictionary<string, object?>();
            string? guestEmail = null; string guestName = "Guest";
            using (var cmd = new NpgsqlCommand(
                "SELECT b.*, g.firstname, g.lastname, g.email, r.roomnumber, rt.name AS roomtypename " +
                "FROM hotelbookings b LEFT JOIN hotelguests g ON b.hotelguestid=g.hotelguestid " +
                "LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid " +
                "LEFT JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid " +
                "WHERE b.hotelbookingid=@b AND b.farmid=@f", conn))
            {
                cmd.Parameters.AddWithValue("@b", bookingId); cmd.Parameters.AddWithValue("@f", farmId);
                using var rd = await cmd.ExecuteReaderAsync();
                if (await rd.ReadAsync())
                {
                    for (int i = 0; i < rd.FieldCount; i++) booking[rd.GetName(i).ToLower()] = rd.IsDBNull(i) ? null : rd.GetValue(i);
                    guestEmail = booking.GetValueOrDefault("email")?.ToString();
                    guestName = $"{booking.GetValueOrDefault("firstname")} {booking.GetValueOrDefault("lastname")}".Trim();
                }
            }

            // Get hotel name
            string hotelName = "Hotel";
            using (var cmd = new NpgsqlCommand("SELECT hotelname FROM hotelprofiles WHERE farmid=@f LIMIT 1", conn))
            {
                cmd.Parameters.AddWithValue("@f", farmId);
                var result = await cmd.ExecuteScalarAsync();
                if (result != null && result != DBNull.Value) hotelName = result.ToString()!;
            }

            return (guestEmail, guestName, hotelName, booking);
        }

        private static string FormatDate(object? val) => val switch
        {
            DateTime dt => dt.ToString("MMMM dd, yyyy"),
            DateTimeOffset dto => dto.ToString("MMMM dd, yyyy"),
            string s when DateTime.TryParse(s, out var d) => d.ToString("MMMM dd, yyyy"),
            _ => "—"
        };

        private static string FormatAmount(object? val) => val switch
        {
            decimal d => d.ToString("N2"),
            double d => d.ToString("N2"),
            int i => i.ToString("N2"),
            _ => "0.00"
        };

        private static string BuildHtml(string hotelName, string content) => $@"
<!DOCTYPE html>
<html>
<head><meta charset='utf-8'></head>
<body style='margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif'>
<div style='max-width:600px;margin:0 auto;padding:24px'>
    <div style='background:#7c3aed;color:white;padding:20px 24px;border-radius:12px 12px 0 0;text-align:center'>
        <h1 style='margin:0;font-size:22px'>{hotelName}</h1>
    </div>
    <div style='background:white;padding:24px;border-radius:0 0 12px 12px;box-shadow:0 1px 3px rgba(0,0,0,.1)'>
        {content}
    </div>
    <p style='text-align:center;color:#94a3b8;font-size:12px;margin-top:16px'>
        This is an automated email from {hotelName}. Please do not reply.
    </p>
</div>
</body>
</html>";
    }
}
