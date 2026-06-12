using System.Threading.Tasks;
using PoultryFarmApp.Business;
using PoultryWeb.Models;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class ReportsController : Controller
    {
        private readonly IReportWebApiService _reportService;

        public ReportsController(IReportWebApiService reportService)
        {
            _reportService = reportService;
        }

        public IActionResult Index() 
        {
            var model = new ReportRequestModel
            {
                StartDate = DateTime.Today.AddDays(-7),
                EndDate = DateTime.Today
            };
            // Set default values if needed, e.g. model.ReportType = ...
            return View(model);
        }

        [HttpPost]
        public async Task<IActionResult> ExportCsv(ReportRequestModel model)
        {
            var bytes = await _reportService.ExportCsvAsync(model);
            return File(bytes, "text/csv", $"{model.ReportType}_Report.csv");
        }

        [HttpPost]
        public async Task<IActionResult> ExportPdf(ReportRequestModel model)
        {
            var bytes = await _reportService.ExportPdfAsync(model);
            return File(bytes, "application/pdf", $"{model.ReportType}_Report.pdf");
        }

        [HttpPost]
        public async Task<IActionResult> ExportExcel(ReportRequestModel model)
        {
            var bytes = await _reportService.ExportExcelAsync(model);
            return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"{model.ReportType}_Report.xlsx");
        }
    }
}
