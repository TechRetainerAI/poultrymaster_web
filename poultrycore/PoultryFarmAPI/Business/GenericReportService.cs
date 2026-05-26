using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericReportService : IGenericReportService
    {
        private readonly string _connectionString;
        public GenericReportService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Dashboard - 4 result sets
        // ====================================================================
        public async Task<GenericDashboardModel> GetDashboardAsync(string farmId, DateTime? asOf)
        {
            var dash = new GenericDashboardModel();

            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_Dashboard", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AsOf", (object?)asOf ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            // RS 1: today
            if (await reader.ReadAsync())
            {
                dash.Today = new GenericDashboardToday
                {
                    TodaySales         = reader.GetDecimal(reader.GetOrdinal("TodaySales")),
                    TodayExpenses      = reader.GetDecimal(reader.GetOrdinal("TodayExpenses")),
                    TodayPurchasesPaid = reader.GetDecimal(reader.GetOrdinal("TodayPurchasesPaid")),
                    TodayGrossProfit   = reader.GetDecimal(reader.GetOrdinal("TodayGrossProfit")),
                    YesterdaySales     = reader.GetDecimal(reader.GetOrdinal("YesterdaySales")),
                    CashAtHand         = reader.GetDecimal(reader.GetOrdinal("CashAtHand")),
                    InventoryValue     = reader.GetDecimal(reader.GetOrdinal("InventoryValue")),
                    CustomerDebt       = reader.GetDecimal(reader.GetOrdinal("CustomerDebt")),
                    SupplierDebt       = reader.GetDecimal(reader.GetOrdinal("SupplierDebt")),
                };
            }

            // RS 2: week
            if (await reader.NextResultAsync() && await reader.ReadAsync())
            {
                dash.Week = new GenericDashboardWeek
                {
                    WeekSales          = reader.GetDecimal(reader.GetOrdinal("WeekSales")),
                    WeekExpenses       = reader.GetDecimal(reader.GetOrdinal("WeekExpenses")),
                    WeekPurchasesPaid  = reader.GetDecimal(reader.GetOrdinal("WeekPurchasesPaid")),
                    WeekGrossProfit    = reader.GetDecimal(reader.GetOrdinal("WeekGrossProfit")),
                    TopSellingItem     = reader.IsDBNull(reader.GetOrdinal("TopSellingItem")) ? null : reader.GetString(reader.GetOrdinal("TopSellingItem")),
                    TopSellingQuantity = reader.IsDBNull(reader.GetOrdinal("TopSellingQuantity")) ? 0 : reader.GetDecimal(reader.GetOrdinal("TopSellingQuantity")),
                    TopExpenseCategory = reader.IsDBNull(reader.GetOrdinal("TopExpenseCategory")) ? null : reader.GetString(reader.GetOrdinal("TopExpenseCategory")),
                    TopExpenseAmount   = reader.IsDBNull(reader.GetOrdinal("TopExpenseAmount")) ? 0 : reader.GetDecimal(reader.GetOrdinal("TopExpenseAmount")),
                };
            }

            // RS 3: cash accounts
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    dash.CashAccounts.Add(new GenericDashboardCashAccount
                    {
                        GenericCashAccountId = reader.GetInt32(reader.GetOrdinal("GenericCashAccountId")),
                        AccountName          = reader.GetString(reader.GetOrdinal("AccountName")),
                        AccountType          = reader.GetString(reader.GetOrdinal("AccountType")),
                        CurrentBalance       = reader.GetDecimal(reader.GetOrdinal("CurrentBalance")),
                        IsActive             = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    });
                }
            }

            // RS 4: alerts
            if (await reader.NextResultAsync() && await reader.ReadAsync())
            {
                dash.Alerts = new GenericDashboardAlerts
                {
                    LowStockCount        = reader.GetInt32(reader.GetOrdinal("LowStockCount")),
                    DraftSalesCount      = reader.GetInt32(reader.GetOrdinal("DraftSalesCount")),
                    DraftExpensesCount   = reader.GetInt32(reader.GetOrdinal("DraftExpensesCount")),
                    CustomersOwingCount  = reader.GetInt32(reader.GetOrdinal("CustomersOwingCount")),
                    SuppliersOwedCount   = reader.GetInt32(reader.GetOrdinal("SuppliersOwedCount")),
                    PendingClosingsCount = reader.GetInt32(reader.GetOrdinal("PendingClosingsCount")),
                };
            }

            return dash;
        }

        // ====================================================================
        // Period P&L
        // ====================================================================
        public async Task<GenericPeriodPnLModel> GetPeriodPnLAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_PeriodPnL", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return new GenericPeriodPnLModel { PeriodStart = fromDate, PeriodEnd = toDate };

            return new GenericPeriodPnLModel
            {
                PeriodStart        = reader.GetDateTime(reader.GetOrdinal("PeriodStart")),
                PeriodEnd          = reader.GetDateTime(reader.GetOrdinal("PeriodEnd")),
                TotalIncome        = reader.GetDecimal(reader.GetOrdinal("TotalIncome")),
                TotalExpenses      = reader.GetDecimal(reader.GetOrdinal("TotalExpenses")),
                CostOfGoodsSold    = reader.GetDecimal(reader.GetOrdinal("CostOfGoodsSold")),
                GrossProfit        = reader.GetDecimal(reader.GetOrdinal("GrossProfit")),
                NetProfit          = reader.GetDecimal(reader.GetOrdinal("NetProfit")),
                ProfitMarginPct    = reader.GetDecimal(reader.GetOrdinal("ProfitMarginPct")),
                TotalPurchasesPaid = reader.GetDecimal(reader.GetOrdinal("TotalPurchasesPaid")),
                SalesCount         = reader.GetInt32(reader.GetOrdinal("SalesCount")),
            };
        }

        // ====================================================================
        // Sales by product
        // ====================================================================
        public async Task<List<GenericSalesByProductRow>> GetSalesByProductAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var list = new List<GenericSalesByProductRow>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_SalesByProduct", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericSalesByProductRow
                {
                    GenericProductId = reader.IsDBNull(reader.GetOrdinal("GenericProductId")) ? null : reader.GetInt32(reader.GetOrdinal("GenericProductId")),
                    ProductName      = reader.GetString(reader.GetOrdinal("ProductName")),
                    SKU              = reader.IsDBNull(reader.GetOrdinal("SKU")) ? null : reader.GetString(reader.GetOrdinal("SKU")),
                    TotalQuantity    = reader.GetDecimal(reader.GetOrdinal("TotalQuantity")),
                    TotalRevenue     = reader.GetDecimal(reader.GetOrdinal("TotalRevenue")),
                    TotalCost        = reader.GetDecimal(reader.GetOrdinal("TotalCost")),
                    SalesCount       = reader.GetInt32(reader.GetOrdinal("SalesCount")),
                });
            }
            return list;
        }

        // ====================================================================
        // Sales by customer
        // ====================================================================
        public async Task<List<GenericSalesByCustomerRow>> GetSalesByCustomerAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var list = new List<GenericSalesByCustomerRow>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_SalesByCustomer", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericSalesByCustomerRow
                {
                    GenericCustomerId = reader.IsDBNull(reader.GetOrdinal("GenericCustomerId")) ? null : reader.GetInt32(reader.GetOrdinal("GenericCustomerId")),
                    CustomerName      = reader.GetString(reader.GetOrdinal("CustomerName")),
                    PhoneNumber       = reader.IsDBNull(reader.GetOrdinal("PhoneNumber")) ? null : reader.GetString(reader.GetOrdinal("PhoneNumber")),
                    SalesCount        = reader.GetInt32(reader.GetOrdinal("SalesCount")),
                    TotalRevenue      = reader.GetDecimal(reader.GetOrdinal("TotalRevenue")),
                    TotalPaid         = reader.GetDecimal(reader.GetOrdinal("TotalPaid")),
                    TotalOutstanding  = reader.GetDecimal(reader.GetOrdinal("TotalOutstanding")),
                });
            }
            return list;
        }

        // ====================================================================
        // Expenses by category
        // ====================================================================
        public async Task<List<GenericExpenseByCategoryRow>> GetExpensesByCategoryAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var list = new List<GenericExpenseByCategoryRow>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_ExpensesByCategory", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericExpenseByCategoryRow
                {
                    GenericExpenseCategoryId = reader.GetInt32(reader.GetOrdinal("GenericExpenseCategoryId")),
                    CategoryName             = reader.GetString(reader.GetOrdinal("CategoryName")),
                    ExpenseCount             = reader.GetInt32(reader.GetOrdinal("ExpenseCount")),
                    TotalAmount              = reader.GetDecimal(reader.GetOrdinal("TotalAmount")),
                });
            }
            return list;
        }

        // ====================================================================
        // Inventory value - 2 result sets
        // ====================================================================
        public async Task<GenericInventoryValueReport> GetInventoryValueAsync(string farmId)
        {
            var report = new GenericInventoryValueReport();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_InventoryValue", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                report.ByCategory.Add(new GenericInventoryValueRow
                {
                    GenericProductCategoryId = reader.IsDBNull(reader.GetOrdinal("GenericProductCategoryId")) ? null : reader.GetInt32(reader.GetOrdinal("GenericProductCategoryId")),
                    CategoryName             = reader.GetString(reader.GetOrdinal("CategoryName")),
                    ProductCount             = reader.GetInt32(reader.GetOrdinal("ProductCount")),
                    TotalUnits               = reader.GetDecimal(reader.GetOrdinal("TotalUnits")),
                    TotalCostValue           = reader.GetDecimal(reader.GetOrdinal("TotalCostValue")),
                    TotalRetailValue         = reader.GetDecimal(reader.GetOrdinal("TotalRetailValue")),
                });
            }

            if (await reader.NextResultAsync() && await reader.ReadAsync())
            {
                report.TotalCostValue   = reader.GetDecimal(reader.GetOrdinal("TotalCostValue"));
                report.TotalRetailValue = reader.GetDecimal(reader.GetOrdinal("TotalRetailValue"));
                report.ProductCount    = reader.GetInt32(reader.GetOrdinal("ProductCount"));
            }

            return report;
        }

        // ====================================================================
        // Cash summary - 2 result sets
        // ====================================================================
        public async Task<GenericCashSummaryReport> GetCashSummaryAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var report = new GenericCashSummaryReport();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericReport_CashSummary", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                report.Accounts.Add(new GenericCashSummaryRow
                {
                    GenericCashAccountId = reader.GetInt32(reader.GetOrdinal("GenericCashAccountId")),
                    AccountName          = reader.GetString(reader.GetOrdinal("AccountName")),
                    AccountType          = reader.GetString(reader.GetOrdinal("AccountType")),
                    CurrentBalance       = reader.GetDecimal(reader.GetOrdinal("CurrentBalance")),
                    PeriodCashIn         = reader.GetDecimal(reader.GetOrdinal("PeriodCashIn")),
                    PeriodCashOut        = reader.GetDecimal(reader.GetOrdinal("PeriodCashOut")),
                    IsActive             = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                });
            }

            if (await reader.NextResultAsync() && await reader.ReadAsync())
            {
                report.TotalCashAtHand = reader.GetDecimal(reader.GetOrdinal("TotalCashAtHand"));
            }

            return report;
        }
    }
}
