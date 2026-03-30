namespace PoultryWeb.Models
{
    public class DashboardViewModel
    {
        public int TotalEggsToday { get; set; }
        public decimal FeedUsedTodayKg { get; set; }
        public decimal SalesToday { get; set; }
        public decimal ExpensesToday { get; set; }
        public int ActiveFlocks { get; set; }

        public List<ChartPoint> EggChart { get; set; } = new();
        public List<ChartPoint> FeedChart { get; set; } = new();
        public List<ChartPoint> SalesChart { get; set; } = new();
        public List<ChartPoint> ExpensesChart { get; set; } = new();
    }

    public class ChartPoint
    {
        public string Label { get; set; } = string.Empty;
        public decimal Value { get; set; }
    }

}
