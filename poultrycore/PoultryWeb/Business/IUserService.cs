using PoultryWeb.Models;
using System.Security.Claims;

namespace PoultryWeb.Business
{
    public interface IUserService
    {
        Models.AppUser GetUser();
        //AppUser GetUser(ClaimsPrincipal user);
    }
}
