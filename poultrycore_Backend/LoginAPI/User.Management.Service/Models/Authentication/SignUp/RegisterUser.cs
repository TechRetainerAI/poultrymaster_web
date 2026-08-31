using System.ComponentModel.DataAnnotations;

namespace User.Management.Service.Models.Authentication.SignUp
{
    public class RegisterUser
    {
        // Optional: an owner may register with no company and create their first
        // company later in the Business Office.
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
        // Optional at signup. When present it must be one of the three types;
        // empty/null means "no company yet" (create it later in the Business Office).
        [RegularExpression("^(Poultry|Water|Generic|Hotel|Restaurant)?$",
            ErrorMessage = "CompanyType must be Poultry, Water, Generic, Hotel, or Restaurant.")]
        public string? CompanyType { get; set; }

        // Prompt 2 — the owner's Business Office (HQ). Optional so older clients
        // still register; stored on the owner's account (migration 118).
        public string? BusinessOfficeName { get; set; }
        public string? BusinessOfficeCurrency { get; set; }
        public string? BusinessOfficeCountry { get; set; }

        // Prompt 3 — owner-chosen Organization Code for OrgCode-based login.
        public string? OrganizationCode { get; set; }
    }
}
