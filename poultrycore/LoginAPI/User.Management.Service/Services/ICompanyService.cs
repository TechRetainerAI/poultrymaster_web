using System.Collections.Generic;
using System.Threading.Tasks;
using User.Management.Data.Models;
using User.Management.Service.Models;
using User.Management.Service.Models.Authentication.User;

namespace User.Management.Service.Services
{
    public interface ICompanyService
    {
        Task<ApiResponse<List<CompanyResponse>>> GetMineAsync(string userId);

        Task<ApiResponse<CompanyResponse>> CreateAsync(string userId, CreateCompanyRequest req);

        // Switch the user's active farm; persists the new FarmId/FarmName on the
        // AspNetUsers row and re-issues a JWT with updated claims.
        Task<ApiResponse<LoginResponse>> SwitchAsync(string userId, string targetFarmId);
    }
}
