using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace User.Management.Service.Models.Authentication.User
{
    public class LoginResponse
    {
        public TokenType AccessToken { get; set; }
        public TokenType RefreshToken { get; set; }

        //Newly added
        public string UserId { get; set; } // Required for OTP verification
        public string Username { get; set; }

        public bool IsStaff { get; set; }       // 👈 Added: tells if user is staff
        public string FarmId { get; set; }      // 👈 Added: tells which farm user belongs to
        public string FarmName { get; set; }
        public bool IsSubscriber { get; set; }
        public bool IsAdmin { get; set; }
        public string? AdminTitle { get; set; }
        public Dictionary<string, bool>? Permissions { get; set; }
        public Dictionary<string, bool>? FeaturePermissions { get; set; }
    }

    public class Otp
    {
        public string UserId { get; set; }
        public string UserName { get; set; }
        [Required]
        public string OtpCode { get; set; }
    }
}
