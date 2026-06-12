using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // SMTP email sender backed by MailKit. Mirrors the implementation in
    // PoultryWeb/Business/EmailService.cs but adds attachment support.
    public class EmailService : IEmailService
    {
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
            if (string.IsNullOrWhiteSpace(_config.SmtpServer))
                throw new InvalidOperationException(
                    "Email is not configured. Set EmailConfiguration__SmtpServer / Port / UserName / Password / From.");

            if (string.IsNullOrWhiteSpace(_config.From))
                throw new InvalidOperationException("EmailConfiguration__From is required.");

            var recipients = to?.Where(s => !string.IsNullOrWhiteSpace(s)).ToList() ?? new List<string>();
            if (recipients.Count == 0)
                throw new ArgumentException("At least one recipient is required.", nameof(to));

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress("PoultryCore Reports", _config.From));
            foreach (var addr in recipients)
            {
                message.To.Add(MailboxAddress.Parse(addr));
            }
            message.Subject = subject ?? string.Empty;

            var builder = new BodyBuilder();
            if (isHtml) builder.HtmlBody = body ?? string.Empty;
            else builder.TextBody = body ?? string.Empty;

            if (attachments != null)
            {
                foreach (var att in attachments)
                {
                    if (att?.Content == null || att.Content.Length == 0) continue;
                    var ct = ContentType.Parse(att.ContentType ?? "application/octet-stream");
                    builder.Attachments.Add(att.FileName ?? "attachment", att.Content, ct);
                }
            }

            message.Body = builder.ToMessageBody();

            using var client = new SmtpClient();
            try
            {
                // Port 465 = implicit TLS (SslOnConnect); 587 = STARTTLS.
                var socketOption = _config.UseSsl || _config.Port == 465
                    ? SecureSocketOptions.SslOnConnect
                    : SecureSocketOptions.StartTls;

                await client.ConnectAsync(_config.SmtpServer, _config.Port, socketOption);
                client.AuthenticationMechanisms.Remove("XOAUTH2");

                if (!string.IsNullOrWhiteSpace(_config.UserName))
                {
                    await client.AuthenticateAsync(_config.UserName, _config.Password);
                }

                await client.SendAsync(message);
                _logger.LogInformation(
                    "Email sent to {Recipients}, subject: {Subject}, attachments: {AttachmentCount}",
                    string.Join(",", recipients),
                    subject,
                    attachments?.Count() ?? 0);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex,
                    "Failed to send email to {Recipients}, subject: {Subject}",
                    string.Join(",", recipients),
                    subject);
                throw;
            }
            finally
            {
                if (client.IsConnected)
                {
                    await client.DisconnectAsync(true);
                }
            }
        }
    }
}
