using System.ComponentModel.DataAnnotations;

namespace PoultryWeb.Models.Account
{
    public class ForgotPassword
    {
        [Required]
        [EmailAddress]
        public string Email { get; set; }
    }
}
