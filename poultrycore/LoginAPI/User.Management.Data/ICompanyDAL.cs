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
        Task UpdateAsync(string farmId, CreateCompanyRequest req);
    }
}
