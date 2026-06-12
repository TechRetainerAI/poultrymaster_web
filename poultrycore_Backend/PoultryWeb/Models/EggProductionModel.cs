namespace PoultryWeb.Models
{
    public class EggProductionModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int ProductionId { get; set; }
        public int FlockId { get; set; }
        public DateTime ProductionDate { get; set; }
        public int EggCount { get; set; }

        public int? BrokenEggs { get; set; }
        public string? Notes { get; set; }
    }
}
