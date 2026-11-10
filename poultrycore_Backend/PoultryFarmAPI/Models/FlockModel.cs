namespace PoultryFarmAPIWeb.Models
{
    public class FlockModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int FlockId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Breed { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public int Quantity { get; set; }
        public bool Active { get; set; }
        public int? HouseId { get; set; }
        public string? InactivationReason { get; set; }
        public string? OtherReason { get; set; }
        public int BatchId { get; set; }
        public string? Notes { get; set; }
        public string? BatchName { get; set; }
        public bool HasArrived { get; set; }
    
        /// <summary>When the row was created -- the clock time tables show
        /// beside the business date (migration 301). Null on a database that
        /// predates it.</summary>
        public DateTime? CreatedAt { get; set; }

        /// <summary>
        /// The closed state (migration 338). Set only by Close Flock, cleared only
        /// by Reopen Flock -- a trigger refuses any other writer. A closed flock is
        /// also inactive, but an inactive flock is not necessarily closed: the old
        /// active toggle still exists for flocks that are paused, not finished.
        /// </summary>
        public DateTime? ClosedDate { get; set; }
        public DateTime? ClosedAt { get; set; }
        public string? ClosedBy { get; set; }
        public string? CloseReason { get; set; }
        public int? CloseoutId { get; set; }
        public bool IsClosed => ClosedDate.HasValue;

        /// <summary>
        /// "Layer" or "Broiler" (migration 399). On create/update, null means
        /// "not chosen": a new flock then gets the database default (broiler
        /// breed, else the company's business type) and an existing flock keeps
        /// its type.
        /// </summary>
        public string? FlockType { get; set; }

        /// <summary>
        /// Edit Flock only: the flock's registration history as the farmer now
        /// states it (originally placed, alive when registered, and what happened
        /// to the difference). Null = leave the history as it is. Saved through
        /// the opening-position correction, which posts only the DIFFERENCE to
        /// the bird ledger -- nothing is ever posted twice.
        /// </summary>
        public FlockOpeningHistoryEdit? OpeningHistory { get; set; }
}

    public class FlockOpeningHistoryEdit
    {
        public int OriginallyPlaced { get; set; }
        /// <summary>Birds alive when the flock was registered.</summary>
        public int OpeningLiveBirds { get; set; }
        public bool HistoryKnown { get; set; } = true;
        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public string? Notes { get; set; }
}

}
