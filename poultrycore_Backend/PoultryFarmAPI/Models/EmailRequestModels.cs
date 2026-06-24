namespace PoultryFarmAPIWeb.Models
{
    // Request models for the Email endpoints. Kept in the Models layer (not the
    // controller) so the controller stays a thin HTTP boundary.

    // Multipart form body for POST /api/Email/Report.
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
        public string? SenderName { get; set; }
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
