using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    // Generic, report-agnostic shape that any Water report (or the daily closing)
    // is mapped into before rendering. WaterReportPdfDocument knows only this
    // model, so a single QuestPDF renderer covers both key-value reports
    // (P&L, closing) and tabular reports (driver/route/expense lists).
    public class WaterReportPdfModel
    {
        public string Title { get; set; } = "Report";
        public string? CompanyName { get; set; }
        public string? DateRange { get; set; }
        public string? GeneratedBy { get; set; }
        // "Filters used:" lines echoed into the PDF for auditability.
        public List<KeyValuePair<string, string>> Filters { get; set; } = new();
        public List<WaterReportPdfSection> Sections { get; set; } = new();
    }

    // A section is EITHER a key-value block (Pairs) OR a table (Columns + Rows),
    // optionally under a Heading. Driver Collection uses two sections (detail +
    // totals); P&L / closing use a single Pairs section.
    public class WaterReportPdfSection
    {
        public string? Heading { get; set; }
        public List<KeyValuePair<string, string>> Pairs { get; set; } = new();
        public string[] Columns { get; set; } = System.Array.Empty<string>();
        public List<string[]> Rows { get; set; } = new();
    }
}
