using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterProductService
    {
        Task<int> Insert(WaterProductModel model);
        Task Update(WaterProductModel model);
        Task<WaterProductModel?> GetById(int id, string farmId);
        Task<List<WaterProductModel>> GetAll(string farmId);
        Task Delete(int id, string farmId);
        Task<List<ProductReconcileRow>> ReconcileStockAsync(string farmId, int? productId);
        Task<decimal> SetStockAsync(int productId, ProductSetStockRequest req);
    }

    public interface IWaterCustomerService
    {
        Task<int> Insert(WaterCustomerModel model);
        Task Update(WaterCustomerModel model);
        Task<WaterCustomerModel?> GetById(int id, string farmId);
        Task<List<WaterCustomerModel>> GetAll(string farmId);
        Task Delete(int id, string farmId);
        // Migration 082: ensure the 3 system-managed default customers exist
        // for this farm (GeneralSales / GeneralDelivery / GeneralCredit).
        Task<List<WaterDefaultCustomerResult>> CreateDefaultsAsync(string farmId);
        Task<WaterCustomerModel?> GetDefaultAsync(string farmId, string defaultCustomerType);
    }

    public interface IWaterStockService
    {
        Task<int> AddTransaction(WaterStockTransactionModel model);
        Task<List<WaterStockTransactionModel>> GetTransactions(string farmId, int? productId);
    }

    public interface IWaterSaleService
    {
        Task<int> Create(CreateWaterSaleRequest req);
        Task<WaterSaleModel?> GetById(int id, string farmId);
        Task<List<WaterSaleModel>> GetAll(string farmId);
        Task Cancel(int id, string farmId);
        Task Delete(int id, string farmId);
    }

    public interface IWaterPaymentService
    {
        Task<int> Record(WaterPaymentModel model);
        Task<List<WaterPaymentModel>> GetBySale(int saleId, string farmId);
        Task<List<WaterPaymentModel>> GetAll(string farmId);
    }

    public interface IWaterDashboardService
    {
        Task<WaterDashboardSummaryModel> GetSummary(string farmId);
    }
}
