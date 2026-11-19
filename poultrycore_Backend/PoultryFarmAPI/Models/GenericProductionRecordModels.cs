namespace PoultryFarmAPIWeb.Models
{
    public class GenericProductionRecordModel
    {
        public int GenericProductionRecordId { get; set; }
        public string FarmId { get; set; } = "";
        public int GenericProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal QuantityProduced { get; set; }
        public DateTime ProductionDate { get; set; }
        public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public string? BatchNumber { get; set; }
        public string? MaterialsUsed { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";
        public string? ReversalReason { get; set; }
        public string? CreatedBy { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericProductionRecordCreateInput
    {
        public string FarmId { get; set; } = "";
        public int GenericProductId { get; set; }
        public decimal QuantityProduced { get; set; }
        public DateTime? ProductionDate { get; set; }
        public decimal UnitCost { get; set; }
        public string? BatchNumber { get; set; }
        public string? MaterialsUsed { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericProductionRecordReverseInput
    {
        public string FarmId { get; set; } = "";
        public string Reason { get; set; } = "";
        public string? ReversedBy { get; set; }
    }
}
