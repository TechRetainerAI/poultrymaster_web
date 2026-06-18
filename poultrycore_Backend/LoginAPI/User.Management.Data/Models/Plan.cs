namespace User.Management.Data.Models
{
    public class Plan
    {
        public int PlanId { get; set; }
        public int ProductId { get; set; }
        public string PriceId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Price { get; set; } = string.Empty;
        public string Features { get; set; } = string.Empty;
        public int TransactionLimit { get; set; }
        public bool isEnabled { get; set; }
    }

}
