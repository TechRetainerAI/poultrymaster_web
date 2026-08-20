using System;
using System.Collections.Generic;
using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Shared, reusable calculation + data-reading helpers for the advanced
    // poultry reports. Keeping this logic in one place avoids duplicating the
    // same maths (safe division, percentages, eggs→crates, status banding)
    // across 20 report methods.
    // =========================================================================
    public static class PoultryReportHelpers
    {
        public const int EggsPerCrate = PoultryReportConstants.DefaultEggsPerCrate;

        /// <summary>Division that returns null instead of throwing on a 0/null denominator.</summary>
        public static double? SafeDivide(double numerator, double denominator)
            => denominator == 0 ? (double?)null : numerator / denominator;

        public static decimal? SafeDivide(decimal numerator, decimal denominator)
            => denominator == 0 ? (decimal?)null : numerator / denominator;

        /// <summary>Production percentage = eggs / birds * 100, null-safe.</summary>
        public static double? Percent(double part, double whole)
        {
            var r = SafeDivide(part, whole);
            return r == null ? null : Math.Round(r.Value * 100.0, 2);
        }

        /// <summary>Whole crates from a total egg count (floor).</summary>
        public static long Crates(long totalEggs) => totalEggs / EggsPerCrate;

        /// <summary>Loose eggs left over after whole crates.</summary>
        public static int LooseEggs(long totalEggs) => (int)(totalEggs % EggsPerCrate);

        public static decimal? PerCrateFromPerEgg(decimal? perEgg)
            => perEgg == null ? null : Math.Round(perEgg.Value * EggsPerCrate, 4);

        // ---- Safe NpgsqlDataReader accessors (read by column name; tolerate
        //      missing columns so a slightly older DB schema does not crash). --

        private static int? Ordinal(NpgsqlDataReader r, string col)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase)) return i;
            return null;
        }

        public static string? Str(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? null : Convert.ToString(r.GetValue(i.Value));
        }

        public static int IntOr(NpgsqlDataReader r, string col, int dflt = 0)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? dflt : Convert.ToInt32(r.GetValue(i.Value));
        }

        public static int? IntN(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? (int?)null : Convert.ToInt32(r.GetValue(i.Value));
        }

        public static long LongOr(NpgsqlDataReader r, string col, long dflt = 0)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? dflt : Convert.ToInt64(r.GetValue(i.Value));
        }

        public static decimal DecOr(NpgsqlDataReader r, string col, decimal dflt = 0m)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? dflt : Convert.ToDecimal(r.GetValue(i.Value));
        }

        public static decimal? DecN(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? (decimal?)null : Convert.ToDecimal(r.GetValue(i.Value));
        }

        public static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? (DateTime?)null : Convert.ToDateTime(r.GetValue(i.Value));
        }

        public static bool BoolOr(NpgsqlDataReader r, string col, bool dflt = false)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? dflt : Convert.ToBoolean(r.GetValue(i.Value));
        }

        // ---- Status banding -------------------------------------------------

        /// <summary>
        /// Bands an actual % against a target (or fallback baseline). Good when
        /// at/above target, Watch when within 10pts below, Critical when far below.
        /// </summary>
        public static string BandAgainstTarget(double? actual, double? target)
        {
            if (actual == null || target == null || target == 0) return "N/A";
            if (actual >= target) return "Good";
            if (actual >= target - 10) return "Watch";
            return "Critical";
        }

        public static string MortalityBand(double? cumulativePercent)
        {
            if (cumulativePercent == null) return "N/A";
            if (cumulativePercent <= 5) return "Good";
            if (cumulativePercent <= 10) return "Watch";
            return "High";
        }

        public static string StockBand(decimal currentStock, decimal? reorderLevel)
        {
            if (currentStock <= 0) return "Out of stock";
            if (reorderLevel != null && currentStock <= reorderLevel) return "Low";
            return "OK";
        }

        public static string VarianceBand(int variance)
        {
            if (variance == 0) return "Balanced";
            return Math.Abs(variance) <= 5 ? "Minor variance" : "Check count";
        }

        /// <summary>
        /// Opens the connection and configures a CommandType.StoredProcedure
        /// command — the single ADO.NET shape used by every report read.
        /// </summary>
        public static NpgsqlCommand Proc(NpgsqlConnection conn, string sp)
            => new NpgsqlCommand(sp, conn);
    }
}
