using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Server-side rules for a bulk house batch.
    ///
    /// <para>
    /// The browser runs the same rules in <c>lib/houses/bulk.ts</c> so the grid
    /// can flag a bad row before anyone clicks Create. This class is the one that
    /// actually decides: the frontend copy is a courtesy, not a gate. Keep the
    /// two in step — the messages are worded identically on purpose, so a user who
    /// somehow gets past the grid sees the same sentence from the server.
    /// </para>
    ///
    /// <para>
    /// Pure and static by design: no connection string, no DB. The caller supplies
    /// the existing house names it already read through <c>sphouse_getall</c>, which
    /// keeps this testable and keeps the company scoping in one place (the reader).
    /// </para>
    /// </summary>
    public static class HouseBulkValidator
    {
        /// <summary>
        /// Upper bound on one batch. Not a business rule — a guard so a malformed
        /// or hostile request cannot hold a transaction open over thousands of
        /// inserts. A farm with more than 200 new pens can run the tool twice.
        /// </summary>
        public const int MaxRows = 200;

        /// <summary>
        /// Name/location caps. The single "Add House" form has none, so these are
        /// stricter than that path on purpose: in an all-or-nothing batch a value
        /// the column cannot hold fails the whole submission, and a clear row-level
        /// message beats a rolled-back transaction and a database error string.
        /// </summary>
        public const int MaxNameLength = 100;
        public const int MaxLocationLength = 200;

        /// <summary>Capacity is an int column; stay well inside it.</summary>
        public const int MaxCapacity = 2_000_000_000;

        private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

        /// <summary>
        /// What actually gets stored: the trimmed string, exactly as the preview
        /// grid showed it. No silent renaming — see the duplicate rules below.
        /// </summary>
        public static string NormalizeName(string? raw) => (raw ?? string.Empty).Trim();

        public static string? NormalizeLocation(string? raw)
        {
            var trimmed = (raw ?? string.Empty).Trim();
            return trimmed.Length == 0 ? null : trimmed;
        }

        /// <summary>
        /// The key two names are compared on: case-insensitive, internal runs of
        /// whitespace collapsed. "pen  1" and "Pen 1" are the same pen to a farmer,
        /// so the tool treats them as a duplicate rather than creating both.
        /// </summary>
        public static string DuplicateKey(string? raw) =>
            Whitespace.Replace(NormalizeName(raw), " ").ToLowerInvariant();

        /// <summary>
        /// Every problem with the batch, one entry per (row, field). An empty list
        /// means the batch may be created.
        /// </summary>
        /// <param name="items">Rows as submitted.</param>
        /// <param name="existingNames">
        /// House names already in this company, read through the normal farm-scoped
        /// reader. Pass an empty sequence to skip the check.
        /// </param>
        public static List<BulkHouseRowError> Validate(
            IReadOnlyList<BulkHouseItem>? items,
            IEnumerable<string>? existingNames)
        {
            var errors = new List<BulkHouseRowError>();

            if (items is null || items.Count == 0)
            {
                errors.Add(new BulkHouseRowError { Index = -1, Field = "houses", Message = "Add at least one house before creating." });
                return errors;
            }

            if (items.Count > MaxRows)
            {
                errors.Add(new BulkHouseRowError
                {
                    Index = -1,
                    Field = "houses",
                    Message = $"A single batch can create at most {MaxRows} houses. Split this into smaller batches.",
                });
                return errors;
            }

            var existing = new HashSet<string>(
                (existingNames ?? Enumerable.Empty<string>()).Select(DuplicateKey).Where(k => k.Length > 0));

            // Count first, then report: both "Pen 1" rows get flagged, not just the
            // second one, so the user can see the pair and decide which to fix.
            var counts = new Dictionary<string, int>();
            foreach (var item in items)
            {
                var key = DuplicateKey(item?.HouseName);
                if (key.Length == 0) continue;
                counts[key] = counts.TryGetValue(key, out var n) ? n + 1 : 1;
            }

            for (var i = 0; i < items.Count; i++)
            {
                var item = items[i];
                var name = NormalizeName(item?.HouseName);

                if (name.Length == 0)
                {
                    errors.Add(new BulkHouseRowError { Index = i, Field = "houseName", Message = "House name is required." });
                }
                else if (name.Length > MaxNameLength)
                {
                    errors.Add(new BulkHouseRowError
                    {
                        Index = i,
                        Field = "houseName",
                        Message = $"House name cannot be longer than {MaxNameLength} characters.",
                    });
                }
                else
                {
                    var key = DuplicateKey(name);
                    if (counts.TryGetValue(key, out var n) && n > 1)
                    {
                        errors.Add(new BulkHouseRowError
                        {
                            Index = i,
                            Field = "houseName",
                            Message = $"\"{name}\" appears more than once in this batch.",
                        });
                    }
                    else if (existing.Contains(key))
                    {
                        errors.Add(new BulkHouseRowError
                        {
                            Index = i,
                            Field = "houseName",
                            Message = $"A house named \"{name}\" already exists on this farm.",
                        });
                    }
                }

                var capacity = item?.Capacity;
                if (capacity.HasValue)
                {
                    if (capacity.Value < 0)
                    {
                        errors.Add(new BulkHouseRowError { Index = i, Field = "capacity", Message = "Capacity cannot be negative." });
                    }
                    else if (capacity.Value > MaxCapacity)
                    {
                        errors.Add(new BulkHouseRowError { Index = i, Field = "capacity", Message = "Capacity is too large." });
                    }
                }

                var location = item?.Location;
                if (location is not null && location.Trim().Length > MaxLocationLength)
                {
                    errors.Add(new BulkHouseRowError
                    {
                        Index = i,
                        Field = "location",
                        Message = $"Location cannot be longer than {MaxLocationLength} characters.",
                    });
                }
            }

            return errors;
        }

        /// <summary>
        /// The rows as they will be written: trimmed name, location null rather
        /// than empty. Call only after <see cref="Validate"/> came back clean.
        /// </summary>
        public static List<BulkHouseItem> Normalize(IReadOnlyList<BulkHouseItem> items) =>
            items.Select(i => new BulkHouseItem
            {
                HouseName = NormalizeName(i.HouseName),
                Capacity = i.Capacity,
                Location = NormalizeLocation(i.Location),
            }).ToList();
    }
}
