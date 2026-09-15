using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Migration 250's functions, projected into the read models.
    ///
    /// Two rules this class keeps:
    ///
    /// 1. NOTHING is computed here. Percentages, averages, break-even counts and
    ///    the month grid are all SQL. A number the API invents is a number a
    ///    psql session cannot reproduce.
    ///
    /// 2. A page that shows several panels gets ONE round trip. The dashboard
    ///    batches nine result sets into a single command, and each multi-cut
    ///    report batches its own -- the same shape GenericReportService already
    ///    uses for spgenericreport_dashboard_rs1..rs4.
    /// </summary>
    public class GenericSubscriptionReportService
        : GenericSubscriptionServiceBase, IGenericSubscriptionReportService
    {
        public GenericSubscriptionReportService(string connectionString) : base(connectionString) { }

        // "Today" is the same expression migration 250 uses internally, so a
        // dashboard opened at 00:30 in Accra reads the same month everywhere.
        private const string Today = "COALESCE(@AsOf::date, (now() at time zone 'utc')::date)";
        private const string MonthStart = "date_trunc('month', " + Today + ")::date";
        private const string MonthEnd = "(date_trunc('month', " + Today + ") + interval '1 month' - interval '1 day')::date";

        // =====================================================================
        // Dashboard: nine result sets, one round trip.
        // =====================================================================
        public async Task<GenericSubDashboard> GetDashboardAsync(string farmId, DateTime? asOf)
        {
            var sql =
                "SELECT * FROM spgenericsubdashboard_rs1(p_farmid => @FarmId::text, p_asof => @AsOf::date); " +
                "SELECT * FROM spgenericsubdashboard_rs2(p_farmid => @FarmId::text, p_asof => @AsOf::date, p_days => 30); " +
                "SELECT * FROM spgenericsubdashboard_rs3(p_farmid => @FarmId::text, p_limit => 10); " +
                "SELECT * FROM spgenericsubdashboard_rs4(p_farmid => @FarmId::text, p_asof => @AsOf::date); " +
                "SELECT * FROM spgenericsubdashboard_rs5(p_farmid => @FarmId::text, p_asof => @AsOf::date, p_days => 30); " +
                "SELECT * FROM spgenericsubdashboard_rs6(p_farmid => @FarmId::text, p_limit => 15); " +
                "SELECT * FROM spgenericsubdashboard_rs7(p_farmid => @FarmId::text, p_asof => @AsOf::date); " +
                "SELECT * FROM spgenericsubdashboard_rs8(p_farmid => @FarmId::text, p_asof => @AsOf::date); " +
                // Cash by account for the SAME month, from the existing cash
                // summary rather than a ninth new function.
                "SELECT * FROM spgenericreport_cashsummary_rs1(p_farmid => @FarmId::text, " +
                "    p_fromdate => " + MonthStart + ", p_todate => " + MonthEnd + ")";

            var dash = new GenericSubDashboard();

            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AsOf", DbDate(asOf));

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync()) dash.Kpis = ReadKpis(r);

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.Renewals.Add(ReadRenewal(r));

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.OverdueCustomers.Add(ReadOverdue(r));

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.ExpenseBreakdown.Add(ReadSlice(r));

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.RecurringDue.Add(ReadRecurringDue(r));

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.RecentActivity.Add(ReadActivity(r));

            if (await r.NextResultAsync() && await r.ReadAsync()) dash.Alerts = ReadAlerts(r);

            if (await r.NextResultAsync() && await r.ReadAsync()) dash.StaffSummary = ReadStaffSummary(r);

            if (await r.NextResultAsync())
                while (await r.ReadAsync()) dash.CashAccounts.Add(ReadCashRow(r));

            return dash;
        }

        // =====================================================================
        // Reports
        // =====================================================================
        public Task<List<GenericMrrRow>> GetMrrAsync(string farmId, DateTime fromDate, DateTime toDate) => Query(
            "SELECT * FROM spgenericreport_mrr(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)",
            c => Range(c, farmId, fromDate, toDate),
            ReadMrr);

        public async Task<GenericSubRevenueReport> GetSubscriptionRevenueAsync(
            string farmId, DateTime fromDate, DateTime toDate)
        {
            var sql =
                "SELECT * FROM spgenericreport_subscriptionrevenue_rs1(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date); " +
                "SELECT * FROM spgenericreport_subscriptionrevenue_rs2(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date); " +
                "SELECT * FROM spgenericreport_subscriptionrevenue_rs3(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)";

            var report = new GenericSubRevenueReport();

            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            Range(cmd, farmId, fromDate, toDate);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            while (await r.ReadAsync()) report.ByMonth.Add(ReadRevenueMonth(r));
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) report.ByPlan.Add(ReadRevenuePlan(r));
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) report.ByCustomer.Add(ReadRevenueCustomer(r));

            return report;
        }

        public async Task<GenericIncomeSplit> GetIncomeSplitAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var rows = await Query(
                "SELECT * FROM spgenericreport_incomesplit(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)",
                c => Range(c, farmId, fromDate, toDate),
                r => new GenericIncomeSplit
                {
                    SubscriptionIncome = Dec(r, "subscriptionincome"),
                    SubscriptionInvoiceCount = Int(r, "subscriptioninvoicecount"),
                    OtherIncome = Dec(r, "otherincome"),
                    OtherSalesCount = Int(r, "othersalescount"),
                    TotalIncome = Dec(r, "totalincome"),
                });
            return rows.FirstOrDefault() ?? new GenericIncomeSplit();
        }

        public async Task<GenericExpenseReport> GetExpenseReportAsync(
            string farmId, DateTime fromDate, DateTime toDate)
        {
            var sql =
                // The category cut is 037's function, unchanged: the Expenses by
                // category page and this report must not drift apart.
                "SELECT * FROM spgenericreport_expensesbycategory(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date); " +
                "SELECT * FROM spgenericreport_expensesbysupplier(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date); " +
                "SELECT * FROM spgenericreport_expensetrend(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)";

            var report = new GenericExpenseReport();

            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            Range(cmd, farmId, fromDate, toDate);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            while (await r.ReadAsync())
                report.ByCategory.Add(new GenericExpenseByCategoryRow
                {
                    GenericExpenseCategoryId = Int(r, "genericexpensecategoryid"),
                    CategoryName = Str(r, "categoryname") ?? string.Empty,
                    ExpenseCount = Int(r, "expensecount"),
                    TotalAmount = Dec(r, "totalamount"),
                });

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    report.BySupplier.Add(new GenericExpenseBySupplierRow
                    {
                        GenericSupplierId = IntN(r, "genericsupplierid"),
                        SupplierName = Str(r, "suppliername") ?? string.Empty,
                        ExpenseCount = Int(r, "expensecount"),
                        TotalAmount = Dec(r, "totalamount"),
                        AmountPaid = Dec(r, "amountpaid"),
                        Outstanding = Dec(r, "outstanding"),
                    });

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    report.Trend.Add(new GenericExpenseTrendRow
                    {
                        MonthStart = Date(r, "monthstart"),
                        ExpenseCount = Int(r, "expensecount"),
                        TotalAmount = Dec(r, "totalamount"),
                        RecurringAmount = Dec(r, "recurringamount"),
                        StaffAmount = Dec(r, "staffamount"),
                    });

            return report;
        }

        public async Task<GenericHostingCostReport> GetHostingCostAsync(
            string farmId, DateTime fromDate, DateTime toDate, int[]? categoryIds)
        {
            var sql =
                "SELECT * FROM spgenericreport_hostingcategories(p_farmid => @FarmId::text); " +
                "SELECT * FROM spgenericreport_hostingcost(p_farmid => @FarmId::text, p_from => @From::date, " +
                "    p_to => @To::date, p_categoryids => @Cats::integer[])";

            var report = new GenericHostingCostReport();

            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            Range(cmd, farmId, fromDate, toDate);
            // NULL means "use the suggested categories"; an empty array is a
            // real, different answer -- the owner ticked nothing.
            cmd.Parameters.AddWithValue("@Cats", (object?)categoryIds ?? DBNull.Value);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            while (await r.ReadAsync())
                report.Categories.Add(new GenericHostingCategoryRow
                {
                    GenericExpenseCategoryId = Int(r, "genericexpensecategoryid"),
                    CategoryName = Str(r, "categoryname") ?? string.Empty,
                    IsSuggested = Bool(r, "issuggested"),
                    TotalAmount = Dec(r, "totalamount"),
                });

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    report.Months.Add(new GenericHostingCostRow
                    {
                        MonthStart = Date(r, "monthstart"),
                        HostingCost = Dec(r, "hostingcost"),
                        ExpenseCount = Int(r, "expensecount"),
                        TotalRevenue = Dec(r, "totalrevenue"),
                        TotalExpenses = Dec(r, "totalexpenses"),
                        PctOfRevenue = Dec(r, "pctofrevenue"),
                        PctOfExpenses = Dec(r, "pctofexpenses"),
                    });

            return report;
        }

        public async Task<GenericStaffCostReport> GetStaffCostAsync(
            string farmId, DateTime fromDate, DateTime toDate)
        {
            var sql =
                "SELECT * FROM spgenericreport_staffcost_rs1(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date); " +
                "SELECT * FROM spgenericreport_staffcost_rs2(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date); " +
                "SELECT * FROM spgenericreport_staffcost_rs3(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)";

            var report = new GenericStaffCostReport();

            using var conn = new NpgsqlConnection(ConnectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            Range(cmd, farmId, fromDate, toDate);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            while (await r.ReadAsync())
                report.ByPerson.Add(new GenericStaffCostPersonRow
                {
                    GenericStaffId = Int(r, "genericstaffid"),
                    StaffName = Str(r, "staffname") ?? string.Empty,
                    StaffRole = Str(r, "staffrole"),
                    WorkerType = Str(r, "workertype"),
                    PaymentCount = Int(r, "paymentcount"),
                    StaffPayments = Dec(r, "staffpayments"),
                    PayrollPay = Dec(r, "payrollpay"),
                    TotalPaid = Dec(r, "totalpaid"),
                    LastPaymentDate = DateN(r, "lastpaymentdate"),
                });

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    report.ByMonth.Add(new GenericStaffCostMonthRow
                    {
                        MonthStart = Date(r, "monthstart"),
                        PeoplePaid = Int(r, "peoplepaid"),
                        StaffPayments = Dec(r, "staffpayments"),
                        PayrollPay = Dec(r, "payrollpay"),
                        TotalPaid = Dec(r, "totalpaid"),
                    });

            if (await r.NextResultAsync())
                while (await r.ReadAsync())
                    report.ByRole.Add(new GenericStaffCostRoleRow
                    {
                        StaffRole = Str(r, "staffrole") ?? string.Empty,
                        PeopleCount = Int(r, "peoplecount"),
                        TotalPaid = Dec(r, "totalpaid"),
                        PctOfTotal = Dec(r, "pctoftotal"),
                    });

            return report;
        }

        public async Task<GenericBreakEven> GetBreakEvenAsync(string farmId, DateTime? asOf, int months)
        {
            var rows = await Query(
                "SELECT * FROM spgenericreport_breakeven(p_farmid => @FarmId::text, p_asof => @AsOf::date, p_months => @Months::integer)",
                c =>
                {
                    c.Parameters.AddWithValue("@FarmId", farmId);
                    c.Parameters.AddWithValue("@AsOf", DbDate(asOf));
                    c.Parameters.AddWithValue("@Months", months);
                },
                r => new GenericBreakEven
                {
                    MonthsAveraged = Int(r, "monthsaveraged"),
                    PeriodStart = Date(r, "periodstart"),
                    PeriodEnd = Date(r, "periodend"),
                    MonthlyFixedCosts = Dec(r, "monthlyfixedcosts"),
                    MonthlyRecurringRevenue = Dec(r, "monthlyrecurringrevenue"),
                    ActiveCustomers = Int(r, "activecustomers"),
                    ActiveSubscriptions = Int(r, "activesubscriptions"),
                    AvgRevenuePerCustomer = Dec(r, "avgrevenuepercustomer"),
                    BreakEvenCustomers = Int(r, "breakevencustomers"),
                    CustomerSurplus = Int(r, "customersurplus"),
                    MonthlySurplus = Dec(r, "monthlysurplus"),
                });
            return rows.FirstOrDefault() ?? new GenericBreakEven();
        }

        // =====================================================================
        // Binding and mapping.
        // =====================================================================
        private static void Range(NpgsqlCommand c, string farmId, DateTime from, DateTime to)
        {
            c.Parameters.AddWithValue("@FarmId", farmId);
            c.Parameters.AddWithValue("@From", from.Date);
            c.Parameters.AddWithValue("@To", to.Date);
        }

        private static GenericSubDashboardKpis ReadKpis(NpgsqlDataReader r) => new()
        {
            MonthStart = Date(r, "monthstart"),
            MonthEnd = Date(r, "monthend"),
            MonthlyRecurringRevenue = Dec(r, "monthlyrecurringrevenue"),
            ActiveSubscriptions = Int(r, "activesubscriptions"),
            ActiveCustomers = Int(r, "activecustomers"),
            PaymentsCollected = Dec(r, "paymentscollected"),
            ExpensesPaid = Dec(r, "expensespaid"),
            NetCashFlow = Dec(r, "netcashflow"),
            InvoicedThisMonth = Dec(r, "invoicedthismonth"),
            CustomerBalances = Dec(r, "customerbalances"),
            SupplierBalances = Dec(r, "supplierbalances"),
            CashAtHand = Dec(r, "cashathand"),
            OverdueCustomers = Int(r, "overduecustomers"),
            OverdueAmount = Dec(r, "overdueamount"),
            MonthlyBurnRate = Dec(r, "monthlyburnrate"),
            BreakEvenCustomers = Int(r, "breakevencustomers"),
            NewSubscriptions = Int(r, "newsubscriptions"),
            CancelledSubscriptions = Int(r, "cancelledsubscriptions"),
        };

        private static GenericSubRenewalRow ReadRenewal(NpgsqlDataReader r) => new()
        {
            GenericSubscriptionId = Int(r, "genericsubscriptionid"),
            SubscriptionNumber = Str(r, "subscriptionnumber"),
            GenericCustomerId = Int(r, "genericcustomerid"),
            CustomerName = Str(r, "customername") ?? string.Empty,
            ServiceName = Str(r, "servicename"),
            BillingFrequency = Str(r, "billingfrequency") ?? string.Empty,
            NextBillingDate = DateN(r, "nextbillingdate"),
            TotalBillingAmount = Dec(r, "totalbillingamount"),
            DaysUntil = Int(r, "daysuntil"),
            Status = Str(r, "status") ?? string.Empty,
        };

        private static GenericOverduePartyRow ReadOverdue(NpgsqlDataReader r) => new()
        {
            PartyId = Int(r, "partyid"),
            PartyName = Str(r, "partyname") ?? string.Empty,
            ContactPhone = Str(r, "contactphone"),
            TotalBalance = Dec(r, "totalbalance"),
            OverdueAmount = Dec(r, "overdueamount"),
            OpenDocumentCount = Int(r, "opendocumentcount"),
            OldestDocumentDate = DateN(r, "oldestdocumentdate"),
            LastPaymentDate = DateN(r, "lastpaymentdate"),
        };

        private static GenericExpenseSliceRow ReadSlice(NpgsqlDataReader r) => new()
        {
            GenericExpenseCategoryId = Int(r, "genericexpensecategoryid"),
            CategoryName = Str(r, "categoryname") ?? string.Empty,
            ExpenseCount = Int(r, "expensecount"),
            TotalAmount = Dec(r, "totalamount"),
            PctOfTotal = Dec(r, "pctoftotal"),
        };

        private static GenericRecurringDueRow ReadRecurringDue(NpgsqlDataReader r) => new()
        {
            GenericRecurringExpenseId = Int(r, "genericrecurringexpenseid"),
            ExpenseName = Str(r, "expensename") ?? string.Empty,
            CategoryName = Str(r, "categoryname"),
            SupplierName = Str(r, "suppliername"),
            Amount = Dec(r, "amount"),
            Frequency = Str(r, "frequency") ?? string.Empty,
            NextDueDate = DateN(r, "nextduedate"),
            DaysUntil = Int(r, "daysuntil"),
        };

        private static GenericActivityRow ReadActivity(NpgsqlDataReader r) => new()
        {
            ActivityAt = Date(r, "activityat"),
            ActivityType = Str(r, "activitytype") ?? string.Empty,
            Reference = Str(r, "reference"),
            Party = Str(r, "party"),
            Description = Str(r, "description"),
            Amount = Dec(r, "amount"),
            Status = Str(r, "status") ?? string.Empty,
        };

        private static GenericSubAlerts ReadAlerts(NpgsqlDataReader r) => new()
        {
            DueToBillCount = Int(r, "duetobillcount"),
            DueToBillAmount = Dec(r, "duetobillamount"),
            DraftInvoiceCount = Int(r, "draftinvoicecount"),
            DraftInvoiceAmount = Dec(r, "draftinvoiceamount"),
            EndingSoonCount = Int(r, "endingsooncount"),
            RecurringDueCount = Int(r, "recurringduecount"),
            RecurringDueAmount = Dec(r, "recurringdueamount"),
            OverdueCustomerCount = Int(r, "overduecustomercount"),
            OverdueCustomerAmount = Dec(r, "overduecustomeramount"),
            NegativeAccountCount = Int(r, "negativeaccountcount"),
        };

        private static GenericStaffPaySummary ReadStaffSummary(NpgsqlDataReader r) => new()
        {
            PeoplePaid = Int(r, "peoplepaid"),
            StaffPaymentTotal = Dec(r, "staffpaymenttotal"),
            PayrollTotal = Dec(r, "payrolltotal"),
            TotalPaid = Dec(r, "totalpaid"),
            TopPersonName = Str(r, "toppersonname"),
            TopPersonAmount = Dec(r, "toppersonamount"),
        };

        private static GenericCashSummaryRow ReadCashRow(NpgsqlDataReader r) => new()
        {
            GenericCashAccountId = Int(r, "genericcashaccountid"),
            AccountName = Str(r, "accountname") ?? string.Empty,
            AccountType = Str(r, "accounttype") ?? string.Empty,
            CurrentBalance = Dec(r, "currentbalance"),
            PeriodCashIn = Dec(r, "periodcashin"),
            PeriodCashOut = Dec(r, "periodcashout"),
            IsActive = Bool(r, "isactive"),
        };

        private static GenericMrrRow ReadMrr(NpgsqlDataReader r) => new()
        {
            MonthStart = Date(r, "monthstart"),
            ActiveMrr = Dec(r, "activemrr"),
            ActiveCount = Int(r, "activecount"),
            NewMrr = Dec(r, "newmrr"),
            NewCount = Int(r, "newcount"),
            LostMrr = Dec(r, "lostmrr"),
            LostCount = Int(r, "lostcount"),
            ExpansionMrr = Dec(r, "expansionmrr"),
            ContractionMrr = Dec(r, "contractionmrr"),
            NetMrrChange = Dec(r, "netmrrchange"),
        };

        private static GenericSubRevenueMonthRow ReadRevenueMonth(NpgsqlDataReader r) => new()
        {
            MonthStart = Date(r, "monthstart"),
            InvoiceCount = Int(r, "invoicecount"),
            InvoicedAmount = Dec(r, "invoicedamount"),
            CollectedAmount = Dec(r, "collectedamount"),
            Outstanding = Dec(r, "outstanding"),
            ActiveMrr = Dec(r, "activemrr"),
            NewCount = Int(r, "newcount"),
            LostCount = Int(r, "lostcount"),
        };

        private static GenericSubRevenuePlanRow ReadRevenuePlan(NpgsqlDataReader r) => new()
        {
            GenericServiceId = Int(r, "genericserviceid"),
            ServiceName = Str(r, "servicename") ?? string.Empty,
            BillingFrequency = Str(r, "billingfrequency") ?? string.Empty,
            ActiveSubscriptions = Int(r, "activesubscriptions"),
            ActiveMrr = Dec(r, "activemrr"),
            InvoiceCount = Int(r, "invoicecount"),
            InvoicedAmount = Dec(r, "invoicedamount"),
            CollectedAmount = Dec(r, "collectedamount"),
            Outstanding = Dec(r, "outstanding"),
        };

        private static GenericSubRevenueCustomerRow ReadRevenueCustomer(NpgsqlDataReader r) => new()
        {
            GenericCustomerId = Int(r, "genericcustomerid"),
            CustomerName = Str(r, "customername") ?? string.Empty,
            ContactPhone = Str(r, "contactphone"),
            ActiveSubscriptions = Int(r, "activesubscriptions"),
            ActiveMrr = Dec(r, "activemrr"),
            InvoiceCount = Int(r, "invoicecount"),
            InvoicedAmount = Dec(r, "invoicedamount"),
            CollectedAmount = Dec(r, "collectedamount"),
            Outstanding = Dec(r, "outstanding"),
            LastPaymentDate = DateN(r, "lastpaymentdate"),
        };
    }
}
