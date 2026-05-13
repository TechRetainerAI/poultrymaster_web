namespace PoultryFarmAPIWeb.Models
{
    public class HealthRecordModel
    {
        public int Id { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public int? FlockId { get; set; }
        public int? HouseId { get; set; }
        public int? ItemId { get; set; }
        public DateTime RecordDate { get; set; }
        public string? Vaccination { get; set; }
        public string? Medication { get; set; }
        public decimal? WaterConsumption { get; set; }
        public string? Notes { get; set; }
        public DateTime? CreatedDate { get; set; }

        /// <summary>Optional image bytes (e.g. medication pack photo). JSON: base64 string.</summary>
        public byte[]? AttachmentImage { get; set; }

        public string? AttachmentContentType { get; set; }

        /// <summary>True when a row has stored image bytes (list/detail queries; not stored in DB as a column).</summary>
        public bool HasAttachmentImage { get; set; }

        /// <summary>When true on PUT, <see cref="AttachmentImage"/> and <see cref="AttachmentContentType"/> replace or clear the stored image.</summary>
        public bool SetAttachmentImage { get; set; }
    }
}
