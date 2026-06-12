using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericInventoryService
    {
        // Stock movements (read-only here; writes happen via sales/purchases/
        // adjustments in their own services).
        Task<List<GenericStockMovementModel>> GetMovementsForProductAsync(int productId, string farmId);
        Task<List<GenericStockMovementModel>> GetMovementsForFarmAsync(string farmId, DateTime? fromDate, DateTime? toDate);

        // Stock adjustments (full approval workflow)
        Task<List<GenericStockAdjustmentModel>> GetAdjustmentsAsync(string farmId, string? status);
        Task<GenericStockAdjustmentModel?> GetAdjustmentByIdAsync(int id, string farmId);
        Task<int> InsertAdjustmentAsync(GenericStockAdjustmentModel m);
        Task SubmitAdjustmentAsync(int id, string farmId);
        Task ApproveAdjustmentAsync(int id, string farmId, string? approvedBy);
        Task RejectAdjustmentAsync(int id, string farmId, string rejectionReason, string? approvedBy);
    }
}
