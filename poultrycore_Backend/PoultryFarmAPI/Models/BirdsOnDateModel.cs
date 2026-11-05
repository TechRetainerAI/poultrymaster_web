using System;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// 406 (fnflock_birdsondate): what a new production record for a flock-day
    /// should open with. Birds = previous record's birds left minus the birds
    /// sold since that record (birds sold to date minus what it allowed for).
    /// </summary>
    public class BirdsOnDateModel
    {
        public int? PreviousRecordId { get; set; }
        public DateTime? PreviousRecordDate { get; set; }
        public int PreviousBirdsLeft { get; set; }
        public int PreviousReflected { get; set; }
        /// <summary>Posted bird sales out of the flock, dated on or before the day. Send back as BirdsSoldReflected.</summary>
        public int BirdsSoldToDate { get; set; }
        public int BirdsSoldSince { get; set; }
        public int Birds { get; set; }
    }
}
