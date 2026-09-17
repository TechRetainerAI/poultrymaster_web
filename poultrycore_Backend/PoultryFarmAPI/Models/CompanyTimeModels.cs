// Company time (migration 298).
//
// One company, one timezone. These models are deliberately NOT per-vertical:
// a company's business day is a property of the company, not of whether it
// happens to sell eggs or water.

using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Everything a caller needs to stop asking the browser what day it is.
    /// </summary>
    public class CompanyTimeContextModel
    {
        public string FarmId { get; set; } = string.Empty;

        /// <summary>IANA id, e.g. Africa/Accra. Never a fixed offset.</summary>
        public string TimeZoneId { get; set; } = "UTC";

        /// <summary>
        /// False means migration 298 guessed this from the company currency and
        /// nobody has confirmed it. Nothing behaves differently either way --
        /// it exists so Setup can prompt.
        /// </summary>
        public bool TimeZoneConfirmed { get; set; }

        /// <summary>
        /// Today, for this company. What a date input should default to.
        /// </summary>
        public DateTime BusinessDate { get; set; }

        /// <summary>The company's wall clock right now.</summary>
        public DateTime CompanyLocalDateTime { get; set; }

        /// <summary>The same instant in UTC.</summary>
        public DateTime UtcNow { get; set; }
    }

    public class CompanyTimeZoneUpdateRequest
    {
        public string FarmId { get; set; } = string.Empty;

        /// <summary>
        /// Validated against pg_timezone_names by the SP, not here. A regex or a
        /// hard-coded list in C# would drift from the tz database Postgres
        /// actually uses for AT TIME ZONE, and the two disagreeing is worse than
        /// one round trip.
        /// </summary>
        [Required(ErrorMessage = "A timezone is required.")]
        public string TimeZoneId { get; set; } = string.Empty;

        public string? UpdatedBy { get; set; }
    }

    /// <summary>
    /// One selectable zone. Sourced from pg_timezone_names, so the id is
    /// guaranteed to be one spcompany_settimezone will accept.
    /// </summary>
    public class CompanyTimeZoneOption
    {
        public string TimeZoneId { get; set; } = string.Empty;

        /// <summary>Formatted "+00:00" / "-05:00" -- signed, so it never reads
        /// as ambiguous. This is today's offset: for a DST zone it changes
        /// twice a year, which is why the id and not the offset is stored.</summary>
        public string UtcOffset { get; set; } = string.Empty;

        /// <summary>Whether that offset is currently a daylight-saving one.</summary>
        public bool IsDst { get; set; }
    }

    /// <summary>What the setter gives back, so the caller need not re-read.</summary>
    public class CompanyTimeZoneUpdateResult
    {
        public string TimeZoneId { get; set; } = string.Empty;
        public bool TimeZoneConfirmed { get; set; }
        public DateTime BusinessDate { get; set; }
    }
}
