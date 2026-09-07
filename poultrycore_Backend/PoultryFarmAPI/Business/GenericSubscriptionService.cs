using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Shared plumbing for the three Generic subscription services. Same shape
    /// as the other Business/ classes: a thin wrapper around NpgsqlCommand with
    /// named arguments and explicit casts, no repository and no EF.
    /// </summary>
    public abstract class GenericSubscriptionServiceBase
    {
        protected readonly string ConnectionString;

        protected GenericSubscriptionServiceBase(string connectionString) => ConnectionString = connectionString;

        protected static object Db(object? v) => v ?? DBNull.Value;
        protected static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : DBNull.Value;

        protected static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        protected static decimal Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0m : r.GetDecimal(i);
        }

        protected static int Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }

        protected static int? IntN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        protected static DateTime Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? default : r.GetDateTime(i);
        }

        protected static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        protected static bool Bool(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return !r.IsDBNull(i) && r.GetBoolean(i);
        }

        protected async Task<List<T>> Query<T>(string sql, Action<NpgsqlCommand> bind, Func<NpgsqlDataReader, T> map)
        {
            var list = new List<T>();
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(map(reader));
            return list;
        }

        protected async Task<int> Scalar(string sql, Action<NpgsqlCommand> bind)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null || result is DBNull ? 0 : Convert.ToInt32(result);
        }
    }

    // =========================================================================
    // Templates and module visibility (migration 242).
    // =========================================================================
    public class GenericBusinessTemplateService : GenericSubscriptionServiceBase, IGenericBusinessTemplateService
    {
        public GenericBusinessTemplateService(string connectionString) : base(connectionString) { }

        private static GenericModuleSettings Read(NpgsqlDataReader r) => new()
        {
            FarmId = Str(r, "farmid") ?? string.Empty,
            EnableProducts = Bool(r, "enableproducts"),
            EnableInventory = Bool(r, "enableinventory"),
            EnableStockAdjustments = Bool(r, "enablestockadjustments"),
            EnableInternalUse = Bool(r, "enableinternaluse"),
            EnablePurchases = Bool(r, "enablepurchases"),
            EnableSubscriptions = Bool(r, "enablesubscriptions"),
            EnableInvoices = Bool(r, "enableinvoices"),
            EnableCustomerBalances = Bool(r, "enablecustomerbalances"),
            EnableStaffPayments = Bool(r, "enablestaffpayments"),
            EnableCashAccounts = Bool(r, "enablecashaccounts"),
        };

        /// <summary>
        /// Which template this company is on. Null fields mean "no template",
        /// not "not found" -- an existing Generic company legitimately has none.
        /// </summary>
        public async Task<GenericBusinessTemplateInfo> GetTemplate(string farmId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericbusinesstemplate_get(p_farmid => @FarmId::text)",
                cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
                r => new GenericBusinessTemplateInfo
                {
                    FarmId = Str(r, "farmid") ?? farmId,
                    GenericBusinessTemplate = Str(r, "genericbusinesstemplate"),
                    GenericIndustryTemplate = Str(r, "genericindustrytemplate"),
                });
            return rows.FirstOrDefault() ?? new GenericBusinessTemplateInfo { FarmId = farmId };
        }

        /// <summary>
        /// Never returns null. The SP synthesises a default row for a company
        /// that has none, so an existing Generic company that predates templates
        /// sees every module it sees today.
        /// </summary>
        public async Task<GenericModuleSettings> GetModuleSettings(string farmId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericmodulesettings_get(p_farmid => @FarmId::text)",
                cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
                Read);
            return rows.FirstOrDefault() ?? new GenericModuleSettings { FarmId = farmId };
        }

        public async Task<GenericModuleSettings> SaveModuleSettings(GenericModuleSettings s)
        {
            var rows = await Query(
                "SELECT * FROM spgenericmodulesettings_upsert(p_farmid => @FarmId::text, p_enableproducts => @Products::boolean, p_enableinventory => @Inventory::boolean, p_enablestockadjustments => @StockAdj::boolean, p_enableinternaluse => @InternalUse::boolean, p_enablepurchases => @Purchases::boolean, p_enablesubscriptions => @Subscriptions::boolean, p_enableinvoices => @Invoices::boolean, p_enablecustomerbalances => @CustomerBalances::boolean, p_enablestaffpayments => @StaffPayments::boolean, p_enablecashaccounts => @CashAccounts::boolean)",
                cmd =>
                {
                    cmd.Parameters.AddWithValue("@FarmId", s.FarmId);
                    cmd.Parameters.AddWithValue("@Products", s.EnableProducts);
                    cmd.Parameters.AddWithValue("@Inventory", s.EnableInventory);
                    cmd.Parameters.AddWithValue("@StockAdj", s.EnableStockAdjustments);
                    cmd.Parameters.AddWithValue("@InternalUse", s.EnableInternalUse);
                    cmd.Parameters.AddWithValue("@Purchases", s.EnablePurchases);
                    cmd.Parameters.AddWithValue("@Subscriptions", s.EnableSubscriptions);
                    cmd.Parameters.AddWithValue("@Invoices", s.EnableInvoices);
                    cmd.Parameters.AddWithValue("@CustomerBalances", s.EnableCustomerBalances);
                    cmd.Parameters.AddWithValue("@StaffPayments", s.EnableStaffPayments);
                    cmd.Parameters.AddWithValue("@CashAccounts", s.EnableCashAccounts);
                },
                Read);
            return rows.FirstOrDefault() ?? s;
        }

        /// <summary>
        /// Stamps the template on the profile and seeds this industry's income
        /// categories, expense categories, cash accounts and starter plans.
        /// Every seed is ON CONFLICT DO NOTHING, so re-applying is safe and
        /// never duplicates or overwrites what the owner has since edited.
        /// </summary>
        public async Task ApplyTemplate(ApplyBusinessTemplateRequest r)
        {
            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericbusinesstemplate_apply(p_farmid => @FarmId::text, p_businesstemplate => @Business::text, p_industrytemplate => @Industry::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@Business", r.BusinessTemplate);
            cmd.Parameters.AddWithValue("@Industry", r.IndustryTemplate);
            cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }

    // =========================================================================
    // Subscriptions (migration 243).
    // =========================================================================
    public class GenericSubscriptionService : GenericSubscriptionServiceBase, IGenericSubscriptionService
    {
        public GenericSubscriptionService(string connectionString) : base(connectionString) { }

        // ------------------------------------------------------------- plans

        public Task<List<GenericServicePlanRow>> GetPlans(string farmId, bool activeOnly) => Query(
            "SELECT * FROM spgenericserviceplan_getall(p_farmid => @FarmId::text, p_activeonly => @ActiveOnly::boolean)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@ActiveOnly", activeOnly);
            },
            r => new GenericServicePlanRow
            {
                GenericServiceId = Int(r, "genericserviceid"),
                FarmId = Str(r, "farmid") ?? string.Empty,
                ServiceName = Str(r, "servicename") ?? string.Empty,
                GenericServiceCategoryId = IntN(r, "genericservicecategoryid"),
                CategoryName = Str(r, "categoryname"),
                DefaultPrice = Dec(r, "defaultprice"),
                PlanType = Str(r, "plantype"),
                BillingFrequency = Str(r, "billingfrequency"),
                Notes = Str(r, "notes"),
                IsActive = Bool(r, "isactive"),
                ActiveSubscriptions = Int(r, "activesubscriptions"),
                MonthlyValue = Dec(r, "monthlyvalue"),
            });

        /// <summary>
        /// Sets only the two plan columns. Creating and editing the service
        /// itself still goes through the existing service-catalogue endpoints.
        /// </summary>
        public Task<int> SetPlan(int serviceId, SetServicePlanRequest r) => Scalar(
            "SELECT spgenericserviceplan_setplan(p_genericserviceid => @Id::int, p_farmid => @FarmId::text, p_plantype => @PlanType::text, p_billingfrequency => @Frequency::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@Id", serviceId);
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@PlanType", Db(r.PlanType));
                cmd.Parameters.AddWithValue("@Frequency", Db(r.BillingFrequency));
            });

        // ----------------------------------------------------- subscriptions

        public Task<List<GenericSubscriptionRow>> GetAll(string farmId, string? status) => Query(
            "SELECT * FROM spgenericsubscription_getall(p_farmid => @FarmId::text, p_status => @Status::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Status", Db(status));
            },
            r => new GenericSubscriptionRow
            {
                GenericSubscriptionId = Int(r, "genericsubscriptionid"),
                FarmId = Str(r, "farmid") ?? string.Empty,
                GenericCustomerId = Int(r, "genericcustomerid"),
                CustomerName = Str(r, "customername"),
                GenericServiceId = Int(r, "genericserviceid"),
                ServiceName = Str(r, "servicename"),
                SubscriptionNumber = Str(r, "subscriptionnumber"),
                StartDate = Date(r, "startdate"),
                EndDate = DateN(r, "enddate"),
                BillingFrequency = Str(r, "billingfrequency") ?? string.Empty,
                BillingAmount = Dec(r, "billingamount"),
                DiscountAmount = Dec(r, "discountamount"),
                TaxAmount = Dec(r, "taxamount"),
                TotalBillingAmount = Dec(r, "totalbillingamount"),
                NextBillingDate = DateN(r, "nextbillingdate"),
                LastBillingDate = DateN(r, "lastbillingdate"),
                PaymentDueDays = Int(r, "paymentduedays"),
                AutoGenerateInvoice = Bool(r, "autogenerateinvoice"),
                DefaultPaymentMethod = Str(r, "defaultpaymentmethod"),
                DefaultCashAccountId = IntN(r, "defaultcashaccountid"),
                Status = Str(r, "status") ?? string.Empty,
                Notes = Str(r, "notes"),
                OpenInvoiceCount = Int(r, "openinvoicecount"),
                OpenBalance = Dec(r, "openbalance"),
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat"),
            });

        public Task<int> Create(CreateSubscriptionRequest r) => Scalar(
            "SELECT spgenericsubscription_insert(p_farmid => @FarmId::text, p_genericcustomerid => @CustomerId::int, p_genericserviceid => @ServiceId::int, p_startdate => @StartDate::date, p_billingfrequency => @Frequency::text, p_billingamount => @Amount::numeric, p_discountamount => @Discount::numeric, p_taxamount => @Tax::numeric, p_paymentduedays => @DueDays::int, p_autogenerateinvoice => @AutoGenerate::boolean, p_enddate => @EndDate::date, p_defaultpaymentmethod => @Method::text, p_defaultcashaccountid => @CashAccountId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@CustomerId", r.GenericCustomerId);
                cmd.Parameters.AddWithValue("@ServiceId", r.GenericServiceId);
                cmd.Parameters.AddWithValue("@StartDate", r.StartDate.Date);
                cmd.Parameters.AddWithValue("@Frequency", r.BillingFrequency);
                cmd.Parameters.AddWithValue("@Amount", r.BillingAmount);
                cmd.Parameters.AddWithValue("@Discount", r.DiscountAmount);
                cmd.Parameters.AddWithValue("@Tax", r.TaxAmount);
                cmd.Parameters.AddWithValue("@DueDays", r.PaymentDueDays);
                cmd.Parameters.AddWithValue("@AutoGenerate", r.AutoGenerateInvoice);
                cmd.Parameters.AddWithValue("@EndDate", DbDate(r.EndDate));
                cmd.Parameters.AddWithValue("@Method", Db(r.DefaultPaymentMethod));
                cmd.Parameters.AddWithValue("@CashAccountId", Db(r.DefaultCashAccountId));
                cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        /// <summary>
        /// Pause, resume, suspend, cancel or expire. Cancelling requires a
        /// reason -- the SP enforces that, not this layer.
        /// </summary>
        public Task<int> SetStatus(int subscriptionId, SetSubscriptionStatusRequest r) => Scalar(
            "SELECT spgenericsubscription_setstatus(p_genericsubscriptionid => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text, p_by => @By::text, p_reason => @Reason::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@Id", subscriptionId);
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Status", r.Status);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
                cmd.Parameters.AddWithValue("@Reason", Db(r.Reason));
            });
    }

    // =========================================================================
    // Billing runs (migration 243).
    // =========================================================================
    public class GenericBillingService : GenericSubscriptionServiceBase, IGenericBillingService
    {
        public GenericBillingService(string connectionString) : base(connectionString) { }

        /// <summary>
        /// What generating right now would raise. Preview and generate share the
        /// same selection in SQL, so the owner cannot be shown one set and
        /// charged another.
        /// </summary>
        public Task<List<BillingPreviewRow>> Preview(string farmId, DateTime? asOf) => Query(
            "SELECT * FROM spgenericbillingrun_preview(p_farmid => @FarmId::text, p_asof => @AsOf::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@AsOf", DbDate(asOf));
            },
            r => new BillingPreviewRow
            {
                GenericSubscriptionId = Int(r, "genericsubscriptionid"),
                SubscriptionNumber = Str(r, "subscriptionnumber"),
                GenericCustomerId = Int(r, "genericcustomerid"),
                CustomerName = Str(r, "customername"),
                ServiceName = Str(r, "servicename"),
                BillingFrequency = Str(r, "billingfrequency") ?? string.Empty,
                BillingPeriodStart = Date(r, "billingperiodstart"),
                BillingPeriodEnd = Date(r, "billingperiodend"),
                DueDate = Date(r, "duedate"),
                InvoiceAmount = Dec(r, "invoiceamount"),
                AlreadyBilled = Bool(r, "alreadybilled"),
            });

        /// <summary>
        /// Raises one Draft invoice per unbilled period, catching up any
        /// subscription that is behind. Returns the billing run id. Running it
        /// twice for the same period adds nothing -- a partial unique index on
        /// the subscription and period makes double-billing impossible even if
        /// two people press the button at once.
        /// </summary>
        public Task<int> Generate(GenerateBillingRequest r) => Scalar(
            "SELECT spgenericbillingrun_generate(p_farmid => @FarmId::text, p_asof => @AsOf::date, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@AsOf", DbDate(r.AsOf));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        /// <summary>
        /// The Invoices page. Same rows the Sales page shows, read through an
        /// invoice-shaped lens -- so an invoice raised by a billing run and a
        /// counter sale that is still owed appear side by side.
        /// </summary>
        public Task<List<GenericInvoiceRow>> GetInvoices(
            string farmId, string? status, bool subscriptionOnly, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericinvoice_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_subscriptiononly => @SubsOnly::boolean, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Status", Db(status));
                cmd.Parameters.AddWithValue("@SubsOnly", subscriptionOnly);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new GenericInvoiceRow
            {
                GenericSaleId = Int(r, "genericsaleid"),
                ReceiptNumber = Str(r, "receiptnumber"),
                SaleDate = Date(r, "saledate"),
                DueDate = DateN(r, "duedate"),
                GenericCustomerId = IntN(r, "genericcustomerid"),
                CustomerName = Str(r, "customername"),
                GenericSubscriptionId = IntN(r, "genericsubscriptionid"),
                SubscriptionNumber = Str(r, "subscriptionnumber"),
                BillingPeriodStart = DateN(r, "billingperiodstart"),
                BillingPeriodEnd = DateN(r, "billingperiodend"),
                TotalAmount = Dec(r, "totalamount"),
                AmountPaid = Dec(r, "amountpaid"),
                Balance = Dec(r, "balance"),
                PaymentStatus = Str(r, "paymentstatus") ?? string.Empty,
                Status = Str(r, "status") ?? string.Empty,
                IsOverdue = Bool(r, "isoverdue"),
                AgeDays = Int(r, "agedays"),
                Notes = Str(r, "notes"),
                CreatedAt = DateN(r, "createdat"),
            });

        public Task<List<BillingRunRow>> GetRuns(string farmId) => Query(
            "SELECT * FROM spgenericbillingrun_getall(p_farmid => @FarmId::text)",
            cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
            r => new BillingRunRow
            {
                GenericBillingRunId = Int(r, "genericbillingrunid"),
                BillingRunDate = Date(r, "billingrundate"),
                AsOfDate = Date(r, "asofdate"),
                TotalSubscriptionsChecked = Int(r, "totalsubscriptionschecked"),
                TotalInvoicesGenerated = Int(r, "totalinvoicesgenerated"),
                TotalSkipped = Int(r, "totalskipped"),
                Status = Str(r, "status") ?? string.Empty,
                Notes = Str(r, "notes"),
                CreatedBy = Str(r, "createdby"),
            });
    }
}
