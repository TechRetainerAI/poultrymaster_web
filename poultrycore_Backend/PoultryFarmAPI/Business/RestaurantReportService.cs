using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantReportService : IRestaurantReportService
    {
        private readonly string _cs;
        public RestaurantReportService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };

        public async Task<DailySalesReport> GetDailySalesAsync(string farmId, DateTime date)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_daily_sales(p_farmid=>@F::text,p_date=>@D::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@D", date);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                TotalOrders = r.GetInt64(0), CompletedOrders = r.GetInt64(1), CancelledOrders = r.GetInt64(2),
                TotalRevenue = r.GetDecimal(3), TotalDiscount = r.GetDecimal(4), TotalTax = r.GetDecimal(5),
                TotalServiceCharge = r.GetDecimal(6), NetRevenue = r.GetDecimal(7),
                AvgTicket = r.GetDecimal(8), TotalCovers = r.GetInt64(9),
                DineInCount = r.GetInt64(10), DineInRevenue = r.GetDecimal(11),
                TakeawayCount = r.GetInt64(12), TakeawayRevenue = r.GetDecimal(13),
                DeliveryCount = r.GetInt64(14), DeliveryRevenue = r.GetDecimal(15),
                CashAmount = r.GetDecimal(16), CardAmount = r.GetDecimal(17),
                MobileAmount = r.GetDecimal(18), OtherAmount = r.GetDecimal(19),
            };
            return new();
        }

        public async Task<List<SalesByItemRow>> GetSalesByItemAsync(string farmId, DateTime from, DateTime to)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_sales_by_item(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@A", from); cmd.Parameters.AddWithValue("@B", to);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<SalesByItemRow>();
            while (await r.ReadAsync()) l.Add(new() { MenuItemId = r.GetInt32(0), ItemName = r.GetString(1), QuantitySold = r.GetInt64(2), TotalRevenue = r.GetDecimal(3), AvgPrice = r.GetDecimal(4), OrderCount = r.GetInt64(5) });
            return l;
        }

        public async Task<List<SalesByCategoryRow>> GetSalesByCategoryAsync(string farmId, DateTime from, DateTime to)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_sales_by_category(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@A", from); cmd.Parameters.AddWithValue("@B", to);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<SalesByCategoryRow>();
            while (await r.ReadAsync()) l.Add(new() { CategoryName = r.GetString(0), ItemCount = r.GetInt64(1), QuantitySold = r.GetInt64(2), TotalRevenue = r.GetDecimal(3) });
            return l;
        }

        public async Task<List<SalesByHourRow>> GetSalesByHourAsync(string farmId, DateTime date)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_sales_by_hour(p_farmid=>@F::text,p_date=>@D::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@D", date);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<SalesByHourRow>();
            while (await r.ReadAsync()) l.Add(new() { HourOfDay = r.GetInt32(0), OrderCount = r.GetInt64(1), TotalRevenue = r.GetDecimal(2), AvgTicket = r.GetDecimal(3) });
            return l;
        }

        public async Task<List<RevenueTrendRow>> GetRevenueTrendAsync(string farmId, DateTime from, DateTime to)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_revenue_trend(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@A", from); cmd.Parameters.AddWithValue("@B", to);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<RevenueTrendRow>();
            while (await r.ReadAsync()) l.Add(new() { ReportDate = r.GetDateTime(0), OrderCount = r.GetInt64(1), TotalRevenue = r.GetDecimal(2), AvgTicket = r.GetDecimal(3) });
            return l;
        }

        public async Task<List<FoodCostRow>> GetFoodCostReportAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_food_cost(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(TP("@F", farmId));
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<FoodCostRow>();
            while (await r.ReadAsync()) l.Add(new() { MenuItemId = r.GetInt32(0), ItemName = r.GetString(1), SellingPrice = r.GetDecimal(2), RecipeCost = r.GetDecimal(3), FoodCostPercent = r.GetDecimal(4), Margin = r.GetDecimal(5), CategoryName = r.GetString(6) });
            return l;
        }

        public async Task<List<ServerPerformanceRow>> GetServerPerformanceAsync(string farmId, DateTime from, DateTime to)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_server_performance(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@A", from); cmd.Parameters.AddWithValue("@B", to);
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<ServerPerformanceRow>();
            while (await r.ReadAsync()) l.Add(new() { ServedBy = r.GetString(0), OrderCount = r.GetInt64(1), TotalRevenue = r.GetDecimal(2), AvgTicket = r.GetDecimal(3), TotalCovers = r.GetInt64(4) });
            return l;
        }

        public async Task<List<KpiAlertModel>> ListKpiAlertsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_kpialert_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(TP("@F", farmId));
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<KpiAlertModel>();
            while (await r.ReadAsync()) l.Add(new() { KpiAlertId = r.GetInt32(0), FarmId = r.GetString(1), Name = r.GetString(2), Metric = r.GetString(3), Operator = r.GetString(4), Threshold = r.GetDecimal(5), IsEnabled = r.GetBoolean(6), LastChecked = r.IsDBNull(7) ? null : r.GetDateTime(7), LastTriggered = r.IsDBNull(8) ? null : r.GetDateTime(8), CreatedAt = r.GetDateTime(9) });
            return l;
        }

        public async Task<int> InsertKpiAlertAsync(string farmId, string name, string metric, string op, decimal threshold, bool enabled)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kpialert_insert(p_farmid=>@F::text,p_name=>@N::text,p_metric=>@M::text,p_operator=>@O::text,p_threshold=>@T::numeric,p_isenabled=>@E::boolean)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.AddWithValue("@N", name); cmd.Parameters.AddWithValue("@M", metric);
            cmd.Parameters.AddWithValue("@O", op); cmd.Parameters.AddWithValue("@T", threshold); cmd.Parameters.AddWithValue("@E", enabled);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteKpiAlertAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kpialert_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.Add(TP("@F", farmId));
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // Migration 298 readers.
        //
        // The seven methods above this line each repeat the same nine lines of
        // Npgsql ceremony. Eighteen more of those would be 160 lines of copy in
        // which a single mistyped ordinal hides perfectly. Two helpers carry the
        // ceremony instead, and each report below is left as just its column
        // mapping -- which is the only part that can actually be wrong.
        // =====================================================================

        /// <summary>Runs a (farmid, from, to) report function and maps every row.</summary>
        private async Task<List<T>> RangeRowsAsync<T>(
            string fn, string farmId, DateTime from, DateTime to, Func<System.Data.Common.DbDataReader, T> map)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                $"SELECT * FROM {fn}(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)", conn);
            cmd.Parameters.Add(TP("@F", farmId));
            cmd.Parameters.AddWithValue("@A", from.Date);
            cmd.Parameters.AddWithValue("@B", to.Date);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<T>();
            while (await r.ReadAsync()) list.Add(map(r));
            return list;
        }

        /// <summary>
        /// Same, for the two functions that return exactly one row. Returns a
        /// default-constructed T when the range is empty rather than null, so the
        /// frontend renders a page of honest zeroes instead of handling a null.
        /// </summary>
        private async Task<T> RangeOneAsync<T>(
            string fn, string farmId, DateTime from, DateTime to, Func<System.Data.Common.DbDataReader, T> map) where T : new()
        {
            var rows = await RangeRowsAsync(fn, farmId, from, to, map);
            return rows.Count > 0 ? rows[0] : new T();
        }

        public Task<SalesSummaryReport> GetSalesSummaryAsync(string farmId, DateTime from, DateTime to) =>
            RangeOneAsync("sprestaurant_report_sales_summary", farmId, from, to, r => new SalesSummaryReport
            {
                TotalOrders = r.GetInt64(0), CompletedOrders = r.GetInt64(1), CancelledOrders = r.GetInt64(2),
                GrossRevenue = r.GetDecimal(3), DiscountTotal = r.GetDecimal(4), TaxTotal = r.GetDecimal(5),
                ServiceChargeTotal = r.GetDecimal(6), NetRevenue = r.GetDecimal(7), AvgTicket = r.GetDecimal(8),
                CoversTotal = r.GetInt64(9), RevenuePerCover = r.GetDecimal(10), TipsTotal = r.GetDecimal(11),
                DineInCount = r.GetInt64(12), DineInRevenue = r.GetDecimal(13),
                TakeawayCount = r.GetInt64(14), TakeawayRevenue = r.GetDecimal(15),
                DeliveryCount = r.GetInt64(16), DeliveryRevenue = r.GetDecimal(17),
                ActiveDays = r.GetInt64(18), AvgDailyRevenue = r.GetDecimal(19),
            });

        public Task<List<PaymentMethodRow>> GetPaymentMethodsAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_payment_methods", farmId, from, to, r => new PaymentMethodRow
            {
                MethodName = r.GetString(0), TxnCount = r.GetInt64(1), AmountTotal = r.GetDecimal(2),
                TipsTotal = r.GetDecimal(3), SharePct = r.GetDecimal(4), AvgTxn = r.GetDecimal(5),
            });

        public Task<PnlSummary> GetPnlSummaryAsync(string farmId, DateTime from, DateTime to) =>
            RangeOneAsync("sprestaurant_report_pnl_summary", farmId, from, to, r => new PnlSummary
            {
                Revenue = r.GetDecimal(0), Cogs = r.GetDecimal(1), GrossProfit = r.GetDecimal(2),
                GrossMarginPct = r.GetDecimal(3), ExpensesTotal = r.GetDecimal(4), NetProfit = r.GetDecimal(5),
                NetMarginPct = r.GetDecimal(6), FoodCostPct = r.GetDecimal(7), TipsTotal = r.GetDecimal(8),
                OrderCount = r.GetInt64(9),
            });

        public Task<List<PnlExpenseRow>> GetPnlExpensesAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_pnl_expenses", farmId, from, to, r => new PnlExpenseRow
            {
                ExpenseCategory = r.GetString(0), EntryCount = r.GetInt64(1),
                ExpenseTotal = r.GetDecimal(2), SharePct = r.GetDecimal(3),
            });

        public Task<List<KitchenPerformanceRow>> GetKitchenPerformanceAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_kitchen_performance", farmId, from, to, r => new KitchenPerformanceRow
            {
                StationName = r.GetString(0), ItemsMade = r.GetInt64(1), AvgQueueMins = r.GetDecimal(2),
                AvgPrepMins = r.GetDecimal(3), AvgTicketMins = r.GetDecimal(4), MaxTicketMins = r.GetDecimal(5),
                OverTargetCount = r.GetInt64(6), SlowestItem = r.GetString(7),
            });

        public Task<List<TableTurnoverRow>> GetTableTurnoverAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_table_turnover", farmId, from, to, r => new TableTurnoverRow
            {
                TableLabel = r.GetString(0), SeatCapacity = r.GetInt32(1), OrderCount = r.GetInt64(2),
                CoversServed = r.GetInt64(3), RevenueTotal = r.GetDecimal(4), AvgDwellMins = r.GetDecimal(5),
                TradingDays = r.GetInt64(6), TurnsPerDay = r.GetDecimal(7), RevenuePerCover = r.GetDecimal(8),
            });

        public Task<List<TipsRow>> GetTipsAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_tips", farmId, from, to, r => new TipsRow
            {
                WaiterName = r.GetString(0), OrderCount = r.GetInt64(1), RevenueTotal = r.GetDecimal(2),
                TipsTotal = r.GetDecimal(3), TipPct = r.GetDecimal(4), AvgTip = r.GetDecimal(5),
                TippedOrders = r.GetInt64(6),
            });

        public Task<List<DeliveryPerformanceRow>> GetDeliveryPerformanceAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_delivery_performance", farmId, from, to, r => new DeliveryPerformanceRow
            {
                DriverLabel = r.GetString(0), AssignmentCount = r.GetInt64(1), DeliveredCount = r.GetInt64(2),
                FailedCount = r.GetInt64(3), AvgActualMins = r.GetDecimal(4), AvgEstimatedMins = r.GetDecimal(5),
                MeasuredCount = r.GetInt64(6), OnTimePct = r.GetDecimal(7), TotalDistanceKm = r.GetDecimal(8),
                FeesTotal = r.GetDecimal(9), AvgRating = r.GetDecimal(10),
            });

        public Task<List<DiscountRow>> GetDiscountsAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_discounts", farmId, from, to, r => new DiscountRow
            {
                DiscountLabel = r.GetString(0), DiscountKind = r.GetString(1), TimesApplied = r.GetInt64(2),
                OrdersAffected = r.GetInt64(3), DiscountTotal = r.GetDecimal(4), AvgDiscount = r.GetDecimal(5),
                GrossOnDiscounted = r.GetDecimal(6), EffectivePct = r.GetDecimal(7),
            });

        public Task<List<VoidRow>> GetVoidsAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_voids", farmId, from, to, r => new VoidRow
            {
                VoidKind = r.GetString(0), VoidReason = r.GetString(1), VoidCount = r.GetInt64(2),
                ValueLost = r.GetDecimal(3), CoversLost = r.GetInt64(4), SharePct = r.GetDecimal(5),
            });

        /// <summary>
        /// The one report with no date range: stock on hand is a position, not a
        /// period, so it takes farmId alone and cannot use RangeRowsAsync.
        /// </summary>
        public async Task<List<StockOnHandRow>> GetStockOnHandAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_report_stock_on_hand(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(TP("@F", farmId));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var l = new List<StockOnHandRow>();
            while (await r.ReadAsync()) l.Add(new()
            {
                IngredientName = r.GetString(0), IngredientCategory = r.GetString(1), StockUnit = r.GetString(2),
                OnHand = r.GetDecimal(3), ParLevel = r.GetDecimal(4), ReorderPoint = r.GetDecimal(5),
                UnitCost = r.GetDecimal(6), StockValue = r.GetDecimal(7), SupplierLabel = r.GetString(8),
                StorageLabel = r.GetString(9), StockStatus = r.GetString(10),
            });
            return l;
        }

        public Task<List<WasteDetailRow>> GetWasteDetailAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_waste_detail", farmId, from, to, r => new WasteDetailRow
            {
                WasteReason = r.GetString(0), ItemLabel = r.GetString(1), WasteUnit = r.GetString(2),
                QtyTotal = r.GetDecimal(3), CostTotal = r.GetDecimal(4), EntryCount = r.GetInt64(5),
                SharePct = r.GetDecimal(6),
            });

        public Task<List<ExpenseReportRow>> GetExpenseReportAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_expenses", farmId, from, to, r => new ExpenseReportRow
            {
                ExpenseCategory = r.GetString(0), SupplierLabel = r.GetString(1), MethodLabel = r.GetString(2),
                EntryCount = r.GetInt64(3), ExpenseTotal = r.GetDecimal(4), SharePct = r.GetDecimal(5),
            });

        public Task<List<MenuEngineeringRow>> GetMenuEngineeringAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_menu_engineering", farmId, from, to, r => new MenuEngineeringRow
            {
                ItemLabel = r.GetString(0), CategoryLabel = r.GetString(1), QtySold = r.GetInt64(2),
                RevenueTotal = r.GetDecimal(3), UnitCost = r.GetDecimal(4), UnitMargin = r.GetDecimal(5),
                MarginPct = r.GetDecimal(6), PopularityPct = r.GetDecimal(7), MenuClass = r.GetString(8),
            });

        public Task<CustomerRetentionReport> GetCustomerRetentionAsync(string farmId, DateTime from, DateTime to) =>
            RangeOneAsync("sprestaurant_report_customer_retention", farmId, from, to, r => new CustomerRetentionReport
            {
                IdentifiedCustomers = r.GetInt64(0), WalkinOrders = r.GetInt64(1), NewCustomers = r.GetInt64(2),
                ReturningCustomers = r.GetInt64(3), RepeatRatePct = r.GetDecimal(4), AvgVisits = r.GetDecimal(5),
                AvgSpend = r.GetDecimal(6), TopSpend = r.GetDecimal(7), LapsedCustomers = r.GetInt64(8),
                VipCustomers = r.GetInt64(9),
            });

        public Task<List<ChannelRow>> GetChannelAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_channel", farmId, from, to, r => new ChannelRow
            {
                PlatformLabel = r.GetString(0), OrderCount = r.GetInt64(1), RejectedCount = r.GetInt64(2),
                GrossTotal = r.GetDecimal(3), CommissionTotal = r.GetDecimal(4), PlatformFeeTotal = r.GetDecimal(5),
                NetTotal = r.GetDecimal(6), CommissionPct = r.GetDecimal(7), AvgOrder = r.GetDecimal(8),
            });

        public Task<List<EventsReportRow>> GetEventsReportAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_events", farmId, from, to, r => new EventsReportRow
            {
                EventStatus = r.GetString(0), EventCount = r.GetInt64(1), GuestTotal = r.GetInt64(2),
                ContractedTotal = r.GetDecimal(3), DepositTotal = r.GetDecimal(4), DepositPaidTotal = r.GetDecimal(5),
                BalanceTotal = r.GetDecimal(6), AvgPerHead = r.GetDecimal(7),
            });

        public Task<List<FeedbackReportRow>> GetFeedbackReportAsync(string farmId, DateTime from, DateTime to) =>
            RangeRowsAsync("sprestaurant_report_feedback", farmId, from, to, r => new FeedbackReportRow
            {
                SourceLabel = r.GetString(0), ResponseCount = r.GetInt64(1), AvgOverall = r.GetDecimal(2),
                AvgFood = r.GetDecimal(3), AvgService = r.GetDecimal(4), AvgAmbience = r.GetDecimal(5),
                PromoterCount = r.GetInt64(6), DetractorCount = r.GetInt64(7), UnansweredCount = r.GetInt64(8),
            });
    }
}
