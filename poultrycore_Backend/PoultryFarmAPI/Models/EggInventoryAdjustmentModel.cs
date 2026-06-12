namespace PoultryFarmAPIWeb.Models
{
    public class EggInventoryAdjustmentModel
    {
        public int AdjustmentId { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public DateTime AdjustmentDate { get; set; }
        /// <summary>OpeningBalance, Stocktake, Correction</summary>
        public string AdjustmentType { get; set; } = string.Empty;
        /// <summary>Positive adds eggs to ledger balance; negative removes.</summary>
        public int EggDelta { get; set; }
        public string? Description { get; set; }
        public DateTime CreatedDate { get; set; }
    }
}
