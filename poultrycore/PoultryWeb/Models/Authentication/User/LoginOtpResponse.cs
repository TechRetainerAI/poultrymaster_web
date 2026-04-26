
using Microsoft.AspNetCore.Identity;
//using User.Management.Data.Models;

namespace PoultryWeb.Models.Authentication.User
{
    public class LoginOtpResponse
    {
        public string Token { get; set; } = null!;
        public bool IsTwoFactorEnable { get; set; } 
        public ApplicationUser User { get; set; } = null!;
    }
}
