namespace PoultryFarmAPIWeb.Models
{
    public class CashTransactionDto
    {
        public string Date { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal In { get; set; }
        public decimal Owed { get; set; }
        public decimal Out { get; set; }
        public decimal Balance { get; set; }
        public string SortKey { get; set; } = string.Empty;
    }

    public class CashSummaryModel
    {
        public decimal CurrentCash { get; set; }
        public DateTime LastUpdated { get; set; }
        public List<CashTransactionDto> Transactions { get; set; } = new();
    }
}
