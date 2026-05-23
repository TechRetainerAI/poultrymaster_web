using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IEmailService
    {
        // Sends an HTML or plain-text email with optional attachments.
        // Throws on failure so the controller can surface a useful error.
        Task SendAsync(
            IEnumerable<string> to,
            string subject,
            string body,
            bool isHtml = true,
            IEnumerable<EmailAttachment>? attachments = null
        );
    }
}
