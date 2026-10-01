using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Where a flock's birds are, from fnflock_birdposition (migration 332). Every
    /// figure is derived from the flock, its opening position, its production
    /// records, its tagged bird sales and its closeout dispositions -- nothing
    /// here is typed in, so it cannot drift from what those records say.
    /// </summary>
    public class FlockBirdPosition
    {
        public int FlockId { get; set; }
        /// <summary>True when Initial Farm Setup onboarded the flock with history.</summary>
        public bool HasOpeningPosition { get; set; }
        /// <summary>False when the opening losses were never broken down.</summary>
        public bool HistoryKnown { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningMortality { get; set; }
        public int OpeningSold { get; set; }
        public int OpeningCulled { get; set; }
        public int OpeningTransferred { get; set; }
        public int OpeningOther { get; set; }
        /// <summary>What the flock started life with in the app (flock.quantity).</summary>
        public int OpeningLiveBirds { get; set; }
        public int RecordedMortality { get; set; }
        public int ProductionRecordCount { get; set; }
        /// <summary>noofbirdsleft on the latest production record, else opening live.</summary>
        public int LastCountedBirds { get; set; }
        public DateTime? LastCountDate { get; set; }
        /// <summary>The part of the last count recorded mortality does not explain.</summary>
        public int Correction { get; set; }
        public int BirdsSold { get; set; }
        public int BirdsCulled { get; set; }
        public int BirdsTransferred { get; set; }
        public int CurrentLiveBirds { get; set; }
    }

    /// <summary>Everything the Close Flock wizard needs to open.</summary>
    public class FlockCloseoutContext
    {
        public FlockModel Flock { get; set; } = new();
        public FlockBirdPosition Position { get; set; } = new();
        public bool IsClosed { get; set; }
        /// <summary>Null when the flock can be closed; otherwise why not.</summary>
        public string? IneligibleReason { get; set; }
        public string? HouseName { get; set; }
        /// <summary>The company's calendar day -- the latest date a flock may close on.</summary>
        public DateTime BusinessDate { get; set; }
        /// <summary>Earliest valid closing date: the later of the start and the last count.</summary>
        public DateTime EarliestCloseDate { get; set; }
        /// <summary>The product name a closeout sale is recorded under.</summary>
        public string BirdProductName { get; set; } = "Birds";
    }

    /// <summary>
    /// One sale of the remaining birds. Created through the ordinary SaleService
    /// -- the same cash-account, customer and payment handling as the Sales page.
    /// </summary>
    public class FlockCloseoutSaleLine
    {
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        /// <summary>Optional; defaults to quantity x unit price.</summary>
        public decimal? TotalAmount { get; set; }
        public int? CustomerId { get; set; }
        public string? CustomerName { get; set; }
        /// <summary>"Paid", "Credit" or "PartPaid".</summary>
        public string PaymentTerms { get; set; } = "Paid";
        /// <summary>PartPaid only: the amount received now.</summary>
        public decimal? AmountPaid { get; set; }
        public string? PaymentMethod { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public string? Description { get; set; }
    }

    public class FlockCloseoutCullLine
    {
        public int Quantity { get; set; }
        public string? Notes { get; set; }
    }

    public class FlockCloseoutTransferLine
    {
        public int Quantity { get; set; }
        /// <summary>Where the birds went. They leave the company.</summary>
        public string Destination { get; set; } = string.Empty;
        public string? Notes { get; set; }
    }

    public class FlockCloseoutRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        /// <summary>The business date the flock closes on.</summary>
        public DateTime ClosedDate { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Notes { get; set; }
        public List<FlockCloseoutSaleLine> Sales { get; set; } = new();
        public List<FlockCloseoutCullLine> Culls { get; set; } = new();
        public List<FlockCloseoutTransferLine> Transfers { get; set; } = new();
    }

    public class FlockCloseoutResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public int? CloseoutId { get; set; }
        public List<int> SaleIds { get; set; } = new();
        /// <summary>The house the flock was released from, if it had one.</summary>
        public int? ReleasedHouseId { get; set; }
        public string? ReleasedHouseName { get; set; }
        /// <summary>
        /// Things that went wrong AFTER the flock closed and did not undo it --
        /// e.g. a payment that could not be recorded, leaving that sale on credit.
        /// </summary>
        public List<string> Warnings { get; set; } = new();
        public List<string> Errors { get; set; } = new();
    }

    public class FlockReopenRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        /// <summary>
        /// Migration 333. True (the default): reverse the closeout's sales --
        /// their payments are reversed, the money leaves the cash account, the
        /// sales are removed and the birds come back. False: keep the sales
        /// (they really happened) and only unlock them.
        /// </summary>
        public bool ReverseSales { get; set; } = true;
    }

    public class FlockReopenResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public int? CloseoutId { get; set; }
        public List<string> Warnings { get; set; } = new();
    }

    public class FlockCloseoutDisposition
    {
        public int DispositionId { get; set; }
        public string Disposition { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public int? SaleId { get; set; }
        public string? Destination { get; set; }
        public string? Notes { get; set; }
        public DateTime? ReversedAt { get; set; }
        /// <summary>333: when a reopen reversed this sale (the sale row is then gone).</summary>
        public DateTime? SaleReversedAt { get; set; }
        public decimal? TotalAmount { get; set; }
        public string? CustomerName { get; set; }
        public bool? Paid { get; set; }
    }

    /// <summary>One close of a flock -- open, or reopened later. Snapshot as signed off.</summary>
    public class FlockCloseoutRecord
    {
        public int CloseoutId { get; set; }
        public int FlockId { get; set; }
        public DateTime ClosedDate { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Notes { get; set; }
        public string ClosedBy { get; set; } = string.Empty;
        public DateTime ClosedAt { get; set; }
        public int? HouseId { get; set; }
        public bool HasOpeningPosition { get; set; }
        public bool HistoryKnown { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningMortality { get; set; }
        public int OpeningSold { get; set; }
        public int OpeningCulled { get; set; }
        public int OpeningTransferred { get; set; }
        public int OpeningOther { get; set; }
        public int OpeningLiveBirds { get; set; }
        public int RecordedMortality { get; set; }
        public int Correction { get; set; }
        public int LastCountedBirds { get; set; }
        public DateTime? LastCountDate { get; set; }
        public int SoldBeforeCloseout { get; set; }
        public int LiveBirdsAtCloseout { get; set; }
        public int DisposedSold { get; set; }
        public int DisposedCulled { get; set; }
        public int DisposedTransferred { get; set; }
        public DateTime? ReopenedAt { get; set; }
        public string? ReopenedBy { get; set; }
        public string? ReopenReason { get; set; }
        public List<FlockCloseoutDisposition> Dispositions { get; set; } = new();
    }

    /// <summary>
    /// A flock's lifetime performance, from fnflock_lifetimesummary. The batch,
    /// breed, supplier and house are on the row so any comparison is a grouping
    /// of these rows rather than a second definition of profit.
    ///
    /// Nullable figures are the ones that cannot always be supported: a rate
    /// with nothing to divide by, or a lifetime mortality rate for a flock whose
    /// opening losses were never broken down.
    /// </summary>
    public class FlockLifetimeSummary
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? Breed { get; set; }
        /// <summary>Active, Inactive, Pending or Closed.</summary>
        public string Status { get; set; } = string.Empty;
        public int? BatchId { get; set; }
        public string? BatchCode { get; set; }
        public string? BatchName { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierType { get; set; }
        public int? HouseId { get; set; }
        public string? HouseName { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime? ClosedDate { get; set; }
        public int DaysInProduction { get; set; }
        public bool HasOpeningPosition { get; set; }
        public bool HistoryKnown { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }
        public int OpeningMortality { get; set; }
        public int RecordedMortality { get; set; }
        public int BirdsSold { get; set; }
        public int BirdsCulled { get; set; }
        public int BirdsTransferred { get; set; }
        public int FinalBirds { get; set; }
        public decimal? TrackedMortalityRate { get; set; }
        public decimal? LifetimeMortalityRate { get; set; }
        public long TotalEggs { get; set; }
        public int ProductionDays { get; set; }
        public decimal EggRevenue { get; set; }
        public decimal BirdSaleRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal FeedConsumedKg { get; set; }
        public decimal FeedCost { get; set; }
        public decimal MedicationCost { get; set; }
        public decimal BirdCost { get; set; }
        public bool BirdCostRecorded { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherDirectCost { get; set; }
        public decimal TotalCost { get; set; }
        public decimal Profit { get; set; }
        public decimal? ProfitPerOriginalBird { get; set; }
        public decimal? RevenuePerOriginalBird { get; set; }
        public decimal? FeedKgPerDozenEggs { get; set; }
    }
}
