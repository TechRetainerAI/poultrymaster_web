using System.ComponentModel.DataAnnotations;

namespace User.Management.Service.Models.Authentication.SignUp
{
    public class RegisterUser
    {
        [Required(ErrorMessage = "FarmName  is required")]
        public string? FarmName { get; set; }

        [Required(ErrorMessage = "User Name is required")]
        public string? Username { get; set; }

        [EmailAddress]
        [Required(ErrorMessage = "Email is required")]
        public string? Email { get; set; }

        [Required(ErrorMessage = "Password is required")]
        public string? Password { get; set; }

        [Required(ErrorMessage = "FirstName is required")]
        public string FirstName { get; set; }

        [Required(ErrorMessage = "LastName is required")]
        public string LastName { get; set; }

        public List<string>? Roles { get; set; } = new List<string>();
        public string PhoneNumber { get; set; }

        // Must be Poultry / Water / Generic. The previous "optional, defaults to Poultry"
        // shim hid a real bug: stale frontends or JSON-case mismatches silently
        // created Poultry farms regardless of what the user picked.
        [Required(ErrorMessage = "CompanyType is required (Poultry, Water, or Generic).")]
        [RegularExpression("^(Poultry|Water|Generic)$",
            ErrorMessage = "CompanyType must be Poultry, Water, or Generic.")]
        public string? CompanyType { get; set; }

        // Prompt 2 — the owner's Business Office (HQ). Optional so older clients
        // still register; stored on the owner's account (migration 118).
        public string? BusinessOfficeName { get; set; }
        public string? BusinessOfficeCurrency { get; set; }
        public string? BusinessOfficeCountry { get; set; }
    }
}
