using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Composes and sends the application's notification emails (report share,
    // login credentials, company welcome). Owns the HTML templates and the
    // subject/body resolution that used to live in EmailController, so the
    // controller stays a thin HTTP boundary. Delivery is delegated to
    // IEmailService. Mirrors the WaterReportEmailService pattern.
    public interface IEmailNotificationService
    {
        // Emails a PDF report attachment to one or more recipients. Caller supplies
        // the already-read bytes (the controller owns reading the uploaded
        // IFormFile — a web concern) and the parsed recipient list.
        Task SendReportAsync(
            byte[] content,
            string? fileName,
            string? contentType,
            IEnumerable<string> to,
            string? subject,
            string? body,
            string? farmName,
            string? reportTitle,
            string? senderName);

        // Emails a (new) employee their username + password.
        Task SendCredentialsAsync(EmailCredentialsRequest req);

        // Emails a "company created" confirmation.
        Task SendWelcomeAsync(EmailCompanyWelcomeRequest req);
    }
}
