using System.Collections.Generic;
using System.Threading.Tasks;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFarmSetupService
    {
        /// <summary>Whether this company has completed initial setup, and what it has already.</summary>
        Task<FarmSetupStatusModel> GetStatusAsync(string userId, string farmId);

        /// <summary>Opening positions for the company, with the roll-up the reports need.</summary>
        Task<OpeningPositionSummaryModel> GetOpeningPositionsAsync(string farmId);

        /// <summary>
        /// Create the whole farm — batches, houses, flocks and their opening
        /// positions — in ONE transaction, reusing the same stored functions the
        /// ordinary pages call.
        ///
        /// <para>
        /// Writes no production records. A flock's quantity is set to its opening
        /// LIVE birds, so current-bird maths is right from the first day without
        /// anything pretending to be a day's mortality.
        /// </para>
        /// </summary>
        Task<FarmSetupResult> CompleteAsync(FarmSetupRequest request, System.DateTime effectiveBusinessDate);

        /// <summary>
        /// Restate one flock's opening position. Refused once the flock has
        /// operational history — that is what corrections records are for, and
        /// rewriting a posted day is never the answer.
        /// </summary>
        Task<bool> CorrectOpeningPositionAsync(OpeningFlockPositionCorrection correction);
    }

    /// <summary>A deliberate restatement of one flock's day-one numbers.</summary>
    public class OpeningFlockPositionCorrection
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public int FlockId { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }
        public bool HistoryKnown { get; set; }
        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public int OtherAdjustment { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>
    /// The wizard was already run for this company. Thrown rather than returned so
    /// it cannot be ignored by a caller that forgot to look at a flag.
    /// </summary>
    public class FarmSetupAlreadyCompleteException : System.Exception
    {
        public FarmSetupAlreadyCompleteException()
            : base("Initial farm setup has already been completed for this company. Use the ordinary Flock Purchases, Houses and Flock Groups pages to add more.") { }
    }
}
