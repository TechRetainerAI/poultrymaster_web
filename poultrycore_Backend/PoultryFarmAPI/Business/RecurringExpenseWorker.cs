// Recurring Expense Engine (migration 348) -- the scheduler.
//
// Every few hours, raise the drafts that have fallen due for every company
// with an active template. This is the same call the Recurring Expenses page
// makes when it opens, and it is idempotent: occurrences are keyed by
// (template, occurrence number) with ON CONFLICT DO NOTHING under a
// per-company advisory lock, so a second Cloud Run instance, a page refresh
// and this loop running at the same moment still raise each period once.
// AutoPost templates are posted only by whichever caller actually created the
// draft, so they are posted once too.

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace PoultryFarmAPIWeb.Business
{
    public sealed class RecurringExpenseWorker : BackgroundService
    {
        private readonly IServiceScopeFactory _scopes;
        private readonly ILogger<RecurringExpenseWorker> _log;

        public RecurringExpenseWorker(IServiceScopeFactory scopes, ILogger<RecurringExpenseWorker> log)
        {
            _scopes = scopes;
            _log = log;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            try { await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken); }
            catch (TaskCanceledException) { return; }

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    using var scope = _scopes.CreateScope();
                    var svc = scope.ServiceProvider.GetRequiredService<IRecurringExpenseService>();
                    int generated = 0, posted = 0, failed = 0;
                    foreach (var farmId in await svc.GetFarmsWithActiveTemplatesAsync())
                    {
                        try
                        {
                            var r = await svc.GenerateAsync(farmId, "scheduler");
                            generated += r.Generated; posted += r.AutoPosted; failed += r.AutoPostFailures.Count;
                        }
                        catch (Exception ex)
                        {
                            // One company's failure must not stop the rest.
                            _log.LogError(ex, "Recurring expenses: generation failed for {FarmId}", farmId);
                        }
                    }
                    _log.LogInformation("Recurring expenses pass: {Generated} drafts raised, {Posted} auto-posted, {Failed} auto-post failures",
                        generated, posted, failed);
                }
                catch (Exception ex)
                {
                    _log.LogError(ex, "Recurring expenses pass failed");
                }

                try { await Task.Delay(TimeSpan.FromHours(3), stoppingToken); }
                catch (TaskCanceledException) { return; }
            }
        }
    }
}
