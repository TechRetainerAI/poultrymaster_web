namespace PoultryFarmAPIWeb.Models
{
    public class MortalityModel
    {
        public string UserId { get; set; }
        public int MortalityId { get; set; }
        public int FlockId { get; set; }
        public DateTime DateOfDeath { get; set; }
        public int Quantity { get; set; }
        public string? Reason { get; set; }
    }
}
