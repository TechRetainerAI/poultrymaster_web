using Microsoft.AspNetCore.Identity;
//using User.Management.Data.Models;

namespace PoultryWeb.Models.Authentication.User
{
    public class CreateUserResponse
    {
        public string Token { get; set; }=null!;
        public ApplicationUser User { get; set; } = null!;

    }
   

}
