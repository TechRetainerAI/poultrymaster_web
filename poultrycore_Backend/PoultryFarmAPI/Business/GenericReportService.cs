using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public partial class GenericReportService : IGenericReportService
    {
        private readonly string _connectionString;
        public GenericReportService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Dashboard - 4 result sets
        // ====================================================================
        public async Task<GenericDashboardModel> GetDashboardAsync(string farmId, DateTime? asOf)
        {
            var dash = new GenericDashboardModel();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_dashboard_rs1(p_farmid => @FarmId::text, p_asof => @AsOf::timestamp); SELECT * FROM spgenericreport_dashboard_rs2(p_farmid => @FarmId::text, p_asof => @AsOf::timestamp); SELECT * FROM spgenericreport_dashboard_rs3(p_farmid => @FarmId::text, p_asof => @AsOf::timestamp); SELECT * FROM spgenericreport_dashboard_rs4(p_farmid => @FarmId::text, p_asof => @AsOf::timestamp)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_periodpnl(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_salesbyproduct(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_salesbycustomer(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_expensesbycategory(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_inventoryvalue_rs1(p_farmid => @FarmId::text); SELECT * FROM spgenericreport_inventoryvalue_rs2(p_farmid => @FarmId::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_cashsummary_rs1(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date); SELECT * FROM spgenericreport_cashsummary_rs2(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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

        // ====================================================================
        // Financial Impact Preview (migration 442)
        // ====================================================================
        public async Task<GenericFinancialPreviewModel> GetFinancialPreviewAsync(
            string farmId, int productId, decimal quantity, string transactionType)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericitem_financialpreview(" +
                "p_farmid => @FarmId::text, p_genericproductid => @ProductId::int, " +
                "p_quantity => @Quantity::numeric, p_transactiontype => @TransactionType::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ProductId", productId);
            cmd.Parameters.AddWithValue("@Quantity", quantity);
            cmd.Parameters.AddWithValue("@TransactionType", transactionType);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new GenericFinancialPreviewModel();

            return new GenericFinancialPreviewModel
            {
                ProductName     = r.IsDBNull(r.GetOrdinal("ProductName")) ? "" : r.GetString(r.GetOrdinal("ProductName")),
                TransactionType = r.IsDBNull(r.GetOrdinal("TransactionType")) ? "" : r.GetString(r.GetOrdinal("TransactionType")),
                Quantity        = r.GetDecimal(r.GetOrdinal("Quantity")),
                UnitCost        = r.GetDecimal(r.GetOrdinal("UnitCost")),
                TotalCost       = r.GetDecimal(r.GetOrdinal("TotalCost")),
                InventoryChange = r.GetDecimal(r.GetOrdinal("InventoryChange")),
                RevenueEffect   = r.GetDecimal(r.GetOrdinal("RevenueEffect")),
                COGSEffect      = r.GetDecimal(r.GetOrdinal("COGSEffect")),
                ExpenseEffect   = r.GetDecimal(r.GetOrdinal("ExpenseEffect")),
                CashEffect      = r.GetDecimal(r.GetOrdinal("CashEffect")),
                SupplierEffect  = r.GetDecimal(r.GetOrdinal("SupplierEffect")),
                CurrentStock    = r.GetDecimal(r.GetOrdinal("CurrentStock")),
                StockAfter      = r.GetDecimal(r.GetOrdinal("StockAfter")),
                ExpenseCategory = r.IsDBNull(r.GetOrdinal("ExpenseCategory")) ? null : r.GetString(r.GetOrdinal("ExpenseCategory")),
                Notes           = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            };
        }

        // ====================================================================
        // P&L Breakdown (migration 442)
        // ====================================================================
        public async Task<GenericPnLBreakdownModel> GetPnLBreakdownAsync(
            string farmId, DateTime fromDate, DateTime toDate)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericreport_pnl_breakdown(" +
                "p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", fromDate);
            cmd.Parameters.AddWithValue("@To", toDate);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new GenericPnLBreakdownModel();

            return new GenericPnLBreakdownModel
            {
                TotalIncome         = r.GetDecimal(r.GetOrdinal("TotalIncome")),
                CostOfGoodsSold     = r.GetDecimal(r.GetOrdinal("CostOfGoodsSold")),
                GrossProfit         = r.GetDecimal(r.GetOrdinal("GrossProfit")),
                InternalUseExpenses = r.GetDecimal(r.GetOrdinal("InternalUseExpenses")),
                OperatingExpenses   = r.GetDecimal(r.GetOrdinal("OperatingExpenses")),
                PayrollExpenses     = r.GetDecimal(r.GetOrdinal("PayrollExpenses")),
                TotalExpenses       = r.GetDecimal(r.GetOrdinal("TotalExpenses")),
                NetProfit           = r.GetDecimal(r.GetOrdinal("NetProfit")),
                ProfitMarginPct     = r.GetDecimal(r.GetOrdinal("ProfitMarginPct")),
                SalesCount          = r.GetInt32(r.GetOrdinal("SalesCount")),
                InternalUseCount    = r.GetInt32(r.GetOrdinal("InternalUseCount")),
            };
        }

        // ====================================================================
        // Item Cost Reconciliation (migration 442)
        // ====================================================================
        public async Task<GenericItemCostReconciliationModel> GetItemCostReconciliationAsync(
            string farmId, int productId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericitem_costreconciliation(" +
                "p_farmid => @FarmId::text, p_genericproductid => @ProductId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ProductId", productId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new GenericItemCostReconciliationModel();

            return new GenericItemCostReconciliationModel
            {
                ProductName            = r.IsDBNull(r.GetOrdinal("ProductName")) ? "" : r.GetString(r.GetOrdinal("ProductName")),
                TotalPurchasedQty      = r.GetDecimal(r.GetOrdinal("TotalPurchasedQty")),
                TotalPurchasedCost     = r.GetDecimal(r.GetOrdinal("TotalPurchasedCost")),
                TotalProducedQty       = r.GetDecimal(r.GetOrdinal("TotalProducedQty")),
                TotalProducedCost      = r.GetDecimal(r.GetOrdinal("TotalProducedCost")),
                SoldQty                = r.GetDecimal(r.GetOrdinal("SoldQty")),
                SoldCost               = r.GetDecimal(r.GetOrdinal("SoldCost")),
                InternalUseQty         = r.GetDecimal(r.GetOrdinal("InternalUseQty")),
                InternalUseCost        = r.GetDecimal(r.GetOrdinal("InternalUseCost")),
                ProductionConsumedQty  = r.GetDecimal(r.GetOrdinal("ProductionConsumedQty")),
                ProductionConsumedCost = r.GetDecimal(r.GetOrdinal("ProductionConsumedCost")),
                AdjustmentQty          = r.GetDecimal(r.GetOrdinal("AdjustmentQty")),
                RemainingQty           = r.GetDecimal(r.GetOrdinal("RemainingQty")),
                RemainingCostBasis     = r.GetDecimal(r.GetOrdinal("RemainingCostBasis")),
                CostReconciled         = r.GetBoolean(r.GetOrdinal("CostReconciled")),
            };
        }

        // ====================================================================
        // Phase 5: Inventory Balance (migration 443)
        // ====================================================================
        public async Task<List<GenericInventoryBalanceRow>> GetInventoryBalanceAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var list = new List<GenericInventoryBalanceRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_inventorybalance(p_farmid => @F::text, p_from => @From::date, p_to => @To::date)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@From", fromDate);
            cmd.Parameters.AddWithValue("@To", toDate);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericInventoryBalanceRow
            {
                GenericProductId = r.GetInt32(r.GetOrdinal("GenericProductId")),
                ProductName      = r.GetString(r.GetOrdinal("ProductName")),
                CategoryName     = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
                Purpose          = r.IsDBNull(r.GetOrdinal("Purpose")) ? null : r.GetString(r.GetOrdinal("Purpose")),
                UnitOfMeasure    = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                OpeningQty       = r.GetDecimal(r.GetOrdinal("OpeningQty")),
                PurchasesQty     = r.GetDecimal(r.GetOrdinal("PurchasesQty")),
                ProductionInQty  = r.GetDecimal(r.GetOrdinal("ProductionInQty")),
                ReturnsInQty     = r.GetDecimal(r.GetOrdinal("ReturnsInQty")),
                SalesQty         = r.GetDecimal(r.GetOrdinal("SalesQty")),
                InternalUseQty   = r.GetDecimal(r.GetOrdinal("InternalUseQty")),
                ProductionOutQty = r.GetDecimal(r.GetOrdinal("ProductionOutQty")),
                DamageQty        = r.GetDecimal(r.GetOrdinal("DamageQty")),
                AdjustmentQty    = r.GetDecimal(r.GetOrdinal("AdjustmentQty")),
                OtherQty         = r.GetDecimal(r.GetOrdinal("OtherQty")),
                ClosingQty       = r.GetDecimal(r.GetOrdinal("ClosingQty")),
                UnitCost         = r.GetDecimal(r.GetOrdinal("UnitCost")),
                InventoryValue   = r.GetDecimal(r.GetOrdinal("InventoryValue")),
            });
            return list;
        }

        // ====================================================================
        // Phase 5: Internal Consumption Report (migration 443)
        // ====================================================================
        public async Task<List<GenericConsumptionRow>> GetInternalConsumptionAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? category)
        {
            var list = new List<GenericConsumptionRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_internalconsumption(p_farmid => @F::text, p_from => @From::date, p_to => @To::date, p_category => @Cat::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@From", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@To", (object?)toDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", (object?)category ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericConsumptionRow
            {
                UsageDate              = r.GetDateTime(r.GetOrdinal("UsageDate")),
                GenericProductId       = r.GetInt32(r.GetOrdinal("GenericProductId")),
                ProductName            = r.GetString(r.GetOrdinal("ProductName")),
                CategoryName           = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
                QuantityUsed           = r.GetDecimal(r.GetOrdinal("QuantityUsed")),
                UnitOfMeasure          = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                UnitCost               = r.GetDecimal(r.GetOrdinal("UnitCost")),
                TotalCost              = r.GetDecimal(r.GetOrdinal("TotalCost")),
                ExpenseCategory        = r.IsDBNull(r.GetOrdinal("ExpenseCategory")) ? null : r.GetString(r.GetOrdinal("ExpenseCategory")),
                Reason                 = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
                ReferenceNumber        = r.IsDBNull(r.GetOrdinal("ReferenceNumber")) ? null : r.GetString(r.GetOrdinal("ReferenceNumber")),
                RecordedBy             = r.IsDBNull(r.GetOrdinal("RecordedBy")) ? null : r.GetString(r.GetOrdinal("RecordedBy")),
                Status                 = r.IsDBNull(r.GetOrdinal("Status")) ? null : r.GetString(r.GetOrdinal("Status")),
                GenericInternalUsageId = r.GetInt32(r.GetOrdinal("GenericInternalUsageId")),
            });
            return list;
        }

        public async Task<GenericConsumptionSummary> GetConsumptionSummaryAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_consumptionsummary(p_farmid => @F::text, p_from => @From::date, p_to => @To::date)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@From", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@To", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new GenericConsumptionSummary();
            return new GenericConsumptionSummary
            {
                TotalConsumptionCost = r.GetDecimal(r.GetOrdinal("TotalConsumptionCost")),
                TotalItemsConsumed   = r.GetInt32(r.GetOrdinal("TotalItemsConsumed")),
                TotalRecords         = r.GetInt32(r.GetOrdinal("TotalRecords")),
                TopItemName          = r.IsDBNull(r.GetOrdinal("TopItemName")) ? null : r.GetString(r.GetOrdinal("TopItemName")),
                TopItemCost          = r.GetDecimal(r.GetOrdinal("TopItemCost")),
                CategoryBreakdown    = r.IsDBNull(r.GetOrdinal("CategoryBreakdown")) ? null : r.GetString(r.GetOrdinal("CategoryBreakdown")),
            };
        }

        // ====================================================================
        // Phase 5: Inventory Reconciliation (migration 443)
        // ====================================================================
        public async Task<List<GenericReconciliationRow>> GetInventoryReconciliationAsync(string farmId)
        {
            var list = new List<GenericReconciliationRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_inventoryreconciliation(p_farmid => @F::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericReconciliationRow
            {
                GenericProductId = r.GetInt32(r.GetOrdinal("GenericProductId")),
                ProductName      = r.GetString(r.GetOrdinal("ProductName")),
                LedgerTotal      = r.GetDecimal(r.GetOrdinal("LedgerTotal")),
                CachedStock      = r.GetDecimal(r.GetOrdinal("CachedStock")),
                Drift            = r.GetDecimal(r.GetOrdinal("Drift")),
                IsReconciled     = r.GetBoolean(r.GetOrdinal("IsReconciled")),
            });
            return list;
        }

        // ====================================================================
        // Phase 5: Restock Forecast (migration 443)
        // ====================================================================
        public async Task<List<GenericRestockForecastRow>> GetRestockForecastAsync(string farmId, int lookbackDays)
        {
            var list = new List<GenericRestockForecastRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericreport_restockforecast(p_farmid => @F::text, p_lookback => @L::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@L", lookbackDays);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new GenericRestockForecastRow
            {
                GenericProductId      = r.GetInt32(r.GetOrdinal("GenericProductId")),
                ProductName           = r.GetString(r.GetOrdinal("ProductName")),
                CurrentStock          = r.GetDecimal(r.GetOrdinal("CurrentStock")),
                MinimumStockAlert     = r.GetDecimal(r.GetOrdinal("MinimumStockAlert")),
                UnitOfMeasure         = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                AvgDailySales         = r.GetDecimal(r.GetOrdinal("AvgDailySales")),
                AvgDailyInternalUse   = r.GetDecimal(r.GetOrdinal("AvgDailyInternalUse")),
                AvgDailyProduction    = r.GetDecimal(r.GetOrdinal("AvgDailyProduction")),
                AvgDailyOtherOut      = r.GetDecimal(r.GetOrdinal("AvgDailyOtherOut")),
                AvgDailyTotalOut      = r.GetDecimal(r.GetOrdinal("AvgDailyTotalOut")),
                DaysUntilStockout     = r.GetDecimal(r.GetOrdinal("DaysUntilStockout")),
                DaysUntilReorderPoint = r.GetDecimal(r.GetOrdinal("DaysUntilReorderPoint")),
                SuggestedReorderQty   = r.GetDecimal(r.GetOrdinal("SuggestedReorderQty")),
                UrgencyLevel          = r.GetString(r.GetOrdinal("UrgencyLevel")),
            });
            return list;
        }
    }
}
