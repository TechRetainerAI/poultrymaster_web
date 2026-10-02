using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Server-side rules for dividing a batch into flocks.
    ///
    /// <para>
    /// Every rule here already exists somewhere in the single-flock path — this
    /// class states them once so a batch of fifty is judged exactly as fifty
    /// individual Add Flock submissions would have been:
    /// </para>
    /// <list type="bullet">
    /// <item><b>Batch total</b> — FlockController.Create refuses when
    /// allocated + new &gt; batch.NumberOfBirds. Same rule, summed across rows.</item>
    /// <item><b>House capacity</b> — app/flocks/page.tsx blocks when
    /// occupied + new &gt; capacity, and only when capacity &gt; 0 (a house with no
    /// capacity recorded is unconstrained). Same rule, with the rows aggregated
    /// per house so two rows into one pen cannot each slip under the bar.</item>
    /// <item><b>Occupancy</b> — counted from ACTIVE flocks only, because that is
    /// what the existing check counts. A pen may legitimately hold several.</item>
    /// </list>
    ///
    /// <para>
    /// Pure and static: no connection string, no DB. The caller passes what it
    /// read through the ordinary farm-scoped readers, which is also what keeps
    /// company scoping in one place.
    /// </para>
    /// </summary>
    public static class FlockAllocationValidator
    {
        /// <summary>
        /// Upper bound on one allocation. A farm dividing a batch across more than
        /// 200 pens can post twice; the cap exists so one request cannot hold a
        /// transaction — and the batch's advisory lock — open indefinitely.
        /// </summary>
        public const int MaxRows = 200;

        public const int MaxNameLength = 100;

        private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

        public static string NormalizeName(string? raw) => (raw ?? string.Empty).Trim();

        /// <summary>
        /// The key two flock names are compared on: case-insensitive, internal runs
        /// of whitespace collapsed. "b3 - pen 1" and "B3 - Pen 1" are the same
        /// flock to a farmer.
        /// </summary>
        public static string DuplicateKey(string? raw) =>
            Whitespace.Replace(NormalizeName(raw), " ").ToLowerInvariant();

        /// <summary>
        /// Birds a house can still take: capacity minus what active flocks already
        /// hold. Null means "no capacity recorded", which the existing rule treats
        /// as unconstrained rather than as zero.
        /// </summary>
        public static int? AvailableCapacity(int? capacity, int occupied)
        {
            if (capacity is null || capacity.Value <= 0) return null;
            return Math.Max(0, capacity.Value - occupied);
        }

        /// <summary>
        /// Everything wrong with an allocation, one entry per (row, field). Empty
        /// means it may be created.
        /// </summary>
        /// <param name="items">Rows as submitted.</param>
        /// <param name="availableBirds">
        /// Batch birds not yet allocated: NumberOfBirds − already allocated. The
        /// caller reads this under the batch lock at posting time.
        /// </param>
        /// <param name="houses">Houses of THIS company, with their current occupancy.</param>
        /// <param name="existingFlockNames">Flock names already on this farm.</param>
        public static List<FlockAllocationRowError> Validate(
            IReadOnlyList<FlockAllocationItem>? items,
            int availableBirds,
            IReadOnlyCollection<HouseOccupancyModel> houses,
            IEnumerable<string>? existingFlockNames)
        {
            var errors = new List<FlockAllocationRowError>();

            if (items is null || items.Count == 0)
            {
                errors.Add(new FlockAllocationRowError { Index = -1, Field = "allocations", Message = "Add at least one house before creating flocks." });
                return errors;
            }

            if (items.Count > MaxRows)
            {
                errors.Add(new FlockAllocationRowError
                {
                    Index = -1,
                    Field = "allocations",
                    Message = $"A single allocation can create at most {MaxRows} flocks. Split this into smaller allocations.",
                });
                return errors;
            }

            var housesById = houses.ToDictionary(h => h.HouseId);
            var existing = new HashSet<string>(
                (existingFlockNames ?? Enumerable.Empty<string>()).Select(DuplicateKey).Where(k => k.Length > 0));

            // Flag every row of a duplicated name, not only the later one, so the
            // user can see the pair and decide which to change.
            var nameCounts = new Dictionary<string, int>();
            foreach (var item in items)
            {
                var key = DuplicateKey(item?.Name);
                if (key.Length == 0) continue;
                nameCounts[key] = nameCounts.TryGetValue(key, out var n) ? n + 1 : 1;
            }

            // Rows are aggregated per house before the capacity check: two rows of
            // 1,500 into one 2,000-bird pen must fail, even though neither exceeds
            // the capacity on its own.
            var requestedPerHouse = new Dictionary<int, int>();
            foreach (var item in items)
            {
                if (item is null || item.HouseId <= 0 || item.Quantity <= 0) continue;
                requestedPerHouse[item.HouseId] =
                    (requestedPerHouse.TryGetValue(item.HouseId, out var q) ? q : 0) + item.Quantity;
            }

            for (var i = 0; i < items.Count; i++)
            {
                var item = items[i];
                var name = NormalizeName(item?.Name);

                if (name.Length == 0)
                {
                    errors.Add(new FlockAllocationRowError { Index = i, Field = "name", Message = "Flock name is required." });
                }
                else if (name.Length > MaxNameLength)
                {
                    errors.Add(new FlockAllocationRowError
                    {
                        Index = i,
                        Field = "name",
                        Message = $"Flock name cannot be longer than {MaxNameLength} characters.",
                    });
                }
                else
                {
                    var key = DuplicateKey(name);
                    if (nameCounts.TryGetValue(key, out var n) && n > 1)
                    {
                        errors.Add(new FlockAllocationRowError
                        {
                            Index = i,
                            Field = "name",
                            Message = $"\"{name}\" appears more than once in this allocation.",
                        });
                    }
                    else if (existing.Contains(key))
                    {
                        errors.Add(new FlockAllocationRowError
                        {
                            Index = i,
                            Field = "name",
                            Message = $"A flock named \"{name}\" already exists on this farm.",
                        });
                    }
                }

                var quantity = item?.Quantity ?? 0;
                if (quantity <= 0)
                {
                    errors.Add(new FlockAllocationRowError { Index = i, Field = "quantity", Message = "Enter how many birds go into this house — more than zero." });
                }

                var houseId = item?.HouseId ?? 0;
                if (houseId <= 0)
                {
                    errors.Add(new FlockAllocationRowError { Index = i, Field = "houseId", Message = "Choose a house/pen for this flock." });
                }
                else if (!housesById.TryGetValue(houseId, out var house))
                {
                    // Covers both a deleted house and a house belonging to another
                    // company: the caller only ever passes THIS farm's houses.
                    errors.Add(new FlockAllocationRowError
                    {
                        Index = i,
                        Field = "houseId",
                        Message = "That house/pen is not available on this farm.",
                    });
                }
                else if (quantity > 0)
                {
                    var available = AvailableCapacity(house.Capacity, house.Occupied);
                    if (available is not null && requestedPerHouse[houseId] > available.Value)
                    {
                        var occupiedNote = house.Occupied > 0
                            ? $" and already holds {house.Occupied:N0}"
                            : string.Empty;
                        errors.Add(new FlockAllocationRowError
                        {
                            Index = i,
                            Field = "quantity",
                            Message = $"{house.HouseName} holds {house.Capacity:N0} birds{occupiedNote}. This allocation puts {requestedPerHouse[houseId]:N0} in it — {available.Value:N0} will fit.",
                        });
                    }
                }
            }

            // The batch total is checked last so a row-level problem is reported in
            // its own terms first.
            var requested = items.Where(i => i is not null && i.Quantity > 0).Sum(i => (long)i.Quantity);
            if (requested > availableBirds)
            {
                errors.Add(new FlockAllocationRowError
                {
                    Index = -1,
                    Field = "allocations",
                    Message = $"This allocation places {requested:N0} birds but the batch only has {availableBirds:N0} left to allocate.",
                });
            }

            return errors;
        }
    }
}
