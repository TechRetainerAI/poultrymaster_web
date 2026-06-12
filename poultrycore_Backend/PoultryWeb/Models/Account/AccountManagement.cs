using System.ComponentModel.DataAnnotations;

namespace PoultryWeb.Models.Account
{
    public class AccountManagement
    {
        public string Username { get; set; }

        [Required]
        [EmailAddress]
        public string Email { get; set; }

        [Phone]
        public string PhoneNumber { get; set; }

        // Add other properties as needed
    }
}
