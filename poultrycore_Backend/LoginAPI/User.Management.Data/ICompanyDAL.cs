using System.Collections.Generic;
using System.Threading.Tasks;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public interface ICompanyDAL
    {
        Task<CompanyResponse> CreateAsync(string farmId, CreateCompanyRequest req, string ownerUserId);
        Task<List<CompanyResponse>> GetByUserIdAsync(string userId);
        Task<CompanyResponse?> GetByIdAsync(string farmId, string userId);
        Task<bool> IsMemberAsync(string userId, string farmId);
        // Idempotently links a user to a farm in UserFarms (the table /Companies/mine
        // joins on). Used when creating staff employees so the new user resolves to
        // their company — and the right dashboard — at login.
        Task AddMemberAsync(string userId, string farmId, string role);
        // Doc 3 §6-7: revoke a user's access to a company (removes the UserFarms row).
        Task RemoveMemberAsync(string userId, string farmId);
        // Doc 3 §7: user ids granted access to a company (access-based employee list).
        Task<List<string>> GetMemberUserIdsAsync(string farmId);
        Task UpdateAsync(string farmId, CreateCompanyRequest req);
        Task<bool> DeleteAsync(string farmId, string userId);
    }
}
