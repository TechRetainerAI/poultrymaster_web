namespace PoultryFarmAPIWeb.Models
{
    // Per-farm egg-pick configuration (migration 153). Pick times are 24h "HH:mm"
    // strings used for display/reporting; production records stay labelled
    // 1st/2nd/3rd/4th Pick. EnableFourthPick gates the 4th-pick entry input only —
    // the backend always stores the 4th pick.
    public class FarmProductionSettingsModel
    {
        public int Id { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string? FirstPickTime { get; set; }
        public string? SecondPickTime { get; set; }
        public string? ThirdPickTime { get; set; }
        public string? FourthPickTime { get; set; }
        public bool EnableFourthPick { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedDate { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }
}
