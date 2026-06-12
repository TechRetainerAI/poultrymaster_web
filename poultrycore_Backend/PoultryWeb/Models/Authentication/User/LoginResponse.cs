using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace PoultryWeb.Models.Authentication.User
{
    public class LoginResponse
    {
        public bool IsSuccess { get; set; }
        public string Message { get; set; }
        public int StatusCode { get; set; }
        public bool RequiresTwoFactor { get; set; }
        public ResponseData Response { get; set; }
        public string UserId { get; set; } // Required for OTP verification
        public string Username { get; set; }
        public bool IsStaff { get; set; }       // 👈 Added: tells if user is staff
        public string FarmId { get; set; }      // 👈 Added: tells which farm user belongs to
        public string FarmName { get; set; }      // 👈 Added: tells the farm name user belongs to
        public bool IsSubscriber { get; set; }
    }

    public class Otp
    {
        public string UserId { get; set; }
        public string UserName { get; set; }
        [Required]
        public string OtpCode { get; set; }
    }
    public class ResponseData
    {
        public TokenType AccessToken { get; set; }
        public TokenType RefreshToken { get; set; }
        public string UserId { get; set; } // Required for OTP verification
        public string Username { get; set; }

        public bool IsStaff { get; set; }       // 👈 Added: tells if user is staff
        public string FarmId { get; set; }      // 👈 Added: tells which farm user belongs to
        public string FarmName { get; set; }      // 👈 Added: tells the farm name user belongs to
        public bool IsSubscriber { get; set; }
    }

}
