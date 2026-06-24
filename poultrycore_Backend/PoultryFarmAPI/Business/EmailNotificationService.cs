using System.Net;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Composes and sends the application's notification emails (report share,
    // login credentials, company welcome). Owns the HTML templates and the
    // subject/body resolution that used to live in EmailController, so the
    // controller stays a thin HTTP boundary. Delivery is delegated to
    // IEmailService. Mirrors the WaterReportEmailService pattern.
    public class EmailNotificationService : IEmailNotificationService
    {
        private readonly IEmailService _email;
        private readonly IConfiguration _configuration;

        public EmailNotificationService(IEmailService email, IConfiguration configuration)
        {
            _email = email;
            _configuration = configuration;
        }

        public async Task SendReportAsync(
            byte[] content,
            string? fileName,
            string? contentType,
            IEnumerable<string> to,
            string? subject,
            string? body,
            string? farmName,
            string? reportTitle,
            string? senderName)
        {
            var resolvedSubject = !string.IsNullOrWhiteSpace(subject)
                ? subject
                : !string.IsNullOrWhiteSpace(reportTitle)
                    ? $"{reportTitle} — {(string.IsNullOrWhiteSpace(farmName) ? "Poultry Master" : farmName)}"
                    : "Your Poultry Master report";

            var resolvedBody = !string.IsNullOrWhiteSpace(body)
                ? body
                : BuildDefaultHtmlBody(reportTitle, farmName, senderName);

            var attachment = new EmailAttachment
            {
                FileName = string.IsNullOrWhiteSpace(fileName) ? "report.pdf" : fileName,
                ContentType = string.IsNullOrWhiteSpace(contentType) ? "application/pdf" : contentType,
                Content = content,
            };

            await _email.SendAsync(
                to: to,
                subject: resolvedSubject,
                body: resolvedBody,
                isHtml: true,
                attachments: new[] { attachment });
        }

        public async Task SendCredentialsAsync(EmailCredentialsRequest req)
        {
            var loginUrl = (_configuration["FrontendApp:BaseUrl"] ?? "http://localhost:3000").TrimEnd('/') + "/login";
            var html = BuildCredentialsEmailHtml(req.UserName, req.Password, req.FarmName, loginUrl);
            var subject = string.IsNullOrWhiteSpace(req.FarmName) ? "Your login details" : $"Your {req.FarmName} login details";
            await _email.SendAsync(new[] { req.Email }, subject, html, isHtml: true);
        }

        public async Task SendWelcomeAsync(EmailCompanyWelcomeRequest req)
        {
            var html = BuildCompanyCreatedEmailHtml(req.CompanyName, req.CompanyType);
            await _email.SendAsync(new[] { req.Email }, $"\"{req.CompanyName}\" is ready on Poultry Master", html, isHtml: true);
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

        private static string BuildDefaultHtmlBody(string? reportTitle, string? farmName, string? senderName)
        {
            var hasTitle = !string.IsNullOrWhiteSpace(reportTitle);
            var title = WebUtility.HtmlEncode(hasTitle ? reportTitle! : "report");
            var hasFarm = !string.IsNullOrWhiteSpace(farmName);
            var farm = WebUtility.HtmlEncode(hasFarm ? farmName! : "Poultry Master");
            var generated = DateTime.UtcNow.ToString("MMM d, yyyy 'at' HH:mm 'UTC'");

            // The recipient is often NOT the person who generated the report (an admin
            // shares it with an owner, accountant, partner, etc.), so the copy stays
            // recipient-neutral: no "your report" / "you selected" / "your dashboard".
            // When we know who sent it, we say so to make the message feel personal.
            var hasSender = !string.IsNullOrWhiteSpace(senderName);
            var sender = WebUtility.HtmlEncode(hasSender ? senderName! : "");
            var sharedLine = hasSender
                ? $@"<p style=""margin:0 0 14px;""><strong>{sender}</strong> has shared this report with you from <strong>{farm}</strong>.</p>"
                : $@"<p style=""margin:0 0 14px;"">A new report has been shared with you from <strong>{farm}</strong>.</p>";

            // Branded, email-client-friendly layout (table-based, inline styles) that
            // mirrors the PDF's emerald letterhead.
            return $@"
<div style=""background:#f1f5f9;padding:24px 0;font-family:Arial,Helvetica,sans-serif;"">
  <table role=""presentation"" cellpadding=""0"" cellspacing=""0"" width=""100%"" style=""max-width:600px;margin:0 auto;background:#ffffff;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;"">
    <tr>
      <td style=""background:#047857;padding:20px 28px;"">
        <div style=""color:#ffffff;font-size:18px;font-weight:bold;"">{farm}</div>
        <div style=""color:#d1fae5;font-size:13px;margin-top:2px;"">{(hasTitle ? title : "Report")}</div>
      </td>
    </tr>
    <tr>
      <td style=""padding:28px;color:#0f172a;line-height:1.6;font-size:15px;"">
        <p style=""margin:0 0 14px;"">Hello,</p>
        {sharedLine}
        <p style=""margin:0 0 14px;"">You'll find the <strong>{title}</strong> attached as a PDF, with the key figures at a glance and the full breakdown inside.</p>
        <table role=""presentation"" cellpadding=""0"" cellspacing=""0"" style=""margin:18px 0;"">
          <tr>
            <td style=""background:#ecfdf5;border:1px solid #a7f3d0;border-radius:8px;padding:12px 16px;color:#065f46;font-size:14px;"">
              &#128206;&nbsp; <strong>{title}</strong> &mdash; attached (PDF)
            </td>
          </tr>
        </table>
        <p style=""margin:0;color:#475569;font-size:14px;"">We hope you find it helpful. If you have any questions about these figures, please reach out to {(hasSender ? $"<strong>{sender}</strong>" : "your contact")} at {farm}.</p>
      </td>
    </tr>
    <tr>
      <td style=""border-top:1px solid #e2e8f0;padding:16px 28px;color:#94a3b8;font-size:12px;"">
        Shared via Poultry Master on {generated}.<br/>
        This is an automated message &mdash; please do not reply directly to this email.
      </td>
    </tr>
  </table>
</div>";
        }
    }
}
