
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using QuestPDF.Drawing;
using System.Globalization;
using PoultryFarmAPIWeb.Models;


namespace PoultryFarmAPI.Business
{
    public class ReportPdfDocument : IDocument
    {
        private readonly string _title;
        private readonly ReportRequestModel _request;
        private readonly List<ReportResultModel> _data;

        public ReportPdfDocument(string title, ReportRequestModel request, List<ReportResultModel> data)
        {
            _title = title;
            _request = request;
            _data = data;
        }

        public DocumentMetadata GetMetadata() => DocumentMetadata.Default;

        public void Compose(IDocumentContainer container)
        {
            container.Page(page =>
            {
                page.Margin(30);
                page.Header().Text($"{_title} Report").SemiBold().FontSize(20).FontColor(Colors.Blue.Darken2);
                page.Content().Element(ComposeTable);
                page.Footer().AlignCenter().Text(x =>
                {
                    x.Span("Generated on: ");
                    x.Span(DateTime.Now.ToString("g", CultureInfo.InvariantCulture)).SemiBold();
                });
            });
        }

        void ComposeTable(IContainer container)
        {
            container.Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn();
                    columns.RelativeColumn();
                    columns.RelativeColumn();
                    columns.RelativeColumn();
                    columns.RelativeColumn();
                });

                // Header
                table.Header(header =>
                {
                    header.Cell().Element(CellStyle).Text("Col1").SemiBold();
                    header.Cell().Element(CellStyle).Text("Col2").SemiBold();
                    header.Cell().Element(CellStyle).Text("Col3").SemiBold();
                    header.Cell().Element(CellStyle).Text("Col4").SemiBold();
                    header.Cell().Element(CellStyle).Text("Col5").SemiBold();
                });

                // Data rows
                foreach (var row in _data)
                {
                    table.Cell().Element(CellStyle).Text(row.Column1);
                    table.Cell().Element(CellStyle).Text(row.Column2);
                    table.Cell().Element(CellStyle).Text(row.Column3);
                    table.Cell().Element(CellStyle).Text(row.Column4);
                    table.Cell().Element(CellStyle).Text(row.Column5);
                }

                static IContainer CellStyle(IContainer container)
                {
                    return container.PaddingVertical(4).BorderBottom(1).BorderColor(Colors.Grey.Lighten2);
                }
            });
        }
    }

}
