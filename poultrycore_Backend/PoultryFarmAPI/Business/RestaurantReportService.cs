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
    }
}
