// PROMPT 1 (Platform Activity Foundation): maps a successful mutating request
// (controller + action, as the global AuditLogActionFilter sees them) onto the
// normalized activity vocabulary. One choke point — no per-controller edits.
//
// Three tiers:
//   1. Explicit map   — the business milestones the platform cares about
//                       (meaningful activity + curated ActivityType names).
//   2. Typed non-meaningful map — real events with nice names that do NOT
//                       count as meaningful usage (EmployeeCreated, ...).
//   3. Fallback       — any other successful POST/PUT/DELETE on a recognized
//                       module is recorded as non-meaningful usage with a
//                       derived category; unrecognized controllers are skipped
//                       entirely (auditlogs still captures them).
//
// "Meaningful" follows the spec: production posted, sale created, payment
// recorded, expense entered, booking created, payroll approved, inventory
// received, daily closing completed — never page views or lookups (GETs never
// reach this class). Reversals/cancellations fall through to the fallback.

namespace PoultryFarmAPIWeb.Business
{
    public sealed record ActivityClassification(
        string Category,
        string ActivityType,
        string SourceModule,
        bool IsMeaningful);

    public static class ActivityClassifier
    {
        // Controllers whose writes are platform plumbing, not customer usage.
        private static readonly HashSet<string> Skip = new(StringComparer.OrdinalIgnoreCase)
        {
            "AuditLogs", "Test", "WeatherForecast", "Email", "Chat", "Announcement",
            "PlatformActivity", "PlatformHealth", "PlatformAnalytics", "PlatformCrm", "PlatformRevenue", "PlatformOps", "PlatformFarms",
            "PlatformBillingAdmin", "PlatformBillingAdminApp",
            // The webhook's meaningful payment event is emitted by
            // PlatformBillingService itself (with a correlation id) after commit.
            "PlatformBillingWebhook",
        };

        // Controllers without a family prefix that belong to the Poultry vertical
        // (the app's original module names).
        private static readonly HashSet<string> PoultryLegacy = new(StringComparer.OrdinalIgnoreCase)
        {
            "Sale", "EggProduction", "ProductionRecord", "ProductionBatchRecord",
            "FeedUsage", "Flock", "FlockCloseout", "MainFlockBatch", "House",
            "Expense", "Cash", "CashFlow", "Customer", "Supplier",
            "InventoryItem", "InventoryTransaction",
            "EggInventoryAdjustment", "FeedInventoryAdjustment",
            "Health", "FarmObservation", "FarmProductionSettings", "Dashboard",
        };

        private static readonly HashSet<string> Shared = new(StringComparer.OrdinalIgnoreCase)
        {
            "BusinessOffice", "CompanyTime", "Iam", "UserQuickLink", "ActivityChecks",
        };

        // Tier 1: meaningful business milestones. Key = "Controller.Action".
        private static readonly Dictionary<string, (string Cat, string Type)> Meaningful =
            new(StringComparer.OrdinalIgnoreCase)
        {
            // ---- Poultry ----
            ["Sale.Create"] = ("SALES", "SaleRecorded"),
            ["Sale.CreateGroup"] = ("SALES", "SaleRecorded"),
            ["EggProduction.Create"] = ("PRODUCTION", "ProductionRecorded"),
            ["ProductionRecord.Create"] = ("PRODUCTION", "ProductionRecorded"),
            ["ProductionBatchRecord.Post"] = ("PRODUCTION", "BatchProductionPosted"),
            ["PoultryFeedProductionBatch.Post"] = ("PRODUCTION", "FeedProductionPosted"),
            ["FeedUsage.Create"] = ("OPERATIONS", "FeedUsageRecorded"),
            ["Health.Create"] = ("OPERATIONS", "MedicationRecorded"),
            ["Flock.Create"] = ("OPERATIONS", "FlockCreated"),
            ["MainFlockBatch.Create"] = ("OPERATIONS", "BatchCreated"),
            ["FlockCloseout.Close"] = ("OPERATIONS", "FlockClosed"),
            ["PoultryDailyClosing.Submit"] = ("CLOSING", "DailyClosingCompleted"),
            ["PoultryDailyClosingControl.Close"] = ("CLOSING", "DailyClosingCompleted"),
            ["PoultryPayment.Record"] = ("PAYMENTS", "PaymentRecorded"),
            ["PoultryBalances.RecordCustomerPayment"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["PoultryBalances.RecordSupplierPayment"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["Expense.Create"] = ("EXPENSES", "ExpenseCreated"),
            ["PoultryPayroll.Approve"] = ("PAYROLL", "PayrollApproved"),
            ["PoultryFarmSetup.Complete"] = ("SETUP", "FarmSetupCompleted"),
            ["PoultryCompany.Setup"] = ("SETUP", "CompanySetupCompleted"),
            ["InventoryTransaction.Create"] = ("INVENTORY", "InventoryMovementRecorded"),
            ["PoultryRawMaterialPurchase.Create"] = ("INVENTORY", "InventoryReceived"),
            ["PoultryStock.AddTransaction"] = ("INVENTORY", "InventoryMovementRecorded"),
            ["PoultryDriverReturns.Approve"] = ("DELIVERY", "DriverReturnCompleted"),
            ["PoultryDriverReturns.ApproveReconcile"] = ("DELIVERY", "DriverReturnCompleted"),
            ["PoultryCashReconciliation.Post"] = ("OPERATIONS", "CashReconciled"),

            // ---- Water ----
            ["WaterSale.Create"] = ("SALES", "SaleRecorded"),
            ["WaterPayment.Record"] = ("PAYMENTS", "PaymentRecorded"),
            ["WaterBalances.RecordCustomerPayment"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["WaterBalances.RecordSupplierPayment"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["WaterDailyProduction.Post"] = ("PRODUCTION", "ProductionRecorded"),
            ["WaterProductionBatch.Approve"] = ("PRODUCTION", "BatchProductionPosted"),
            ["WaterDriverReturn.Approve"] = ("DELIVERY", "DriverReturnCompleted"),
            ["WaterDriverReturn.ApproveReconcile"] = ("DELIVERY", "DriverReturnCompleted"),
            ["WaterExpense.Create"] = ("EXPENSES", "ExpenseCreated"),
            ["WaterDailyClosing.Submit"] = ("CLOSING", "DailyClosingCompleted"),
            ["WaterPayroll.Approve"] = ("PAYROLL", "PayrollApproved"),
            ["WaterRawMaterialPurchase.Create"] = ("INVENTORY", "InventoryReceived"),
            ["WaterStock.AddTransaction"] = ("INVENTORY", "InventoryMovementRecorded"),
            ["WaterCompany.Setup"] = ("SETUP", "CompanySetupCompleted"),
            ["WaterCashReconciliation.Post"] = ("OPERATIONS", "CashReconciled"),

            // ---- Hotel ----
            ["HotelBooking.Create"] = ("SALES", "BookingCreated"),
            ["HotelFrontDesk.CheckIn"] = ("OPERATIONS", "CheckInCompleted"),
            ["HotelFrontDesk.CheckOut"] = ("OPERATIONS", "CheckOutCompleted"),
            ["HotelFinance.RecordPayment"] = ("PAYMENTS", "PaymentRecorded"),
            ["HotelFinance.CreateExpense"] = ("EXPENSES", "ExpenseCreated"),
            ["HotelCustomer.CreatePayment"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["HotelSupplier.CreatePayment"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["HotelBalances.RecordCustomer"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["HotelBalances.RecordSupplier"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["HotelOperations.CreateClosing"] = ("CLOSING", "DailyClosingCompleted"),
            ["HotelOperations.RunNightAudit"] = ("CLOSING", "NightAuditCompleted"),
            ["HotelPayroll.ApprovePayrollRun"] = ("PAYROLL", "PayrollApproved"),
            ["HotelSupplies.CreatePurchase"] = ("INVENTORY", "InventoryReceived"),
            ["HotelRestaurant.CreateOrder"] = ("SALES", "OrderCreated"),

            // ---- Restaurant ----
            ["RestaurantOrder.CreateOrder"] = ("SALES", "SaleRecorded"),
            ["RestaurantOrder.AddPayment"] = ("PAYMENTS", "PaymentRecorded"),
            ["RestaurantPublic.PlaceOrder"] = ("SALES", "OrderCreated"),
            ["RestaurantFinance.CloseDay"] = ("CLOSING", "DailyClosingCompleted"),
            ["RestaurantFinance.PostCount"] = ("OPERATIONS", "CashReconciled"),
            ["RestaurantExpense.Create"] = ("EXPENSES", "ExpenseCreated"),
            ["RestaurantCustomerBalances.Record"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["RestaurantBalances.Record"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["RestaurantPurchases.Create"] = ("INVENTORY", "InventoryReceived"),
            ["RestaurantPayroll.Approve"] = ("PAYROLL", "PayrollApproved"),
            ["RestaurantInventory.CompleteStockTake"] = ("INVENTORY", "StockTakeCompleted"),

            // ---- Generic (School, Gym, Agency, ... — template-agnostic) ----
            ["GenericSale.Create"] = ("SALES", "SaleCreated"),
            ["GenericExpenseRecord.Create"] = ("EXPENSES", "ExpenseCreated"),
            ["GenericCustomer.CreatePayment"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["GenericBalances.RecordPayment"] = ("PAYMENTS", "CustomerPaymentReceived"),
            ["GenericBalances.RecordSupplierPayment"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["GenericSupplier.CreatePayment"] = ("PAYMENTS", "SupplierPaymentRecorded"),
            ["GenericPayroll.Approve"] = ("PAYROLL", "PayrollApproved"),
            ["GenericStaffPayments.Record"] = ("PAYROLL", "StaffPaymentRecorded"),
            ["GenericSubscriptions.Create"] = ("SALES", "SubscriptionCreated"),
            ["GenericBillingRuns.Generate"] = ("SALES", "SubscriptionBillingGenerated"),
            ["GenericPurchase.Create"] = ("INVENTORY", "InventoryReceived"),
            ["GenericDailyClosing.Submit"] = ("CLOSING", "DailyClosingCompleted"),
            ["GenericCash.Reconcile"] = ("OPERATIONS", "CashReconciled"),
            ["GenericCompany.Setup"] = ("SETUP", "CompanySetupCompleted"),
        };

        // Tier 2: typed but NOT meaningful on their own.
        private static readonly Dictionary<string, (string Cat, string Type)> TypedNonMeaningful =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["PoultryStaff.Create"] = ("EMPLOYEES", "EmployeeCreated"),
            ["WaterStaff.Create"] = ("EMPLOYEES", "EmployeeCreated"),
            ["GenericStaff.Create"] = ("EMPLOYEES", "EmployeeCreated"),
            ["RestaurantStaff.Create"] = ("EMPLOYEES", "EmployeeCreated"),
            ["HotelOperations.CreateStaff"] = ("EMPLOYEES", "EmployeeCreated"),
            ["Customer.Create"] = ("CUSTOMERS", "CustomerCreated"),
            ["WaterCustomer.Create"] = ("CUSTOMERS", "CustomerCreated"),
            ["HotelGuest.Create"] = ("CUSTOMERS", "CustomerCreated"),
            ["GenericCustomer.Create"] = ("CUSTOMERS", "CustomerCreated"),
            ["RestaurantCRM.CreateCustomer"] = ("CUSTOMERS", "CustomerCreated"),
            ["WaterProductionLines.Create"] = ("SETUP", "ProductionLineConfigured"),
            ["HotelRoom.Create"] = ("SETUP", "RoomConfigured"),
            ["PlatformBilling.Checkout"] = ("BILLING", "CheckoutStarted"),
        };

        /// <summary>Module (vertical) for an audit-log resource name — used by the
        /// error-intelligence views (Prompt 7). Null for unrecognized surfaces.</summary>
        public static string? ModuleForResource(string? resource) =>
            string.IsNullOrWhiteSpace(resource) ? null : ResolveModule(resource);

        // Audit rows store GetResourceName()'s friendly aliases for a few controllers.
        private static readonly Dictionary<string, string> ResourceAliases = new(StringComparer.OrdinalIgnoreCase)
        { ["FlockBatch"] = "MainFlockBatch", ["CashAdjustment"] = "Cash" };

        /// <summary>True when failed requests against this audit resource represent a
        /// CRITICAL business operation (one whose success would be meaningful
        /// activity) — the Prompt 7 customer-impact attention signal. Harmless
        /// surfaces (reports, lookups, settings) never qualify.</summary>
        public static bool IsCriticalResource(string? resource)
        {
            if (string.IsNullOrWhiteSpace(resource)) return false;
            var controller = ResourceAliases.TryGetValue(resource, out var real) ? real : resource;
            return Meaningful.Keys.Any(k => k.StartsWith(controller + ".", StringComparison.OrdinalIgnoreCase));
        }

        public static ActivityClassification? Classify(string? controller, string? action, string httpMethod)
        {
            if (string.IsNullOrWhiteSpace(controller) || string.IsNullOrWhiteSpace(action))
                return null;
            if (httpMethod != "POST" && httpMethod != "PUT" && httpMethod != "DELETE")
                return null;
            if (Skip.Contains(controller))
                return null;

            var module = ResolveModule(controller);
            if (module is null)
                return null;

            var key = controller + "." + action;
            if (Meaningful.TryGetValue(key, out var m))
                return new ActivityClassification(m.Cat, m.Type, module, true);
            if (TypedNonMeaningful.TryGetValue(key, out var t))
                return new ActivityClassification(t.Cat, t.Type, module, false);

            // Tier 3: real usage, generic shape. Never meaningful.
            return new ActivityClassification(FallbackCategory(controller), controller + action, module, false);
        }

        private static string? ResolveModule(string c)
        {
            if (c.StartsWith("Water", StringComparison.OrdinalIgnoreCase)) return "Water";
            if (c.StartsWith("Hotel", StringComparison.OrdinalIgnoreCase)) return "Hotel";
            if (c.StartsWith("Restaurant", StringComparison.OrdinalIgnoreCase)) return "Restaurant";
            if (c.StartsWith("Generic", StringComparison.OrdinalIgnoreCase)) return "Generic";
            if (c.StartsWith("PlatformBilling", StringComparison.OrdinalIgnoreCase)) return "Billing";
            if (c.StartsWith("Poultry", StringComparison.OrdinalIgnoreCase) || PoultryLegacy.Contains(c)) return "Poultry";
            if (Shared.Contains(c)) return "Shared";
            return null; // unknown controller: not recorded (auditlogs still has it)
        }

        private static string FallbackCategory(string c)
        {
            bool Has(params string[] tokens) =>
                tokens.Any(t => c.Contains(t, StringComparison.OrdinalIgnoreCase));

            if (Has("DailyClosing")) return "CLOSING";
            if (Has("Payroll", "StaffPayment", "StaffAttendance", "EmployeeLoan")) return "PAYROLL";
            if (Has("Staff", "Employee")) return "EMPLOYEES";
            if (Has("Billing")) return "BILLING";
            if (Has("Report")) return "REPORTING";
            if (Has("Payment", "Balances", "Loan", "OwnerMoney", "OwnerEntries")) return "PAYMENTS";
            if (Has("Expense", "MoneyOut")) return "EXPENSES";
            if (Has("Inventory", "Stock", "RawMaterial", "Purchase", "Supplies", "Ingredient", "InternalUsage", "InternalUse")) return "INVENTORY";
            if (Has("Delivery", "Driver", "Vehicle", "Route", "Loading", "Distribution")) return "DELIVERY";
            if (Has("Customer", "Guest", "CRM", "Loyalty")) return "CUSTOMERS";
            if (Has("Sale", "Order", "GiftCard", "Subscription")) return "SALES";
            if (Has("Production", "Feed", "Flock", "Batch", "EggSorting", "Treatment", "Pumping", "QualityTest")) return "PRODUCTION";
            if (Has("Setup", "Company", "Settings", "Template", "Menu", "Floor", "Room", "Kds",
                    "CustomOption", "Time", "ServiceCatalog", "Borehole", "Machine", "Product", "House", "Amenit")) return "SETUP";
            return "OPERATIONS";
        }
    }
}
