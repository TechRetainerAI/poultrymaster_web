using PoultryWeb.Models;
using PoultryWeb.Models;
using System.Security.Claims;

namespace PoultryWeb.Business
{
    public class UserService : IUserService
    {
        private readonly IHttpContextAccessor _httpContextAccessor;

        public UserService(IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
        }

        public AppUser GetUser()
        {
            // Access the current user from HttpContext
            var user = _httpContextAccessor.HttpContext.User;
        
            // Extract necessary user information from claims
            var userName = user.Claims.FirstOrDefault(c => c.Type == ClaimTypes.Name)?.Value;
            var userId = user.Claims.FirstOrDefault(c => c.Type == ClaimTypes.NameIdentifier)?.Value;
            var userEmail = user.Claims.FirstOrDefault(c => c.Type == ClaimTypes.Email)?.Value;
            var accessToken = user.Claims.FirstOrDefault(c => c.Type == "AccessToken")?.Value;

            //TODO: Either create a column in db to store this, or use a different model completely here and not the AppUser.
            //var isSubscriber = Convert.ToBoolean(user.Claims.FirstOrDefault(c => c.Type == "isSubscriber")?.Value);   

            // Prepare and return the user profile view model
            return new AppUser
            {
                UserName = userName,
                Email = userEmail,
                Id = userId //,
                //isSubscriber = isSubscriber
            };
        }
    }

}
