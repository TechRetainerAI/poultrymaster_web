using System.Net;
using System.Text.RegularExpressions;
using MailKit.Net.Smtp;
using MimeKit;
using User.Management.Service.Constants;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{
    public class EmailService : IEmailService
    {
        private readonly EmailConfiguration _emailConfig;
        public EmailService(EmailConfiguration emailConfig) => _emailConfig = emailConfig;
        public string SendEmail(Message message)
        {
            var emailMessage = CreateEmailMessage(message);
            Send(emailMessage);
            var recipients = string.Join(", ", message.To);
            return ResponseMessages.GetEmailSuccessMessage(recipients);

        }

        private MimeMessage CreateEmailMessage(Message message)
        {
            var emailMessage = new MimeMessage();
            // A real sender display name (not "email") — generic/odd names hurt deliverability.
            emailMessage.From.Add(new MailboxAddress("Poultry Master", _emailConfig.From));
            emailMessage.To.AddRange(message.To);
            emailMessage.Subject = message.Subject;
            // Ship multipart/alternative: HTML-only mail is penalised by spam filters, so we
            // include a plain-text fallback derived from the HTML.
            var bodyBuilder = new BodyBuilder
            {
                HtmlBody = message.Content,
                TextBody = HtmlToPlainText(message.Content)
            };
            emailMessage.Body = bodyBuilder.ToMessageBody();

            return emailMessage;
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

        private void Send(MimeMessage mailMessage)
        {
            using var client = new SmtpClient();
            try
            {
                client.Connect(_emailConfig.SmtpServer, _emailConfig.Port, true);
                client.AuthenticationMechanisms.Remove("XOAUTH2");
                client.Authenticate(_emailConfig.UserName, _emailConfig.Password);

                client.Send(mailMessage);
            }
            catch
            {
                //log an error message or throw an exception or both.
                throw;
            }
            finally
            {
                client.Disconnect(true);
                client.Dispose();
            }
        }
    }
}
