using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IAuditLogService
    {
        Task<List<AuditLogModel>> GetAllAsync(string? userId, string? farmId, string? status, DateTime? startDate, DateTime? endDate, int page, int pageSize);
        Task<List<AuditLogModel>> GetPlatformRecentAsync(int take);
        Task<AuditLogModel?> GetByIdAsync(string id);
        Task<string> InsertAsync(AuditLogModel log);
        Task<(string Database, int RowCount)> GetDebugInfoAsync();
    }
}


