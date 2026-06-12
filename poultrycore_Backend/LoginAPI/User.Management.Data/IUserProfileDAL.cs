using System.Threading.Tasks;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public interface IUserProfileDAL
    {
        Task<bool> CreateUserAsync(ApplicationUser user);
        Task<bool> DeleteUserByIdAsync(string userId);
        Task<ApplicationUser> FindByIdAsync(string userId);
        Task<ApplicationUser> FindByNameAsync(string normalizedUserName);
        Task<ApplicationUser> UpdateUserAsync(ApplicationUser user);
    }
}
