namespace PoultryFarmAPIWeb.Models
{
    /// <summary>507: body for POST api/MainFlockBatch/{id}/reverse.</summary>
    public class FlockBatchReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        public string? ReasonCode { get; set; }
        public string? Reason { get; set; }
        /// <summary>Per money line ("entry:{account}" | "sp:{paymentId}"): KeepAsCredit | Refund.</summary>
        public Dictionary<string, string>? PaymentHandling { get; set; }
        /// <summary>The user confirmed the batch's (empty) flocks are deleted with it.</summary>
        public bool DeleteFlocks { get; set; }
        public string? ExpectedFingerprint { get; set; }
        public string? IdempotencyKey { get; set; }
    }
}
