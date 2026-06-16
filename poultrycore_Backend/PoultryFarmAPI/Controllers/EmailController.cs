using System.Net;
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
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class EmailController : ControllerBase
    {
        private readonly IEmailService _email;
        private readonly ILogger<EmailController> _logger;
        private readonly IConfiguration _configuration;
        private readonly IWaterDailyClosingService _closings;
        private readonly IWaterReportEmailService _reportEmail;

        public EmailController(
            IEmailService email,
            ILogger<EmailController> logger,
            IConfiguration configuration,
            IWaterDailyClosingService closings,
            IWaterReportEmailService reportEmail)
        {
            _email = email;
            _logger = logger;
            _configuration = configuration;
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
            var to = form.To;
            var subject = form.Subject;
            var body = form.Body;
            var farmName = form.FarmName;
            var reportTitle = form.ReportTitle;

            if (file == null || file.Length == 0)
                return BadRequest("Report file is required.");

            if (string.IsNullOrWhiteSpace(request.To))
                return BadRequest("Recipient email (to) is required.");

            // Basic recipient sanity check — let MimeKit do the real parsing later.
            if (!request.To.Contains('@'))
                return BadRequest("Recipient email looks malformed.");

            byte[] bytes;
            using (var ms = new MemoryStream())
            {
                await file.CopyToAsync(ms);
                bytes = ms.ToArray();
            }

            var resolvedSubject = !string.IsNullOrWhiteSpace(request.Subject)
                ? request.Subject
                : !string.IsNullOrWhiteSpace(request.ReportTitle)
                    ? $"{request.ReportTitle} — {request.FarmName ?? "PoultryCore"}"
                    : "Your PoultryCore report";

            var resolvedBody = !string.IsNullOrWhiteSpace(request.Body)
                ? request.Body
                : BuildDefaultHtmlBody(request.ReportTitle, request.FarmName);

            var attachment = new EmailAttachment
            {
                FileName = string.IsNullOrWhiteSpace(file.FileName) ? "report.pdf" : file.FileName,
                ContentType = string.IsNullOrWhiteSpace(file.ContentType) ? "application/pdf" : file.ContentType,
                Content = bytes,
            };

            try
            {
                await _email.SendAsync(
                    to: new[] { request.To },
                    subject: resolvedSubject,
                    body: resolvedBody,
                    isHtml: true,
                    attachments: new[] { attachment });

                return Ok(new { success = true, message = $"Report emailed to {request.To}." });
            }
            catch (InvalidOperationException ex)
            {
                // Misconfiguration — surfaces helpful message to caller.
                _logger.LogError(ex, "Email send aborted due to misconfiguration.");
                return StatusCode(503, new { success = false, message = ex.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send report email to {Recipient}", request.To);
                return StatusCode(500, new { success = false, message = "Failed to send email. Check API logs." });
            }
        }

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
                var loginUrl = (_configuration["FrontendApp:BaseUrl"] ?? "http://localhost:3000").TrimEnd('/') + "/login";
                var html = BuildCredentialsEmailHtml(req.UserName, req.Password, req.FarmName, loginUrl);
                var subject = string.IsNullOrWhiteSpace(req.FarmName) ? "Your login details" : $"Your {req.FarmName} login details";
                await _email.SendAsync(new[] { req.Email }, subject, html, isHtml: true);
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
                var html = BuildCompanyCreatedEmailHtml(req.CompanyName, req.CompanyType);
                await _email.SendAsync(new[] { req.Email }, $"\"{req.CompanyName}\" is ready on Poultry Master", html, isHtml: true);
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

        // Login-credentials email body. Plaintext password is intentional (the
        // admin-set password handed to the new user); we prompt them to change it.
        private static string BuildCredentialsEmailHtml(string? userName, string? password, string? farmName, string loginUrl)
        {
            var safeUser = WebUtility.HtmlEncode(userName ?? "");
            var safePass = WebUtility.HtmlEncode(password ?? "");
            var safeFarm = WebUtility.HtmlEncode(string.IsNullOrWhiteSpace(farmName) ? "your company" : farmName);
            return $@"
<div style=""font-family:Arial,Helvetica,sans-serif;color:#1f2937;max-width:560px;margin:0 auto;"">
  <h2 style=""color:#0f172a;"">Welcome to {safeFarm}</h2>
  <p>An account has been created for you. Use the details below to sign in:</p>
  <table style=""border-collapse:collapse;margin:16px 0;"">
    <tr><td style=""padding:6px 12px;font-weight:bold;"">Username</td><td style=""padding:6px 12px;"">{safeUser}</td></tr>
    <tr><td style=""padding:6px 12px;font-weight:bold;"">Password</td><td style=""padding:6px 12px;"">{safePass}</td></tr>
  </table>
  <p><a href=""{loginUrl}"" style=""display:inline-block;background:#0ea5e9;color:#ffffff;text-decoration:none;padding:10px 18px;border-radius:6px;"">Log in</a></p>
  <p style=""color:#64748b;font-size:13px;"">For your security, please change your password after your first login.</p>
</div>";
        }

        private static string BuildCompanyCreatedEmailHtml(string? name, string? type)
        {
            var safeName = WebUtility.HtmlEncode(name ?? "");
            var safeType = WebUtility.HtmlEncode(type ?? "");
            return $@"
<div style=""font-family:Arial,Helvetica,sans-serif;color:#1f2937;max-width:560px;margin:0 auto;"">
  <h2 style=""color:#0f172a;"">Your company is ready</h2>
  <p><strong>{safeName}</strong>{(string.IsNullOrWhiteSpace(safeType) ? "" : $" ({safeType})")} has been created on Poultry Master.</p>
  <p>You can now log in and start setting it up.</p>
</div>";
        }

        private static string BuildDefaultHtmlBody(string? reportTitle, string? farmName)
        {
            var title = string.IsNullOrWhiteSpace(reportTitle) ? "report" : reportTitle;
            var farm = string.IsNullOrWhiteSpace(farmName) ? "" : $" for <strong>{System.Net.WebUtility.HtmlEncode(farmName)}</strong>";
            var generated = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm 'UTC'");
            return $@"
<div style=""font-family:Arial,Helvetica,sans-serif;color:#0f172a;line-height:1.5;"">
  <p>Hi,</p>
  <p>Your <strong>{System.Net.WebUtility.HtmlEncode(title)}</strong>{farm} is attached as a PDF.</p>
  <p style=""color:#64748b;font-size:12px;"">Generated by PoultryCore at {generated}.</p>
</div>";
        }
    }

    // Bundling the multipart fields into one [FromForm] model lets Swashbuckle
    // describe the request body (mixing a bare IFormFile with scalar [FromForm]
    // params trips Swagger generation in Swashbuckle 6.6.2).
    public class SendReportRequest
    {
        public IFormFile File { get; set; } = default!;
        public string To { get; set; } = default!;
        public string? Subject { get; set; }
        public string? Body { get; set; }
        public string? FarmName { get; set; }
        public string? ReportTitle { get; set; }
    }

    // Body for POST /api/Email/send-credentials.
    public class EmailCredentialsRequest
    {
        public string Email { get; set; } = string.Empty;
        public string? UserName { get; set; }
        public string? Password { get; set; }
        public string? FarmName { get; set; }
    }

    // Body for POST /api/Email/send-welcome.
    public class EmailCompanyWelcomeRequest
    {
        public string Email { get; set; } = string.Empty;
        public string? CompanyName { get; set; }
        public string? CompanyType { get; set; }
    }
}
