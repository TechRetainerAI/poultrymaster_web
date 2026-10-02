// The one billing scheduler (spec Part 33: "do not create multiple
// schedulers"). Runs the same maintenance pass an admin can trigger by hand:
// due market changes, past-due bookkeeping, the Active→PastDue→GracePeriod→
// Suspended ladder, period-end cancellations, and — only when
// autoinvoiceenabled says so — each Active account's next invoice.
//
// A Postgres advisory lock inside the pass makes concurrent Cloud Run
// instances harmless: whoever loses the lock skips, and every step is
// idempotent anyway, so the six-hour cadence is a re-check, not a re-do.

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace PoultryFarmAPIWeb.Business
{
    public sealed class PlatformBillingWorker : BackgroundService
    {
        private readonly IServiceScopeFactory _scopes;
        private readonly ILogger<PlatformBillingWorker> _log;

        public PlatformBillingWorker(IServiceScopeFactory scopes, ILogger<PlatformBillingWorker> log)
        {
            _scopes = scopes;
            _log = log;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            // Let the service finish binding before the first pass.
            try { await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken); }
            catch (TaskCanceledException) { return; }

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    using var scope = _scopes.CreateScope();
                    var svc = scope.ServiceProvider.GetRequiredService<IPlatformBillingService>();
                    var report = await svc.RunDailyMaintenanceAsync("scheduler");
                    _log.LogInformation("Billing worker pass: {Report}", report);
                }
                catch (Exception ex)
                {
                    // A failed pass must never take the API down; the next pass retries.
                    _log.LogError(ex, "Billing worker pass failed");
                }

                try { await Task.Delay(TimeSpan.FromHours(6), stoppingToken); }
                catch (TaskCanceledException) { return; }
            }
        }
    }
}
