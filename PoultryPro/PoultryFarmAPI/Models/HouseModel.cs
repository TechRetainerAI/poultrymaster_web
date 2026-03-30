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
    }
}
