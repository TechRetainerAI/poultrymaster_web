using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using User.Management.Service.Constants;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{
    // Email sender backed by the Resend HTTP API (https://api.resend.com/emails).
    //
    // We deliberately do NOT use SMTP: Cloud Run throttles/blocks outbound SMTP
    // (25/465/587), so MailKit-over-SMTP times out in production. The HTTP API is
    // Resend's recommended path for serverless hosts.
    //
    // EmailConfiguration is reused as-is so no env-var changes are needed:
    //   Password -> the Resend API key (re_...)
    //   From     -> the verified sender address
    // SmtpServer / Port / UserName are ignored (kept only for backward compat).
    public class EmailService : IEmailService
    {
        // One shared HttpClient for the process (avoids socket exhaustion).
        private static readonly HttpClient _http = new HttpClient
        {
            BaseAddress = new Uri("https://api.resend.com/"),
            Timeout = TimeSpan.FromSeconds(30),
        };

        private readonly EmailConfiguration _emailConfig;
        public EmailService(EmailConfiguration emailConfig) => _emailConfig = emailConfig;

        public string SendEmail(Message message)
        {
            if (string.IsNullOrWhiteSpace(_emailConfig.Password))
                throw new InvalidOperationException(
                    "Email is not configured. Set EmailConfiguration__Password to your Resend API key (re_...) and EmailConfiguration__From to a verified sender.");

            if (string.IsNullOrWhiteSpace(_emailConfig.From))
                throw new InvalidOperationException("EmailConfiguration__From is required.");

            var recipients = message.To
                .Select(a => a.Address)
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .ToList();
            if (recipients.Count == 0)
                throw new ArgumentException("At least one recipient is required.", nameof(message));

            var payload = new Dictionary<string, object?>
            {
                ["from"] = _emailConfig.From,
                ["to"] = recipients,
                ["subject"] = message.Subject ?? string.Empty,
                // Ship both parts: HTML-only mail is penalised by spam filters.
                ["html"] = message.Content ?? string.Empty,
                ["text"] = HtmlToPlainText(message.Content),
            };

            var json = JsonSerializer.Serialize(payload);

            using var request = new HttpRequestMessage(HttpMethod.Post, "emails")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _emailConfig.Password.Trim());

            var response = _http.Send(request);
            var responseBody = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            if (!response.IsSuccessStatusCode)
            {
                // Surface Resend's exact reason (domain not verified, bad key, etc.).
                throw new Exception($"Resend rejected the email ({(int)response.StatusCode}): {responseBody}");
            }

            return ResponseMessages.GetEmailSuccessMessage(string.Join(", ", recipients));
        }

        // Minimal HTML→text for the plain-text alternative part. Not a full parser — strips
        // tags, drops style/script, collapses whitespace, and decodes entities.
        private static string HtmlToPlainText(string html)
        {
            if (string.IsNullOrWhiteSpace(html)) return string.Empty;
            var text = Regex.Replace(html, "<(script|style)[^>]*>.*?</\\1>", "", RegexOptions.Singleline | RegexOptions.IgnoreCase);
            text = Regex.Replace(text, "<(br|/p|/div|/h[1-6])[^>]*>", "\n", RegexOptions.IgnoreCase);
            text = Regex.Replace(text, "<[^>]+>", "");
            text = WebUtility.HtmlDecode(text);
            text = Regex.Replace(text, "[ \\t]+", " ");
            text = Regex.Replace(text, "(\\s*\\n\\s*){2,}", "\n\n");
            return text.Trim();
        }
    }
}
