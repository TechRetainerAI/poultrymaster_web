using System.ComponentModel.DataAnnotations;

namespace PoultryWeb.Models.Account
{
    public class ChangeEmail
    {
        [Required]
        [EmailAddress]
        [Display(Name = "New Email")]
        public string Email { get; set; }
    }
}
