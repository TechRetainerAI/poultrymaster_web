using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // All outbound email lives here. Routes under /api/Email/* (the proxy sends
    // that prefix to the Farm API). Report = multipart PDF upload; the others
    // are stateless JSON sends. Daily-closing loads the closing then builds its
    // PDF server-side.
    //
    // This controller is a thin HTTP boundary: it validates input and maps
    // results/exceptions to status codes. Email composition and delivery live in
    // IEmailNotificationService / IWaterReportEmailService (the Business layer).
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class EmailController : ControllerBase
    {
        private readonly ILogger<EmailController> _logger;
        private readonly IEmailNotificationService _notifications;
        private readonly IWaterDailyClosingService _closings;
        private readonly IWaterReportEmailService _reportEmail;

        public EmailController(
            ILogger<EmailController> logger,
            IEmailNotificationService notifications,
            IWaterDailyClosingService closings,
            IWaterReportEmailService reportEmail)
        {
            _logger = logger;
            _notifications = notifications;
            _closings = closings;
            _reportEmail = reportEmail;
        }

        // POST: api/Email/Report
        // Multipart form upload:
        //   - file: the PDF report (required)
        //   - to:   recipient email (required for now; future: resolve from JWT)
        //   - subject: email subject (optional, defaults to "Your report from PoultryCore")
        //   - body:    HTML body (optional, default template used otherwise)
        //   - farmName: optional, used in default body
        //   - reportTitle: optional, used in default body
        [HttpPost("Report")]
        [Consumes("multipart/form-data")] // required so Swashbuckle can describe the IFormFile + form fields
        [RequestSizeLimit(20_000_000)] // 20 MB cap
        public async Task<IActionResult> SendReport([FromForm] SendReportRequest form)
        {
            var file = form.File;

            if (file == null || file.Length == 0)
                return BadRequest("Report file is required.");

            if (string.IsNullOrWhiteSpace(form.To))
                return BadRequest("Recipient email (to) is required.");

            // The "to" field may carry several addresses (comma/semicolon/newline
            // separated). Parse them, then sanity-check each — let MimeKit do the
            // real parsing later.
            var recipients = ParseRecipients(form.To);
            if (recipients.Count == 0)
                return BadRequest("Recipient email (to) is required.");

            var malformed = recipients.Where(r => !r.Contains('@')).ToList();
            if (malformed.Count > 0)
                return BadRequest($"These recipient emails look malformed: {string.Join(", ", malformed)}");

            byte[] bytes;
            using (var ms = new MemoryStream())
            {
                await file.CopyToAsync(ms);
                bytes = ms.ToArray();
            }

            try
            {
                await _notifications.SendReportAsync(
                    content: bytes,
                    fileName: file.FileName,
                    contentType: file.ContentType,
                    to: recipients,
                    subject: form.Subject,
                    body: form.Body,
                    farmName: form.FarmName,
                    reportTitle: form.ReportTitle,
                    senderName: form.SenderName);

                var joined = string.Join(", ", recipients);
                return Ok(new { success = true, message = $"Report emailed to {joined}." });
            }
            catch (InvalidOperationException ex)
            {
                // Misconfiguration — surfaces helpful message to caller.
                _logger.LogError(ex, "Email send aborted due to misconfiguration.");
                return StatusCode(503, new { success = false, message = ex.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send report email to {Recipients}", string.Join(", ", recipients));
                // Surface the underlying reason (incl. inner exception) so the
                // caller sees what actually failed instead of a generic message.
                var detail = ex.InnerException is not null ? $"{ex.Message} — {ex.InnerException.Message}" : ex.Message;
                return StatusCode(500, new { success = false, message = $"Failed to send email: {detail}" });
            }
        }

        // Splits the raw "to" field (comma / semicolon / newline separated) into
        // trimmed, de-duplicated recipient addresses.
        private static List<string> ParseRecipients(string raw) =>
            raw.Split(new[] { ',', ';', '\n', '\r' },
                      StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
               .Distinct(StringComparer.OrdinalIgnoreCase)
               .ToList();

        // POST: api/Email/send-credentials
        // Emails a (new) employee their username + password. Stateless: the caller
        // supplies everything (the plaintext password only lives in the request).
        [HttpPost("send-credentials")]
        public async Task<IActionResult> SendCredentials([FromBody] EmailCredentialsRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.Email) || !req.Email.Contains('@'))
                return Ok(new { success = false, message = "A valid recipient email is required." });
            try
            {
                await _notifications.SendCredentialsAsync(req);
                return Ok(new { success = true, message = $"Credentials emailed to {req.Email}." });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "send-credentials failed for {Email}", req.Email);
                return Ok(new { success = false, message = ex.Message });
            }
        }

        // POST: api/Email/send-welcome
        // Emails a "company created" confirmation.
        [HttpPost("send-welcome")]
        public async Task<IActionResult> SendWelcome([FromBody] EmailCompanyWelcomeRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.Email) || !req.Email.Contains('@'))
                return Ok(new { success = false, message = "A valid recipient email is required." });
            try
            {
                await _notifications.SendWelcomeAsync(req);
                return Ok(new { success = true, message = $"Welcome email sent to {req.Email}." });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "send-welcome failed for {Email}", req.Email);
                return Ok(new { success = false, message = ex.Message });
            }
        }

        // POST: api/Email/daily-closing?id=&farmId=&to=&companyName=
        // Loads the closing (scoped to the company) and emails its server-side PDF.
        [HttpPost("daily-closing")]
        public async Task<IActionResult> DailyClosing([FromQuery] int id, [FromQuery] string farmId, [FromQuery] string to, [FromQuery] string? companyName)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(to) || !to.Contains('@')) return BadRequest("A valid recipient email is required.");
            var m = await _closings.GetByIdAsync(id, farmId);
            if (m is null) return NotFound();
            try
            {
                await _reportEmail.EmailClosingAsync(m, to, companyName);
                return Ok(new { success = true, message = $"Closing report emailed to {to}." });
            }
            catch (InvalidOperationException ex)
            {
                return StatusCode(503, new { success = false, message = ex.Message });
            }
            catch
            {
                return StatusCode(500, new { success = false, message = "Failed to send email. Check API logs." });
            }
        }
    }
}
