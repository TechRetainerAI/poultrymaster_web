namespace PoultryWeb.Models
{
    public class FlockModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int FlockId { get; set; }
        public string Name { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public string Breed { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public bool Active { get; set; }
    }

}
