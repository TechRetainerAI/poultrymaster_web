namespace PoultryFarmAPIWeb.Models
{
    // Per-farm egg-pick configuration (migrations 153 and 248). Pick times are
    // 24h "HH:mm" strings used for display/reporting; production records stay
    // labelled 1st..6th Pick. The Enable* flags gate the entry inputs only —
    // the backend always stores the 4th pick.
    //
    // The 5th and 6th are configuration ahead of storage: productionrecords has
    // no column for either yet, so a farm can name the times and turn them on,
    // and the entry forms will fill them when those columns exist.
    public class FarmProductionSettingsModel
    {
        public int Id { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string? FirstPickTime { get; set; }
        public string? SecondPickTime { get; set; }
        public string? ThirdPickTime { get; set; }
        public string? FourthPickTime { get; set; }
        public string? FifthPickTime { get; set; }
        public string? SixthPickTime { get; set; }
        public bool EnableFourthPick { get; set; }
        public bool EnableFifthPick { get; set; }
        public bool EnableSixthPick { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedDate { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }
}
