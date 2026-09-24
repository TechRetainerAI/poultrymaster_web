using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelEmployeeLoanService
    {
        Task<List<HotelEmployeeLoanModel>> GetAllAsync(string farmId, string? status, int? staffId);
        Task<HotelEmployeeLoanModel?> GetByIdAsync(int id, string farmId);
        Task<int> CreateAsync(HotelEmployeeLoanCreateRequest req, string? createdBy);
        Task UpdateAsync(int id, HotelEmployeeLoanUpdateRequest req, string? by);
        Task DisburseAsync(int id, string farmId, int? cashAccountId, DateTime? date, string? reference, string? by);
        Task CancelAsync(int id, string farmId, string? reason, string? by);
        Task ReverseAsync(int id, string farmId, string? reason, string? by);
        /// <summary>One loan's repayments, or every repayment of the hotel when loanId is null.</summary>
        Task<List<HotelEmployeeLoanRepaymentModel>> GetRepaymentsAsync(int? loanId, string farmId);
        Task<int> RecordRepaymentAsync(HotelEmployeeLoanRepaymentRequest req, string? createdBy);
        Task ReverseRepaymentAsync(int repaymentId, string farmId, string? reason, string? by);
        Task<HotelEmployeeLoanSummaryModel> GetSummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<HotelEmployeeLoanEligibleModel>> GetEligibleAsync(string farmId, int staffId, int? excludeItemId);
        Task<List<HotelEmployeeLoanStaffReportRow>> GetStaffReportAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<HotelPayrollDeductionModel>> GetPayrollDeductionsAsync(string farmId, int runId);
    }
}
