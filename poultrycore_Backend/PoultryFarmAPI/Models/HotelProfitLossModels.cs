namespace PoultryFarmAPIWeb.Models
{
    public class HotelProfitLossLine
    {
        public string Section { get; set; } = string.Empty;
        public string LineKey { get; set; } = string.Empty;
        public string LineLabel { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public int SortOrder { get; set; }
        public bool IsInformational { get; set; }
        public int EntryCount { get; set; }
    }

    public class HotelProfitLossReport
    {
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }

        // Revenue
        public decimal RoomRevenue { get; set; }
        public decimal RestaurantRevenue { get; set; }
        public decimal DepositsNet { get; set; }
        public decimal TotalRevenue { get; set; }

        // Expenses
        public decimal StaffWages { get; set; }
        public decimal TotalExpenseCategory { get; set; }
        public decimal TotalExpenses { get; set; }

        // Profit
        public decimal NetProfit { get; set; }
        public decimal? NetMarginPercent { get; set; }
        public string Status { get; set; } = "Break-even";

        // Counts
        public int RevenueEntries { get; set; }
        public int ExpenseEntries { get; set; }

        public List<HotelProfitLossLine> Lines { get; set; } = new();
    }

    public class HotelPlExpenseRow
    {
        public int HotelExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string? Category { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? Vendor { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Status { get; set; }
        public string? PlLineKey { get; set; }
    }

    public class HotelPlRevenueRow
    {
        public string? SourceType { get; set; }
        public int SourceId { get; set; }
        public DateTime EntryDate { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? Method { get; set; }
        public string? PlLineKey { get; set; }
    }
}
