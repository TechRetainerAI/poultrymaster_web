namespace PoultryWeb.Models
{
    public class ProductionRecordViewModel
    {
        public int Id { get; set; } 
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public string CreatedBy { get; set; } 
        public string UpdatedBy { get; set; } 
        public int AgeInWeeks { get; set; }
        public DateTime Date { get; set; }
        public int NoOfBirds { get; set; }
        public int Mortality { get; set; }
        public int NoOfBirdsLeft { get; set; }
        public decimal FeedKg { get; set; }
        public string Medication { get; set; }
        public int Production9AM { get; set; }
        public int Production12PM { get; set; }
        public int Production4PM { get; set; }
        public int TotalProduction { get; set; }
    }
}
