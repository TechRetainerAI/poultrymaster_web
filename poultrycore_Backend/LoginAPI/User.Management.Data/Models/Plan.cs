namespace User.Management.Data.Models
{
    public class Plan
    {
        public int PlanId { get; set; }
        public int ProductId { get; set; }
        public string PriceId { get; set; }
        public string Name { get; set; }
        public string Price { get; set; }
        public string Features { get; set; }
        public int TransactionLimit { get; set; }
        public bool isEnabled { get; set; }
    }

}
