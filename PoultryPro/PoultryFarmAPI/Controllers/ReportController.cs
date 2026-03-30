using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPI.Business;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using QuestPDF.Fluent;
using System.Text;

namespace PoultryWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ReportController : ControllerBase
    {
        private readonly IReportService _reportService;
        public ReportController(IReportService reportService)
        {
            _reportService = reportService;
        }

        [HttpPost("export/csv")]
        public async Task<IActionResult> ExportCsv(ReportRequestModel request)
        {
            var data = await _reportService.GetReportAsync(request);
            var csv = new StringBuilder();

            // Header
            csv.AppendLine("Col1,Col2,Col3,Col4,Col5");

            // Data
            foreach (var row in data)
            {
                csv.AppendLine($"{row.Column1},{row.Column2},{row.Column3},{row.Column4},{row.Column5}");
            }

            var bytes = Encoding.UTF8.GetBytes(csv.ToString());
            return File(bytes, "text/csv", $"{request.ReportType}_Report.csv");
        }

        [HttpPost("export/pdf")]
        public async Task<IActionResult> ExportPdf(ReportRequestModel request)
        {
            try
            {
                var data = await _reportService.GetReportAsync(request);

                var pdf = new ReportPdfDocument(request.ReportType, request, data);
                var stream = new MemoryStream();
                pdf.GeneratePdf(stream);
                stream.Position = 0;

                return File(stream.ToArray(), "application/pdf", $"{request.ReportType}_Report.pdf");
            }
            catch (Exception ex)
            {
                return BadRequest("Error generating PDF: " + ex.Message);
            }
        }

        [HttpPost("export/excel")]
        public async Task<IActionResult> ExportExcel(ReportRequestModel request)
        {
            var data = await _reportService.GetReportAsync(request);

            using var workbook = new ClosedXML.Excel.XLWorkbook();
            var worksheet = workbook.Worksheets.Add($"{request.ReportType} Report");
            
            worksheet.Columns().AdjustToContents();
            //worksheet.RangeUsed().Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
            //worksheet.RangeUsed().Style.Font.FontName = "Segoe UI";

            // Header
            worksheet.Cell(1, 1).Value = "Column 1";
            worksheet.Cell(1, 2).Value = "Column 2";
            worksheet.Cell(1, 3).Value = "Column 3";
            worksheet.Cell(1, 4).Value = "Column 4";
            worksheet.Cell(1, 5).Value = "Column 5";

            // Data
            for (int i = 0; i < data.Count; i++)
            {
                var row = data[i];
                worksheet.Cell(i + 2, 1).Value = row.Column1;
                worksheet.Cell(i + 2, 2).Value = row.Column2;
                worksheet.Cell(i + 2, 3).Value = row.Column3;
                worksheet.Cell(i + 2, 4).Value = row.Column4;
                worksheet.Cell(i + 2, 5).Value = row.Column5;
            }

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            stream.Position = 0;

            return File(stream.ToArray(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                $"{request.ReportType}_Report.xlsx");
        }


    }

}
