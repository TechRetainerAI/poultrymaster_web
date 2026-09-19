namespace PoultryFarmAPIWeb.Models
{
    public class HouseModel
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public int HouseId { get; set; }
        public string HouseName { get; set; } = string.Empty;
        public int? Capacity { get; set; }
        public string? Location { get; set; }
    
        /// <summary>When the row was created -- the clock time tables show
        /// beside the business date (migration 301). Null on a database that
        /// predates it.</summary>
        public DateTime? CreatedAt { get; set; }
}
}
