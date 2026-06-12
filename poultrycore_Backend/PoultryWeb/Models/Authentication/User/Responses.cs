using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace PoultryWeb.Models.Authentication.User
{
    //public class LoginResponse
    //{
    //    public bool IsSuccess { get; set; }
    //    public string Token { get; set; }
    //    public string Message { get; set; }
    //}

    public class RegisterResponse
    {
        public bool IsSuccess { get; set; }
        public string Message { get; set; }
    }

    public class BaseResponse
    {
        public string Status { get; set; }
        public string Message { get; set; }
        public bool IsSuccess { get; set; }
    }

    public class RefreshTokenResponse
    {
        public string AccessToken { get; set; }
        public string RefreshToken { get; set; }
        public bool IsSuccess { get; set; }
    }
}
