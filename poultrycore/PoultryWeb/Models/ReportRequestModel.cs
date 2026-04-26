namespace PoultryWeb.Models
{
    public class ReportRequestModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public string ReportType { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public int? FlockId { get; set; }
        public int? CustomerId { get; set; }
    }
}
