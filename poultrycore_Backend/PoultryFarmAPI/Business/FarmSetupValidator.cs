using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Server-side rules for the Initial Farm Setup wizard.
    ///
    /// <para>
    /// The browser runs the same rules in <c>lib/farm-setup/wizard.ts</c> so the
    /// grids can flag a bad row as it is typed. This copy is the one that decides.
    /// </para>
    ///
    /// <para><b>Errors versus warnings.</b> Two of the checks here deliberately
    /// differ in severity, and the difference is the point of the feature:</para>
    /// <list type="bullet">
    /// <item><b>Batch total is an ERROR.</b> Flocks claiming 7,000 birds originally
    /// placed out of a 6,000-bird batch is not a thing that can be true, and the
    /// existing single-flock path already refuses it.</item>
    /// <item><b>House capacity is a WARNING.</b> Capacity is a number somebody
    /// typed into a setup form; the birds standing in the pen are a fact. An
    /// established farm onboarding 2,400 birds into a pen recorded as holding
    /// 2,000 is telling us the capacity is wrong, and refusing the onboarding
    /// would be refusing reality. The operational path (Batch Allocation) still
    /// blocks, because there the birds have not been placed yet and the number is
    /// a plan rather than a fact.</item>
    /// </list>
    ///
    /// <para>
    /// Pure and static: no connection string, no DB. Callers pass what they read
    /// through the ordinary farm-scoped readers, which keeps company scoping in
    /// one place.
    /// </para>
    /// </summary>
    public static class FarmSetupValidator
    {
        public const int MaxBatches = 50;
        public const int MaxHouses = 200;
        public const int MaxFlocks = 200;
        public const int MaxNameLength = 100;
        public const int MaxBatchCodeLength = 25;

        private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

        public static string Normalize(string? raw) => (raw ?? string.Empty).Trim();

        public static string DuplicateKey(string? raw) =>
            Whitespace.Replace(Normalize(raw), " ").ToLowerInvariant();

        /// <summary>
        /// Birds unaccounted for between placement and the opening date. Never
        /// negative: a flock with more birds standing than were placed is rejected
        /// as a row error rather than quietly clamped.
        /// </summary>
        public static int HistoricalReduction(FarmSetupFlockInput flock) =>
            Math.Max(0, flock.OriginallyPlaced - flock.CurrentLiveBirds);

        /// <summary>
        /// The breakdown a flock's opening position will actually carry.
        ///
        /// <para>
        /// When the farm does not know the history, the ENTIRE difference becomes
        /// an unknown adjustment and every other bucket is zero. This is the rule
        /// the whole feature turns on: an unexplained reduction is not mortality,
        /// and must never be counted as any.
        /// </para>
        /// </summary>
        public static (int Mortality, int Sold, int Culled, int Transferred, int Other) Breakdown(FarmSetupFlockInput flock)
        {
            var difference = HistoricalReduction(flock);
            if (!flock.HistoryKnown) return (0, 0, 0, 0, difference);

            var known = flock.HistoricalMortality + flock.HistoricalSold
                        + flock.HistoricalCulled + flock.HistoricalTransferred;
            // Whatever the stated buckets do not cover is unknown, not mortality.
            var other = Math.Max(0, difference - known);
            return (flock.HistoricalMortality, flock.HistoricalSold,
                    flock.HistoricalCulled, flock.HistoricalTransferred, other);
        }

        /// <summary>
        /// A start date derived from a stated age. Whole weeks back from the
        /// opening date — an approximation, and the caller records it as estimated
        /// so nothing later presents it as an exact historical timestamp.
        /// </summary>
        public static DateTime DeriveStartDate(DateTime effectiveDate, int ageInWeeks) =>
            effectiveDate.Date.AddDays(-7 * Math.Max(0, ageInWeeks));

        /// <summary>
        /// Whether a correction to an existing opening position may be applied.
        /// Returns null when it may; an error when it may not.
        ///
        /// <para>
        /// The rule follows the application's append-only philosophy. With NO
        /// production records the flock has no operational history, its quantity
        /// is still exactly its opening figure, and restating day one is safe.
        /// </para>
        ///
        /// <para>
        /// Once production exists, the counts are frozen: every
        /// <c>noofbirdsleft</c> already reported was computed forward from the
        /// opening figure, so moving it would rewrite conclusions that have
        /// already been drawn. What IS still allowed is <b>reclassification</b> --
        /// a farm that later remembers 60 of those 90 birds actually died may say
        /// so. That moves nothing: the reduction is the same size, it just stops
        /// being "unknown". Refusing even that would leave a farm permanently
        /// unable to record something it knows to be true.
        /// </para>
        /// </summary>
        public static FarmSetupRowError? ValidateCorrection(
            OpeningFlockPositionModel existing,
            int originallyPlaced,
            int openingLiveBirds,
            bool hasProductionRecords)
        {
            if (originallyPlaced <= 0)
                return Row("Originally placed must be more than zero.", "originallyPlaced");
            if (openingLiveBirds < 0 || openingLiveBirds > originallyPlaced)
                return Row("There cannot be more birds standing than were placed.", "openingLiveBirds");

            if (!hasProductionRecords) return null;

            var movesTheCounts = originallyPlaced != existing.OriginallyPlaced
                                 || openingLiveBirds != existing.OpeningLiveBirds;
            if (!movesTheCounts) return null;

            return Row(
                "This flock already has production records, so its opening bird counts are fixed — " +
                "changing them now would rewrite figures that have already been reported. " +
                "You can still record what the missing birds were (mortality, sold, culled, transferred); " +
                "to change the counts themselves, correct the production records instead.",
                "openingLiveBirds");

            static FarmSetupRowError Row(string message, string field) =>
                new() { Section = "flocks", Index = -1, Field = field, Message = message };
        }

        /// <summary>
        /// Everything wrong with the setup. An empty error list means it can run;
        /// warnings never block.
        /// </summary>
        /// <param name="request">The wizard's payload.</param>
        /// <param name="existingBatches">Batches already on this farm.</param>
        /// <param name="existingHouses">Houses already on this farm, with occupancy.</param>
        /// <param name="existingFlockNames">Flock names already on this farm.</param>
        /// <param name="allocatedByBatchId">
        /// Birds already allocated out of each existing batch, so reusing one does
        /// not let the farm overspend it.
        /// </param>
        public static (List<FarmSetupRowError> Errors, List<FarmSetupRowError> Warnings) Validate(
            FarmSetupRequest request,
            IReadOnlyCollection<MainFlockBatchModel> existingBatches,
            IReadOnlyCollection<HouseOccupancyModel> existingHouses,
            IEnumerable<string> existingFlockNames,
            IReadOnlyDictionary<int, int> allocatedByBatchId)
        {
            var errors = new List<FarmSetupRowError>();
            var warnings = new List<FarmSetupRowError>();

            void Error(string section, int index, string field, string message) =>
                errors.Add(new FarmSetupRowError { Section = section, Index = index, Field = field, Message = message });
            void Warn(string section, int index, string field, string message) =>
                warnings.Add(new FarmSetupRowError { Section = section, Index = index, Field = field, Message = message });

            var batches = request.Batches ?? new List<FarmSetupBatchInput>();
            var houses = request.Houses ?? new List<FarmSetupHouseInput>();
            var flocks = request.Flocks ?? new List<FarmSetupFlockInput>();

            if (flocks.Count == 0)
            {
                Error("setup", -1, "flocks", "Add at least one flock — that is what tells us how many birds you have.");
                return (errors, warnings);
            }
            if (batches.Count > MaxBatches) Error("setup", -1, "batches", $"At most {MaxBatches} batches in one setup.");
            if (houses.Count > MaxHouses) Error("setup", -1, "houses", $"At most {MaxHouses} houses in one setup.");
            if (flocks.Count > MaxFlocks) Error("setup", -1, "flocks", $"At most {MaxFlocks} flocks in one setup.");
            if (errors.Count > 0) return (errors, warnings);

            // ---- Batches --------------------------------------------------
            var existingBatchById = existingBatches.ToDictionary(b => b.BatchId);
            var existingBatchCodes = new HashSet<string>(existingBatches.Select(b => DuplicateKey(b.BatchCode)));
            var batchKeys = new Dictionary<string, FarmSetupBatchInput>(StringComparer.OrdinalIgnoreCase);
            var newBatchCodes = new Dictionary<string, int>();

            for (var i = 0; i < batches.Count; i++)
            {
                var b = batches[i];
                var key = Normalize(b.Key);
                if (key.Length == 0) Error("batches", i, "key", "Every batch row needs an internal reference.");
                else if (batchKeys.ContainsKey(key)) Error("batches", i, "key", "Two batch rows share a reference.");
                else batchKeys[key] = b;

                if (b.ExistingBatchId.HasValue)
                {
                    // Reusing one the farm already has: nothing else on the row matters.
                    if (!existingBatchById.ContainsKey(b.ExistingBatchId.Value))
                        Error("batches", i, "existingBatchId", "That batch is not available on this farm.");
                    continue;
                }

                if (Normalize(b.BatchName).Length == 0) Error("batches", i, "batchName", "Batch name is required.");
                else if (Normalize(b.BatchName).Length > MaxNameLength)
                    Error("batches", i, "batchName", $"Batch name cannot be longer than {MaxNameLength} characters.");

                var code = Normalize(b.BatchCode);
                if (code.Length == 0) Error("batches", i, "batchCode", "Batch code is required.");
                else if (code.Length > MaxBatchCodeLength)
                    Error("batches", i, "batchCode", $"Batch code cannot be longer than {MaxBatchCodeLength} characters.");
                else
                {
                    var codeKey = DuplicateKey(code);
                    if (existingBatchCodes.Contains(codeKey))
                        Error("batches", i, "batchCode", $"A batch with code \"{code}\" already exists — reuse it instead of creating a second one.");
                    else if (newBatchCodes.TryGetValue(codeKey, out _))
                        Error("batches", i, "batchCode", $"\"{code}\" appears more than once in this setup.");
                    else newBatchCodes[codeKey] = i;
                }

                if (Normalize(b.Breed).Length == 0) Error("batches", i, "breed", "Breed is required.");
                if (b.NumberOfBirds <= 0) Error("batches", i, "numberOfBirds", "Enter how many birds the batch originally had — more than zero.");
                if (b.StartDate == default) Error("batches", i, "startDate", "Give the batch an arrival or placement date.");
            }

            // ---- Houses ---------------------------------------------------
            var existingHouseById = existingHouses.ToDictionary(h => h.HouseId);
            var existingHouseNames = new HashSet<string>(existingHouses.Select(h => DuplicateKey(h.HouseName)));
            var houseKeys = new Dictionary<string, FarmSetupHouseInput>(StringComparer.OrdinalIgnoreCase);
            var newHouseNames = new HashSet<string>();

            for (var i = 0; i < houses.Count; i++)
            {
                var h = houses[i];
                var key = Normalize(h.Key);
                if (key.Length == 0) Error("houses", i, "key", "Every house row needs an internal reference.");
                else if (houseKeys.ContainsKey(key)) Error("houses", i, "key", "Two house rows share a reference.");
                else houseKeys[key] = h;

                if (h.ExistingHouseId.HasValue)
                {
                    if (!existingHouseById.ContainsKey(h.ExistingHouseId.Value))
                        Error("houses", i, "existingHouseId", "That house/pen is not available on this farm.");
                    continue;
                }

                var name = Normalize(h.HouseName);
                if (name.Length == 0) Error("houses", i, "houseName", "House name is required.");
                else if (name.Length > MaxNameLength)
                    Error("houses", i, "houseName", $"House name cannot be longer than {MaxNameLength} characters.");
                else
                {
                    var nameKey = DuplicateKey(name);
                    if (existingHouseNames.Contains(nameKey))
                        Error("houses", i, "houseName", $"A house named \"{name}\" already exists — select it instead of creating a second one.");
                    else if (!newHouseNames.Add(nameKey))
                        Error("houses", i, "houseName", $"\"{name}\" appears more than once in this setup.");
                }

                if (h.Capacity.HasValue && h.Capacity.Value < 0)
                    Error("houses", i, "capacity", "Capacity cannot be negative.");
            }

            // ---- Flocks ---------------------------------------------------
            var existingNames = new HashSet<string>(
                (existingFlockNames ?? Enumerable.Empty<string>()).Select(DuplicateKey).Where(k => k.Length > 0));

            var flockNameCounts = new Dictionary<string, int>();
            foreach (var f in flocks)
            {
                var key = DuplicateKey(f?.Name);
                if (key.Length == 0) continue;
                flockNameCounts[key] = flockNameCounts.TryGetValue(key, out var n) ? n + 1 : 1;
            }

            // Placed birds per batch key, and standing birds per house key, so the
            // batch and capacity checks below see the whole setup rather than a row.
            var placedByBatchKey = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var standingByHouseKey = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            for (var i = 0; i < flocks.Count; i++)
            {
                var f = flocks[i];
                var name = Normalize(f.Name);

                if (name.Length == 0) Error("flocks", i, "name", "Flock name is required.");
                else if (name.Length > MaxNameLength)
                    Error("flocks", i, "name", $"Flock name cannot be longer than {MaxNameLength} characters.");
                else
                {
                    var key = DuplicateKey(name);
                    if (flockNameCounts.TryGetValue(key, out var n) && n > 1)
                        Error("flocks", i, "name", $"\"{name}\" appears more than once in this setup.");
                    else if (existingNames.Contains(key))
                        Error("flocks", i, "name", $"A flock named \"{name}\" already exists on this farm.");
                }

                if (f.OriginallyPlaced <= 0)
                    Error("flocks", i, "originallyPlaced", "Enter how many birds were originally placed in this flock.");
                if (f.CurrentLiveBirds < 0)
                    Error("flocks", i, "currentLiveBirds", "Current live birds cannot be negative.");
                else if (f.OriginallyPlaced > 0 && f.CurrentLiveBirds > f.OriginallyPlaced)
                    Error("flocks", i, "currentLiveBirds",
                        $"There cannot be more birds standing ({f.CurrentLiveBirds:N0}) than were placed ({f.OriginallyPlaced:N0}).");

                // Age or date, but we need one of them.
                if (f.StartDate is null && (f.CurrentAgeInWeeks is null || f.CurrentAgeInWeeks < 0))
                    Error("flocks", i, "startDate", "Give either the placement date or the flock's current age in weeks.");

                // The breakdown, when the farm says it knows it, must not claim more
                // than actually went missing.
                if (f.HistoryKnown)
                {
                    var difference = HistoricalReduction(f);
                    if (f.HistoricalMortality < 0 || f.HistoricalSold < 0 || f.HistoricalCulled < 0 || f.HistoricalTransferred < 0)
                        Error("flocks", i, "breakdown", "Historical figures cannot be negative.");
                    var known = f.HistoricalMortality + f.HistoricalSold + f.HistoricalCulled + f.HistoricalTransferred;
                    if (known > difference)
                        Error("flocks", i, "breakdown",
                            $"The breakdown adds up to {known:N0} but only {difference:N0} birds remain to account for.");
                }

                var batchKey = Normalize(f.BatchKey);
                if (batchKey.Length == 0 || !batchKeys.ContainsKey(batchKey))
                    Error("flocks", i, "batchKey", "Choose which batch this flock came from.");
                else if (f.OriginallyPlaced > 0)
                    placedByBatchKey[batchKey] = (placedByBatchKey.TryGetValue(batchKey, out var p) ? p : 0) + f.OriginallyPlaced;

                var houseKey = Normalize(f.HouseKey);
                if (houseKey.Length == 0 || !houseKeys.ContainsKey(houseKey))
                    Error("flocks", i, "houseKey", "Choose which house/pen this flock is in.");
                else if (f.CurrentLiveBirds > 0)
                    standingByHouseKey[houseKey] = (standingByHouseKey.TryGetValue(houseKey, out var s) ? s : 0) + f.CurrentLiveBirds;
            }

            // ---- Batch integrity: an ERROR --------------------------------
            foreach (var (key, placed) in placedByBatchKey)
            {
                var batch = batchKeys[key];
                var index = batches.IndexOf(batch);

                int capacity;
                int alreadyAllocated = 0;
                if (batch.ExistingBatchId.HasValue && existingBatchById.TryGetValue(batch.ExistingBatchId.Value, out var existing))
                {
                    capacity = existing.NumberOfBirds;
                    allocatedByBatchId.TryGetValue(existing.BatchId, out alreadyAllocated);
                }
                else
                {
                    capacity = batch.NumberOfBirds;
                }

                if (capacity <= 0) continue;  // already reported as a row error
                if (placed + alreadyAllocated > capacity)
                {
                    var label = batch.ExistingBatchId.HasValue
                        ? existingBatchById[batch.ExistingBatchId.Value].BatchCode
                        : Normalize(batch.BatchCode);
                    var allocatedNote = alreadyAllocated > 0 ? $" ({alreadyAllocated:N0} already allocated)" : string.Empty;
                    Error("batches", index, "numberOfBirds",
                        $"Flocks from {label} were placed with {placed:N0} birds{allocatedNote}, but the batch only had {capacity:N0}.");
                }
            }

            // ---- House capacity: a WARNING --------------------------------
            foreach (var (key, standing) in standingByHouseKey)
            {
                var house = houseKeys[key];
                var index = houses.IndexOf(house);

                int? capacity;
                var occupied = 0;
                if (house.ExistingHouseId.HasValue && existingHouseById.TryGetValue(house.ExistingHouseId.Value, out var existing))
                {
                    capacity = existing.Capacity;
                    occupied = existing.Occupied;
                }
                else
                {
                    capacity = house.Capacity;
                }

                if (capacity is null || capacity.Value <= 0) continue;
                if (standing + occupied > capacity.Value)
                {
                    var label = house.ExistingHouseId.HasValue
                        ? existingHouseById[house.ExistingHouseId.Value].HouseName
                        : Normalize(house.HouseName);
                    var occupiedNote = occupied > 0 ? $" and already holds {occupied:N0}" : string.Empty;
                    Warn("houses", index, "capacity",
                        $"{label} is recorded as holding {capacity.Value:N0} birds{occupiedNote}, but you are placing {standing:N0} in it. The birds are real — check the capacity.");
                }
            }

            return (errors, warnings);
        }
    }
}
