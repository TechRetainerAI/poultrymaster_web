using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.ComponentModel.DataAnnotations;
using System.Net;
using User.Management.Service.Models;
using User.Management.Service.Services;

namespace User.Management.API.Controllers
{
    // Public contact-form endpoint. Marketing sites (e.g. techretainer.com) POST here
    // and the shared Resend-backed EmailService delivers the enquiry — so no static site
    // needs its own Resend API key. CORS for techretainer.com is already allowed in
    // Program.cs ("AllowOrigin"). Anonymous by design.
    [Route("api/[controller]")]
    [ApiController]
    [AllowAnonymous]
    public class ContactController : ControllerBase
    {
        private readonly IEmailService _emailService;
        private readonly IConfiguration _config;
        private readonly ILogger<ContactController> _logger;

        public ContactController(IEmailService emailService, IConfiguration config, ILogger<ContactController> logger)
        {
            _emailService = emailService;
            _config = config;
            _logger = logger;
        }

        public class ContactRequest
        {
            public string? Name { get; set; }
            public string? Email { get; set; }
            public string? Company { get; set; }
            public string? Message { get; set; }
            public string? Source { get; set; } // optional: which site/form sent it
        }

        [HttpPost]
        public IActionResult Post([FromBody] ContactRequest req)
        {
            if (req is null
                || string.IsNullOrWhiteSpace(req.Name)
                || string.IsNullOrWhiteSpace(req.Email)
                || string.IsNullOrWhiteSpace(req.Message))
                return BadRequest(new { error = "Please provide your name, email and message." });

            if (!new EmailAddressAttribute().IsValid(req.Email))
                return BadRequest(new { error = "Please enter a valid email address." });

            // Where enquiries land. Override with ContactInbox env/appsettings if needed.
            var inbox = _config["ContactInbox"];
            if (string.IsNullOrWhiteSpace(inbox)) inbox = "info@techretainer.com";
            var source = string.IsNullOrWhiteSpace(req.Source) ? "the website" : req.Source!.Trim();

            string Enc(string? s) => WebUtility.HtmlEncode(s ?? string.Empty);
            var subject = $"New enquiry from {req.Name}"
                        + (string.IsNullOrWhiteSpace(req.Company) ? string.Empty : $" ({req.Company})");
            var html =
                $"<h2 style=\"font-family:sans-serif\">New enquiry from {Enc(source)}</h2>" +
                $"<p style=\"font-family:sans-serif\"><b>Name:</b> {Enc(req.Name)}</p>" +
                $"<p style=\"font-family:sans-serif\"><b>Email:</b> {Enc(req.Email)}</p>" +
                $"<p style=\"font-family:sans-serif\"><b>Company:</b> {(string.IsNullOrWhiteSpace(req.Company) ? "—" : Enc(req.Company))}</p>" +
                $"<p style=\"font-family:sans-serif\"><b>Message:</b><br>{Enc(req.Message).Replace("\n", "<br>")}</p>" +
                $"<hr><p style=\"font-family:sans-serif;color:#666\">Reply directly to {Enc(req.Email)}.</p>";

            try
            {
                _emailService.SendEmail(new Message(new[] { inbox! }, subject, html));
                return Ok(new { ok = true });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Contact form send failed");
                return StatusCode(502, new
                {
                    error = "Could not send your message right now. Please email info@techretainer.com directly.",
                    detail = ex.Message,
                });
            }
        }
    }
}
