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
        Task UpdateAsync(string farmId, CreateCompanyRequest req);
    }
}
