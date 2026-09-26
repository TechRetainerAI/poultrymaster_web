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
        /// <param name="revalidate">
        /// Re-runs the caller's validation against freshly read data, and is invoked
        /// INSIDE the company's setup lock.
        ///
        /// <para>This is what replaced "one setup per company, ever". The tool is
        /// now meant to be reopened — a farm that builds new pens or buys another
        /// batch comes back to it — so a completed setup can no longer be the thing
        /// that refuses a submission. What must still be refused is creating the
        /// same farm twice, and every way of doing that is already a validation
        /// error: a duplicate batch code, house name or flock name.</para>
        ///
        /// <para>Validating once in the caller is not enough, because two tabs can
        /// both pass before either commits. Running it again under the lock closes
        /// that window: the second session reads what the first just committed and
        /// is rejected with ordinary row errors rather than silently doubling the
        /// farm.</para>
        /// </param>
        Task<FarmSetupResult> CompleteAsync(
            FarmSetupRequest request,
            System.DateTime effectiveBusinessDate,
            System.Func<Task<IReadOnlyList<FarmSetupRowError>>> revalidate);

        /// <summary>The company's unfinished setup, or null when there is none.</summary>
        Task<FarmSetupDraftModel?> GetDraftAsync(string farmId);

        /// <summary>Write the unfinished setup, replacing whatever was there.</summary>
        Task<DateTime> SaveDraftAsync(FarmSetupDraftModel draft);

        /// <summary>Throw it away. Returns false when there was nothing to discard.</summary>
        Task<bool> DeleteDraftAsync(string farmId);

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
    /// A database error during setup, with the step that caused it.
    ///
    /// <para>The setup runs about twenty statements in one transaction. A bare
    /// SQLSTATE tells you what went wrong and nothing about where, which is a
    /// long way to walk back. This names the step.</para>
    /// </summary>
    public class FarmSetupStageException : System.Exception
    {
        public string Stage { get; }
        public Npgsql.PostgresException Inner { get; }

        public FarmSetupStageException(string stage, Npgsql.PostgresException inner)
            : base($"{inner.SqlState}: {inner.MessageText} — while {stage}", inner)
        {
            Stage = stage;
            Inner = inner;
        }
    }

    /// <summary>
    /// Another session created part of this farm while this one was being filled
    /// in, so submitting it now would create something twice. Carries the ordinary
    /// row errors, so the wizard can point at the rows that clash rather than
    /// showing a bare conflict.
    ///
    /// <para>Thrown rather than returned so it cannot be ignored by a caller that
    /// forgot to look at a flag.</para>
    /// </summary>
    public class FarmSetupConflictException : System.Exception
    {
        public IReadOnlyList<FarmSetupRowError> Errors { get; }

        public FarmSetupConflictException(IReadOnlyList<FarmSetupRowError> errors)
            : base(errors.Count == 1
                ? errors[0].Message
                : $"{errors.Count} rows now clash with records created while this setup was open.")
        {
            Errors = errors;
        }
    }
}
