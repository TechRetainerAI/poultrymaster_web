namespace PoultryFarmAPIWeb.Models
{
    public class HealthRecordModel
    {
        public int Id { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public int? FlockId { get; set; }
        public int? HouseId { get; set; }
        public int? ItemId { get; set; }
        public DateTime RecordDate { get; set; }
        public string? Vaccination { get; set; }
        public string? Medication { get; set; }
        public decimal? WaterConsumption { get; set; }
        public string? Notes { get; set; }
        public DateTime? CreatedDate { get; set; }
    }
}
