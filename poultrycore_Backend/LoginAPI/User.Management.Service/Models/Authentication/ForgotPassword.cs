using System.ComponentModel.DataAnnotations;

namespace User.Management.Service.Models.Authentication
{
    public class ForgotPassword
    {
        [Required]
        [EmailAddress]
        public string Email { get; set; }
    }
}
