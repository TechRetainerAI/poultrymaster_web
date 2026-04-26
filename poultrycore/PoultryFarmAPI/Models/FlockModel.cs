namespace PoultryFarmAPIWeb.Models
{
    public class FlockModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int FlockId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Breed { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public int Quantity { get; set; }
        public bool Active { get; set; }
        public int? HouseId { get; set; }
        public string? InactivationReason { get; set; }
        public string? OtherReason { get; set; }
        public int BatchId { get; set; }
        public string? Notes { get; set; }
        public string? BatchName { get; set; }
    }

}
