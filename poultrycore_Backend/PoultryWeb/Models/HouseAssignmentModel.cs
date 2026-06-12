namespace PoultryWeb.Models
{
    public class HouseAssignmentModel
    {
        public int AssignmentId { get; set; }
        public int FlockId { get; set; }
        public int HouseId { get; set; }
        public DateTime DateAssigned { get; set; }
    }
}
