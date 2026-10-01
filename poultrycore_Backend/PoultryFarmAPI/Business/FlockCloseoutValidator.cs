using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Linq;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// The checks a closeout must pass BEFORE anything is written.
    ///
    /// <para>
    /// spflock_closeout re-checks the bird balance itself, inside its transaction,
    /// and that is the check that decides. This one exists because the sales are
    /// created first (through SaleService, which owns its own connections), so a
    /// request that was always going to fail must be refused before a single sale
    /// exists -- otherwise the refusal becomes "create four sales, then delete
    /// them again". Mirrored in lib/flocks/closeout.ts for the wizard.
    /// </para>
    /// </summary>
    public static class FlockCloseoutValidator
    {
        public static readonly string[] PaymentTerms = { "Paid", "Credit", "PartPaid" };

        /// <summary>
        /// spsale_insert's bird rule, and fnpoultrysale_isbirdsale's. A product
        /// name that fails it would be stored as a sale the stock side never sees
        /// as birds, and the closeout would refuse to link it.
        /// </summary>
        public static bool IsBirdSaleProduct(string? product)
        {
            var p = (product ?? string.Empty).Trim().ToLowerInvariant();
            if (p.Contains("egg")) return false;
            return p == "birds" || p.Contains("bird") || p.Contains("chick") || p.Contains("cockerel");
        }

        public static decimal SaleTotal(FlockCloseoutSaleLine s) =>
            s.TotalAmount ?? Math.Round(s.Quantity * s.UnitPrice, 2);

        public static List<string> Validate(FlockCloseoutRequest request, FlockCloseoutContext context)
        {
            var errors = new List<string>();

            if (context.IsClosed)
            {
                errors.Add("This flock is already closed.");
                return errors;
            }
            if (context.IneligibleReason != null)
            {
                errors.Add(context.IneligibleReason);
                return errors;
            }

            if (string.IsNullOrWhiteSpace(request.Reason))
                errors.Add("A reason is required to close a flock.");

            var closed = request.ClosedDate.Date;
            if (closed > context.BusinessDate.Date)
                errors.Add("The closing date cannot be in the future.");
            if (closed < context.EarliestCloseDate.Date)
                errors.Add($"The closing date cannot be before {context.EarliestCloseDate:dd MMM yyyy}.");

            var sales = request.Sales ?? new();
            var culls = request.Culls ?? new();
            var transfers = request.Transfers ?? new();

            for (var i = 0; i < sales.Count; i++)
            {
                var s = sales[i];
                var n = $"Sale {i + 1}";
                if (s.Quantity <= 0) errors.Add($"{n}: enter how many birds were sold.");
                if (s.UnitPrice < 0 || (s.TotalAmount ?? 0) < 0) errors.Add($"{n}: the price cannot be negative.");

                var terms = PaymentTerms.FirstOrDefault(t => string.Equals(t, s.PaymentTerms, StringComparison.OrdinalIgnoreCase));
                if (terms == null)
                {
                    errors.Add($"{n}: choose whether it was paid, on credit or part paid.");
                    continue;
                }

                var total = SaleTotal(s);
                var hasCustomer = s.CustomerId.HasValue || !string.IsNullOrWhiteSpace(s.CustomerName);

                // Money received needs somewhere to land; money owed needs someone
                // to owe it. The same two rules the Sales page applies.
                if (terms != "Credit" && !s.PoultryCashAccountId.HasValue)
                    errors.Add($"{n}: choose the cash account the money was received into.");
                if (terms != "Paid" && !hasCustomer)
                    errors.Add($"{n}: a sale on credit needs a customer, so the balance has someone to belong to.");
                if (terms == "PartPaid")
                {
                    var paid = s.AmountPaid ?? 0;
                    if (paid <= 0 || paid >= total)
                        errors.Add($"{n}: a part payment must be more than zero and less than the sale total ({total:N2}).");
                }
                if (terms != "Credit" && string.IsNullOrWhiteSpace(s.PaymentMethod))
                    errors.Add($"{n}: choose how the customer paid.");
            }

            for (var i = 0; i < culls.Count; i++)
                if (culls[i].Quantity <= 0) errors.Add($"Cull {i + 1}: enter how many birds were culled.");

            for (var i = 0; i < transfers.Count; i++)
            {
                if (transfers[i].Quantity <= 0) errors.Add($"Transfer {i + 1}: enter how many birds were transferred.");
                if (string.IsNullOrWhiteSpace(transfers[i].Destination))
                    errors.Add($"Transfer {i + 1}: say where the birds went.");
            }

            var disposed = sales.Sum(s => Math.Max(0, s.Quantity))
                         + culls.Sum(c => Math.Max(0, c.Quantity))
                         + transfers.Sum(t => Math.Max(0, t.Quantity));
            var live = context.Position.CurrentLiveBirds;

            if (live < 0)
                errors.Add($"The flock's records account for {-live:N0} more birds than it had. Check for a bird sale that was also deducted on a production record before closing.");
            else if (disposed < live)
                errors.Add($"Unresolved bird balance: {live - disposed:N0} bird(s) are still unaccounted for. Sell, cull or transfer them, or record any unrecorded deaths as mortality on a production record, before closing.");
            else if (disposed > live)
                errors.Add($"Unresolved bird balance: the dispositions account for {disposed - live:N0} more bird(s) than the flock has ({live:N0}).");

            return errors;
        }
    }
}
