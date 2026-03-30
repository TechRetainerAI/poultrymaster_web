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
    }
}
