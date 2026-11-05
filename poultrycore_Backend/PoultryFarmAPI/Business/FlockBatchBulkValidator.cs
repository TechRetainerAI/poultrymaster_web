using System;
using System.Collections.Generic;
using System.Linq;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Rules for "Add Multiple Batches". Mirrored in lib/flock-batches/bulk.ts so
    /// the grid can flag a row before submit; this copy is the one that decides.
    /// Messages are worded identically -- change one, change the other.
    ///
    /// The same rules as the single Add Flock Batch form (name, code, start date,
    /// birds &gt; 0) plus the ones a batch of many needs: codes unique within the
    /// request and against the farm (the same per-farm key migration 329's index
    /// and FarmSetupValidator use), the length limits the wizard enforces, no
    /// negative money, and paid not more than the cost.
    /// </summary>
    public static class FlockBatchBulkValidator
    {
        public const int MaxRows = 100;

        public static List<BulkFlockBatchRowError> Validate(
            IReadOnlyList<BulkFlockBatchItem>? rows, IEnumerable<string?> existingCodes)
        {
            var errors = new List<BulkFlockBatchRowError>();
            void Error(int i, string field, string message) =>
                errors.Add(new BulkFlockBatchRowError { Index = i, Field = field, Message = message });

            if (rows == null || rows.Count == 0)
            {
                Error(-1, "batches", "Add at least one batch.");
                return errors;
            }
            if (rows.Count > MaxRows)
            {
                Error(-1, "batches", $"A single request can create at most {MaxRows} batches.");
                return errors;
            }

            var existing = new HashSet<string>(existingCodes.Select(c => FarmSetupValidator.DuplicateKey(c)));
            var seen = new HashSet<string>();

            for (var i = 0; i < rows.Count; i++)
            {
                var r = rows[i];

                var name = FarmSetupValidator.Normalize(r.BatchName);
                if (name.Length == 0) Error(i, "batchName", "Batch name is required.");
                else if (name.Length > FarmSetupValidator.MaxNameLength)
                    Error(i, "batchName", $"Batch name cannot be longer than {FarmSetupValidator.MaxNameLength} characters.");

                var code = FarmSetupValidator.Normalize(r.BatchCode);
                if (code.Length == 0) Error(i, "batchCode", "Batch code is required.");
                else if (code.Length > FarmSetupValidator.MaxBatchCodeLength)
                    Error(i, "batchCode", $"Batch code cannot be longer than {FarmSetupValidator.MaxBatchCodeLength} characters.");
                else
                {
                    var key = FarmSetupValidator.DuplicateKey(code);
                    if (existing.Contains(key)) Error(i, "batchCode", $"A batch with code \"{code}\" already exists.");
                    else if (!seen.Add(key)) Error(i, "batchCode", $"\"{code}\" appears more than once in this list.");
                }

                if (r.NumberOfBirds <= 0) Error(i, "numberOfBirds", "Number of birds must be greater than 0.");
                if (r.StartDate == default) Error(i, "startDate", "Start date is required.");
                if (r.CostPerChick < 0) Error(i, "costPerChick", "Cost per chick cannot be negative.");
                if (r.AmountPaid < 0) Error(i, "amountPaid", "Amount paid cannot be negative.");
                else if (r.AmountPaid > 0 && r.AmountPaid > TotalCost(r))
                    Error(i, "amountPaid", "Amount paid cannot be more than the total cost.");
            }
            return errors;
        }

        /// <summary>Total cost as the single form computes it: given, else cost per chick x birds.</summary>
        public static decimal TotalCost(BulkFlockBatchItem r) =>
            r.TotalCost > 0 ? r.TotalCost : r.CostPerChick * Math.Max(r.NumberOfBirds, 0);

        /// <summary>The rows as they will be stored: trimmed, total filled in, breed never null.</summary>
        public static List<MainFlockBatchModel> ToModels(string userId, string farmId, IReadOnlyList<BulkFlockBatchItem> rows) =>
            rows.Select(r => new MainFlockBatchModel
            {
                UserId = userId,
                FarmId = farmId,
                BatchName = FarmSetupValidator.Normalize(r.BatchName),
                BatchCode = FarmSetupValidator.Normalize(r.BatchCode),
                // mainflockbatch.breed is NOT NULL.
                Breed = FarmSetupValidator.Normalize(r.Breed),
                StartDate = r.StartDate,
                NumberOfBirds = r.NumberOfBirds,
                CostPerChick = r.CostPerChick,
                TotalCost = TotalCost(r),
                AmountPaid = r.AmountPaid,
                SupplierType = string.IsNullOrWhiteSpace(r.SupplierType) ? "local" : r.SupplierType!.Trim(),
                SupplierId = r.SupplierId,
                PoultryCashAccountId = r.PoultryCashAccountId,
                Status = string.IsNullOrWhiteSpace(r.Status) ? "active" : r.Status!.Trim(),
                Notes = string.IsNullOrWhiteSpace(r.Notes) ? null : r.Notes!.Trim(),
            }).ToList();
    }
}
