namespace PoultryFarmAPIWeb.Models
{
    public class HouseAssignmentModel
    {
        public string UserId { get; set; }
        public int AssignmentId { get; set; }
        public int FlockId { get; set; }
        public int HouseId { get; set; }
        public DateTime DateAssigned { get; set; }
    }
}
