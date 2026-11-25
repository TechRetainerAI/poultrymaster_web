using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericInvoiceDocumentService : GenericSubscriptionServiceBase, IGenericInvoiceDocumentService
    {
        public GenericInvoiceDocumentService(string connectionString) : base(connectionString) { }

        // =================================================================
        // Settings
        // =================================================================

        public async Task<InvoiceSettingsDto> GetSettings(string farmId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericinvoicesettings_get(@fid)",
                c => c.Parameters.AddWithValue("fid", farmId),
                r => new InvoiceSettingsDto
                {
                    FarmId = Str(r, "farmid") ?? farmId,
                    InvoicePrefix = Str(r, "invoiceprefix") ?? "INV",
                    NextNumber = Int(r, "nextnumber"),
                    DefaultPaymentTerms = Str(r, "defaultpaymentterms") ?? "DueImmediately",
                    PaymentInstructions = Str(r, "paymentinstructions"),
                    FooterNotes = Str(r, "footernotes"),
                    TermsAndConditions = Str(r, "termsandconditions"),
                    AutoGenerateInvoiceAfterSale = Bool(r, "autogenerateinvoiceaftersale"),
                    AutoSendInvoiceAfterIssuance = Bool(r, "autosendinvoiceafterissuance"),
                });
            return rows.FirstOrDefault() ?? new InvoiceSettingsDto { FarmId = farmId };
        }

        public async Task SaveSettings(InvoiceSettingsDto s)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericinvoicesettings_save(@fid, @prefix, @terms, @instr, @footer, @tnc, @autoGen, @autoSend)", conn);
            cmd.Parameters.AddWithValue("fid", s.FarmId);
            cmd.Parameters.AddWithValue("prefix", Db(s.InvoicePrefix));
            cmd.Parameters.AddWithValue("terms", Db(s.DefaultPaymentTerms));
            cmd.Parameters.AddWithValue("instr", Db(s.PaymentInstructions));
            cmd.Parameters.AddWithValue("footer", Db(s.FooterNotes));
            cmd.Parameters.AddWithValue("tnc", Db(s.TermsAndConditions));
            cmd.Parameters.AddWithValue("autoGen", s.AutoGenerateInvoiceAfterSale);
            cmd.Parameters.AddWithValue("autoSend", s.AutoSendInvoiceAfterIssuance);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =================================================================
        // Generate
        // =================================================================

        public async Task<int> Generate(GenerateInvoiceDocumentRequest r)
        {
            return await Scalar(
                "SELECT spgenericinvoicedocument_generate(@fid, @sid, @due, @terms, @po, @del, @notes, @by)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", r.FarmId);
                    c.Parameters.AddWithValue("sid", r.SaleId);
                    c.Parameters.AddWithValue("due", DbDate(r.DueDate));
                    c.Parameters.AddWithValue("terms", Db(r.PaymentTerms));
                    c.Parameters.AddWithValue("po", Db(r.PurchaseOrderReference));
                    c.Parameters.AddWithValue("del", Db(r.DeliveryReference));
                    c.Parameters.AddWithValue("notes", Db(r.PaymentInstructions));
                    c.Parameters.AddWithValue("by", Db(r.CreatedBy));
                });
        }

        // =================================================================
        // Get single
        // =================================================================

        public async Task<InvoiceDocumentDetail?> Get(string farmId, int docId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericinvoicedocument_get(@fid, @did)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", farmId);
                    c.Parameters.AddWithValue("did", docId);
                },
                ReadDetail);

            var doc = rows.FirstOrDefault();
            if (doc == null) return null;

            // Populate lines and history in parallel
            var linesTask = GetSaleLines(farmId, doc.GenericSaleId);
            var histTask = GetHistory(farmId, docId);
            await Task.WhenAll(linesTask, histTask);
            doc.Lines = linesTask.Result;
            doc.History = histTask.Result;
            return doc;
        }

        public async Task<InvoiceSaleLookup?> GetBySale(string farmId, int saleId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericinvoicedocument_getbysale(@fid, @sid)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", farmId);
                    c.Parameters.AddWithValue("sid", saleId);
                },
                r => new InvoiceSaleLookup
                {
                    GenericInvoiceDocumentId = Int(r, "genericinvoicedocumentid"),
                    InvoiceNumber = Str(r, "invoicenumber") ?? "",
                    DocumentStatus = Str(r, "documentstatus") ?? "",
                    IssueDate = Date(r, "issuedate"),
                    DueDate = DateN(r, "duedate"),
                });
            return rows.FirstOrDefault();
        }

        // =================================================================
        // List
        // =================================================================

        public async Task<List<InvoiceDocumentRow>> GetAll(
            string farmId, string? documentStatus, string? paymentStatus,
            int? customerId, int? projectId,
            DateTime? from, DateTime? to, bool overdueOnly)
        {
            return await Query(
                "SELECT * FROM spgenericinvoicedocument_getall(@fid, @ds, @ps, @cid, @pid, @from, @to, @ov)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", farmId);
                    c.Parameters.AddWithValue("ds", Db(documentStatus));
                    c.Parameters.AddWithValue("ps", Db(paymentStatus));
                    c.Parameters.AddWithValue("cid", customerId.HasValue ? customerId.Value : DBNull.Value);
                    c.Parameters.AddWithValue("pid", projectId.HasValue ? projectId.Value : DBNull.Value);
                    c.Parameters.AddWithValue("from", DbDate(from));
                    c.Parameters.AddWithValue("to", DbDate(to));
                    c.Parameters.AddWithValue("ov", overdueOnly);
                },
                r => new InvoiceDocumentRow
                {
                    GenericInvoiceDocumentId = Int(r, "genericinvoicedocumentid"),
                    GenericSaleId = Int(r, "genericsaleid"),
                    InvoiceNumber = Str(r, "invoicenumber") ?? "",
                    IssueDate = Date(r, "issuedate"),
                    DueDate = DateN(r, "duedate"),
                    PaymentTerms = Str(r, "paymentterms") ?? "DueImmediately",
                    DocumentStatus = Str(r, "documentstatus") ?? "Draft",
                    CustomerBillingName = Str(r, "customerbillingname"),
                    GenericProjectId = IntN(r, "genericprojectid"),
                    ProjectName = Str(r, "projectname"),
                    SaleReceiptNumber = Str(r, "salereceiptnumber"),
                    TotalAmount = Dec(r, "totalamount"),
                    AmountPaid = Dec(r, "amountpaid"),
                    Balance = Dec(r, "balance"),
                    PaymentStatus = Str(r, "paymentstatus"),
                    IsOverdue = Bool(r, "isoverdue"),
                    DaysUntilDue = IntN(r, "daysuntildue"),
                    CreatedAt = DateN(r, "createdat"),
                });
        }

        // =================================================================
        // Lifecycle
        // =================================================================

        public async Task Issue(string farmId, int docId, string issuedBy)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericinvoicedocument_issue(@fid, @did, @by)", conn);
            cmd.Parameters.AddWithValue("fid", farmId);
            cmd.Parameters.AddWithValue("did", docId);
            cmd.Parameters.AddWithValue("by", Db(issuedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task Void(string farmId, int docId, string reason, string voidedBy)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericinvoicedocument_void(@fid, @did, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("fid", farmId);
            cmd.Parameters.AddWithValue("did", docId);
            cmd.Parameters.AddWithValue("reason", reason);
            cmd.Parameters.AddWithValue("by", Db(voidedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateDraft(string farmId, int docId, UpdateDraftInvoiceRequest r)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericinvoicedocument_updatedraft(@fid, @did, @due, @terms, @po, @del, @notes, @footer, @tnc, @by)", conn);
            cmd.Parameters.AddWithValue("fid", farmId);
            cmd.Parameters.AddWithValue("did", docId);
            cmd.Parameters.AddWithValue("due", DbDate(r.DueDate));
            cmd.Parameters.AddWithValue("terms", Db(r.PaymentTerms));
            cmd.Parameters.AddWithValue("po", Db(r.PurchaseOrderReference));
            cmd.Parameters.AddWithValue("del", Db(r.DeliveryReference));
            cmd.Parameters.AddWithValue("notes", Db(r.PaymentInstructions));
            cmd.Parameters.AddWithValue("footer", Db(r.FooterNotes));
            cmd.Parameters.AddWithValue("tnc", Db(r.TermsAndConditions));
            cmd.Parameters.AddWithValue("by", Db(r.UpdatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =================================================================
        // Supporting data
        // =================================================================

        public async Task<List<InvoiceSaleLineRow>> GetSaleLines(string farmId, int saleId)
        {
            return await Query(
                "SELECT * FROM spgenericinvoicedocument_getsalelines(@fid, @sid)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", farmId);
                    c.Parameters.AddWithValue("sid", saleId);
                },
                r => new InvoiceSaleLineRow
                {
                    GenericSaleItemId = Int(r, "genericsaleitemid"),
                    ItemType = Str(r, "itemtype"),
                    GenericProductId = IntN(r, "genericproductid"),
                    GenericServiceId = IntN(r, "genericserviceid"),
                    ProductName = Str(r, "productname"),
                    ServiceName = Str(r, "servicename"),
                    Description = Str(r, "description"),
                    Quantity = Dec(r, "quantity"),
                    UnitName = Str(r, "unitname"),
                    UnitPrice = Dec(r, "unitprice"),
                    DiscountAmount = Dec(r, "discountamount"),
                    TaxAmount = Dec(r, "taxamount"),
                    LineTotal = Dec(r, "linetotal"),
                    GenericProjectId = IntN(r, "genericprojectid"),
                });
        }

        public async Task<List<InvoiceHistoryRow>> GetHistory(string farmId, int docId)
        {
            return await Query(
                "SELECT * FROM spgenericinvoicedocument_gethistory(@fid, @did)",
                c =>
                {
                    c.Parameters.AddWithValue("fid", farmId);
                    c.Parameters.AddWithValue("did", docId);
                },
                r => new InvoiceHistoryRow
                {
                    GenericInvoiceHistoryId = Int(r, "genericinvoicehistoryid"),
                    Action = Str(r, "action") ?? "",
                    PreviousValue = Str(r, "previousvalue"),
                    NewValue = Str(r, "newvalue"),
                    UserId = Str(r, "userid"),
                    CreatedAt = DateN(r, "createdat"),
                });
        }

        // =================================================================
        // Reconciliation
        // =================================================================

        public async Task<List<InvoiceReconciliationRow>> Reconcile(string farmId)
        {
            return await Query(
                "SELECT * FROM fngenericinvoicedocument_reconcile(@fid)",
                c => c.Parameters.AddWithValue("fid", farmId),
                r => new InvoiceReconciliationRow
                {
                    CheckName = Str(r, "checkname") ?? "",
                    Severity = Str(r, "severity") ?? "",
                    DocumentId = IntN(r, "documentid"),
                    SaleId = IntN(r, "saleid"),
                    Detail = Str(r, "detail") ?? "",
                });
        }

        // =================================================================
        // Private reader
        // =================================================================

        private static InvoiceDocumentDetail ReadDetail(NpgsqlDataReader r) => new()
        {
            GenericInvoiceDocumentId = Int(r, "genericinvoicedocumentid"),
            FarmId = Str(r, "farmid") ?? "",
            GenericSaleId = Int(r, "genericsaleid"),
            InvoiceNumber = Str(r, "invoicenumber") ?? "",
            IssueDate = Date(r, "issuedate"),
            DueDate = DateN(r, "duedate"),
            PaymentTerms = Str(r, "paymentterms") ?? "DueImmediately",
            DocumentStatus = Str(r, "documentstatus") ?? "Draft",
            CustomerBillingName = Str(r, "customerbillingname"),
            CustomerBillingAddress = Str(r, "customerbillingaddress"),
            CustomerBillingEmail = Str(r, "customerbillingemail"),
            CustomerBillingPhone = Str(r, "customerbillingphone"),
            PaymentInstructions = Str(r, "paymentinstructions"),
            FooterNotes = Str(r, "footernotes"),
            TermsAndConditions = Str(r, "termsandconditions"),
            PurchaseOrderReference = Str(r, "purchaseorderreference"),
            DeliveryReference = Str(r, "deliveryreference"),
            GenericProjectId = IntN(r, "genericprojectid"),
            ProjectName = Str(r, "projectname"),
            Version = Int(r, "version"),
            VoidedBy = Str(r, "voidedby"),
            VoidedAt = DateN(r, "voidedat"),
            VoidReason = Str(r, "voidreason"),
            IssuedBy = Str(r, "issuedby"),
            IssuedAt = DateN(r, "issuedat"),
            CreatedBy = Str(r, "createdby"),
            CreatedAt = DateN(r, "createdat"),
            SaleReceiptNumber = Str(r, "salereceiptnumber"),
            SaleDate = DateN(r, "saledate"),
            SalesType = Str(r, "salestype"),
            SubtotalAmount = Dec(r, "subtotalamount"),
            DiscountAmount = Dec(r, "discountamount"),
            TaxAmount = Dec(r, "taxamount"),
            TotalAmount = Dec(r, "totalamount"),
            AmountPaid = Dec(r, "amountpaid"),
            Balance = Dec(r, "balance"),
            PaymentStatus = Str(r, "paymentstatus"),
            SaleStatus = Str(r, "salestatus"),
            IsOverdue = Bool(r, "isoverdue"),
            DaysUntilDue = IntN(r, "daysuntildue"),
        };
    }
}
