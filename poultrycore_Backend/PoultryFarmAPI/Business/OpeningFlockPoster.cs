using System;
using System.Threading.Tasks;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// The ONE way an already-operating flock is created: Initial Farm Setup, the
    /// Flocks page and the Farm Setup → Flocks view all come through here, inside
    /// the caller's transaction.
    ///
    /// <para><b>How the 1,500 → 1,350 example is posted.</b> The flock is created
    /// holding its CURRENT live birds (1,350) and an opening position records that
    /// 1,500 were placed and why 150 are gone. That is migration 319's model and
    /// every bird reader already understands it:</para>
    /// <list type="bullet">
    /// <item>the batch is charged 1,500, exactly once —
    /// <c>spflock_getconsumedforbatch</c> adds the 150 back;</item>
    /// <item>the flock reads 1,350 with no production record;</item>
    /// <item>the 150 are one 'Opening Adjustment' ledger movement that names the
    /// batch and flock (413), never "today's mortality".</item>
    /// </list>
    /// <para>Nothing here subtracts the 150 from the batch's unplaced pool: the
    /// flock-level history and the batch-level pool are separate.</para>
    /// </summary>
    public static class OpeningFlockPoster
    {
        public sealed class Result
        {
            public int FlockId { get; set; }
            public int OpeningPositionId { get; set; }
            public int LedgerRows { get; set; }
        }

        public static async Task<Result> PostAsync(
            NpgsqlConnection conn, NpgsqlTransaction tx, FlockModel flock,
            ExistingFlockHistory history, DateTime effectiveDate, bool startDateEstimated,
            string source, string userId)
        {
            if (history.OriginallyPlaced < history.CurrentLiveBirds)
                throw new ArgumentException("Birds now cannot be more than birds originally placed. Record the extra birds as a transfer in or a correction.");

            var (mortality, sold, culled, transferred, other) = history.Breakdown();

            // The flock holds what is standing today (319).
            flock.Quantity = history.CurrentLiveBirds;
            using var flockCmd = BirdFlockService.BuildFlockInsertCommand(conn, tx, flock);
            var flockId = Convert.ToInt32(await flockCmd.ExecuteScalarAsync());
            if (!string.IsNullOrWhiteSpace(flock.FlockType))
                await BirdFlockService.ApplyFlockTypeAsync(conn, tx, flockId, flock);

            using var openingCmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryopeningposition_insert(" +
                "p_farmid => @FarmId::text, p_flockid => @FlockId::int, " +
                "p_effectivebusinessdate => @EffectiveDate::date, " +
                "p_originallyplaced => @OriginallyPlaced::int, p_openinglivebirds => @OpeningLive::int, " +
                "p_historicalmortality => @Mortality::int, p_historicalsold => @Sold::int, " +
                "p_historicalculled => @Culled::int, p_historicaltransferred => @Transferred::int, " +
                "p_otheradjustment => @Other::int, p_historyknown => @HistoryKnown::boolean, " +
                "p_startdateestimated => @Estimated::boolean, p_source => @Source::text, " +
                "p_notes => @Notes::text, p_createdby => @CreatedBy::text)", conn, tx);
            openingCmd.Parameters.AddWithValue("@FarmId", flock.FarmId);
            openingCmd.Parameters.AddWithValue("@FlockId", flockId);
            openingCmd.Parameters.AddWithValue("@EffectiveDate", effectiveDate.Date);
            openingCmd.Parameters.AddWithValue("@OriginallyPlaced", history.OriginallyPlaced);
            openingCmd.Parameters.AddWithValue("@OpeningLive", history.CurrentLiveBirds);
            openingCmd.Parameters.AddWithValue("@Mortality", mortality);
            openingCmd.Parameters.AddWithValue("@Sold", sold);
            openingCmd.Parameters.AddWithValue("@Culled", culled);
            openingCmd.Parameters.AddWithValue("@Transferred", transferred);
            openingCmd.Parameters.AddWithValue("@Other", other);
            openingCmd.Parameters.AddWithValue("@HistoryKnown", history.HistoryKnown);
            openingCmd.Parameters.AddWithValue("@Estimated", startDateEstimated);
            openingCmd.Parameters.AddWithValue("@Source", source);
            openingCmd.Parameters.AddWithValue("@Notes", (object?)history.Notes ?? DBNull.Value);
            openingCmd.Parameters.AddWithValue("@CreatedBy", userId);
            var openingPositionId = Convert.ToInt32(await openingCmd.ExecuteScalarAsync());

            var ledgerRows = 0;
            var reduction = history.OriginallyPlaced - history.CurrentLiveBirds;
            if (reduction > 0)
            {
                // 413: the function now tags the row with this flock and its batch.
                using var ledgerCmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryopeningbirdstock_post(" +
                    "p_farmid => @FarmId::text, p_openingpositionid => @OpeningId::int, " +
                    "p_reduction => @Reduction::int, p_effectivedate => @EffectiveDate::date, " +
                    "p_note => @Note::text, p_createdby => @CreatedBy::text)", conn, tx);
                ledgerCmd.Parameters.AddWithValue("@FarmId", flock.FarmId);
                ledgerCmd.Parameters.AddWithValue("@OpeningId", openingPositionId);
                ledgerCmd.Parameters.AddWithValue("@Reduction", reduction);
                ledgerCmd.Parameters.AddWithValue("@EffectiveDate", effectiveDate.Date);
                ledgerCmd.Parameters.AddWithValue("@Note", $"Opening historical reduction for {flock.Name} ({source})");
                ledgerCmd.Parameters.AddWithValue("@CreatedBy", userId);
                ledgerRows = Convert.ToInt32(await ledgerCmd.ExecuteScalarAsync());
            }

            return new Result { FlockId = flockId, OpeningPositionId = openingPositionId, LedgerRows = ledgerRows };
        }
    }
}
