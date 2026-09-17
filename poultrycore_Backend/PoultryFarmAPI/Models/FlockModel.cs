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
        public bool HasArrived { get; set; }
    
        /// <summary>When the row was created -- the clock time tables show
        /// beside the business date (migration 301). Null on a database that
        /// predates it.</summary>
        public DateTime? CreatedAt { get; set; }
}

}
