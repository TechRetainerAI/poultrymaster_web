using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Email sender backed by the Resend HTTP API (https://api.resend.com/emails).
    //
    // We deliberately do NOT use SMTP: Cloud Run throttles/blocks outbound SMTP
    // (ports 25/465/587), so MailKit-over-SMTP times out in production. The HTTP
    // API is Resend's recommended path for serverless hosts.
    //
    // EmailConfiguration is reused as-is so no env-var changes are needed:
    //   Password -> the Resend API key (re_...)
    //   From     -> the verified sender address
    // SmtpServer / Port / UseSsl are ignored (kept only for backward compat).
    public class EmailService : IEmailService
    {
        // One shared HttpClient for the process (avoids socket exhaustion).
        private static readonly HttpClient _http = new HttpClient
        {
            BaseAddress = new Uri("https://api.resend.com/"),
            Timeout = TimeSpan.FromSeconds(30),
        };

        private readonly EmailConfiguration _config;
        private readonly ILogger<EmailService> _logger;

        public EmailService(EmailConfiguration config, ILogger<EmailService> logger)
        {
            _config = config;
            _logger = logger;
        }

        public async Task SendAsync(
            IEnumerable<string> to,
            string subject,
            string body,
            bool isHtml = true,
            IEnumerable<EmailAttachment>? attachments = null)
        {
            if (string.IsNullOrWhiteSpace(_config.Password))
                throw new InvalidOperationException(
                    "Email is not configured. Set EmailConfiguration__Password to your Resend API key (re_...) and EmailConfiguration__From to a verified sender.");

            if (string.IsNullOrWhiteSpace(_config.From))
                throw new InvalidOperationException("EmailConfiguration__From is required.");

            var recipients = to?.Where(s => !string.IsNullOrWhiteSpace(s)).ToList() ?? new List<string>();
            if (recipients.Count == 0)
                throw new ArgumentException("At least one recipient is required.", nameof(to));

            var payload = new Dictionary<string, object?>
            {
                ["from"] = _config.From,
                ["to"] = recipients,
                ["subject"] = subject ?? string.Empty,
            };
            if (isHtml) payload["html"] = body ?? string.Empty;
            else payload["text"] = body ?? string.Empty;

            if (attachments != null)
            {
                var atts = new List<object>();
                foreach (var att in attachments)
                {
                    if (att?.Content == null || att.Content.Length == 0) continue;
                    // Resend expects base64-encoded attachment content.
                    atts.Add(new
                    {
                        filename = string.IsNullOrWhiteSpace(att.FileName) ? "attachment" : att.FileName,
                        content = Convert.ToBase64String(att.Content),
                    });
                }
                if (atts.Count > 0) payload["attachments"] = atts;
            }

            var json = JsonSerializer.Serialize(payload);

            using var request = new HttpRequestMessage(HttpMethod.Post, "emails")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _config.Password.Trim());

            HttpResponseMessage response;
            try
            {
                response = await _http.SendAsync(request);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex,
                    "Resend API request failed for {Recipients}, subject: {Subject}",
                    string.Join(",", recipients), subject);
                throw;
            }

            var responseBody = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError(
                    "Resend API returned {Status} for {Recipients}: {Body}",
                    (int)response.StatusCode, string.Join(",", recipients), responseBody);
                // Surface Resend's exact reason (domain not verified, bad key, etc.).
                throw new Exception($"Resend rejected the email ({(int)response.StatusCode}): {responseBody}");
            }

            _logger.LogInformation(
                "Email sent via Resend to {Recipients}, subject: {Subject}, attachments: {AttachmentCount}",
                string.Join(",", recipients), subject, attachments?.Count() ?? 0);
        }
    }
}
