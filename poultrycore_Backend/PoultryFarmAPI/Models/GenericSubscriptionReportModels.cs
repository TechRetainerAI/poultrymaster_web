namespace PoultryFarmAPIWeb.Models
{
    // Read models for migration 250: the Generic subscription dashboard and the
    // reports that go with it.
    //
    // Everything here is a projection of a function in 250 (or, where the number
    // already existed, of one from 037/244/248). Nothing is computed in C# --
    // if a figure needed arithmetic it was done in SQL, so the API and a psql
    // session give the same answer.

    // =========================================================================
    // Dashboard
    // =========================================================================

    /// <summary>The whole subscription dashboard in one response.</summary>
    public class GenericSubDashboard
    {
        public GenericSubDashboardKpis Kpis { get; set; } = new();
        public List<GenericSubRenewalRow> Renewals { get; set; } = new();
        public List<GenericOverduePartyRow> OverdueCustomers { get; set; } = new();
        public List<GenericExpenseSliceRow> ExpenseBreakdown { get; set; } = new();
        public List<GenericRecurringDueRow> RecurringDue { get; set; } = new();
        public List<GenericActivityRow> RecentActivity { get; set; } = new();
        public GenericSubAlerts Alerts { get; set; } = new();
        public GenericStaffPaySummary StaffSummary { get; set; } = new();
        public List<GenericCashSummaryRow> CashAccounts { get; set; } = new();
    }

    public class GenericSubDashboardKpis
    {
        public DateTime MonthStart { get; set; }
        public DateTime MonthEnd { get; set; }
        public decimal MonthlyRecurringRevenue { get; set; }
        public int ActiveSubscriptions { get; set; }
        public int ActiveCustomers { get; set; }
        public decimal PaymentsCollected { get; set; }
        public decimal ExpensesPaid { get; set; }
        public decimal NetCashFlow { get; set; }
        public decimal InvoicedThisMonth { get; set; }
        public decimal CustomerBalances { get; set; }
        public decimal SupplierBalances { get; set; }
        public decimal CashAtHand { get; set; }
        public int OverdueCustomers { get; set; }
        public decimal OverdueAmount { get; set; }
        public decimal MonthlyBurnRate { get; set; }
        public int BreakEvenCustomers { get; set; }
        public int NewSubscriptions { get; set; }
        public int CancelledSubscriptions { get; set; }
    }

    public class GenericSubRenewalRow
    {
        public int GenericSubscriptionId { get; set; }
        public string? SubscriptionNumber { get; set; }
        public int GenericCustomerId { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string? ServiceName { get; set; }
        public string BillingFrequency { get; set; } = string.Empty;
        public DateTime? NextBillingDate { get; set; }
        public decimal TotalBillingAmount { get; set; }
        /// <summary>Negative when the subscription is already late to bill.</summary>
        public int DaysUntil { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    public class GenericOverduePartyRow
    {
        public int PartyId { get; set; }
        public string PartyName { get; set; } = string.Empty;
        public string? ContactPhone { get; set; }
        public decimal TotalBalance { get; set; }
        public decimal OverdueAmount { get; set; }
        public int OpenDocumentCount { get; set; }
        public DateTime? OldestDocumentDate { get; set; }
        public DateTime? LastPaymentDate { get; set; }
    }

    public class GenericExpenseSliceRow
    {
        public int GenericExpenseCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public int ExpenseCount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal PctOfTotal { get; set; }
    }

    public class GenericRecurringDueRow
    {
        public int GenericRecurringExpenseId { get; set; }
        public string ExpenseName { get; set; } = string.Empty;
        public string? CategoryName { get; set; }
        public string? SupplierName { get; set; }
        public decimal Amount { get; set; }
        public string Frequency { get; set; } = string.Empty;
        public DateTime? NextDueDate { get; set; }
        public int DaysUntil { get; set; }
    }

    public class GenericActivityRow
    {
        public DateTime ActivityAt { get; set; }
        public string ActivityType { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Party { get; set; }
        public string? Description { get; set; }
        /// <summary>Signed: money out is negative.</summary>
        public decimal Amount { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    public class GenericSubAlerts
    {
        public int DueToBillCount { get; set; }
        public decimal DueToBillAmount { get; set; }
        public int DraftInvoiceCount { get; set; }
        public decimal DraftInvoiceAmount { get; set; }
        public int EndingSoonCount { get; set; }
        public int RecurringDueCount { get; set; }
        public decimal RecurringDueAmount { get; set; }
        public int OverdueCustomerCount { get; set; }
        public decimal OverdueCustomerAmount { get; set; }
        public int NegativeAccountCount { get; set; }
    }

    public class GenericStaffPaySummary
    {
        public int PeoplePaid { get; set; }
        public decimal StaffPaymentTotal { get; set; }
        public decimal PayrollTotal { get; set; }
        public decimal TotalPaid { get; set; }
        public string? TopPersonName { get; set; }
        public decimal TopPersonAmount { get; set; }
    }

    // =========================================================================
    // Reports
    // =========================================================================

    public class GenericMrrRow
    {
        public DateTime MonthStart { get; set; }
        public decimal ActiveMrr { get; set; }
        public int ActiveCount { get; set; }
        public decimal NewMrr { get; set; }
        public int NewCount { get; set; }
        public decimal LostMrr { get; set; }
        public int LostCount { get; set; }
        /// <summary>Always 0: there is no subscription amount history to derive it from.</summary>
        public decimal ExpansionMrr { get; set; }
        /// <summary>Always 0, for the same reason as <see cref="ExpansionMrr"/>.</summary>
        public decimal ContractionMrr { get; set; }
        public decimal NetMrrChange { get; set; }
    }

    public class GenericSubRevenueMonthRow
    {
        public DateTime MonthStart { get; set; }
        public int InvoiceCount { get; set; }
        public decimal InvoicedAmount { get; set; }
        /// <summary>Paid against that month's invoices as of now, not cash received that month.</summary>
        public decimal CollectedAmount { get; set; }
        public decimal Outstanding { get; set; }
        public decimal ActiveMrr { get; set; }
        public int NewCount { get; set; }
        public int LostCount { get; set; }
    }

    public class GenericSubRevenuePlanRow
    {
        public int GenericServiceId { get; set; }
        public string ServiceName { get; set; } = string.Empty;
        public string BillingFrequency { get; set; } = string.Empty;
        public int ActiveSubscriptions { get; set; }
        public decimal ActiveMrr { get; set; }
        public int InvoiceCount { get; set; }
        public decimal InvoicedAmount { get; set; }
        public decimal CollectedAmount { get; set; }
        public decimal Outstanding { get; set; }
    }

    public class GenericSubRevenueCustomerRow
    {
        public int GenericCustomerId { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string? ContactPhone { get; set; }
        public int ActiveSubscriptions { get; set; }
        public decimal ActiveMrr { get; set; }
        public int InvoiceCount { get; set; }
        public decimal InvoicedAmount { get; set; }
        public decimal CollectedAmount { get; set; }
        public decimal Outstanding { get; set; }
        public DateTime? LastPaymentDate { get; set; }
    }

    /// <summary>All three revenue cuts in one response, so the page makes one call.</summary>
    public class GenericSubRevenueReport
    {
        public List<GenericSubRevenueMonthRow> ByMonth { get; set; } = new();
        public List<GenericSubRevenuePlanRow> ByPlan { get; set; } = new();
        public List<GenericSubRevenueCustomerRow> ByCustomer { get; set; } = new();
    }

    public class GenericIncomeSplit
    {
        public decimal SubscriptionIncome { get; set; }
        public int SubscriptionInvoiceCount { get; set; }
        public decimal OtherIncome { get; set; }
        public int OtherSalesCount { get; set; }
        public decimal TotalIncome { get; set; }
    }

    public class GenericExpenseBySupplierRow
    {
        /// <summary>Null on the "No supplier" row.</summary>
        public int? GenericSupplierId { get; set; }
        public string SupplierName { get; set; } = string.Empty;
        public int ExpenseCount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Outstanding { get; set; }
    }

    public class GenericExpenseTrendRow
    {
        public DateTime MonthStart { get; set; }
        public int ExpenseCount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal RecurringAmount { get; set; }
        public decimal StaffAmount { get; set; }
    }

    /// <summary>The full expense report: categories, suppliers and the trend.</summary>
    public class GenericExpenseReport
    {
        public List<GenericExpenseByCategoryRow> ByCategory { get; set; } = new();
        public List<GenericExpenseBySupplierRow> BySupplier { get; set; } = new();
        public List<GenericExpenseTrendRow> Trend { get; set; } = new();
    }

    public class GenericHostingCategoryRow
    {
        public int GenericExpenseCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        /// <summary>Matched the hosting name pattern. A suggestion, not a decision.</summary>
        public bool IsSuggested { get; set; }
        public decimal TotalAmount { get; set; }
    }

    public class GenericHostingCostRow
    {
        public DateTime MonthStart { get; set; }
        public decimal HostingCost { get; set; }
        public int ExpenseCount { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal PctOfRevenue { get; set; }
        public decimal PctOfExpenses { get; set; }
    }

    public class GenericHostingCostReport
    {
        public List<GenericHostingCategoryRow> Categories { get; set; } = new();
        public List<GenericHostingCostRow> Months { get; set; } = new();
    }

    public class GenericStaffCostPersonRow
    {
        public int GenericStaffId { get; set; }
        public string StaffName { get; set; } = string.Empty;
        public string? StaffRole { get; set; }
        public string? WorkerType { get; set; }
        public int PaymentCount { get; set; }
        public decimal StaffPayments { get; set; }
        public decimal PayrollPay { get; set; }
        public decimal TotalPaid { get; set; }
        public DateTime? LastPaymentDate { get; set; }
    }

    public class GenericStaffCostMonthRow
    {
        public DateTime MonthStart { get; set; }
        public int PeoplePaid { get; set; }
        public decimal StaffPayments { get; set; }
        public decimal PayrollPay { get; set; }
        public decimal TotalPaid { get; set; }
    }

    public class GenericStaffCostRoleRow
    {
        public string StaffRole { get; set; } = string.Empty;
        public int PeopleCount { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal PctOfTotal { get; set; }
    }

    public class GenericStaffCostReport
    {
        public List<GenericStaffCostPersonRow> ByPerson { get; set; } = new();
        public List<GenericStaffCostMonthRow> ByMonth { get; set; } = new();
        public List<GenericStaffCostRoleRow> ByRole { get; set; } = new();
    }

    public class GenericBreakEven
    {
        public int MonthsAveraged { get; set; }
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public decimal MonthlyFixedCosts { get; set; }
        public decimal MonthlyRecurringRevenue { get; set; }
        public int ActiveCustomers { get; set; }
        public int ActiveSubscriptions { get; set; }
        public decimal AvgRevenuePerCustomer { get; set; }
        public int BreakEvenCustomers { get; set; }
        /// <summary>Negative means that many customers short of covering the month.</summary>
        public int CustomerSurplus { get; set; }
        public decimal MonthlySurplus { get; set; }
    }
}
