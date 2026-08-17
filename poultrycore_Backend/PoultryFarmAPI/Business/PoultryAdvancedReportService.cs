
using Npgsql;
using PoultryFarmAPIWeb.Models;
using static PoultryFarmAPIWeb.Business.PoultryReportHelpers;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Advanced Poultry Reports service. Each method EXECs a dedicated
    // spPoultryReport_* procedure (detail rows), then computes summary cards
    // and derived percentages in C# using PoultryReportHelpers. Read-only.
    // =========================================================================
    public class PoultryAdvancedReportService : IPoultryAdvancedReportService
    {
        private readonly string _connectionString;
        public PoultryAdvancedReportService(string connectionString) => _connectionString = connectionString;

        // ---- shared scaffolding --------------------------------------------

        private static (DateTime start, DateTime end) ResolveRange(PoultryReportFilterDto f)
        {
            var today = DateTime.Today;
            var start = (f.StartDate ?? today.AddDays(-29)).Date;
            var end = (f.EndDate ?? today).Date;
            if (end < start) (start, end) = (end, start);
            return (start, end);
        }

        private static PoultryReportResponse<TS, TR> NewResponse<TS, TR>(
            string name, PoultryReportFilterDto f, DateTime start, DateTime end)
            => new()
            {
                ReportName = name,
                FarmId = f.FarmId,
                StartDate = start,
                EndDate = end,
                GeneratedAt = DateTime.UtcNow,
                EggsPerCrate = EggsPerCrate,
                AppliedFilters = BuildFilters(f, start, end),
            };

        private static Dictionary<string, string?> BuildFilters(PoultryReportFilterDto f, DateTime start, DateTime end)
        {
            var d = new Dictionary<string, string?>
            {
                ["Date range"] = $"{start:yyyy-MM-dd} → {end:yyyy-MM-dd}",
            };
            if (!string.IsNullOrWhiteSpace(f.DatePreset)) d["Period"] = f.DatePreset;
            if (f.FlockId.HasValue) d["Flock"] = f.FlockId.Value.ToString();
            if (!string.IsNullOrWhiteSpace(f.CustomerName)) d["Customer"] = f.CustomerName;
            if (!string.IsNullOrWhiteSpace(f.SupplierName)) d["Supplier"] = f.SupplierName;
            if (f.IncludeClosedFlocks) d["Include closed flocks"] = "Yes";
            return d;
        }

        private static NpgsqlParameter PFlock(PoultryReportFilterDto f) =>
            new("@FlockId", (object?)f.FlockId ?? DBNull.Value);

        // =====================================================================
        // 1. Farm Summary
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryFarmSummaryReportSummary, PoultryFarmSummaryReportRow>>
            GetFarmSummaryAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryFarmSummaryReportSummary, PoultryFarmSummaryReportRow>("Poultry Farm Summary", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_farmsummary_rs1(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int); SELECT * FROM sppoultryreport_farmsummary_rs2(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var eggs = LongOr(r, "EggsProduced");
                var birdDays = LongOr(r, "BirdDays");
                var rev = DecOr(r, "SalesRevenue");
                var exp = DecOr(r, "ExpensesAllocated");
                resp.Rows.Add(new PoultryFarmSummaryReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    StartingBirds = IntOr(r, "StartingBirds"),
                    CurrentBirds = IntOr(r, "CurrentBirds"),
                    EggsProduced = eggs,
                    BrokenRejectedEggs = LongOr(r, "BrokenRejectedEggs"),
                    EggProductionPercent = Percent(eggs, birdDays),
                    FeedConsumedKg = DecOr(r, "FeedConsumedKg"),
                    Deaths = IntOr(r, "Deaths"),
                    SalesRevenue = rev,
                    ExpensesAllocated = exp,
                    EstimatedProfit = rev - exp,
                });
            }

            var summary = new PoultryFarmSummaryReportSummary
            {
                ActiveBirds = resp.Rows.Where(x => x.CurrentBirds > 0).Sum(x => x.CurrentBirds),
            };
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                var totalEggs = LongOr(r, "TotalEggs");
                var broken = LongOr(r, "BrokenRejectedEggs");
                var rev = DecOr(r, "SalesRevenue");
                var exp = DecOr(r, "Expenses");
                summary.TotalEggsProduced = totalEggs;
                summary.SaleableEggs = Math.Max(0, totalEggs - broken);
                summary.BrokenRejectedEggs = broken;
                summary.Deaths = IntOr(r, "Deaths");
                summary.FeedConsumedKg = DecOr(r, "FeedConsumedKg");
                summary.SalesRevenue = rev;
                summary.Expenses = exp;
                summary.EstimatedProfit = rev - exp;
                summary.CashCollected = DecOr(r, "CashCollected");
                summary.CustomerReceivables = DecOr(r, "CustomerReceivables");
                summary.ActiveFlocks = IntOr(r, "ActiveFlocks");
            }
            resp.Summary = summary;
            resp.Warnings.Add("Feed cost is shown from expenses categorised as \"Feed\"; itemised feed valuation is not tracked.");
            return resp;
        }

        // =====================================================================
        // 2. Daily Egg Production
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryDailyEggProductionReportSummary, PoultryDailyEggProductionReportRow>>
            GetDailyEggProductionAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryDailyEggProductionReportSummary, PoultryDailyEggProductionReportRow>("Poultry Daily Egg Production", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_dailyeggproduction(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var total = LongOr(r, "TotalEggs");
                var broken = (int)LongOr(r, "BrokenEggs");
                var birds = LongOr(r, "BirdCount");
                resp.Rows.Add(new PoultryDailyEggProductionReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    AgeInWeeks = IntN(r, "AgeInWeeks"),
                    MorningEggs = IntOr(r, "MorningEggs"),
                    MiddayEggs = IntOr(r, "MiddayEggs"),
                    EveningEggs = IntOr(r, "EveningEggs"),
                    FourthPickEggs = IntOr(r, "FourthPickEggs"),
                    TotalEggs = total,
                    BrokenEggs = broken,
                    SaleableEggs = Math.Max(0, total - broken),
                    EggProductionPercent = Percent(total, birds),
                    Notes = Str(r, "Notes"),
                });
            }

            var byDay = resp.Rows.GroupBy(x => x.Date.Date)
                                 .Select(g => new { Day = g.Key, Eggs = g.Sum(x => x.TotalEggs) }).ToList();
            var summary = new PoultryDailyEggProductionReportSummary
            {
                TotalEggs = resp.Rows.Sum(x => x.TotalEggs),
                TotalBrokenEggs = resp.Rows.Sum(x => (long)x.BrokenEggs),
                AverageEggsPerDay = byDay.Count == 0 ? 0 : Math.Round(byDay.Average(x => (double)x.Eggs), 1),
                AverageProductionPercent = resp.Rows.Where(x => x.EggProductionPercent != null).Any()
                    ? Math.Round(resp.Rows.Where(x => x.EggProductionPercent != null).Average(x => x.EggProductionPercent!.Value), 2)
                    : (double?)null,
            };
            if (byDay.Count > 0)
            {
                var best = byDay.OrderByDescending(x => x.Eggs).First();
                var low = byDay.OrderBy(x => x.Eggs).First();
                summary.BestProductionDay = best.Day; summary.BestProductionDayEggs = best.Eggs;
                summary.LowestProductionDay = low.Day; summary.LowestProductionDayEggs = low.Eggs;
            }
            resp.Summary = summary;
            return resp;
        }

        // =====================================================================
        // 3. Flock Production Summary
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryFlockProductionSummaryReportSummary, PoultryFlockProductionSummaryReportRow>>
            GetFlockProductionSummaryAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryFlockProductionSummaryReportSummary, PoultryFlockProductionSummaryReportRow>("Poultry Flock Production Summary", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_flockproductionsummary(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var eggs = LongOr(r, "TotalEggs");
                var days = IntOr(r, "ProductionDays");
                var birdDays = LongOr(r, "BirdDays");
                var deaths = IntOr(r, "Deaths");
                var pct = Percent(eggs, birdDays);
                resp.Rows.Add(new PoultryFlockProductionSummaryReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    FlockAgeWeeks = IntN(r, "FlockAgeWeeks"),
                    BirdsPlaced = IntOr(r, "BirdsPlaced"),
                    CurrentBirds = IntOr(r, "CurrentBirds"),
                    TotalEggs = eggs,
                    AverageDailyEggs = days == 0 ? 0 : Math.Round((double)eggs / days, 1),
                    PeakDailyEggs = LongOr(r, "PeakDailyEggs"),
                    BrokenEggs = LongOr(r, "BrokenEggs"),
                    ProductionPercent = pct,
                    FeedConsumedKg = DecOr(r, "FeedConsumedKg"),
                    Deaths = deaths,
                    Status = BandAgainstTarget(pct, 75),
                });
            }

            var produced = resp.Rows.Where(x => x.TotalEggs > 0).ToList();
            resp.Summary = new PoultryFlockProductionSummaryReportSummary
            {
                ActiveFlocks = resp.Rows.Count,
                TotalEggs = resp.Rows.Sum(x => x.TotalEggs),
                AverageEggsPerFlock = resp.Rows.Count == 0 ? 0 : Math.Round(resp.Rows.Average(x => (double)x.TotalEggs), 1),
                AverageProductionPercent = produced.Where(x => x.ProductionPercent != null).Any()
                    ? Math.Round(produced.Where(x => x.ProductionPercent != null).Average(x => x.ProductionPercent!.Value), 2) : (double?)null,
                BestProducingFlock = produced.OrderByDescending(x => x.TotalEggs).FirstOrDefault()?.FlockName,
                LowestProducingFlock = produced.OrderBy(x => x.TotalEggs).FirstOrDefault()?.FlockName,
            };
            return resp;
        }

        // =====================================================================
        // 4. Hen-Day Production
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryHenDayProductionReportSummary, PoultryHenDayProductionReportRow>>
            GetHenDayProductionAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryHenDayProductionReportSummary, PoultryHenDayProductionReportRow>("Poultry Hen-Day Production", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_hendayproduction(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var birds = LongOr(r, "LiveBirds");
                var eggs = LongOr(r, "EggsProduced");
                var hd = Percent(eggs, birds);
                resp.Rows.Add(new PoultryHenDayProductionReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    LiveBirds = (int)birds,
                    EggsProduced = eggs,
                    HenDayPercent = hd,
                    TargetPercent = null,
                    Variance = null,
                    Status = hd == null ? "N/A" : (hd >= 80 ? "Good" : hd >= 60 ? "Watch" : "Critical"),
                });
            }

            var hds = resp.Rows.Where(x => x.HenDayPercent != null).Select(x => x.HenDayPercent!.Value).ToList();
            resp.Summary = new PoultryHenDayProductionReportSummary
            {
                AverageHenDayPercent = hds.Count == 0 ? null : Math.Round(hds.Average(), 2),
                HighestHenDayPercent = hds.Count == 0 ? null : Math.Round(hds.Max(), 2),
                LowestHenDayPercent = hds.Count == 0 ? null : Math.Round(hds.Min(), 2),
                FlocksBelowTarget = resp.Rows.Where(x => x.Status == "Critical" || x.Status == "Watch")
                                            .Select(x => x.FlockId).Distinct().Count(),
            };
            resp.Warnings.Add("No per-flock production target is configured; status uses standard layer bands (Good ≥ 80%, Watch 60–80%).");
            return resp;
        }

        // =====================================================================
        // 5. Mortality
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryMortalityReportSummary, PoultryMortalityReportRow>>
            GetMortalityAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryMortalityReportSummary, PoultryMortalityReportRow>("Poultry Mortality", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_mortality(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // Rows arrive ordered by flock, date (asc) so we can build cumulative.
            var cumulativeByFlock = new Dictionary<int, int>();
            while (await r.ReadAsync())
            {
                var flockKey = IntN(r, "FlockId") ?? -1;
                var deaths = IntOr(r, "Deaths");
                var placed = IntOr(r, "BirdsPlaced");
                var opening = IntN(r, "OpeningBirds");
                cumulativeByFlock.TryGetValue(flockKey, out var prior);
                var cumulative = prior + deaths;
                cumulativeByFlock[flockKey] = cumulative;
                resp.Rows.Add(new PoultryMortalityReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    OpeningBirds = opening,
                    Deaths = deaths,
                    Culls = null,
                    BirdsSoldTransferred = null,
                    ClosingBirds = IntN(r, "ClosingBirds"),
                    DailyMortalityPercent = opening.HasValue ? Percent(deaths, opening.Value) : null,
                    CumulativeMortalityPercent = placed > 0 ? Percent(cumulative, placed) : null,
                    Notes = Str(r, "Notes"),
                });
            }

            var byDay = resp.Rows.GroupBy(x => x.Date.Date).Select(g => new { g.Key, D = g.Sum(x => x.Deaths) }).ToList();
            var totalDeaths = resp.Rows.Sum(x => x.Deaths);
            resp.Summary = new PoultryMortalityReportSummary
            {
                TotalDeaths = totalDeaths,
                AverageDailyDeaths = byDay.Count == 0 ? 0 : Math.Round(byDay.Average(x => (double)x.D), 1),
                HighestMortalityDay = byDay.OrderByDescending(x => x.D).FirstOrDefault()?.Key,
                HighestMortalityDayDeaths = byDay.OrderByDescending(x => x.D).FirstOrDefault()?.D ?? 0,
                CumulativeMortalityPercent = resp.Rows.Where(x => x.CumulativeMortalityPercent != null)
                                                     .OrderByDescending(x => x.Date).FirstOrDefault()?.CumulativeMortalityPercent,
                FlocksWithHighMortality = resp.Rows.Where(x => (x.CumulativeMortalityPercent ?? 0) > 10)
                                                  .Select(x => x.FlockId).Distinct().Count(),
            };
            return resp;
        }

        // =====================================================================
        // 6. Birds on Hand
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryBirdsOnHandReportSummary, PoultryBirdsOnHandReportRow>>
            GetBirdsOnHandAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryBirdsOnHandReportSummary, PoultryBirdsOnHandReportRow>("Poultry Birds on Hand", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_birdsonhand(p_farmid => @FarmId::text, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var placed = IntOr(r, "BirdsPlaced");
                var deaths = IntOr(r, "Deaths");
                var current = IntN(r, "CurrentRecordedBirds") ?? Math.Max(0, placed - deaths);
                var expected = placed - deaths; // culls / sold / transfers not tracked
                var variance = current - expected;
                resp.Rows.Add(new PoultryBirdsOnHandReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    BirdsPlaced = placed,
                    TransfersIn = null,
                    Deaths = deaths,
                    Culls = null,
                    BirdsSold = null,
                    TransfersOut = null,
                    ExpectedBirdsOnHand = expected,
                    CurrentRecordedBirds = current,
                    Variance = variance,
                    Status = VarianceBand(variance),
                });
            }

            resp.Summary = new PoultryBirdsOnHandReportSummary
            {
                TotalBirdsPlaced = resp.Rows.Sum(x => x.BirdsPlaced),
                CurrentLiveBirds = resp.Rows.Sum(x => x.CurrentRecordedBirds),
                TotalDeaths = resp.Rows.Sum(x => x.Deaths),
                TotalCulls = 0,
                TotalBirdsSoldTransferred = 0,
                BirdVariance = resp.Rows.Sum(x => x.Variance),
            };
            resp.Warnings.Add("Culls, bird sales and transfers are not separately tracked; they are shown as N/A and excluded from the expected count.");
            return resp;
        }

        // =====================================================================
        // 7. Feed Usage
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryFeedUsageReportSummary, PoultryFeedUsageReportRow>>
            GetFeedUsageAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryFeedUsageReportSummary, PoultryFeedUsageReportRow>("Poultry Feed Usage", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_feedusage(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var consumed = DecOr(r, "FeedConsumedKg");
                var birds = IntN(r, "LiveBirds");
                var eggs = LongOr(r, "EggsProduced");
                resp.Rows.Add(new PoultryFeedUsageReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    FeedType = Str(r, "FeedType") ?? "General feed",
                    FeedIssuedKg = null,
                    FeedReturnedKg = null,
                    FeedConsumedKg = consumed,
                    LiveBirds = birds,
                    FeedPerBirdKg = birds is > 0 ? SafeDivide(consumed, birds.Value) : null,
                    EggsProduced = eggs == 0 ? (long?)null : eggs,
                    FeedPerEggKg = eggs > 0 ? SafeDivide(consumed, eggs) : null,
                    Notes = null,
                });
            }

            var totalFeed = resp.Rows.Sum(x => x.FeedConsumedKg);
            var days = resp.Rows.Select(x => x.Date.Date).Distinct().Count();
            var byFlock = resp.Rows.GroupBy(x => x.FlockName).Select(g => new { g.Key, F = g.Sum(x => x.FeedConsumedKg) }).ToList();
            resp.Summary = new PoultryFeedUsageReportSummary
            {
                TotalFeedConsumedKg = totalFeed,
                AverageFeedPerDayKg = days == 0 ? 0 : Math.Round(totalFeed / days, 2),
                AverageFeedPerBirdKg = null,
                HighestFeedConsumingFlock = byFlock.OrderByDescending(x => x.F).FirstOrDefault()?.Key,
                FeedWastageKg = null,
            };
            resp.Warnings.Add("Feed issued vs returned is not tracked separately; recorded feed is treated as consumed.");
            return resp;
        }

        // =====================================================================
        // 8. Feed Inventory Balance
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryFeedInventoryBalanceReportSummary, PoultryFeedInventoryBalanceReportRow>>
            GetFeedInventoryBalanceAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryFeedInventoryBalanceReportSummary, PoultryFeedInventoryBalanceReportRow>("Poultry Feed Inventory Balance", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_feedinventorybalance_rs1(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date); SELECT * FROM sppoultryreport_feedinventorybalance_rs2(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                resp.Rows.Add(new PoultryFeedInventoryBalanceReportRow
                {
                    FeedItem = Str(r, "FeedItem") ?? "General feed",
                    Category = "Feed",
                    OpeningStockKg = null,
                    ReceivedKg = 0,
                    IssuedKg = DecOr(r, "IssuedKg"),
                    AdjustmentsKg = 0,
                    CurrentStockKg = 0,
                    Unit = "kg",
                    UnitCost = null,
                    StockValue = null,
                    ReorderLevelKg = null,
                    EstimatedDaysRemaining = null,
                    Status = "Not itemised",
                });
            }

            var summary = new PoultryFeedInventoryBalanceReportSummary();
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                var net = DecOr(r, "NetAdjustmentsKg");
                var issuedAll = DecOr(r, "TotalIssuedAllTimeKg");
                var last30 = DecOr(r, "Last30IssuedKg");
                var stock = net - issuedAll;
                var avgDaily = last30 / 30m;
                summary.TotalFeedStockKg = stock;
                summary.TotalFeedStockValue = null;
                summary.LowStockItems = stock <= 0 ? 0 : 0;
                summary.OutOfStockItems = stock <= 0 ? 1 : 0;
                summary.EstimatedDaysRemaining = avgDaily > 0 ? (double)Math.Round(stock / avgDaily, 1) : (double?)null;
            }
            resp.Summary = summary;
            resp.Warnings.Add("Feed purchases are not itemised by feed type; per-item opening stock, unit cost and valuation are shown as N/A. The combined farm feed balance is derived from feed adjustments minus feed issued.");
            return resp;
        }

        // =====================================================================
        // 9. Feed Cost Per Egg
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryFeedCostPerEggReportSummary, PoultryFeedCostPerEggReportRow>>
            GetFeedCostPerEggAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryFeedCostPerEggReportSummary, PoultryFeedCostPerEggReportRow>("Poultry Feed Cost Per Egg", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_feedcostperegg(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var feedKg = DecOr(r, "FeedConsumedKg");
                var eggs = LongOr(r, "EggsProduced");
                var birdDays = LongOr(r, "BirdDays");
                var feedCost = DecN(r, "FeedCost");
                var perEgg = feedCost.HasValue && eggs > 0 ? SafeDivide(feedCost.Value, eggs) : null;
                resp.Rows.Add(new PoultryFeedCostPerEggReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    FeedConsumedKg = feedKg,
                    AverageFeedUnitCost = feedCost.HasValue && feedKg > 0 ? SafeDivide(feedCost.Value, feedKg) : null,
                    TotalFeedCost = feedCost,
                    EggsProduced = eggs,
                    FeedCostPerEgg = perEgg,
                    FeedCostPerCrate = PerCrateFromPerEgg(perEgg),
                    ProductionPercent = Percent(eggs, birdDays),
                    Status = perEgg == null ? "N/A" : "OK",
                });
            }

            var totalFeedCost = resp.Rows.Where(x => x.TotalFeedCost != null).Sum(x => x.TotalFeedCost!.Value);
            var totalEggs = resp.Rows.Sum(x => x.EggsProduced);
            var avgPerEgg = totalEggs > 0 ? SafeDivide(totalFeedCost, totalEggs) : null;
            resp.Summary = new PoultryFeedCostPerEggReportSummary
            {
                TotalFeedCost = resp.Rows.Any(x => x.TotalFeedCost != null) ? totalFeedCost : (decimal?)null,
                TotalEggs = totalEggs,
                AverageFeedCostPerEgg = avgPerEgg,
                AverageFeedCostPerCrate = PerCrateFromPerEgg(avgPerEgg),
                MostExpensiveFlock = resp.Rows.Where(x => x.FeedCostPerEgg != null)
                                             .OrderByDescending(x => x.FeedCostPerEgg).FirstOrDefault()?.FlockName,
            };
            resp.Warnings.Add("Feed cost is taken from expenses categorised as \"Feed\" and allocated to a flock when the expense has a flock; unallocated feed expenses are excluded.");
            return resp;
        }

        // =====================================================================
        // 10. Egg Stock Balance
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryEggStockBalanceReportSummary, PoultryEggStockBalanceReportRow>>
            GetEggStockBalanceAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryEggStockBalanceReportSummary, PoultryEggStockBalanceReportRow>("Poultry Egg Stock Balance", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_eggstockbalance(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            long opening = 0, produced = 0, broken = 0, adjustments = 0, openAdj = 0, openSales = 0, salesInRange = 0;
            if (await r.ReadAsync())
            {
                opening = LongOr(r, "OpeningProducedSaleable");
                openAdj = LongOr(r, "OpeningAdjustments");
                openSales = LongOr(r, "OpeningSales");
                produced = LongOr(r, "ProductionAdded");
                broken = LongOr(r, "BrokenInRange");
                adjustments = LongOr(r, "AdjustmentsInRange");
                salesInRange = LongOr(r, "SalesInRange");
            }
            var openingStock = Math.Max(0, opening + openAdj - openSales);
            var saleableProduced = Math.Max(0, produced - broken);
            // Current stock = opening + saleable production + adjustments − eggs sold in range.
            var current = Math.Max(0, openingStock + saleableProduced + adjustments - salesInRange);
            resp.Rows.Add(new PoultryEggStockBalanceReportRow
            {
                ProductGrade = "All eggs (combined)",
                OpeningStock = openingStock,
                ProductionAdded = saleableProduced,
                SalesRemoved = salesInRange,
                LossesAdjustments = broken,
                CurrentStockEggs = current,
                CurrentStockCrates = Crates(current),
                LooseEggs = LooseEggs(current),
                AverageSellingPrice = null,
                StockValue = null,
                Status = current > 0 ? "In stock" : "Empty",
            });

            resp.Summary = new PoultryEggStockBalanceReportSummary
            {
                TotalEggsInStock = current,
                TotalCrates = Crates(current),
                LooseEggs = LooseEggs(current),
                SaleableEggs = current,
                BrokenRejectedEggs = broken,
                StockValue = null,
            };
            resp.Warnings.Add("Egg stock is reported as a single combined balance: egg grades and selling-price valuation are not tracked through to inventory. Eggs sold (sales with an \"egg\" product) are deducted from the balance.");
            return resp;
        }

        // =====================================================================
        // 11. Egg Sales
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryEggSalesReportSummary, PoultryEggSalesReportRow>>
            GetEggSalesAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryEggSalesReportSummary, PoultryEggSalesReportRow>("Poultry Egg Sales", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_eggsales_rs1(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_customername => @CustomerName::text, p_flockid => @FlockId::int); SELECT * FROM sppoultryreport_eggsales_rs2(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_customername => @CustomerName::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@CustomerName", (object?)f.CustomerName ?? DBNull.Value);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var total = DecOr(r, "TotalAmount");
                var paid = BoolOr(r, "Paid", true);
                // Migration 197 returns AmountPaid (part-payments from
                // dbo.PoultryPayments). The default keeps older databases — where
                // the column isn't selected — on the previous all-or-nothing rule.
                var amountPaid = DecOr(r, "AmountPaid", paid ? total : 0m);
                if (amountPaid > total) amountPaid = total;   // over-payment isn't negative debt
                var balance = total - amountPaid;
                resp.Rows.Add(new PoultryEggSalesReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    SaleId = IntOr(r, "SaleId"),
                    Customer = Str(r, "Customer"),
                    ProductGrade = Str(r, "Size") ?? Str(r, "Product"),
                    QuantitySold = DecOr(r, "QuantitySold"),
                    Unit = Str(r, "Size"),
                    EggsEquivalent = null,
                    UnitPrice = DecOr(r, "UnitPrice"),
                    TotalAmount = total,
                    AmountPaid = amountPaid,
                    Balance = balance,
                    PaymentStatus = balance <= 0 ? "Paid" : amountPaid > 0 ? "Part paid" : "Unpaid",
                    PaymentMethod = Str(r, "PaymentMethod"),
                });
            }

            // Result set 2 (migration 197): the non-egg sales the report filters
            // out. Reported as a warning so the exclusion is never silent.
            var excludedCount = 0;
            var excludedAmount = 0m;
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                excludedCount = IntOr(r, "ExcludedCount");
                excludedAmount = DecOr(r, "ExcludedAmount");
            }

            var topCustomer = resp.Rows.Where(x => !string.IsNullOrWhiteSpace(x.Customer))
                .GroupBy(x => x.Customer!).Select(g => new { g.Key, T = g.Sum(x => x.TotalAmount) })
                .OrderByDescending(x => x.T).FirstOrDefault()?.Key;
            resp.Summary = new PoultryEggSalesReportSummary
            {
                TotalSalesRevenue = resp.Rows.Sum(x => x.TotalAmount),
                TotalEggsSold = resp.Rows.Sum(x => x.QuantitySold),
                TotalCratesSold = 0,
                TotalPaid = resp.Rows.Sum(x => x.AmountPaid),
                TotalUnpaid = resp.Rows.Sum(x => x.Balance),
                TopCustomer = topCustomer,
            };
            resp.Warnings.Add("Sale quantity unit is recorded free-form; crate/egg equivalents are not derived automatically.");
            if (excludedCount > 0)
                resp.Warnings.Add($"Egg products only — {excludedCount} non-egg sale(s) worth {excludedAmount:N2} (bird, manure or other) were excluded from these totals.");
            return resp;
        }

        // =====================================================================
        // 12. Customer Balance
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryCustomerBalanceReportSummary, PoultryCustomerBalanceReportRow>>
            GetCustomerBalanceAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryCustomerBalanceReportSummary, PoultryCustomerBalanceReportRow>("Poultry Customer Balance", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_customerbalance(p_farmid => @FarmId::text, p_enddate => @EndDate::date, p_customername => @CustomerName::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.AddWithValue("@CustomerName", (object?)f.CustomerName ?? DBNull.Value);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var sales = DecOr(r, "TotalSales");
                var paid = DecOr(r, "TotalPaid");
                var balance = sales - paid;
                resp.Rows.Add(new PoultryCustomerBalanceReportRow
                {
                    Customer = Str(r, "Customer") ?? "Unknown",
                    TotalSales = sales,
                    TotalPaid = paid,
                    CurrentBalance = balance,
                    LastSaleDate = DateN(r, "LastSaleDate"),
                    LastPaymentDate = null,
                    OverdueAmount = null,
                    Status = balance <= 0 ? "Settled" : "Owing",
                });
            }

            var owing = resp.Rows.Where(x => x.CurrentBalance > 0).ToList();
            resp.Summary = new PoultryCustomerBalanceReportSummary
            {
                CustomersWithBalance = owing.Count,
                TotalReceivables = owing.Sum(x => x.CurrentBalance),
                OverdueAmount = null,
                HighestOwingCustomer = owing.OrderByDescending(x => x.CurrentBalance).FirstOrDefault()?.Customer,
            };
            resp.Warnings.Add("Balances count part-payments recorded against a sale. Credit notes and due dates are not tracked, so overdue amount is N/A.");
            return resp;
        }

        // =====================================================================
        // 13. Expense Summary
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryExpenseSummaryReportSummary, PoultryExpenseSummaryReportRow>>
            GetExpenseSummaryAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryExpenseSummaryReportSummary, PoultryExpenseSummaryReportRow>("Poultry Expense Summary", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_expensesummary(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_supplier => @Supplier::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@Supplier", (object?)f.SupplierName ?? DBNull.Value);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var amount = DecOr(r, "Amount");
                resp.Rows.Add(new PoultryExpenseSummaryReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    ExpenseId = IntOr(r, "ExpenseId"),
                    Category = Str(r, "Category") ?? "Uncategorised",
                    Description = Str(r, "Description"),
                    FlockName = Str(r, "FlockName"),
                    Supplier = Str(r, "Supplier"),
                    Amount = amount,
                    AmountPaid = amount,
                    Balance = 0,
                    PaymentMethod = Str(r, "PaymentMethod"),
                    Status = "Paid",
                    CreatedBy = Str(r, "CreatedBy"),
                });
            }

            var total = resp.Rows.Sum(x => x.Amount);
            var days = resp.Rows.Select(x => x.Date.Date).Distinct().Count();
            var byCat = resp.Rows.GroupBy(x => x.Category).Select(g => new { g.Key, A = g.Sum(x => x.Amount) }).ToList();
            resp.Summary = new PoultryExpenseSummaryReportSummary
            {
                TotalExpenses = total,
                PaidExpenses = total,
                UnpaidExpenses = 0,
                LargestExpenseCategory = byCat.OrderByDescending(x => x.A).FirstOrDefault()?.Key,
                AverageDailyExpense = days == 0 ? 0 : Math.Round(total / days, 2),
            };
            resp.Warnings.Add("Poultry expenses do not track a payment status; all are treated as paid (unpaid balance = 0).");
            return resp;
        }

        // =====================================================================
        // 14. Cash Movement
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryCashMovementReportSummary, PoultryCashMovementReportRow>>
            GetCashMovementAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryCashMovementReportSummary, PoultryCashMovementReportRow>("Poultry Cash Movement", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_cashmovement_rs1(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date); SELECT * FROM sppoultryreport_cashmovement_rs2(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            decimal opening = 0;
            if (await r.ReadAsync()) opening = DecOr(r, "OpeningCashBalance");

            var running = opening;
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    var inflow = DecOr(r, "Inflow");
                    var outflow = DecOr(r, "Outflow");
                    running += inflow - outflow;
                    resp.Rows.Add(new PoultryCashMovementReportRow
                    {
                        Date = DateN(r, "Date") ?? start,
                        CashAccount = "Farm cash",
                        SourceType = Str(r, "SourceType") ?? "—",
                        Reference = Str(r, "Reference"),
                        Description = Str(r, "Description"),
                        Inflow = inflow,
                        Outflow = outflow,
                        BalanceAfter = running,
                        CreatedBy = Str(r, "CreatedBy"),
                        Status = null,
                    });
                }
            }

            var inflows = resp.Rows.Sum(x => x.Inflow);
            var outflows = resp.Rows.Sum(x => x.Outflow);
            resp.Summary = new PoultryCashMovementReportSummary
            {
                OpeningCashBalance = opening,
                TotalInflows = inflows,
                TotalOutflows = outflows,
                EndingBalance = opening + inflows - outflows,
                NetCashMovement = inflows - outflows,
            };
            resp.Warnings.Add("Poultry has no dedicated cash-account ledger; cash movement is reconstructed from paid sales (inflows) and expenses (outflows).");
            return resp;
        }

        // =====================================================================
        // 15. Profit & Loss by Flock
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryProfitLossByFlockReportSummary, PoultryProfitLossByFlockReportRow>>
            GetProfitLossByFlockAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryProfitLossByFlockReportSummary, PoultryProfitLossByFlockReportRow>("Poultry Profit & Loss by Flock", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_profitlossbyflock(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var eggRev = DecOr(r, "EggRevenue");
                var birdRev = DecOr(r, "BirdSalesRevenue");
                var otherRev = DecOr(r, "OtherRevenue");
                var revenue = DecOr(r, "TotalRevenue");
                var feed = DecOr(r, "FeedCost");
                var med = DecOr(r, "MedicineVaccineCost");
                var labor = DecOr(r, "LaborCost");
                var other = DecOr(r, "OtherExpenses");
                var eggs = LongOr(r, "EggsProduced");
                var placed = IntOr(r, "BirdsPlaced");
                var totalCost = feed + med + labor + other;
                var net = revenue - totalCost;
                resp.Rows.Add(new PoultryProfitLossByFlockReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    EggRevenue = eggRev,
                    BirdSalesRevenue = birdRev,
                    OtherRevenue = otherRev,
                    FeedCost = feed,
                    MedicineVaccineCost = med,
                    LaborCost = labor,
                    OtherExpenses = other,
                    TotalRevenue = revenue,
                    TotalCost = totalCost,
                    GrossProfit = revenue - feed,
                    NetProfit = net,
                    ProfitPerBirdPlaced = placed > 0 ? SafeDivide(net, placed) : null,
                    ProfitPerEgg = eggs > 0 ? SafeDivide(net, eggs) : null,
                    Status = net >= 0 ? "Profit" : "Loss",
                });
            }

            var rev = resp.Rows.Sum(x => x.TotalRevenue);
            var exp = resp.Rows.Sum(x => x.TotalCost);
            resp.Summary = new PoultryProfitLossByFlockReportSummary
            {
                TotalRevenue = rev,
                TotalExpenses = exp,
                GrossProfit = resp.Rows.Sum(x => x.GrossProfit),
                NetProfit = rev - exp,
                MostProfitableFlock = resp.Rows.OrderByDescending(x => x.NetProfit).FirstOrDefault()?.FlockName,
                LeastProfitableFlock = resp.Rows.OrderBy(x => x.NetProfit).FirstOrDefault()?.FlockName,
                EggRevenue = resp.Rows.Sum(x => x.EggRevenue),
                BirdSalesRevenue = resp.Rows.Sum(x => x.BirdSalesRevenue),
                OtherRevenue = resp.Rows.Sum(x => x.OtherRevenue),
                FeedCost = resp.Rows.Sum(x => x.FeedCost ?? 0),
                MedicineVaccineCost = resp.Rows.Sum(x => x.MedicineVaccineCost ?? 0),
                LaborCost = resp.Rows.Sum(x => x.LaborCost ?? 0),
                OtherExpenses = resp.Rows.Sum(x => x.OtherExpenses),
            };
            resp.Warnings.Add("Revenue and costs are allocated to a flock only when the sale/expense record has a flock id. Revenue is split by the sale's product name (egg / bird / other). Unallocated (farm-level) income and costs are not shown per flock.");
            return resp;
        }

        // =====================================================================
        // 15b. Profit & Loss (company-wide — all sales/expenses, not per flock)
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryProfitLossReportSummary, PoultryProfitLossReportRow>>
            GetProfitLossAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryProfitLossReportSummary, PoultryProfitLossReportRow>("Poultry Profit & Loss", f, start, end);

            decimal eggRev = 0, birdRev = 0, otherRev = 0, totalRev = 0;
            decimal feed = 0, med = 0, labor = 0, otherExp = 0, totalExp = 0;

            using (var conn = new NpgsqlConnection(_connectionString))
            using (var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_profitloss(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
                cmd.Parameters.AddWithValue("@StartDate", start);
                cmd.Parameters.AddWithValue("@EndDate", end);

                await conn.OpenAsync();
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    eggRev   = DecOr(r, "EggRevenue");
                    birdRev  = DecOr(r, "BirdSalesRevenue");
                    otherRev = DecOr(r, "OtherRevenue");
                    totalRev = DecOr(r, "TotalRevenue");
                    feed     = DecOr(r, "FeedCost");
                    med      = DecOr(r, "MedicineVaccineCost");
                    labor    = DecOr(r, "LaborCost");
                    otherExp = DecOr(r, "OtherExpenses");
                    totalExp = DecOr(r, "TotalExpenses");
                }
            }

            var grossProfit = totalRev - feed;   // feed is the primary cost of goods in poultry
            var netProfit = totalRev - totalExp;

            decimal? Pct(decimal part, decimal whole) =>
                whole == 0 ? (decimal?)null : Math.Round(part / whole * 100m, 1);

            // A single wide company row (mirrors the per-flock P&L table layout).
            resp.Rows.Add(new PoultryProfitLossReportRow
            {
                Scope = $"{start:yyyy-MM-dd} → {end:yyyy-MM-dd}",
                EggRevenue = eggRev,
                BirdSalesRevenue = birdRev,
                OtherRevenue = otherRev,
                TotalRevenue = totalRev,
                FeedCost = feed,
                MedicineVaccineCost = med,
                LaborCost = labor,
                OtherExpenses = otherExp,
                TotalCost = totalExp,
                GrossProfit = grossProfit,
                NetProfit = netProfit,
                Status = netProfit >= 0 ? "Profit" : "Loss",
            });

            resp.Summary = new PoultryProfitLossReportSummary
            {
                TotalRevenue = totalRev,
                TotalExpenses = totalExp,
                GrossProfit = grossProfit,
                NetProfit = netProfit,
                NetMarginPercent = Pct(netProfit, totalRev),
                EggRevenue = eggRev,
                BirdSalesRevenue = birdRev,
                OtherRevenue = otherRev,
                FeedCost = feed,
                MedicineVaccineCost = med,
                LaborCost = labor,
                OtherExpenses = otherExp,
                Status = netProfit >= 0 ? "Profit" : "Loss",
            };
            resp.Warnings.Add("Company-wide figures include ALL sales and expenses for the period, whether or not they are attributed to a flock. Revenue is split by the sale's product name and expenses by category keyword; anything unrecognised falls under \"Other\".");
            return resp;
        }

        // =====================================================================
        // 16. Cost Per Egg
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryCostPerEggReportSummary, PoultryCostPerEggReportRow>>
            GetCostPerEggAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryCostPerEggReportSummary, PoultryCostPerEggReportRow>("Poultry Cost Per Egg", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_costperegg(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_includeclosedflocks => @IncludeClosedFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            cmd.Parameters.AddWithValue("@IncludeClosedFlocks", f.IncludeClosedFlocks);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var eggs = LongOr(r, "EggsProduced");
                var feed = DecOr(r, "FeedCost");
                var med = DecOr(r, "MedicineVaccineCost");
                var labor = DecOr(r, "LaborCost");
                var totalCost = DecOr(r, "TotalAllocatedCost");
                var other = Math.Max(0, totalCost - feed - med - labor);
                var price = DecN(r, "SellingPricePerUnit");
                var perEgg = eggs > 0 ? SafeDivide(totalCost, eggs) : null;
                resp.Rows.Add(new PoultryCostPerEggReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    EggsProduced = eggs,
                    FeedCost = feed,
                    MedicineVaccineCost = med,
                    LaborCost = labor,
                    OtherAllocatedCost = other,
                    TotalCost = totalCost,
                    CostPerEgg = perEgg,
                    CostPerCrate = PerCrateFromPerEgg(perEgg),
                    SellingPricePerEgg = price,
                    MarginPerEgg = price.HasValue && perEgg.HasValue ? price - perEgg : null,
                });
            }

            var totalEggs = resp.Rows.Sum(x => x.EggsProduced);
            var totalCostAll = resp.Rows.Sum(x => x.TotalCost);
            var avgPerEgg = totalEggs > 0 ? SafeDivide(totalCostAll, totalEggs) : null;
            resp.Summary = new PoultryCostPerEggReportSummary
            {
                TotalEggsProduced = totalEggs,
                TotalDirectCosts = resp.Rows.Sum(x => x.FeedCost ?? 0) + resp.Rows.Sum(x => x.MedicineVaccineCost ?? 0),
                TotalAllocatedCosts = totalCostAll,
                AverageCostPerEgg = avgPerEgg,
                AverageCostPerCrate = PerCrateFromPerEgg(avgPerEgg),
            };
            resp.Warnings.Add("Cost per egg uses flock-allocated expenses only. Labour and overheads are included only when categorised and allocated to the flock.");
            return resp;
        }

        // =====================================================================
        // 17. Vaccination Schedule
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryVaccinationScheduleReportSummary, PoultryVaccinationScheduleReportRow>>
            GetVaccinationScheduleAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryVaccinationScheduleReportSummary, PoultryVaccinationScheduleReportRow>("Poultry Vaccination Schedule", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_vaccinationschedule(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                resp.Rows.Add(new PoultryVaccinationScheduleReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    Vaccine = Str(r, "Vaccine"),
                    Disease = null,
                    RecommendedAgeOrDate = null,
                    ScheduledDate = null,
                    ActualDate = DateN(r, "ActualDate"),
                    Dose = null,
                    Route = null,
                    Status = "Completed",
                    AdministeredBy = Str(r, "AdministeredBy"),
                    Notes = Str(r, "Notes"),
                });
            }

            resp.Summary = new PoultryVaccinationScheduleReportSummary
            {
                Upcoming = 0,
                DueToday = 0,
                OverdueMissed = 0,
                Completed = resp.Rows.Count,
            };
            resp.Warnings.Add("A structured vaccination schedule is not yet tracked. This report lists vaccinations already recorded in health records (all shown as Completed); upcoming/due/overdue are not available.");
            return resp;
        }

        // =====================================================================
        // 18. Medicine Usage
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryMedicineUsageReportSummary, PoultryMedicineUsageReportRow>>
            GetMedicineUsageAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryMedicineUsageReportSummary, PoultryMedicineUsageReportRow>("Poultry Medicine Usage", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_medicineusage(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                resp.Rows.Add(new PoultryMedicineUsageReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unassigned",
                    Medicine = Str(r, "Medicine"),
                    SymptomsCondition = null,
                    Dosage = null,
                    QuantityUsed = null,
                    UnitCost = null,
                    TotalCost = null,
                    StartDate = null,
                    EndDate = null,
                    WithdrawalPeriod = null,
                    AdministeredBy = Str(r, "CreatedBy"),
                    Notes = Str(r, "Notes"),
                });
            }

            var mostUsed = resp.Rows.Where(x => !string.IsNullOrWhiteSpace(x.Medicine))
                .GroupBy(x => x.Medicine!).OrderByDescending(g => g.Count()).FirstOrDefault()?.Key;
            resp.Summary = new PoultryMedicineUsageReportSummary
            {
                TotalMedicineCost = null,
                NumberOfTreatments = resp.Rows.Count,
                MostUsedMedicine = mostUsed,
                FlocksUnderTreatment = resp.Rows.Select(x => x.FlockId).Distinct().Count(),
                ExpiringMedicine = null,
            };
            resp.Warnings.Add("Medicine records are free-text (from health records and production-record medication notes). Structured quantity, unit cost and withdrawal periods are not tracked, so cost is N/A.");
            return resp;
        }

        // =====================================================================
        // 19. Missing Daily Records
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryMissingDailyRecordsReportSummary, PoultryMissingDailyRecordsReportRow>>
            GetMissingDailyRecordsAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryMissingDailyRecordsReportSummary, PoultryMissingDailyRecordsReportRow>("Poultry Missing Daily Records", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_missingdailyrecords_rs1(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int); SELECT * FROM sppoultryreport_missingdailyrecords_rs2(p_farmid => @FarmId::text, p_startdate => @StartDate::date, p_enddate => @EndDate::date, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@StartDate", start);
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var hasProd = BoolOr(r, "HasProductionRecord");
                var hasFeed = BoolOr(r, "HasFeedUsage");
                var hasMort = BoolOr(r, "HasMortalityUpdate");
                var hasHealth = BoolOr(r, "HasHealthNote");
                var missing = new List<string>();
                if (!hasProd) missing.Add("Production");
                if (!hasFeed) missing.Add("Feed");
                if (!hasMort) missing.Add("Bird update");
                resp.Rows.Add(new PoultryMissingDailyRecordsReportRow
                {
                    Date = DateN(r, "Date") ?? start,
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    HasProductionRecord = hasProd,
                    HasFeedUsage = hasFeed,
                    HasMortalityUpdate = hasMort,
                    HasHealthNote = hasHealth,
                    MissingItems = missing.Count == 0 ? "—" : string.Join(", ", missing),
                    AssignedEmployee = null,
                    Status = missing.Count == 0 ? "Complete" : "Incomplete",
                });
            }

            var summary = new PoultryMissingDailyRecordsReportSummary();
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                summary.ActiveFlocks = IntOr(r, "ActiveFlocks");
                summary.MissingProductionRecords = IntOr(r, "MissingProductionRecords");
                summary.MissingFeedRecords = IntOr(r, "MissingFeedRecords");
                summary.MissingHealthRecords = IntOr(r, "MissingHealthRecords");
                summary.CompleteFlockDays = IntOr(r, "CompleteFlockDays");
            }
            resp.Summary = summary;
            resp.Warnings.Add("A flock-day is flagged when a production record or feed entry is missing. Feed is considered present if a feed-usage entry exists or the production record has feed recorded.");
            return resp;
        }

        // =====================================================================
        // 20. End-of-Flock
        // =====================================================================
        public async Task<PoultryReportResponse<PoultryEndOfFlockReportSummary, PoultryEndOfFlockReportRow>>
            GetEndOfFlockAsync(PoultryReportFilterDto f)
        {
            var (start, end) = ResolveRange(f);
            var resp = NewResponse<PoultryEndOfFlockReportSummary, PoultryEndOfFlockReportRow>("Poultry End-of-Flock", f, start, end);

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_endofflock(p_farmid => @FarmId::text, p_enddate => @EndDate::date, p_includeactiveflocks => @IncludeActiveFlocks::boolean, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", f.FarmId ?? "");
            cmd.Parameters.AddWithValue("@EndDate", end);
            cmd.Parameters.Add(PFlock(f));
            // Active flocks included by default; the "include closed flocks" flag,
            // when OFF, restricts to closed/inactive flocks (lifecycle view).
            cmd.Parameters.AddWithValue("@IncludeActiveFlocks", true);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var placed = IntOr(r, "BirdsPlaced");
                var deaths = IntOr(r, "TotalDeaths");
                var eggs = LongOr(r, "TotalEggsProduced");
                var broken = LongOr(r, "BrokenRejectedEggs");
                var birdDays = LongOr(r, "BirdDays");
                var feed = DecOr(r, "TotalFeedConsumedKg");
                var feedCost = DecOr(r, "FeedCost");
                var med = DecOr(r, "MedicineVaccineCost");
                var labor = DecOr(r, "LaborCost");
                var other = DecOr(r, "OtherCost");
                var revenue = DecOr(r, "TotalRevenue");
                var totalCost = feedCost + med + labor + other;
                var net = revenue - totalCost;
                var perEgg = eggs > 0 ? SafeDivide(net, eggs) : null;
                resp.Rows.Add(new PoultryEndOfFlockReportRow
                {
                    FlockId = IntN(r, "FlockId"),
                    FlockName = Str(r, "FlockName") ?? "Unnamed flock",
                    PlacementDate = DateN(r, "PlacementDate"),
                    ClosingDate = null,
                    FlockAgeWeeks = IntN(r, "FlockAgeWeeks"),
                    BirdsPlaced = placed,
                    TotalDeaths = deaths,
                    Culls = null,
                    BirdsSoldTransferred = null,
                    FinalBirdsRemaining = IntOr(r, "FinalBirdsRemaining"),
                    TotalEggsProduced = eggs,
                    SaleableEggs = Math.Max(0, eggs - broken),
                    BrokenRejectedEggs = broken,
                    PeakProductionDay = LongOr(r, "PeakProductionDay"),
                    AverageProductionPercent = Percent(eggs, birdDays),
                    TotalFeedConsumedKg = feed,
                    FeedCost = feedCost,
                    MedicineVaccineCost = med,
                    LaborCost = labor,
                    OtherCost = other,
                    EggSalesRevenue = revenue,
                    BirdSalesRevenue = 0,
                    OtherRevenue = 0,
                    TotalRevenue = revenue,
                    TotalCost = totalCost,
                    NetProfit = net,
                    ProfitPerBirdPlaced = placed > 0 ? SafeDivide(net, placed) : null,
                    ProfitPerEgg = perEgg,
                    MortalityPercent = placed > 0 ? Percent(deaths, placed) : null,
                    Status = BoolOr(r, "Active", true) ? "Active" : "Closed",
                });
            }

            var totalEggs = resp.Rows.Sum(x => x.TotalEggsProduced);
            var totalFeedCost = resp.Rows.Sum(x => x.FeedCost ?? 0);
            var revSum = resp.Rows.Sum(x => x.TotalRevenue);
            var costSum = resp.Rows.Sum(x => x.TotalCost);
            var placedSum = resp.Rows.Sum(x => x.BirdsPlaced);
            var deathsSum = resp.Rows.Sum(x => x.TotalDeaths);
            resp.Summary = new PoultryEndOfFlockReportSummary
            {
                BirdsPlaced = placedSum,
                BirdsRemaining = resp.Rows.Sum(x => x.FinalBirdsRemaining),
                BirdsSoldOrDead = Math.Max(0, placedSum - resp.Rows.Sum(x => x.FinalBirdsRemaining)),
                TotalEggs = totalEggs,
                TotalFeedConsumedKg = resp.Rows.Sum(x => x.TotalFeedConsumedKg),
                TotalRevenue = revSum,
                TotalCost = costSum,
                NetProfit = revSum - costSum,
                MortalityPercent = placedSum > 0 ? Percent(deathsSum, placedSum) : null,
                FeedCostPerEgg = totalEggs > 0 ? SafeDivide(totalFeedCost, totalEggs) : null,
                ProfitPerBird = placedSum > 0 ? SafeDivide(revSum - costSum, placedSum) : null,
            };
            resp.Warnings.Add("Closing date, culls and bird-sales are not tracked. End-of-flock figures cover the flock lifecycle up to the selected end date.");
            return resp;
        }
    }
}
