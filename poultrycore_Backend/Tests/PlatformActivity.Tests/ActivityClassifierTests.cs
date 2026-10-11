using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformActivity.Tests
{
    public class ActivityClassifierTests
    {
        // ---- meaningful business milestones per vertical ----

        [Fact]
        public void PoultryProduction_IsMeaningful()
        {
            var c = ActivityClassifier.Classify("EggProduction", "Create", "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("PRODUCTION", c.Category);
            Assert.Equal("ProductionRecorded", c.ActivityType);
            Assert.Equal("Poultry", c.SourceModule);
        }

        [Fact]
        public void WaterProductionPost_IsMeaningful()
        {
            var c = ActivityClassifier.Classify("WaterDailyProduction", "Post", "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("PRODUCTION", c.Category);
            Assert.Equal("Water", c.SourceModule);
        }

        [Theory]
        [InlineData("Sale", "Create", "SALES", "SaleRecorded", "Poultry")]
        [InlineData("GenericSale", "Create", "SALES", "SaleCreated", "Generic")]
        [InlineData("RestaurantOrder", "CreateOrder", "SALES", "SaleRecorded", "Restaurant")]
        [InlineData("HotelBooking", "Create", "SALES", "BookingCreated", "Hotel")]
        public void Sales_AreMeaningful(string controller, string action, string cat, string type, string module)
        {
            var c = ActivityClassifier.Classify(controller, action, "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal(cat, c.Category);
            Assert.Equal(type, c.ActivityType);
            Assert.Equal(module, c.SourceModule);
        }

        [Theory]
        [InlineData("Expense", "Create")]
        [InlineData("WaterExpense", "Create")]
        [InlineData("GenericExpenseRecord", "Create")]
        public void Expenses_AreMeaningful(string controller, string action)
        {
            var c = ActivityClassifier.Classify(controller, action, "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("EXPENSES", c.Category);
            Assert.Equal("ExpenseCreated", c.ActivityType);
        }

        [Theory]
        [InlineData("PoultryDailyClosingControl", "Close")]
        [InlineData("WaterDailyClosing", "Submit")]
        [InlineData("RestaurantFinance", "CloseDay")]
        [InlineData("GenericDailyClosing", "Submit")]
        public void DailyClosings_AreMeaningful(string controller, string action)
        {
            var c = ActivityClassifier.Classify(controller, action, "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("CLOSING", c.Category);
            Assert.Equal("DailyClosingCompleted", c.ActivityType);
        }

        [Theory]
        [InlineData("PoultryPayroll", "Approve")]
        [InlineData("HotelPayroll", "ApprovePayrollRun")]
        public void PayrollApprovals_AreMeaningful(string controller, string action)
        {
            var c = ActivityClassifier.Classify(controller, action, "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("PAYROLL", c.Category);
            Assert.Equal("PayrollApproved", c.ActivityType);
        }

        [Fact]
        public void InventoryReceipt_IsMeaningful()
        {
            var c = ActivityClassifier.Classify("GenericPurchase", "Create", "POST");
            Assert.NotNull(c);
            Assert.True(c!.IsMeaningful);
            Assert.Equal("INVENTORY", c.Category);
            Assert.Equal("InventoryReceived", c.ActivityType);
        }

        // ---- things that must NOT count as meaningful ----

        [Fact]
        public void Reversal_FallsBackToNonMeaningful()
        {
            var c = ActivityClassifier.Classify("WaterDriverReturn", "Reverse", "POST");
            Assert.NotNull(c);
            Assert.False(c!.IsMeaningful);
        }

        [Fact]
        public void EmployeeCreated_IsTypedButNotMeaningful()
        {
            var c = ActivityClassifier.Classify("PoultryStaff", "Create", "POST");
            Assert.NotNull(c);
            Assert.False(c!.IsMeaningful);
            Assert.Equal("EmployeeCreated", c.ActivityType);
            Assert.Equal("EMPLOYEES", c.Category);
        }

        [Fact]
        public void Reads_AreNeverRecorded()
        {
            Assert.Null(ActivityClassifier.Classify("Sale", "GetAll", "GET"));
        }

        [Theory]
        [InlineData("AuditLogs")]
        [InlineData("PlatformActivity")]
        [InlineData("PlatformFarms")]
        [InlineData("PlatformBillingAdmin")]
        [InlineData("PlatformBillingWebhook")]
        public void PlatformPlumbing_IsSkipped(string controller)
        {
            Assert.Null(ActivityClassifier.Classify(controller, "Create", "POST"));
        }

        [Fact]
        public void UnknownController_IsSkipped()
        {
            Assert.Null(ActivityClassifier.Classify("SomethingUnrelated", "Create", "POST"));
        }

        // ---- extensibility: a future Generic template needs no core change ----

        [Fact]
        public void FutureGenericTemplateController_StillClassifies()
        {
            // e.g. a Pharmacy-specific controller added later under the Generic family
            var c = ActivityClassifier.Classify("GenericPharmacyDispense", "Create", "POST");
            Assert.NotNull(c);
            Assert.Equal("Generic", c!.SourceModule);
            Assert.False(c.IsMeaningful); // until explicitly promoted to the meaningful map
        }

        [Fact]
        public void FallbackCategory_IsDerivedFromControllerName()
        {
            var c = ActivityClassifier.Classify("WaterMaintenanceLog", "Create", "POST");
            Assert.NotNull(c);
            Assert.Equal("OPERATIONS", c!.Category);
            Assert.Equal("Water", c.SourceModule);
        }
    }
}
