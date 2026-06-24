using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Builds the daily-closing PDF and emails it via IEmailService. Used by the
    // daily-closing controller (auto-sent on submit + manual re-send). Reports
    // themselves are emailed client-side (jsPDF → POST /api/Email/Report); only
    // the closing-on-submit needs a server-side PDF (no rendered page at submit).
    public interface IWaterReportEmailService
    {
        Task EmailClosingAsync(WaterDailyClosingModel closing, string to, string? companyName);
    }
}
