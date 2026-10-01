// GENERATED from the web's <FormSection>/<FormField> markup.
// 63 pages, 221 sections, 656 fields — same section titles, colours, column
// counts, field labels, input kinds and required flags as the site.

import 'form_spec.dart';

const Map<String, FormDef> generatedForms = {
  "/generic-cash-transfers": FormDef(route: "/generic-cash-transfers", specKey: "generic-cash-transfers", sections: [
    FormSectionDef(title: "Accounts", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "From", kind: FormFieldKind.select, required: true, placeholder: "Source...", name: "fromGenericCashAccountId"),
      FormFieldDef(label: "To", kind: FormFieldKind.select, required: true, placeholder: "Destination...", name: "toGenericCashAccountId"),
    ]),
    FormSectionDef(title: "Transfer details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "transferDate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-customer-payments": FormDef(route: "/generic-customer-payments", specKey: "generic-customer-payments", sections: [
    FormSectionDef(title: "Payment details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "paymentDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (receives)", kind: FormFieldKind.select, name: "genericCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-customers": FormDef(route: "/generic-customers", specKey: "generic-customers", sections: [
    FormSectionDef(title: "Personal information", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "customerType"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
    ]),
    FormSectionDef(title: "Address", color: "green", columns: 2, fields: [
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, full: true, name: "address"),
    ]),
    FormSectionDef(title: "Credit & balance", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Credit limit", kind: FormFieldKind.money, name: "creditLimit"),
      FormFieldDef(label: "Payment terms (days)", kind: FormFieldKind.number, name: "paymentTermsDays"),
      FormFieldDef(label: "Opening balance owed", kind: FormFieldKind.money, full: true, name: "openingBalance"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-internal-use": FormDef(route: "/generic-internal-use", specKey: "generic-internal-usage", sections: [
    FormSectionDef(title: "What was used, and why", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Who received it", kind: FormFieldKind.text, placeholder: "e.g. Production team", hint: "Optional", name: "recipientName"),
      FormFieldDef(label: "Detail", kind: FormFieldKind.text, placeholder: "e.g. Friday staff allowance", hint: "Optional", name: "reason"),
    ]),
    FormSectionDef(title: "How much", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Product", kind: FormFieldKind.text, full: true),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, full: true, placeholder: "Pick a product", name: "genericProductId"),
      FormFieldDef(label: "How do you want to enter it?", kind: FormFieldKind.text, full: true, name: "useStaffHelper"),
      FormFieldDef(label: "Number of staff", kind: FormFieldKind.number, name: "staffCount"),
    ]),
    FormSectionDef(title: "Check before you save", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, hint: "Optional", name: "notes"),
    ]),
  ]),
  "/generic-owner-money": FormDef(route: "/generic-owner-money", specKey: "generic-owner-entries", sections: [
    FormSectionDef(title: "What happened", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, required: true, name: "entryType"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "entryDate"),
      FormFieldDef(label: "Owner", kind: FormFieldKind.text, name: "ownerName"),
    ]),
    FormSectionDef(title: "Which account", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, required: true, placeholder: "Pick one", name: "cashAccountId"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "reference"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-payroll": FormDef(route: "/generic-payroll", specKey: "generic-payroll-runs", sections: [
    FormSectionDef(title: "Period", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Period start", kind: FormFieldKind.date, required: true, name: "periodStart"),
      FormFieldDef(label: "Period end", kind: FormFieldKind.date, required: true, name: "periodEnd"),
    ]),
    FormSectionDef(title: "Pay-out", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Pay date (optional)", kind: FormFieldKind.date, name: "payDate"),
      FormFieldDef(label: "Pay from", kind: FormFieldKind.select, placeholder: "Select cash account", name: "genericCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-products": FormDef(route: "/generic-products", specKey: "generic-products", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Product name", kind: FormFieldKind.text, required: true, full: true, name: "productName"),
      FormFieldDef(label: "SKU (code)", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Barcode", kind: FormFieldKind.text, name: "barcode"),
      FormFieldDef(label: "Unit (e.g. piece, kg)", kind: FormFieldKind.text, full: true, name: "unitOfMeasure"),
    ]),
    FormSectionDef(title: "Pricing", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Cost price", kind: FormFieldKind.money, required: true, name: "costPrice"),
      FormFieldDef(label: "Selling price", kind: FormFieldKind.money, required: true, name: "sellingPrice"),
      FormFieldDef(label: "Wholesale price (optional)", kind: FormFieldKind.money, name: "wholesalePrice"),
      FormFieldDef(label: "Retail price (optional)", kind: FormFieldKind.money, name: "retailPrice"),
    ]),
    FormSectionDef(title: "Inventory", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Opening stock", kind: FormFieldKind.money, name: "openingStock"),
      FormFieldDef(label: "Low-stock alert at", kind: FormFieldKind.money, name: "minimumStockAlert"),
    ]),
    FormSectionDef(title: "Status & notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Track inventory", kind: FormFieldKind.bool, name: "trackInventory"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-recurring-expenses": FormDef(route: "/generic-recurring-expenses", specKey: "generic-recurring-expenses", sections: [
    FormSectionDef(title: "What repeats", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. Google Cloud hosting", name: "expenseName"),
      FormFieldDef(label: "Expense category", kind: FormFieldKind.select, required: true, placeholder: "Pick one", name: "genericExpenseCategoryId"),
      FormFieldDef(label: "Supplier (optional)", kind: FormFieldKind.select, placeholder: "Nobody in particular", name: "genericSupplierId"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
    ]),
    FormSectionDef(title: "How often", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Frequency", kind: FormFieldKind.select, name: "frequency"),
      FormFieldDef(label: "First due", kind: FormFieldKind.date, required: true, name: "startDate"),
      FormFieldDef(label: "Stops after (optional)", kind: FormFieldKind.date, name: "endDate"),
    ]),
    FormSectionDef(title: "How it is paid", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, placeholder: "Pick one", name: "defaultCashAccountId"),
      FormFieldDef(label: "Already paid when raised", kind: FormFieldKind.bool, full: true, name: "autoPayOnGenerate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-service-plans": FormDef(route: "/generic-service-plans", specKey: "generic-service-plans", sections: [
    FormSectionDef(title: "The plan", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Default price", kind: FormFieldKind.money, name: "defaultPrice"),
      FormFieldDef(label: "Income category", kind: FormFieldKind.select, placeholder: "Pick one", name: "genericServiceCategoryId"),
    ]),
    FormSectionDef(title: "How it bills", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Plan type", kind: FormFieldKind.select, name: "planType"),
      FormFieldDef(label: "Billing frequency", kind: FormFieldKind.select, name: "billingFrequency"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-staff": FormDef(route: "/generic-staff", specKey: "generic-staff", sections: [
    FormSectionDef(title: "Personal information", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
    ]),
    FormSectionDef(title: "Role & pay", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
      FormFieldDef(label: "Salary type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Base pay", kind: FormFieldKind.money, name: "basePay"),
      FormFieldDef(label: "Commission rate (optional)", kind: FormFieldKind.number, placeholder: "e.g. 0.05 for 5%", name: "commissionRate"),
    ]),
    FormSectionDef(title: "Status & notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-staff-payments": FormDef(route: "/generic-staff-payments", specKey: "generic-staff-payments", sections: [
    FormSectionDef(title: "Who and how much", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Person", kind: FormFieldKind.select, required: true, placeholder: "Pick someone", name: "genericStaffId"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Paid on", kind: FormFieldKind.date, name: "paymentDate"),
    ]),
    FormSectionDef(title: "Out of which account", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, placeholder: "Pick one", name: "cashAccountId"),
    ]),
    FormSectionDef(title: "What period it covers", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "From", kind: FormFieldKind.date, name: "periodStart"),
      FormFieldDef(label: "To", kind: FormFieldKind.date, name: "periodEnd"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "reference"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, placeholder: "Left empty, this describes itself from the name and period.", name: "description"),
    ]),
  ]),
  "/generic-stock-adjustments": FormDef(route: "/generic-stock-adjustments", specKey: "generic-inventory-adjustments", sections: [
    FormSectionDef(title: "Product", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Product", kind: FormFieldKind.select, required: true, placeholder: "Pick product...", name: "genericProductId"),
    ]),
    FormSectionDef(title: "Adjustment details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, required: true, name: "adjustmentType"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, required: true, name: "quantity"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, full: true, name: "adjustmentDate"),
    ]),
    FormSectionDef(title: "Reason & notes", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.text, required: true, placeholder: "e.g. damaged in storage, found extras, stocktake correction", name: "reason"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-subscriptions": FormDef(route: "/generic-subscriptions", specKey: "generic-subscriptions", sections: [
    FormSectionDef(title: "When and how often", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Starts", kind: FormFieldKind.date, required: true, name: "startDate"),
      FormFieldDef(label: "Ends (optional)", kind: FormFieldKind.date, name: "endDate"),
      FormFieldDef(label: "Billing frequency", kind: FormFieldKind.select, name: "billingFrequency"),
      FormFieldDef(label: "Payment terms (days)", kind: FormFieldKind.number, name: "paymentDueDays"),
    ]),
    FormSectionDef(title: "What it bills", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "billingAmount"),
      FormFieldDef(label: "Discount", kind: FormFieldKind.money, name: "discountAmount"),
      FormFieldDef(label: "Tax", kind: FormFieldKind.money, name: "taxAmount"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-supplier-payments": FormDef(route: "/generic-supplier-payments", specKey: "generic-supplier-payments", sections: [
    FormSectionDef(title: "Supplier", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Supplier", kind: FormFieldKind.select, required: true, placeholder: "Pick supplier...", name: "genericSupplierId"),
    ]),
    FormSectionDef(title: "Payment details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "paymentDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (paid from)", kind: FormFieldKind.select, name: "genericCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-suppliers": FormDef(route: "/generic-suppliers", specKey: "generic-suppliers", sections: [
    FormSectionDef(title: "Personal information", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Supplier name", kind: FormFieldKind.text, required: true, full: true, name: "supplierName"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "supplierType"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
    ]),
    FormSectionDef(title: "Address", color: "green", columns: 2, fields: [
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, full: true, name: "address"),
    ]),
    FormSectionDef(title: "Payment terms", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Payment terms (days)", kind: FormFieldKind.number, name: "paymentTermsDays"),
      FormFieldDef(label: "Opening balance (you owe)", kind: FormFieldKind.money, name: "openingBalance"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/hotel-expenses": FormDef(route: "/hotel-expenses", specKey: "hotel-finance-expenses", sections: [
    FormSectionDef(title: "Expense Details", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Expense date", kind: FormFieldKind.date, required: true, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, required: true, placeholder: "Pick category", name: "hotelExpenseCategoryId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, required: true, placeholder: "e.g. Laundry detergent", name: "description"),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (debit from)", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick account to debit", name: "hotelCashAccountId"),
    ]),
    FormSectionDef(title: "Details", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Paid to / Vendor", kind: FormFieldKind.text, placeholder: "Supplier name", name: "paidTo"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/hotel-payroll": FormDef(route: "/hotel-payroll", specKey: "hotel-payroll-diag", sections: [
    FormSectionDef(title: "Period", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Period Start", kind: FormFieldKind.date, required: true, name: "periodStart"),
      FormFieldDef(label: "Period End", kind: FormFieldKind.date, required: true, name: "periodEnd"),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Cash Account", kind: FormFieldKind.select, placeholder: "Select cash account", name: "hotelCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, placeholder: "Optional notes", name: "notes"),
    ]),
    FormSectionDef(title: "Add individual staff", color: "indigo", columns: 3, fields: [
      FormFieldDef(label: "Staff", kind: FormFieldKind.select, required: true, placeholder: "Select staff", name: "hotelStaffId"),
      FormFieldDef(label: "Basic Pay", kind: FormFieldKind.money, name: "basicPay"),
      FormFieldDef(label: "Daily Wage", kind: FormFieldKind.money, name: "dailyWage"),
      FormFieldDef(label: "Commission", kind: FormFieldKind.money, name: "commission"),
      FormFieldDef(label: "Bonus", kind: FormFieldKind.money, name: "bonus"),
      FormFieldDef(label: "Deductions", kind: FormFieldKind.money, name: "deductions"),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "", kind: FormFieldKind.text),
    ]),
  ]),
  "/hotel-shift-handover": FormDef(route: "/hotel-shift-handover", specKey: "hotel-shift-handovers", sections: [
    FormSectionDef(title: "Shift Info", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "shiftDate"),
      FormFieldDef(label: "Shift", kind: FormFieldKind.select, name: "shiftType"),
    ]),
    FormSectionDef(title: "Handover Details", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Handover By", kind: FormFieldKind.select, required: true, placeholder: "Select staff", name: "handoverBy"),
      FormFieldDef(label: "Handover To", kind: FormFieldKind.select, required: true, placeholder: "Select incoming staff", name: "handoverTo"),
      FormFieldDef(label: "Key Messages", kind: FormFieldKind.textarea, placeholder: "Important things the next shift needs to know", name: "keyMessages"),
      FormFieldDef(label: "Pending Items", kind: FormFieldKind.textarea, placeholder: "Tasks not completed that need follow-up", name: "pendingItems"),
      FormFieldDef(label: "VIP Guests", kind: FormFieldKind.textarea, placeholder: "VIP arrivals/departures, special treatment", name: "vipGuests"),
      FormFieldDef(label: "Incidents", kind: FormFieldKind.textarea, placeholder: "Any incidents or issues", name: "incidents"),
    ]),
    FormSectionDef(title: "Cash", color: "green", columns: 1, fields: [
      FormFieldDef(label: "Cash Balance", kind: FormFieldKind.money, placeholder: "Cash on hand at end of shift", name: "cashBalance"),
    ]),
  ]),
  "/hotel-staff": FormDef(route: "/hotel-staff", specKey: "hotel-staff", sections: [
    FormSectionDef(title: "Person", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, required: true, placeholder: "e.g. Ama", name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, required: true, placeholder: "e.g. Mensah", name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, placeholder: "0241234567", name: "phone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, placeholder: "ama@hotel.com", name: "email"),
    ]),
    FormSectionDef(title: "Role & Pay", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Department", kind: FormFieldKind.select, required: true, name: "department"),
      FormFieldDef(label: "Role", kind: FormFieldKind.select, required: true, name: "role"),
      FormFieldDef(label: "Monthly Salary", kind: FormFieldKind.number, name: "salaryAmount"),
      FormFieldDef(label: "Hire Date", kind: FormFieldKind.date, name: "hireDate"),
    ]),
    FormSectionDef(title: "Status", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
    ]),
  ]),
  "/poultry-assets": FormDef(route: "/poultry-assets", specKey: "poultry-assets", sections: [
    FormSectionDef(title: "What it is", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Investment name", kind: FormFieldKind.text, placeholder: "Poultry House 4", name: "assetName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, placeholder: "Choose a category", name: "assetCategoryId"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Serial number", kind: FormFieldKind.text, name: "serialNumber"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, full: true, name: "description"),
    ]),
    FormSectionDef(title: "What it cost", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Acquisition date", kind: FormFieldKind.date, name: "acquisitionDate"),
      FormFieldDef(label: "Cost", kind: FormFieldKind.number, hint: "Leave blank for an investment you will build up cost by cost.", name: "amount"),
      FormFieldDef(label: "Supplier / payee", kind: FormFieldKind.text, name: "supplier"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, full: true, hint: "Leave blank if paid in full.", name: "amountPaid"),
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Balance due date", kind: FormFieldKind.date, name: "dueDate"),
    ]),
    FormSectionDef(title: "How it depreciates", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "In-service date", kind: FormFieldKind.date, hint: "Depreciation starts in this month. Leave blank if it is not in use yet.", name: "inServiceDate"),
      FormFieldDef(label: "Useful life (months)", kind: FormFieldKind.number, name: "usefulLifeMonths"),
      FormFieldDef(label: "Residual value", kind: FormFieldKind.number, hint: "What you expect it to still be worth at the end. Book value never falls below it.", name: "residualValue"),
      FormFieldDef(label: "Method", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Investment name", kind: FormFieldKind.text, name: "assetName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, placeholder: "Choose a category", name: "assetCategoryId"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Serial number", kind: FormFieldKind.text, name: "serialNumber"),
      FormFieldDef(label: "Acquired", kind: FormFieldKind.text, hint: "Set when the investment was recorded and not editable here."),
      FormFieldDef(label: "Investment number", kind: FormFieldKind.text),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, full: true, name: "description"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Depreciation", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "In-service date", kind: FormFieldKind.date, name: "inServiceDate"),
      FormFieldDef(label: "Useful life (months)", kind: FormFieldKind.number, name: "usefulLifeMonths"),
      FormFieldDef(label: "Residual value", kind: FormFieldKind.number, name: "residualValue"),
      FormFieldDef(label: "Method", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "How to treat it", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Cost treatment", kind: FormFieldKind.select, full: true, name: "treatment"),
    ]),
    FormSectionDef(title: "Cost", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "costDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "What it was for", kind: FormFieldKind.text, placeholder: "Roofing sheets", name: "description"),
      FormFieldDef(label: "Cost type", kind: FormFieldKind.text, placeholder: "Materials / Labour", name: "costCategory"),
      FormFieldDef(label: "Supplier / payee", kind: FormFieldKind.text, name: "supplier"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, full: true, hint: "Leave blank if paid in full.", name: "amountPaid"),
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Balance due date", kind: FormFieldKind.date, hint: "When the unpaid part falls due.", name: "dueDate"),
    ]),
    FormSectionDef(title: "Disposal", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "disposalDate"),
      FormFieldDef(label: "Proceeds", kind: FormFieldKind.number, hint: "Leave blank if nothing was received.", name: "proceeds"),
      FormFieldDef(label: "Received into", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
  ]),
  "/poultry-cash-accounts/[id]": FormDef(route: "/poultry-cash-accounts/[id]", specKey: "poultry-cash-accounts", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Direction", kind: FormFieldKind.select, name: "direction"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, required: true, placeholder: "Why is the balance changing?", name: "reason"),
    ]),
  ]),
  "/poultry-cash-transfers": FormDef(route: "/poultry-cash-transfers", specKey: "poultry-cash-transfers", sections: [
    FormSectionDef(title: "Movement", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Transfer date", kind: FormFieldKind.date, required: true, name: "transferDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true, name: "amount"),
      FormFieldDef(label: "From account", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick the account the money leaves", name: "fromPoultryCashAccountId"),
      FormFieldDef(label: "To account", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick the account the money arrives in", name: "toPoultryCashAccountId"),
    ]),
    FormSectionDef(title: "Reference", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, placeholder: "Bank or MoMo reference", name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Why", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.textarea, required: true, placeholder: "Why is this being reversed?", hint: "Written to the audit trail."),
    ]),
  ]),
  "/poultry-deliveries": FormDef(route: "/poultry-deliveries", specKey: "poultry-deliveries", sections: [
    FormSectionDef(title: "Load details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Product", kind: FormFieldKind.select, required: true, placeholder: "Pick product", name: "poultryProductId"),
      FormFieldDef(label: "Quantity loaded", kind: FormFieldKind.number, required: true, name: "quantityLoaded"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.select, name: "unit"),
      FormFieldDef(label: "Unit price", kind: FormFieldKind.money, name: "unitPrice"),
      FormFieldDef(label: "Driver", kind: FormFieldKind.text, name: "driverName"),
      FormFieldDef(label: "Vehicle", kind: FormFieldKind.text, name: "vehicleName"),
      FormFieldDef(label: "Route", kind: FormFieldKind.text, name: "route"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "deliveryDate"),
    ]),
    FormSectionDef(title: "Egg accounting", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Sold", kind: FormFieldKind.number, name: "quantitySold"),
      FormFieldDef(label: "Returned", kind: FormFieldKind.number, name: "quantityReturned"),
      FormFieldDef(label: "Broken", kind: FormFieldKind.number, name: "quantityBroken"),
      FormFieldDef(label: "Short / missing", kind: FormFieldKind.number, name: "quantityShort"),
      FormFieldDef(label: "", kind: FormFieldKind.text, full: true),
    ]),
    FormSectionDef(title: "Money", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Cash collected", kind: FormFieldKind.money, name: "cashCollected"),
      FormFieldDef(label: "Credit sales", kind: FormFieldKind.money, name: "creditSales"),
      FormFieldDef(label: "Delivery expenses", kind: FormFieldKind.money, name: "deliveryExpenses"),
      FormFieldDef(label: "Expected sales (auto)", kind: FormFieldKind.text),
    ]),
  ]),
  "/poultry-driver-returns": FormDef(route: "/poultry-driver-returns", specKey: "poultry-driver-returns", sections: [
    FormSectionDef(title: "Driver & route", color: "indigo", columns: 3, fields: [
      FormFieldDef(label: "Driver", kind: FormFieldKind.select, required: true, placeholder: "Pick driver", name: "poultryDriverId"),
      FormFieldDef(label: "Vehicle", kind: FormFieldKind.select, required: true, placeholder: "Pick vehicle", name: "poultryVehicleId"),
      FormFieldDef(label: "Route", kind: FormFieldKind.select, placeholder: "Pick route", name: "poultryRouteId"),
      FormFieldDef(label: "Load date", kind: FormFieldKind.date, name: "loadDate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea),
    ]),
  ]),
  "/poultry-drivers": FormDef(route: "/poultry-drivers", specKey: "poultry-drivers", sections: [
    FormSectionDef(title: "Driver details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Driver name", kind: FormFieldKind.text, required: true, full: true, name: "driverName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "License number", kind: FormFieldKind.text, name: "licenseNumber"),
      FormFieldDef(label: "Default vehicle", kind: FormFieldKind.select, placeholder: "(none)", name: "defaultVehicleId"),
      FormFieldDef(label: "Default route", kind: FormFieldKind.select, placeholder: "(none)", name: "defaultRouteId"),
      FormFieldDef(label: "Base pay", kind: FormFieldKind.number, name: "basePay"),
      FormFieldDef(label: "Commission per crate", kind: FormFieldKind.money, name: "commissionPerCrate"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, full: true, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "New employee details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, placeholder: "optional", name: "email"),
      FormFieldDef(label: "Username", kind: FormFieldKind.text, required: true, name: "userName"),
      FormFieldDef(label: "Password", kind: FormFieldKind.text, required: true, name: "password"),
    ]),
    FormSectionDef(title: "", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Employee", kind: FormFieldKind.select, required: true, full: true, placeholder: "Select an employee", name: "employeeUserId"),
      FormFieldDef(label: "License number", kind: FormFieldKind.text, name: "licenseNumber"),
    ]),
    FormSectionDef(title: "Pay", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Base pay", kind: FormFieldKind.number, name: "basePay"),
      FormFieldDef(label: "Commission per crate", kind: FormFieldKind.money, name: "commissionPerCrate"),
    ]),
  ]),
  "/poultry-feed-formulas": FormDef(route: "/poultry-feed-formulas", specKey: "poultry-feed-formulas", sections: [
    FormSectionDef(title: "Formula details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Formula name", kind: FormFieldKind.text, required: true, placeholder: "e.g. Layer Mash Formula", name: "formulaName"),
      FormFieldDef(label: "Finished feed (optional)", kind: FormFieldKind.select, placeholder: "Any finished feed", hint: "Formulas are reusable \u2014 leave blank to use with any finished feed", name: "finishedFeedItemId"),
      FormFieldDef(label: "Default output unit", kind: FormFieldKind.select, placeholder: "Pick a unit", hint: "Used as the batch's output unit when this formula is applied", name: "defaultOutputUnit"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
  ]),
  "/poultry-internal-use": FormDef(route: "/poultry-internal-use", specKey: "poultry-internal-usage", sections: [
    FormSectionDef(title: "What was used, and why", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Who received it", kind: FormFieldKind.text, placeholder: "e.g. Production team", hint: "Optional", name: "recipientName"),
      FormFieldDef(label: "Detail", kind: FormFieldKind.text, placeholder: "e.g. Friday staff allowance", hint: "Optional", name: "reason"),
    ]),
    FormSectionDef(title: "How much", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Product", kind: FormFieldKind.text, full: true),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, full: true, placeholder: "Pick a product", name: "poultryProductId"),
      FormFieldDef(label: "Given out as", kind: FormFieldKind.text, full: true, name: "entryUnit"),
      FormFieldDef(label: "How do you want to enter it?", kind: FormFieldKind.text, full: true, name: "useStaffHelper"),
      FormFieldDef(label: "Number of staff", kind: FormFieldKind.number, name: "staffCount"),
    ]),
    FormSectionDef(title: "Check before you save", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, hint: "Optional", name: "notes"),
    ]),
  ]),
  "/poultry-loss-records": FormDef(route: "/poultry-loss-records", specKey: "poultry-loss-records", sections: [
    FormSectionDef(title: "Loss details", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "lossDate"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "lossType"),
      FormFieldDef(label: "Product (optional)", kind: FormFieldKind.select, placeholder: "\u2014", name: "poultryProductId"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Estimated value", kind: FormFieldKind.money, name: "estimatedValue"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.text, full: true, name: "reason"),
    ]),
  ]),
  "/poultry-owner-money": FormDef(route: "/poultry-owner-money", specKey: "poultry-owner-money", sections: [
    FormSectionDef(title: "", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "transactionDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true, name: "amount"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, required: true, full: true, name: "poultryCashAccountId"),
    ]),
    FormSectionDef(title: "Details", color: "slate", columns: 2, fields: [
      FormFieldDef(label: "Owner", kind: FormFieldKind.text, placeholder: "Whose money is this?", name: "ownerName"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, placeholder: "Bank or MoMo reference", name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Why", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.textarea, required: true, placeholder: "Why is this being reversed?", hint: "Written to the audit trail."),
    ]),
  ]),
  "/poultry-payroll": FormDef(route: "/poultry-payroll", specKey: "poultry-payroll-deductions", sections: [
    FormSectionDef(title: "Period", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Period start", kind: FormFieldKind.date, required: true, name: "periodStart"),
      FormFieldDef(label: "Period end", kind: FormFieldKind.date, required: true, name: "periodEnd"),
      FormFieldDef(label: "Pay date", kind: FormFieldKind.date, name: "payDate"),
      FormFieldDef(label: "Cash account (paid from)", kind: FormFieldKind.select, placeholder: "Select account", name: "poultryCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "Add / update a line", color: "amber", columns: 4, fields: [
      FormFieldDef(label: "Staff", kind: FormFieldKind.select, placeholder: "Pick staff", name: "poultryStaffId"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Basic pay", kind: FormFieldKind.money, name: "basicPay"),
      FormFieldDef(label: "Daily wage", kind: FormFieldKind.money, name: "dailyWage"),
      FormFieldDef(label: "Commission", kind: FormFieldKind.money, name: "commission"),
      FormFieldDef(label: "Bonus", kind: FormFieldKind.money, name: "bonus"),
      FormFieldDef(label: "Deductions", kind: FormFieldKind.money, name: "deductions"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
      FormFieldDef(label: "&nbsp;", kind: FormFieldKind.text, full: true),
      FormFieldDef(label: "&nbsp;", kind: FormFieldKind.text, full: true),
    ]),
  ]),
  "/poultry-products": FormDef(route: "/poultry-products", specKey: "poultry-products", sections: [
    FormSectionDef(title: "Product details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "name"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "productType"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.select, placeholder: "Pick unit", name: "unit"),
      FormFieldDef(label: "Selling price", kind: FormFieldKind.money, name: "unitPrice"),
      FormFieldDef(label: "Size", kind: FormFieldKind.text, hint: "e.g. Small / Medium / Large / Crate", name: "size"),
      FormFieldDef(label: "SKU", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Is this a raw egg product?", kind: FormFieldKind.select, name: "isRawEggProduct"),
      FormFieldDef(label: "Requires recipe setup?", kind: FormFieldKind.select, name: "requiresRecipeSetup"),
    ]),
    FormSectionDef(title: "Bill of materials (per output unit)", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Recipe name", kind: FormFieldKind.text, placeholder: "Optional"),
    ]),
    FormSectionDef(title: "Stock addition", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, required: true, name: "quantity"),
      FormFieldDef(label: "Unit cost / value", kind: FormFieldKind.money, name: "unitCost"),
      FormFieldDef(label: "Note", kind: FormFieldKind.text, full: true, name: "note"),
    ]),
  ]),
  "/poultry-routes": FormDef(route: "/poultry-routes", specKey: "poultry-routes", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Route name", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. Kumasi East", name: "routeName"),
      FormFieldDef(label: "Area covered", kind: FormFieldKind.text, full: true, name: "areaCovered"),
    ]),
    FormSectionDef(title: "Assignment", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Default vehicle", kind: FormFieldKind.select, full: true, placeholder: "(none)", name: "defaultVehicleId"),
      FormFieldDef(label: "Expected customers", kind: FormFieldKind.number, name: "expectedCustomers"),
      FormFieldDef(label: "Expected crates/day", kind: FormFieldKind.number, name: "expectedCratesSold"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/poultry-staff": FormDef(route: "/poultry-staff", specKey: "poultry-staff", sections: [
    FormSectionDef(title: "Person", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
    ]),
    FormSectionDef(title: "Pay", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
      FormFieldDef(label: "Salary type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Base pay", kind: FormFieldKind.money, name: "basePay"),
      FormFieldDef(label: "Commission rate", kind: FormFieldKind.number, name: "commissionRate"),
    ]),
    FormSectionDef(title: "Other", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "Day", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "attendanceDate"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, name: "status"),
      FormFieldDef(label: "Shift", kind: FormFieldKind.text, placeholder: "e.g. Morning", name: "shift"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/poultry-stock": FormDef(route: "/poultry-stock", specKey: "poultry-stock-transactions", sections: [
    FormSectionDef(title: "Movement", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Item", kind: FormFieldKind.select, required: true, placeholder: "Pick a finished product, raw material or supply", name: "target"),
      FormFieldDef(label: "Movement type", kind: FormFieldKind.select, name: "movementType"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, hint: "Always enter a positive number; the movement type sets the direction.", name: "quantity"),
      FormFieldDef(label: "Unit cost / value", kind: FormFieldKind.money, name: "unitCost"),
      FormFieldDef(label: "Note", kind: FormFieldKind.text, full: true, name: "note"),
    ]),
  ]),
  "/poultry-vehicles": FormDef(route: "/poultry-vehicles", specKey: "poultry-vehicles", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Vehicle name", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. Truck 1", name: "vehicleName"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "vehicleType"),
      FormFieldDef(label: "Registration #", kind: FormFieldKind.text, name: "registrationNumber"),
    ]),
    FormSectionDef(title: "Details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Capacity (crates)", kind: FormFieldKind.number, name: "capacityCrates"),
      FormFieldDef(label: "Fuel type", kind: FormFieldKind.text, placeholder: "Petrol / Diesel", name: "fuelType"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, full: true, name: "status"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-assets": FormDef(route: "/water-assets", specKey: "water-assets", sections: [
    FormSectionDef(title: "What it is", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Asset name", kind: FormFieldKind.text, placeholder: "Borehole 2", name: "assetName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, placeholder: "Choose a category", name: "assetCategoryId"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Serial number", kind: FormFieldKind.text, name: "serialNumber"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, full: true, name: "description"),
    ]),
    FormSectionDef(title: "What it cost", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Acquisition date", kind: FormFieldKind.date, name: "acquisitionDate"),
      FormFieldDef(label: "Cost", kind: FormFieldKind.number, hint: "Leave blank for an asset you will build up cost by cost.", name: "amount"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, full: true, name: "amountPaid"),
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Balance due date", kind: FormFieldKind.date, name: "dueDate"),
    ]),
    FormSectionDef(title: "How it depreciates", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "In-service date", kind: FormFieldKind.date, hint: "Depreciation starts in this month. Leave blank if it is not in use yet.", name: "inServiceDate"),
      FormFieldDef(label: "Useful life (months)", kind: FormFieldKind.number, name: "usefulLifeMonths"),
      FormFieldDef(label: "Residual value", kind: FormFieldKind.number, hint: "What you expect it to still be worth at the end. Book value never falls below it.", name: "residualValue"),
      FormFieldDef(label: "Method", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Asset name", kind: FormFieldKind.text, name: "assetName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, placeholder: "Choose a category", name: "assetCategoryId"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Serial number", kind: FormFieldKind.text, name: "serialNumber"),
      FormFieldDef(label: "Acquired", kind: FormFieldKind.text, hint: "Set when the asset was recorded and not editable here."),
      FormFieldDef(label: "Asset number", kind: FormFieldKind.text),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, full: true, name: "description"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Depreciation", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "In-service date", kind: FormFieldKind.date, name: "inServiceDate"),
      FormFieldDef(label: "Useful life (months)", kind: FormFieldKind.number, name: "usefulLifeMonths"),
      FormFieldDef(label: "Residual value", kind: FormFieldKind.number, name: "residualValue"),
      FormFieldDef(label: "Method", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "How to treat it", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Cost treatment", kind: FormFieldKind.select, full: true, name: "treatment"),
    ]),
    FormSectionDef(title: "Cost", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "costDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "What it was for", kind: FormFieldKind.text, placeholder: "Submersible pump", name: "description"),
      FormFieldDef(label: "Cost type", kind: FormFieldKind.text, placeholder: "Materials / Labour", name: "costCategory"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, full: true, hint: "Leave blank if paid in full.", name: "amountPaid"),
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Balance due date", kind: FormFieldKind.date, hint: "When the unpaid part falls due.", name: "dueDate"),
    ]),
    FormSectionDef(title: "Disposal", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "disposalDate"),
      FormFieldDef(label: "Proceeds", kind: FormFieldKind.number, hint: "Leave blank if nothing was received.", name: "proceeds"),
      FormFieldDef(label: "Received into", kind: FormFieldKind.select, placeholder: "Cash account", name: "cashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
  ]),
  "/water-boreholes": FormDef(route: "/water-boreholes", specKey: "water-boreholes", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Borehole name", kind: FormFieldKind.text, required: true, full: true, name: "boreholeName"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, full: true, name: "location"),
    ]),
    FormSectionDef(title: "Pump & Tank", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Pump type", kind: FormFieldKind.text, name: "pumpType"),
      FormFieldDef(label: "Pump capacity", kind: FormFieldKind.text, placeholder: "e.g. 5000 L/hr", name: "pumpCapacity"),
      FormFieldDef(label: "Tank capacity", kind: FormFieldKind.text, full: true, placeholder: "e.g. 10000 L", name: "tankCapacity"),
    ]),
    FormSectionDef(title: "Treatment", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Treatment method", kind: FormFieldKind.text, name: "waterTreatmentMethod"),
      FormFieldDef(label: "Filtration", kind: FormFieldKind.text, name: "filtrationSystem"),
      FormFieldDef(label: "UV sterilization", kind: FormFieldKind.bool, full: true, name: "uvSterilizationAvailable"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, full: true, name: "status"),
    ]),
    FormSectionDef(title: "Maintenance", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Maint. frequency (days)", kind: FormFieldKind.number, full: true, name: "maintenanceFrequencyDays"),
      FormFieldDef(label: "Last maintenance", kind: FormFieldKind.date, name: "lastMaintenanceDate"),
      FormFieldDef(label: "Next maintenance", kind: FormFieldKind.date, name: "nextMaintenanceDate"),
      FormFieldDef(label: "Water quality test due date", kind: FormFieldKind.date, full: true, name: "waterQualityTestDueDate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-cash-accounts/[id]": FormDef(route: "/water-cash-accounts/[id]", specKey: "water-cash-accounts", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Direction", kind: FormFieldKind.select, name: "direction"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, required: true, placeholder: "Why is the balance changing?", name: "reason"),
      FormFieldDef(label: "Say what happened", kind: FormFieldKind.text, required: true, placeholder: "e.g. Till float returned from the depot", name: "reasonNote"),
    ]),
  ]),
  "/water-cash-transfers": FormDef(route: "/water-cash-transfers", specKey: "water-cash-transfers", sections: [
    FormSectionDef(title: "Movement", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Transfer date", kind: FormFieldKind.date, required: true, name: "transferDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true, name: "amount"),
      FormFieldDef(label: "From account", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick the account the money leaves", name: "fromWaterCashAccountId"),
      FormFieldDef(label: "To account", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick the account the money arrives in", name: "toWaterCashAccountId"),
    ]),
    FormSectionDef(title: "Reference", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, placeholder: "Bank or MoMo reference", name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Why", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.textarea, required: true, placeholder: "Why is this being reversed?", hint: "Written to the audit trail."),
    ]),
  ]),
  "/water-customers": FormDef(route: "/water-customers", specKey: "water-customers", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, full: true, name: "name"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "contactEmail"),
    ]),
    FormSectionDef(title: "Address", color: "green", columns: 2, fields: [
      FormFieldDef(label: "Address", kind: FormFieldKind.text, full: true, name: "address"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-driver-returns": FormDef(route: "/water-driver-returns", specKey: "water-driver-returns", sections: [
    FormSectionDef(title: "Driver & route", color: "indigo", columns: 3, fields: [
      FormFieldDef(label: "Driver", kind: FormFieldKind.select, required: true, placeholder: "Pick driver", name: "waterDriverId"),
      FormFieldDef(label: "Vehicle", kind: FormFieldKind.select, required: true, placeholder: "Pick vehicle", name: "waterVehicleId"),
      FormFieldDef(label: "Route", kind: FormFieldKind.select, placeholder: "Pick route", name: "waterRouteId"),
      FormFieldDef(label: "Assistant (optional)", kind: FormFieldKind.select, placeholder: "Pick assistant", name: "assistantStaffId"),
      FormFieldDef(label: "Load date", kind: FormFieldKind.date, name: "loadDate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Delivery", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Driver", kind: FormFieldKind.select, placeholder: "Pick driver", name: "waterDriverId"),
      FormFieldDef(label: "Vehicle", kind: FormFieldKind.select, placeholder: "Pick vehicle", name: "waterVehicleId"),
      FormFieldDef(label: "Route", kind: FormFieldKind.select, placeholder: "Pick route", name: "waterRouteId"),
      FormFieldDef(label: "Opening cash with driver", kind: FormFieldKind.money, name: "openingCashWithDriver"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text),
    ]),
  ]),
  "/water-drivers": FormDef(route: "/water-drivers", specKey: "water-drivers", sections: [
    FormSectionDef(title: "Driver details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Driver name", kind: FormFieldKind.text, required: true, full: true, name: "driverName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "License number", kind: FormFieldKind.text, name: "licenseNumber"),
      FormFieldDef(label: "Assigned vehicle", kind: FormFieldKind.select, full: true, placeholder: "(none)", name: "assignedWaterVehicleId"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, full: true, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "New employee details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, placeholder: "optional", name: "email"),
      FormFieldDef(label: "Username", kind: FormFieldKind.text, required: true, name: "userName"),
      FormFieldDef(label: "Password", kind: FormFieldKind.text, required: true, name: "password"),
    ]),
    FormSectionDef(title: "", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Employee", kind: FormFieldKind.select, required: true, full: true, placeholder: "Select an employee", name: "employeeUserId"),
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
      FormFieldDef(label: "License number", kind: FormFieldKind.text, name: "licenseNumber"),
    ]),
    FormSectionDef(title: "Assignment & pay", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Default vehicle", kind: FormFieldKind.select, placeholder: "(none)", name: "defaultVehicleId"),
      FormFieldDef(label: "Default route", kind: FormFieldKind.select, placeholder: "(none)", name: "defaultRouteId"),
    ]),
  ]),
  "/water-expenses": FormDef(route: "/water-expenses", specKey: "water-expenses", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Expense date", kind: FormFieldKind.date, required: true, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, required: true, placeholder: "Pick category", name: "waterExpenseCategoryId"),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Amount", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Payment status", kind: FormFieldKind.select, required: true, name: "paymentMethod"),
      FormFieldDef(label: "Due date", kind: FormFieldKind.date),
    ]),
    FormSectionDef(title: "Details", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Description", kind: FormFieldKind.text, placeholder: "e.g. Fuel for Truck 1", name: "description"),
      FormFieldDef(label: "Paid to (Supplier)", kind: FormFieldKind.text, name: "supplierId"),
      FormFieldDef(label: "Paid to (freetext, optional)", kind: FormFieldKind.text, placeholder: "Used only if no supplier picked above", name: "paidTo"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-internal-use": FormDef(route: "/water-internal-use", specKey: "water-internal-usage", sections: [
    FormSectionDef(title: "What was used, and why", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Who received it", kind: FormFieldKind.text, placeholder: "e.g. Production team", hint: "Optional", name: "recipientName"),
      FormFieldDef(label: "Detail", kind: FormFieldKind.text, placeholder: "e.g. Friday staff allowance", hint: "Optional", name: "reason"),
    ]),
    FormSectionDef(title: "How much water", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Product", kind: FormFieldKind.text, full: true),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, full: true, placeholder: "Pick a water product", name: "waterProductId"),
      FormFieldDef(label: "Given out as", kind: FormFieldKind.text, full: true, name: "entryUnit"),
      FormFieldDef(label: "How do you want to enter it?", kind: FormFieldKind.text, full: true, name: "useStaffHelper"),
      FormFieldDef(label: "Number of staff", kind: FormFieldKind.number, name: "staffCount"),
    ]),
    FormSectionDef(title: "Check before you save", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, hint: "Optional", name: "notes"),
    ]),
  ]),
  "/water-loss-records": FormDef(route: "/water-loss-records", specKey: "water-loss-records", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "lossDate"),
      FormFieldDef(label: "Loss type", kind: FormFieldKind.select, name: "lossType"),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, full: true, placeholder: "(optional)", name: "waterProductId"),
    ]),
    FormSectionDef(title: "Quantity & Value", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Bags", kind: FormFieldKind.number, name: "quantityBags"),
      FormFieldDef(label: "Sachets", kind: FormFieldKind.number, name: "quantitySachets"),
    ]),
    FormSectionDef(title: "Details", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.textarea, required: true, name: "reason"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-machines": FormDef(route: "/water-machines", specKey: "water-machines", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Machine name", kind: FormFieldKind.text, required: true, full: true, name: "machineName"),
      FormFieldDef(label: "Machine number", kind: FormFieldKind.text, name: "machineNumber"),
      FormFieldDef(label: "Type", kind: FormFieldKind.text, placeholder: "e.g. Sachet filling, Bottling", name: "machineType"),
      FormFieldDef(label: "Manufacturer", kind: FormFieldKind.text, name: "manufacturer"),
    ]),
    FormSectionDef(title: "Details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Capacity / hour (bags)", kind: FormFieldKind.number, name: "capacityPerHour"),
      FormFieldDef(label: "Purchase date", kind: FormFieldKind.date, name: "purchaseDate"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, full: true, name: "status"),
    ]),
    FormSectionDef(title: "Maintenance", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Maintenance frequency (days)", kind: FormFieldKind.number, full: true, name: "maintenanceFrequencyDays"),
      FormFieldDef(label: "Last maintenance", kind: FormFieldKind.date, name: "lastMaintenanceDate"),
      FormFieldDef(label: "Next maintenance", kind: FormFieldKind.date, name: "nextMaintenanceDate"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-maintenance": FormDef(route: "/water-maintenance", specKey: "water-maintenance", sections: [
    FormSectionDef(title: "Asset", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Asset type", kind: FormFieldKind.select, name: "assetType"),
      FormFieldDef(label: "Asset label / name", kind: FormFieldKind.text, placeholder: "e.g. Truck 1, Genset", name: "assetLabel"),
      FormFieldDef(label: "Issue description", kind: FormFieldKind.textarea, required: true, full: true, name: "issueDescription"),
    ]),
    FormSectionDef(title: "Repair details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Technician", kind: FormFieldKind.text, name: "technicianName"),
      FormFieldDef(label: "Downtime hours", kind: FormFieldKind.number, name: "downtimeHours"),
      FormFieldDef(label: "Parts replaced", kind: FormFieldKind.text, name: "partsReplaced"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Cash impact", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Cash account (optional)", kind: FormFieldKind.select, placeholder: "None (no cash impact)"),
    ]),
  ]),
  "/water-owner-money": FormDef(route: "/water-owner-money", specKey: "water-owner-money", sections: [
    FormSectionDef(title: "", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "transactionDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true, name: "amount"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, required: true, full: true, name: "waterCashAccountId"),
    ]),
    FormSectionDef(title: "Details", color: "slate", columns: 2, fields: [
      FormFieldDef(label: "Owner", kind: FormFieldKind.text, placeholder: "Whose money is this?", name: "ownerName"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, placeholder: "Bank or MoMo reference", name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, full: true, name: "notes"),
    ]),
    FormSectionDef(title: "Why", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Reason", kind: FormFieldKind.textarea, required: true, placeholder: "Why is this being reversed?", hint: "Written to the audit trail."),
    ]),
  ]),
  "/water-payroll": FormDef(route: "/water-payroll", specKey: "water-payroll-runs", sections: [
    FormSectionDef(title: "Period", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Period start", kind: FormFieldKind.date, required: true, name: "periodStart"),
      FormFieldDef(label: "Period end", kind: FormFieldKind.date, required: true, name: "periodEnd"),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 1, fields: [
      FormFieldDef(label: "Cash account (used at Mark-Paid)", kind: FormFieldKind.select, placeholder: "Pick account", name: "waterCashAccountId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-production-batches": FormDef(route: "/water-production-batches", specKey: "water-production-batches", sections: [
    FormSectionDef(title: "Batch information", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch number", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. B-20260524-093015", name: "batchNumber"),
      FormFieldDef(label: "Production date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Shift", kind: FormFieldKind.select, name: "shift"),
      FormFieldDef(label: "Machine", kind: FormFieldKind.select, placeholder: "Pick machine", name: "machineScope"),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, placeholder: "Pick product", name: "waterProductId"),
    ]),
    FormSectionDef(title: "Production output", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Produced bags", kind: FormFieldKind.number, required: true, hint: "Total bags before subtracting damaged", name: "bagsProduced"),
      FormFieldDef(label: "Sachets per bag", kind: FormFieldKind.number, name: "sachetsPerBag"),
      FormFieldDef(label: "Damaged bags", kind: FormFieldKind.number, hint: "Counted as loss \u2014 not added to stock", name: "damagedBags"),
      FormFieldDef(label: "Rejected sachets", kind: FormFieldKind.number, hint: "Counted as loss", name: "rejectedSachets"),
    ]),
    FormSectionDef(title: "Production costs", color: "green", columns: 2, fields: [
      FormFieldDef(label: "Electricity", kind: FormFieldKind.money, name: "electricityCost"),
      FormFieldDef(label: "Fuel", kind: FormFieldKind.money, name: "fuelCost"),
      FormFieldDef(label: "Labor", kind: FormFieldKind.money, name: "laborCost"),
      FormFieldDef(label: "Other", kind: FormFieldKind.money, name: "otherProductionCost"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-products": FormDef(route: "/water-products", specKey: "water-products", sections: [
    FormSectionDef(title: "Restock", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number),
      FormFieldDef(label: "Unit cost (optional)", kind: FormFieldKind.money),
    ]),
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, full: true, name: "name"),
      FormFieldDef(label: "Product type", kind: FormFieldKind.select, full: true, name: "productType"),
      FormFieldDef(label: "SKU", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Product category", kind: FormFieldKind.select, placeholder: "Select\u2026", name: "productCategory"),
    ]),
    FormSectionDef(title: "Packaging & Pricing", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Size per unit", kind: FormFieldKind.select, name: "sizeMl"),
      FormFieldDef(label: "Inventory unit", kind: FormFieldKind.select, required: true, placeholder: "Select\u2026", name: "unit"),
      FormFieldDef(label: "Packaging unit", kind: FormFieldKind.select, required: true, placeholder: "Select\u2026", name: "packagingUnit"),
      FormFieldDef(label: "Default sales unit", kind: FormFieldKind.select, required: true, placeholder: "Select\u2026", name: "defaultSalesUnit"),
      FormFieldDef(label: "Active", kind: FormFieldKind.text, full: true, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "green", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-raw-materials": FormDef(route: "/water-raw-materials", specKey: "water-raw-material-usage-history", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Item name", kind: FormFieldKind.text, required: true, full: true, name: "itemName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Production unit of measure", kind: FormFieldKind.select, placeholder: "Pick a unit", name: "unitOfMeasure"),
      FormFieldDef(label: "Purchase unit of measure", kind: FormFieldKind.select, name: "purchaseUnitOfMeasure"),
      FormFieldDef(label: "Minimum stock alert", kind: FormFieldKind.number, full: true, name: "minimumStockAlert"),
      FormFieldDef(label: "Order of item usage", kind: FormFieldKind.text, full: true, hint: "Decides which purchase batch a production run consumes, and the price it is costed at", name: "usageMethod"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "Item, Supplier & Date", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Supplier", kind: FormFieldKind.text, full: true, name: "supplierId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "purchaseDate"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
    ]),
    FormSectionDef(title: "Purchase Quantity & Production Costing", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Purchase unit", kind: FormFieldKind.select, required: true, placeholder: "Pick unit", name: "purchaseUnit"),
      FormFieldDef(label: "", kind: FormFieldKind.bool, full: true),
      FormFieldDef(label: "Total purchase cost", kind: FormFieldKind.money, required: true),
      FormFieldDef(label: "Purchase unit cost (auto)", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Production Conversion", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "", kind: FormFieldKind.bool, full: true),
      FormFieldDef(label: "Production unit", kind: FormFieldKind.select, required: true, placeholder: "Pick unit", name: "productionUnit"),
      FormFieldDef(label: "Production units per purchase unit", kind: FormFieldKind.number, required: true, name: "productionUnitsPerPurchaseUnit"),
      FormFieldDef(label: "Production-level quantity", kind: FormFieldKind.number, hint: "Editable \u2014 sets units per purchase unit", name: "productionUnitsPerPurchaseUnit"),
      FormFieldDef(label: "Production-level unit cost (auto)", kind: FormFieldKind.text),
      FormFieldDef(label: "", kind: FormFieldKind.text, full: true),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Amount paid", kind: FormFieldKind.money, name: "amountPaid"),
      FormFieldDef(label: "Receipt URL", kind: FormFieldKind.text, name: "receiptUrl"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
    FormSectionDef(title: "Payment", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Amount paid", kind: FormFieldKind.money, required: true, name: "amount"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Payment date", kind: FormFieldKind.date, name: "paymentDate"),
    ]),
  ]),
  "/water-routes": FormDef(route: "/water-routes", specKey: "water-routes", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Route name", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. Kumasi East", name: "routeName"),
      FormFieldDef(label: "Area covered", kind: FormFieldKind.text, full: true, name: "areaCovered"),
    ]),
    FormSectionDef(title: "Assignment", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Default vehicle", kind: FormFieldKind.select, full: true, placeholder: "(none)", name: "defaultVehicleId"),
      FormFieldDef(label: "Expected customers", kind: FormFieldKind.number, name: "expectedCustomers"),
      FormFieldDef(label: "Expected bags/day", kind: FormFieldKind.number, name: "expectedBagsSold"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-staff": FormDef(route: "/water-staff", specKey: "water-staff", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
    ]),
    FormSectionDef(title: "Role & Pay", color: "amber", columns: 2, fields: [
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
      FormFieldDef(label: "Salary type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Commission rate (per bag / %)", kind: FormFieldKind.money, name: "commissionRate"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, full: true, name: "isActive"),
    ]),
    FormSectionDef(title: "Driver details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "License number", kind: FormFieldKind.text, placeholder: "e.g. DVLA-0000-2026"),
      FormFieldDef(label: "Assigned vehicle", kind: FormFieldKind.select, placeholder: "(none)", name: "assignedWaterVehicleId"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-stock": FormDef(route: "/water-stock", specKey: "water-stock-transactions", sections: [
    FormSectionDef(title: "Stock entry", color: "sky", columns: 2, fields: [
      FormFieldDef(label: "Item", kind: FormFieldKind.select, required: true, full: true, placeholder: "Pick a finished product, raw material or supply\u2026", name: "target"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "txnType"),
      FormFieldDef(label: "Unit cost (optional, for restocks)", kind: FormFieldKind.money, name: "unitCost"),
      FormFieldDef(label: "Note", kind: FormFieldKind.text, full: true, name: "note"),
    ]),
  ]),
  "/water-suppliers": FormDef(route: "/water-suppliers", specKey: "water-suppliers", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Supplier name", kind: FormFieldKind.text, required: true, full: true, name: "supplierName"),
      FormFieldDef(label: "Supplier type", kind: FormFieldKind.select, name: "supplierType"),
      FormFieldDef(label: "Active", kind: FormFieldKind.select, name: "isActive"),
    ]),
    FormSectionDef(title: "Contact", color: "green", columns: 2, fields: [
      FormFieldDef(label: "Contact person", kind: FormFieldKind.text, name: "contactPerson"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, full: true, name: "address"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/water-vehicles": FormDef(route: "/water-vehicles", specKey: "water-vehicles", sections: [
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Vehicle name", kind: FormFieldKind.text, required: true, full: true, placeholder: "e.g. Truck 1", name: "vehicleName"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "vehicleType"),
      FormFieldDef(label: "Registration #", kind: FormFieldKind.text, name: "registrationNumber"),
    ]),
    FormSectionDef(title: "Details", color: "blue", columns: 2, fields: [
      FormFieldDef(label: "Capacity (bags)", kind: FormFieldKind.number, name: "capacityBags"),
      FormFieldDef(label: "Fuel type", kind: FormFieldKind.text, placeholder: "Petrol / Diesel", name: "fuelType"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, full: true, name: "status"),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/cash-flow": FormDef(route: "/cash-flow", specKey: "poultry-cash-flow", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, required: true),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Lender", kind: FormFieldKind.text, required: true),
      FormFieldDef(label: "Owner name (optional)", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Description", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Description (optional)", kind: FormFieldKind.text),
    ]),
  ]),
  "/water-cash-flow": FormDef(route: "/water-cash-flow", specKey: "water-cash-flow", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, required: true),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Lender", kind: FormFieldKind.text, required: true),
      FormFieldDef(label: "Owner name (optional)", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Description", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Description (optional)", kind: FormFieldKind.text),
    ]),
  ]),
  "/poultry-cash-reconciliation": FormDef(route: "/poultry-cash-reconciliation", specKey: "poultry-cash-reconciliations", sections: [
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes (optional)", kind: FormFieldKind.textarea),
    ]),
  ]),
  "/water-cash-reconciliation": FormDef(route: "/water-cash-reconciliation", specKey: "water-cash-reconciliations", sections: [
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes (optional)", kind: FormFieldKind.textarea),
    ]),
  ]),
  "/poultry-loans": FormDef(route: "/poultry-loans", specKey: "loans", sections: [
    FormSectionDef(title: "Loan", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Loan being repaid", kind: FormFieldKind.select, required: true, name: "loanId"),
    ]),
    FormSectionDef(title: "What the payment is for", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Principal", kind: FormFieldKind.number, name: "principalAmount"),
      FormFieldDef(label: "Interest", kind: FormFieldKind.number, name: "interestAmount"),
      FormFieldDef(label: "Fees", kind: FormFieldKind.number, name: "feeAmount"),
      FormFieldDef(label: "Other", kind: FormFieldKind.number, name: "otherAmount"),
    ]),
    FormSectionDef(title: "What this does", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Payment details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, required: true, name: "accountId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "paymentDate"),
      FormFieldDef(label: "Next payment due", kind: FormFieldKind.date, name: "nextPaymentDate"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-loans": FormDef(route: "/water-loans", specKey: "water-loans", sections: [
    FormSectionDef(title: "Loan", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Loan being repaid", kind: FormFieldKind.select, required: true, name: "loanId"),
    ]),
    FormSectionDef(title: "What the payment is for", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Principal", kind: FormFieldKind.number, name: "principalAmount"),
      FormFieldDef(label: "Interest", kind: FormFieldKind.number, name: "interestAmount"),
      FormFieldDef(label: "Fees", kind: FormFieldKind.number, name: "feeAmount"),
      FormFieldDef(label: "Other", kind: FormFieldKind.number, name: "otherAmount"),
    ]),
    FormSectionDef(title: "What this does", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Payment details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Paid from", kind: FormFieldKind.select, required: true, name: "accountId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "paymentDate"),
      FormFieldDef(label: "Next payment due", kind: FormFieldKind.date, name: "nextPaymentDate"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "referenceNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/poultry-cash-accounts": FormDef(route: "/poultry-cash-accounts", specKey: "poultry-cash-accounts", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, required: true, name: "accountId"),
      FormFieldDef(label: "Direction", kind: FormFieldKind.select, required: true),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, required: true),
    ]),
  ]),
  "/water-cash-accounts": FormDef(route: "/water-cash-accounts", specKey: "water-cash-accounts", sections: [
    FormSectionDef(title: "Adjustment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, required: true, name: "accountId"),
      FormFieldDef(label: "Direction", kind: FormFieldKind.select, required: true),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Reason", kind: FormFieldKind.select, required: true),
    ]),
  ]),
  "/poultry-feed-production/[id]": FormDef(route: "/poultry-feed-production/[id]", specKey: "poultry-feed-production", sections: [
    FormSectionDef(title: "Finished feed output", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Finished feed", kind: FormFieldKind.select, required: true, name: "finishedFeedItemId"),
      FormFieldDef(label: "Feed formula", kind: FormFieldKind.select, name: "formulaId"),
      FormFieldDef(label: "Production date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Quantity produced", kind: FormFieldKind.number, required: true, name: "quantityProduced"),
      FormFieldDef(label: "Output unit", kind: FormFieldKind.text, name: "outputUnit"),
      FormFieldDef(label: "Batch number", kind: FormFieldKind.text, name: "batchNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Ingredient breakdown", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Additional production costs", color: "indigo", columns: 1, fields: [
    ]),
  ]),
  "/poultry-feed-production/new": FormDef(route: "/poultry-feed-production/new", specKey: "poultry-feed-production", sections: [
    FormSectionDef(title: "Finished feed output", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Finished feed", kind: FormFieldKind.select, required: true, name: "finishedFeedItemId"),
      FormFieldDef(label: "Feed formula", kind: FormFieldKind.select, name: "formulaId"),
      FormFieldDef(label: "Production date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Quantity produced", kind: FormFieldKind.number, required: true, name: "quantityProduced"),
      FormFieldDef(label: "Output unit", kind: FormFieldKind.text, name: "outputUnit"),
      FormFieldDef(label: "Batch number", kind: FormFieldKind.text, name: "batchNumber"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Ingredient breakdown", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Additional production costs", color: "indigo", columns: 1, fields: [
    ]),
  ]),
  "/batch-production-records": FormDef(route: "/batch-production-records", specKey: "productionbatchrecord", sections: [
    FormSectionDef(title: "Batch & Date", color: "sky", columns: 2, description: "Which flocks these totals cover, and the day they were collected.", fields: [
      FormFieldDef(label: "Batch scope", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Batch name", kind: FormFieldKind.text),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs. These are BATCH totals, split across flocks at allocation.", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds", color: "emerald", columns: 2, description: "Batch-level deaths and remaining birds. Allocation shares deaths across the included flocks.", fields: [
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "deaths"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.number, name: "birdsLeft"),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Drawn from inventory. Allocation computes each flock's share from these lines.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Drawn from inventory for the whole batch.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this batch.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/batch-production-records/[id]/edit": FormDef(route: "/batch-production-records/[id]/edit", specKey: "productionbatchrecord", sections: [
    FormSectionDef(title: "Batch & Date", color: "sky", columns: 2, description: "Which flocks these totals cover, and the day they were collected.", fields: [
      FormFieldDef(label: "Batch scope", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Batch name", kind: FormFieldKind.text),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs. These are BATCH totals, split across flocks at allocation.", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds", color: "emerald", columns: 2, description: "Batch-level deaths and remaining birds. Allocation shares deaths across the included flocks.", fields: [
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "deaths"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.number, name: "birdsLeft"),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Drawn from inventory. Allocation computes each flock's share from these lines.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Drawn from inventory for the whole batch.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this batch.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/batch-production-records/new": FormDef(route: "/batch-production-records/new", specKey: "productionbatchrecord", sections: [
    FormSectionDef(title: "Batch & Date", color: "sky", columns: 2, description: "Which flocks these totals cover, and the day they were collected.", fields: [
      FormFieldDef(label: "Batch scope", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Batch name", kind: FormFieldKind.text),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs. These are BATCH totals, split across flocks at allocation.", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds", color: "emerald", columns: 2, description: "Batch-level deaths and remaining birds. Allocation shares deaths across the included flocks.", fields: [
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "deaths"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.number, name: "birdsLeft"),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Drawn from inventory. Allocation computes each flock's share from these lines.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Drawn from inventory for the whole batch.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this batch.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Flocks in scope", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/production-records": FormDef(route: "/production-records", specKey: "production-records", sections: [
    FormSectionDef(title: "Flock & Date", color: "sky", columns: 2, description: "Which flock this record is for, and the day it covers.", fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, required: true, name: "flockId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds & Age", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Number of birds", kind: FormFieldKind.number, name: "numBirds"),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "mortality"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age (weeks)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (days)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (years)", kind: FormFieldKind.number),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Draw feed from inventory as lines, or record a plain quantity.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Medication drawn from inventory for this flock on this day.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this day.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/production-records/[id]": FormDef(route: "/production-records/[id]", specKey: "production-records", sections: [
    FormSectionDef(title: "Flock & Date", color: "sky", columns: 2, description: "Which flock this record is for, and the day it covers.", fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, required: true, name: "flockId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds & Age", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Number of birds", kind: FormFieldKind.number, name: "numBirds"),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "mortality"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age (weeks)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (days)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (years)", kind: FormFieldKind.number),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Draw feed from inventory as lines, or record a plain quantity.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Medication drawn from inventory for this flock on this day.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this day.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/production-records/new": FormDef(route: "/production-records/new", specKey: "production-records", sections: [
    FormSectionDef(title: "Flock & Date", color: "sky", columns: 2, description: "Which flock this record is for, and the day it covers.", fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, required: true, name: "flockId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, required: true, name: "date"),
      FormFieldDef(label: "Egg grade", kind: FormFieldKind.select, name: "eggGrade"),
    ]),
    FormSectionDef(title: "Egg Production", color: "amber", columns: 1, description: "Total = crates \u00d7 30 + loose eggs", fields: [
      FormFieldDef(label: "Crates", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose eggs", kind: FormFieldKind.number, name: "loose"),
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Egg Losses / Quality", color: "rose", columns: 2, description: "Eggs that cannot be sold. Net sellable = total picked \u2212 these.", fields: [
      FormFieldDef(label: "Broken eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Meaty eggs", kind: FormFieldKind.number, name: "meatyEggs"),
      FormFieldDef(label: "Soft eggs", kind: FormFieldKind.number, name: "softEggs"),
      FormFieldDef(label: "Lost eggs", kind: FormFieldKind.number, name: "lostEggs"),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Birds & Age", color: "emerald", columns: 2, fields: [
      FormFieldDef(label: "Number of birds", kind: FormFieldKind.number, name: "numBirds"),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.number, name: "mortality"),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Age (weeks)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (days)", kind: FormFieldKind.number),
      FormFieldDef(label: "Age (years)", kind: FormFieldKind.number),
    ]),
    FormSectionDef(title: "Feed", color: "orange", columns: 1, description: "Draw feed from inventory as lines, or record a plain quantity.", lines: FormLineDef(name: "feedLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Feed Used", kind: FormFieldKind.select, name: "specificFeedUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalFeedConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total feed (kg)", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total feed cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Medication", color: "violet", columns: 1, description: "Medication drawn from inventory for this flock on this day.", lines: FormLineDef(name: "medicationLines", addLabel: "Add line", fields: [FormFieldDef(label: "Specific Medication Used", kind: FormFieldKind.select, name: "specificMedicationUsedId"), FormFieldDef(label: "Consumed", kind: FormFieldKind.number, name: "totalMedicationConsumed"), FormFieldDef(label: "Unit Cost", kind: FormFieldKind.calc), FormFieldDef(label: "Total Cost", kind: FormFieldKind.calc)]), fields: [
      FormFieldDef(label: "Total medication consumed", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total medication cost", kind: FormFieldKind.calc),
    ]),
    FormSectionDef(title: "Notes", color: "slate", columns: 1, description: "Anything worth remembering about this day.", fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, placeholder: "Optional", name: "notes"),
    ]),
    FormSectionDef(title: "Summary", color: "indigo", columns: 2, description: "Check these before saving.", fields: [
      FormFieldDef(label: "Total eggs", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total crates", kind: FormFieldKind.calc),
      FormFieldDef(label: "Broken", kind: FormFieldKind.calc),
      FormFieldDef(label: "Meaty", kind: FormFieldKind.calc),
      FormFieldDef(label: "Soft", kind: FormFieldKind.calc),
      FormFieldDef(label: "Lost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Net sellable", kind: FormFieldKind.calc),
      FormFieldDef(label: "Deaths", kind: FormFieldKind.calc),
      FormFieldDef(label: "Birds left", kind: FormFieldKind.calc),
      FormFieldDef(label: "Feed cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Medication cost", kind: FormFieldKind.calc),
      FormFieldDef(label: "Total production cost", kind: FormFieldKind.calc),
    ]),
  ]),
  "/poultry-raw-materials": FormDef(route: "/poultry-raw-materials", specKey: "raw-materials", sections: [
    FormSectionDef(title: "Item, Supplier & Date", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Raw material item", kind: FormFieldKind.select, required: true, name: "poultryRawMaterialItemId"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.text, name: "supplierName"),
      FormFieldDef(label: "Purchase date", kind: FormFieldKind.date, name: "purchaseDate"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
    ]),
    FormSectionDef(title: "Purchase Quantity & Production Costing", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Purchase unit", kind: FormFieldKind.select, required: true, name: "purchaseUnit"),
      FormFieldDef(label: "", kind: FormFieldKind.bool),
      FormFieldDef(label: "Total purchase cost", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Purchase unit cost (auto)", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Production Conversion", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "", kind: FormFieldKind.bool),
      FormFieldDef(label: "Production unit", kind: FormFieldKind.select, name: "productionUnit"),
      FormFieldDef(label: "Production units per purchase unit", kind: FormFieldKind.number, name: "productionUnitsPerPurchaseUnit"),
      FormFieldDef(label: "Production-level quantity", kind: FormFieldKind.number),
      FormFieldDef(label: "Production-level unit cost", kind: FormFieldKind.number),
      FormFieldDef(label: "Production-level unit cost (auto)", kind: FormFieldKind.text),
      FormFieldDef(label: "", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Payment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Amount paid", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Pay from cash account", kind: FormFieldKind.select, name: "poultryCashAccountId"),
      FormFieldDef(label: "Balance (auto)", kind: FormFieldKind.text),
      FormFieldDef(label: "", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-setup": FormDef(route: "/water-setup", specKey: "water-company", sections: [
    FormSectionDef(title: "Basics", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "name"),
      FormFieldDef(label: "SKU", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Size (mL)", kind: FormFieldKind.number, name: "sizeMl"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text, name: "unit"),
      FormFieldDef(label: "Unit price", kind: FormFieldKind.number, name: "unitPrice"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "productType"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Contact", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "name"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, name: "address"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Identity", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Driver name", kind: FormFieldKind.text, required: true, name: "driverName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "License #", kind: FormFieldKind.text, name: "licenseNumber"),
    ]),
    FormSectionDef(title: "Assignment", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Assigned vehicle", kind: FormFieldKind.select, name: "defaultVehicleId"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Vehicle", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "vehicleName"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "vehicleType"),
      FormFieldDef(label: "Registration #", kind: FormFieldKind.text, name: "registrationNumber"),
      FormFieldDef(label: "Capacity (bags)", kind: FormFieldKind.number, name: "capacityBags"),
      FormFieldDef(label: "Fuel type", kind: FormFieldKind.text, name: "fuelType"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, name: "status"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Route", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "routeName"),
      FormFieldDef(label: "Area covered", kind: FormFieldKind.text, name: "areaCovered"),
      FormFieldDef(label: "Default vehicle", kind: FormFieldKind.select, name: "defaultVehicleId"),
      FormFieldDef(label: "Expected customers", kind: FormFieldKind.number, name: "expectedCustomers"),
      FormFieldDef(label: "Expected bags", kind: FormFieldKind.number, name: "expectedBagsSold"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Machine", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "machineName"),
      FormFieldDef(label: "Machine #", kind: FormFieldKind.text, name: "machineNumber"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "machineType"),
      FormFieldDef(label: "Manufacturer", kind: FormFieldKind.text, name: "manufacturer"),
      FormFieldDef(label: "Capacity / hour", kind: FormFieldKind.number, name: "capacityPerHour"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, name: "status"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Borehole", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "boreholeName"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Pump type", kind: FormFieldKind.text, name: "pumpType"),
      FormFieldDef(label: "Pump capacity", kind: FormFieldKind.text, name: "pumpCapacity"),
      FormFieldDef(label: "Tank capacity", kind: FormFieldKind.text, name: "tankCapacity"),
      FormFieldDef(label: "Treatment method", kind: FormFieldKind.text, name: "waterTreatmentMethod"),
      FormFieldDef(label: "Filtration system", kind: FormFieldKind.text, name: "filtrationSystem"),
      FormFieldDef(label: "UV sterilization?", kind: FormFieldKind.bool, name: "uvSterilizationAvailable"),
      FormFieldDef(label: "Status", kind: FormFieldKind.select, name: "status"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Material", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, required: true, name: "itemName"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Unit of measure", kind: FormFieldKind.text, name: "unitOfMeasure"),
      FormFieldDef(label: "Min stock alert", kind: FormFieldKind.number, name: "minimumStockAlert"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
    FormSectionDef(title: "Identity", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, required: true, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, required: true, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
    ]),
    FormSectionDef(title: "Compensation", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Salary type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Base pay", kind: FormFieldKind.number, name: "basePay"),
      FormFieldDef(label: "Commission rate (%)", kind: FormFieldKind.number, name: "commissionRate"),
      FormFieldDef(label: "Active", kind: FormFieldKind.bool, name: "isActive"),
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-daily-production/[id]/edit": FormDef(route: "/water-daily-production/[id]/edit", specKey: "water-daily-productions", sections: [
    FormSectionDef(title: "Batch & scope", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Production date", kind: FormFieldKind.date, required: true),
      FormFieldDef(label: "Document number", kind: FormFieldKind.text),
      FormFieldDef(label: "Shift", kind: FormFieldKind.select),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, required: true, name: "waterProductId"),
      FormFieldDef(label: "Borehole", kind: FormFieldKind.select, name: "waterBoreholeId"),
      FormFieldDef(label: "Machines", kind: FormFieldKind.select, required: true),
    ]),
    FormSectionDef(title: "Batch output", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Bags produced", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Sachets per bag", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose sachets", kind: FormFieldKind.number),
      FormFieldDef(label: "Rejected sachets", kind: FormFieldKind.number),
      FormFieldDef(label: "Damaged bags", kind: FormFieldKind.number),
      FormFieldDef(label: "Packaging rolls used", kind: FormFieldKind.number),
      FormFieldDef(label: "Water used (litres)", kind: FormFieldKind.number),
      FormFieldDef(label: "Good bags", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Production costs", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Electricity", kind: FormFieldKind.number),
      FormFieldDef(label: "Fuel", kind: FormFieldKind.number),
      FormFieldDef(label: "Labor", kind: FormFieldKind.number),
      FormFieldDef(label: "Other", kind: FormFieldKind.number),
    ]),
    FormSectionDef(title: "Raw materials used", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/water-daily-production/new": FormDef(route: "/water-daily-production/new", specKey: "water-daily-productions", sections: [
    FormSectionDef(title: "Batch & scope", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Production date", kind: FormFieldKind.date, required: true),
      FormFieldDef(label: "Document number", kind: FormFieldKind.text),
      FormFieldDef(label: "Shift", kind: FormFieldKind.select),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, required: true, name: "waterProductId"),
      FormFieldDef(label: "Borehole", kind: FormFieldKind.select, name: "waterBoreholeId"),
      FormFieldDef(label: "Machines", kind: FormFieldKind.select, required: true),
    ]),
    FormSectionDef(title: "Batch output", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Bags produced", kind: FormFieldKind.number, required: true),
      FormFieldDef(label: "Sachets per bag", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose sachets", kind: FormFieldKind.number),
      FormFieldDef(label: "Rejected sachets", kind: FormFieldKind.number),
      FormFieldDef(label: "Damaged bags", kind: FormFieldKind.number),
      FormFieldDef(label: "Packaging rolls used", kind: FormFieldKind.number),
      FormFieldDef(label: "Water used (litres)", kind: FormFieldKind.number),
      FormFieldDef(label: "Good bags", kind: FormFieldKind.text),
    ]),
    FormSectionDef(title: "Production costs", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Electricity", kind: FormFieldKind.number),
      FormFieldDef(label: "Fuel", kind: FormFieldKind.number),
      FormFieldDef(label: "Labor", kind: FormFieldKind.number),
      FormFieldDef(label: "Other", kind: FormFieldKind.number),
    ]),
    FormSectionDef(title: "Raw materials used", color: "indigo", columns: 1, fields: [
    ]),
    FormSectionDef(title: "Notes", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/business-office": FormDef(route: "/business-office", specKey: "businessoffice-company-snapshot", sections: [
    FormSectionDef(title: "Create new company", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Business type", kind: FormFieldKind.select, name: "businessTypeId"),
      FormFieldDef(label: "Company name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Contact email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
    ]),
  ]),
  "/cash": FormDef(route: "/cash", specKey: "cash", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "adjustmentType"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "adjustmentDate"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Description (optional)", kind: FormFieldKind.text, name: "description"),
    ]),
  ]),
  "/companies": FormDef(route: "/companies", specKey: "companies-mine", sections: [
    FormSectionDef(title: "Create new company", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "businessTypeId"),
      FormFieldDef(label: "Company name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Contact email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
    ]),
  ]),
  "/customers": FormDef(route: "/customers", specKey: "customer", sections: [
    FormSectionDef(title: "Add New Customer", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Full Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
      FormFieldDef(label: "Full Address", kind: FormFieldKind.text, name: "address"),
    ]),
  ]),
  "/customers/[id]": FormDef(route: "/customers/[id]", specKey: "customer", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Full Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, name: "address"),
    ]),
  ]),
  "/customers/new": FormDef(route: "/customers/new", specKey: "customer", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Full Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
      FormFieldDef(label: "Full Address", kind: FormFieldKind.text, name: "address"),
    ]),
  ]),
  "/egg-production": FormDef(route: "/egg-production", specKey: "eggproduction", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Production Date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Total Eggs Collected", kind: FormFieldKind.number),
      FormFieldDef(label: "Broken Eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Egg size (slot / sort)", kind: FormFieldKind.select, name: "eggGrade"),
      FormFieldDef(label: "\u2014 Crates \u00d7 + Loose Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Crates", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose Eggs", kind: FormFieldKind.number),
      FormFieldDef(label: "Total", kind: FormFieldKind.text),
      FormFieldDef(label: "Total Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/egg-production/[id]": FormDef(route: "/egg-production/[id]", specKey: "eggproduction", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Production Date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Total Eggs Collected", kind: FormFieldKind.number),
      FormFieldDef(label: "Broken Eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Egg size (slot / sort)", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "\u2014 Crates \u00d7 + Loose Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Crates", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose Eggs", kind: FormFieldKind.number),
      FormFieldDef(label: "Total", kind: FormFieldKind.text),
      FormFieldDef(label: "Total Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/egg-production/new": FormDef(route: "/egg-production/new", specKey: "eggproduction", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Production Date", kind: FormFieldKind.date, name: "productionDate"),
      FormFieldDef(label: "Total Eggs Collected", kind: FormFieldKind.number),
      FormFieldDef(label: "Broken Eggs", kind: FormFieldKind.number, name: "brokenEggs"),
      FormFieldDef(label: "Egg size (slot / sort)", kind: FormFieldKind.select, name: "eggGrade"),
      FormFieldDef(label: "\u2014 Crates \u00d7 + Loose Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Crates", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose Eggs", kind: FormFieldKind.number),
      FormFieldDef(label: "Total", kind: FormFieldKind.text),
      FormFieldDef(label: "Total Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/egg-tracker": FormDef(route: "/egg-tracker", specKey: "egginventoryadjustment", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "adjustmentType"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "adjustmentDate"),
      FormFieldDef(label: "Egg change (whole eggs)", kind: FormFieldKind.number, name: "eggDelta"),
      FormFieldDef(label: "Description (optional)", kind: FormFieldKind.text, name: "description"),
    ]),
  ]),
  "/employees": FormDef(route: "/employees", specKey: "admin-company-employees", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Username (letters, digits, underscores only)", kind: FormFieldKind.text, name: "userName"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Password", kind: FormFieldKind.text, name: "password"),
      FormFieldDef(label: "Confirm Password", kind: FormFieldKind.text, name: "confirmPassword"),
    ]),
  ]),
  "/employees/[id]": FormDef(route: "/employees/[id]", specKey: "admin-company-employees", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "phoneNumber"),
    ]),
  ]),
  "/employees/new": FormDef(route: "/employees/new", specKey: "admin-company-employees", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone Number", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Username (letters, digits, underscores only)", kind: FormFieldKind.text, name: "userName"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Password", kind: FormFieldKind.text, name: "password"),
      FormFieldDef(label: "Confirm Password", kind: FormFieldKind.text, name: "confirmPassword"),
    ]),
  ]),
  "/expenses": FormDef(route: "/expenses", specKey: "expenses", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Expense Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Pay from cash account", kind: FormFieldKind.select, name: "poultryCashAccountId"),
    ]),
  ]),
  "/expenses/[id]": FormDef(route: "/expenses/[id]", specKey: "expenses", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Expense Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Pay from cash account", kind: FormFieldKind.select, name: "poultryCashAccountId"),
      FormFieldDef(label: "Amount (\$)", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, name: "description"),
    ]),
  ]),
  "/expenses/new": FormDef(route: "/expenses/new", specKey: "expenses", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Expense Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Pay from cash account", kind: FormFieldKind.select, name: "poultryCashAccountId"),
    ]),
  ]),
  "/feed-usage": FormDef(route: "/feed-usage", specKey: "feedusage", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Usage Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Feed Type", kind: FormFieldKind.select, name: "feedType"),
      FormFieldDef(label: "Quantity (kg)", kind: FormFieldKind.number, name: "quantityKg"),
    ]),
  ]),
  "/feed-usage/[id]": FormDef(route: "/feed-usage/[id]", specKey: "feedusage", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Usage Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Feed Type", kind: FormFieldKind.select, name: "feedType"),
      FormFieldDef(label: "Quantity (kg)", kind: FormFieldKind.number, name: "quantityKg"),
    ]),
  ]),
  "/feed-usage/new": FormDef(route: "/feed-usage/new", specKey: "feedusage", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch", kind: FormFieldKind.select, name: "value"),
      FormFieldDef(label: "Select Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Usage Date", kind: FormFieldKind.date, name: "usageDate"),
      FormFieldDef(label: "Feed Type", kind: FormFieldKind.select, name: "feedType"),
      FormFieldDef(label: "Quantity (kg)", kind: FormFieldKind.number, name: "quantityKg"),
    ]),
  ]),
  "/flock-batch": FormDef(route: "/flock-batch", specKey: "flock", sections: [
    FormSectionDef(title: "Add New Flock Batch", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch Name", kind: FormFieldKind.text, name: "batchName"),
      FormFieldDef(label: "Batch Code", kind: FormFieldKind.text, name: "batchCode"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "numberOfBirds"),
      FormFieldDef(label: "Cost Per Chick", kind: FormFieldKind.number, name: "costPerChick"),
      FormFieldDef(label: "Total Cost", kind: FormFieldKind.number, name: "totalCost"),
      FormFieldDef(label: "Amount Paid Now", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "supplierType"),
      FormFieldDef(label: "Dollar Conversion Rate", kind: FormFieldKind.number, name: "dollarConversionRate"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.select, name: "supplierId"),
      FormFieldDef(label: "Order Placement Date", kind: FormFieldKind.date, name: "orderPlacementDate"),
      FormFieldDef(label: "Estimated Arrival Date", kind: FormFieldKind.date, name: "estimatedArrivalDate"),
      FormFieldDef(label: "Batch Has Arrived", kind: FormFieldKind.bool, name: "active"),
      FormFieldDef(label: "Active Batch", kind: FormFieldKind.text),
      FormFieldDef(label: "Notes (Optional)", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/flock-batch/[id]": FormDef(route: "/flock-batch/[id]", specKey: "flock", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch Name", kind: FormFieldKind.text, name: "batchName"),
      FormFieldDef(label: "Batch Code", kind: FormFieldKind.text, name: "batchCode"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "numberOfBirds"),
    ]),
  ]),
  "/flock-batch/new": FormDef(route: "/flock-batch/new", specKey: "flock", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Batch Name", kind: FormFieldKind.text, name: "batchName"),
      FormFieldDef(label: "Batch Code", kind: FormFieldKind.text, name: "batchCode"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "numberOfBirds"),
    ]),
  ]),
  "/flocks": FormDef(route: "/flocks", specKey: "flocks", sections: [
    FormSectionDef(title: "Add New Flock", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Assign to Flock Batch", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Assign to House", kind: FormFieldKind.select, name: "houseId"),
      FormFieldDef(label: "Flock Has Arrived", kind: FormFieldKind.bool, name: "active"),
      FormFieldDef(label: "Active Flock", kind: FormFieldKind.text),
      FormFieldDef(label: "Inactivation Reason", kind: FormFieldKind.text, name: "inactivationReason"),
      FormFieldDef(label: "Other Reason", kind: FormFieldKind.text, name: "otherReason"),
      FormFieldDef(label: "Notes (Optional)", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/flocks/[id]": FormDef(route: "/flocks/[id]", specKey: "flocks", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Assign to Flock Batch", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Assign to House", kind: FormFieldKind.select, name: "houseId"),
      FormFieldDef(label: "Active Flock", kind: FormFieldKind.text),
      FormFieldDef(label: "Reason for Inactivation", kind: FormFieldKind.text, name: "inactivationReason"),
      FormFieldDef(label: "Other Reason", kind: FormFieldKind.text, name: "otherReason"),
      FormFieldDef(label: "Notes (Optional)", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/flocks/new": FormDef(route: "/flocks/new", specKey: "flocks", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Assign to Flock Batch", kind: FormFieldKind.select, name: "batchId"),
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Breed", kind: FormFieldKind.text, name: "breed"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "Number of Birds", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Assign to House", kind: FormFieldKind.select, name: "houseId"),
      FormFieldDef(label: "Active Flock", kind: FormFieldKind.text),
      FormFieldDef(label: "Inactivation Reason", kind: FormFieldKind.text, name: "inactivationReason"),
      FormFieldDef(label: "Other Reason", kind: FormFieldKind.text, name: "otherReason"),
      FormFieldDef(label: "Notes (Optional)", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-daily-closings": FormDef(route: "/generic-daily-closings", specKey: "generic-daily-closings", sections: [
    FormSectionDef(title: "Daily closing", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Closing date", kind: FormFieldKind.date, name: "closingDate"),
      FormFieldDef(label: "Opening cash (optional)", kind: FormFieldKind.number, name: "openingCash"),
      FormFieldDef(label: "Actual cash counted", kind: FormFieldKind.number, name: "actualCashCounted"),
      FormFieldDef(label: "Manager notes", kind: FormFieldKind.textarea, name: "managerNotes"),
      FormFieldDef(label: "Reason for any cash difference", kind: FormFieldKind.textarea, name: "differenceReason"),
    ]),
  ]),
  "/generic-expenses": FormDef(route: "/generic-expenses", specKey: "generic-expenses", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "genericExpenseCategoryId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Paid to", kind: FormFieldKind.text, name: "paidTo"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Supplier (credit)", kind: FormFieldKind.select, name: "genericSupplierId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-expenses/new": FormDef(route: "/generic-expenses/new", specKey: "generic-expenses", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "genericExpenseCategoryId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Paid to", kind: FormFieldKind.text, name: "paidTo"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Supplier (credit)", kind: FormFieldKind.select, name: "genericSupplierId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-payroll/[id]": FormDef(route: "/generic-payroll/[id]", specKey: "generic-payroll-runs", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Staff", kind: FormFieldKind.select, name: "genericStaffId"),
      FormFieldDef(label: "Basic pay", kind: FormFieldKind.number, name: "basicPay"),
      FormFieldDef(label: "Daily wage", kind: FormFieldKind.number, name: "dailyWage"),
      FormFieldDef(label: "Commission", kind: FormFieldKind.number, name: "commission"),
      FormFieldDef(label: "Bonus", kind: FormFieldKind.number, name: "bonus"),
      FormFieldDef(label: "Deductions", kind: FormFieldKind.number, name: "deductions"),
      FormFieldDef(label: "Payment method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/generic-purchases": FormDef(route: "/generic-purchases", specKey: "generic-purchases", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Purchase date", kind: FormFieldKind.date, name: "purchaseDate"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.select, name: "genericSupplierId"),
      FormFieldDef(label: "Invoice number", kind: FormFieldKind.text, name: "invoiceNumber"),
      FormFieldDef(label: "Discount (header)", kind: FormFieldKind.number, name: "headerDiscountAmount"),
      FormFieldDef(label: "Tax", kind: FormFieldKind.number, name: "taxAmount"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (paid from)", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-purchases/new": FormDef(route: "/generic-purchases/new", specKey: "generic-purchases", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Purchase date", kind: FormFieldKind.date, name: "purchaseDate"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.select, name: "genericSupplierId"),
      FormFieldDef(label: "Invoice number", kind: FormFieldKind.text, name: "invoiceNumber"),
      FormFieldDef(label: "Discount (header)", kind: FormFieldKind.number, name: "headerDiscountAmount"),
      FormFieldDef(label: "Tax", kind: FormFieldKind.number, name: "taxAmount"),
      FormFieldDef(label: "Amount paid now", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (paid from)", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-sales": FormDef(route: "/generic-sales", specKey: "generic-sales", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Sale date", kind: FormFieldKind.date, name: "saleDate"),
      FormFieldDef(label: "Sales type", kind: FormFieldKind.select, name: "salesType"),
      FormFieldDef(label: "Customer (optional)", kind: FormFieldKind.select, name: "genericCustomerId"),
      FormFieldDef(label: "Receipt no.", kind: FormFieldKind.text, name: "receiptNumber"),
      FormFieldDef(label: "Discount (header)", kind: FormFieldKind.number, name: "headerDiscountAmount"),
      FormFieldDef(label: "Tax", kind: FormFieldKind.number, name: "taxAmount"),
      FormFieldDef(label: "Amount paid", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (receives payment)", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-sales/new": FormDef(route: "/generic-sales/new", specKey: "generic-sales", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Sale date", kind: FormFieldKind.date, name: "saleDate"),
      FormFieldDef(label: "Sales type", kind: FormFieldKind.select, name: "salesType"),
      FormFieldDef(label: "Customer (optional)", kind: FormFieldKind.select, name: "genericCustomerId"),
      FormFieldDef(label: "Receipt no.", kind: FormFieldKind.text, name: "receiptNumber"),
      FormFieldDef(label: "Discount (header)", kind: FormFieldKind.number, name: "headerDiscountAmount"),
      FormFieldDef(label: "Tax", kind: FormFieldKind.number, name: "taxAmount"),
      FormFieldDef(label: "Amount paid", kind: FormFieldKind.number, name: "amountPaid"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Cash account (receives payment)", kind: FormFieldKind.select, name: "genericCashAccountId"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-setup": FormDef(route: "/generic-setup", specKey: "generic-business-template", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "What kind of business is this?", kind: FormFieldKind.select, name: "businessTypeId"),
      FormFieldDef(label: "Default currency", kind: FormFieldKind.text, name: "defaultCurrency"),
      FormFieldDef(label: "Business start date", kind: FormFieldKind.date, name: "businessStartDate"),
      FormFieldDef(label: "Owner name", kind: FormFieldKind.text, name: "ownerName"),
      FormFieldDef(label: "Phone number", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Main location", kind: FormFieldKind.text, name: "mainLocation"),
      FormFieldDef(label: "Opening cash", kind: FormFieldKind.number, name: "openingCashBalance"),
      FormFieldDef(label: "Business description", kind: FormFieldKind.textarea, name: "businessDescription"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/generic-staff/[id]": FormDef(route: "/generic-staff/[id]", specKey: "generic-staff", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phoneNumber"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Role", kind: FormFieldKind.select, name: "role"),
      FormFieldDef(label: "Salary type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Base pay", kind: FormFieldKind.number, name: "basePay"),
      FormFieldDef(label: "Commission rate (optional)", kind: FormFieldKind.bool, name: "commissionRate"),
      FormFieldDef(label: "Active", kind: FormFieldKind.text),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/health": FormDef(route: "/health", specKey: "health", sections: [
    FormSectionDef(title: "Create Health Record", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "House", kind: FormFieldKind.select, name: "houseId"),
      FormFieldDef(label: "Inventory Item", kind: FormFieldKind.select, name: "itemId"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "recordDate"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select),
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "vaccination"),
      FormFieldDef(label: "Treatment", kind: FormFieldKind.text, name: "medication"),
      FormFieldDef(label: "Dosage", kind: FormFieldKind.number, name: "waterConsumption"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/hotel-billing": FormDef(route: "/hotel-billing", specKey: "hotel-billing-charges", sections: [
    FormSectionDef(title: "Add Charge \u2014", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Charge Type", kind: FormFieldKind.select, name: "chargeType"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Unit Price", kind: FormFieldKind.number, name: "unitPrice"),
    ]),
  ]),
  "/hotel-bookings": FormDef(route: "/hotel-bookings", specKey: "hotel-bookings", sections: [
    FormSectionDef(title: "{editing ? `Edit Booking \$` : \"New Booking\"}", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Guest", kind: FormFieldKind.select, name: "hotelGuestId"),
      FormFieldDef(label: "Room Type", kind: FormFieldKind.select, name: "hotelRoomTypeId"),
      FormFieldDef(label: "Room (optional)", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Check-in", kind: FormFieldKind.date, name: "checkInDate"),
      FormFieldDef(label: "Check-out", kind: FormFieldKind.date, name: "checkOutDate"),
      FormFieldDef(label: "Nightly Rate", kind: FormFieldKind.number, name: "nightlyRate"),
      FormFieldDef(label: "Total", kind: FormFieldKind.number, name: "totalAmount"),
      FormFieldDef(label: "Source", kind: FormFieldKind.select, name: "source"),
      FormFieldDef(label: "Adults", kind: FormFieldKind.number, name: "adults"),
      FormFieldDef(label: "Children", kind: FormFieldKind.number, name: "children"),
      FormFieldDef(label: "Total Guests", kind: FormFieldKind.number, name: "numberOfGuests"),
      FormFieldDef(label: "Special Requests", kind: FormFieldKind.text, name: "specialRequests"),
    ]),
  ]),
  "/hotel-cash-accounts": FormDef(route: "/hotel-cash-accounts", specKey: "hotel-finance-cash-accounts", sections: [
    FormSectionDef(title: "Add Cash Account", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Account Name", kind: FormFieldKind.text, name: "accountName"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "accountType"),
      FormFieldDef(label: "Link To (Purpose)", kind: FormFieldKind.select, name: "purpose"),
      FormFieldDef(label: "Opening Balance", kind: FormFieldKind.number, name: "openingBalance"),
    ]),
  ]),
  "/hotel-check-in": FormDef(route: "/hotel-check-in", specKey: "hotel-bookings", sections: [
    FormSectionDef(title: "Check In:", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Assign Room", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Key Card Number", kind: FormFieldKind.text),
      FormFieldDef(label: "Deposit Amount", kind: FormFieldKind.number),
      FormFieldDef(label: "Deposit Method", kind: FormFieldKind.select),
    ]),
  ]),
  "/hotel-check-out": FormDef(route: "/hotel-check-out", specKey: "hotel-bookings", sections: [
    FormSectionDef(title: "Record Payment:", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Payment Amount", kind: FormFieldKind.number),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.text),
    ]),
  ]),
  "/hotel-communications": FormDef(route: "/hotel-communications", specKey: "hotel-communications", sections: [
    FormSectionDef(title: "Log Guest Communication", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Guest", kind: FormFieldKind.select, name: "hotelGuestId"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "commType"),
      FormFieldDef(label: "Priority", kind: FormFieldKind.select, name: "priority"),
      FormFieldDef(label: "Subject", kind: FormFieldKind.text, name: "subject"),
      FormFieldDef(label: "Message", kind: FormFieldKind.textarea, name: "message"),
      FormFieldDef(label: "Assigned To", kind: FormFieldKind.select, name: "assignedTo"),
    ]),
  ]),
  "/hotel-daily-closing": FormDef(route: "/hotel-daily-closing", specKey: "hotel-reports-daily-closings", sections: [
    FormSectionDef(title: "Close Day", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "closingDate"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/hotel-guest-requests": FormDef(route: "/hotel-guest-requests", specKey: "hotel-guest-requests", sections: [
    FormSectionDef(title: "New Guest Request", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Booking (optional)", kind: FormFieldKind.select, name: "hotelBookingId"),
      FormFieldDef(label: "Room", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Type", kind: FormFieldKind.text, name: "requestType"),
      FormFieldDef(label: "Scheduled Time", kind: FormFieldKind.text, name: "scheduledTime"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, name: "description"),
      FormFieldDef(label: "Assigned To", kind: FormFieldKind.select, name: "assignedTo"),
      FormFieldDef(label: "Staff Name", kind: FormFieldKind.text, name: "assignedTo"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/hotel-guests": FormDef(route: "/hotel-guests", specKey: "hotel-guests", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "ID Type", kind: FormFieldKind.select, name: "description"),
      FormFieldDef(label: "ID Number", kind: FormFieldKind.text, name: "idNumber"),
      FormFieldDef(label: "Specify ID Type", kind: FormFieldKind.text, name: "idType"),
      FormFieldDef(label: "Nationality", kind: FormFieldKind.text, name: "nationality"),
      FormFieldDef(label: "Address", kind: FormFieldKind.text, name: "address"),
    ]),
  ]),
  "/hotel-housekeeping-schedule": FormDef(route: "/hotel-housekeeping-schedule", specKey: "hotel-housekeeping-schedule", sections: [
    FormSectionDef(title: "Add Schedule Entry", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Room", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Task Type", kind: FormFieldKind.text, name: "taskType"),
      FormFieldDef(label: "Priority", kind: FormFieldKind.select, name: "priority"),
      FormFieldDef(label: "Assigned To", kind: FormFieldKind.select, name: "assignedTo"),
      FormFieldDef(label: "Staff Name", kind: FormFieldKind.text, name: "assignedTo"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/hotel-inventory": FormDef(route: "/hotel-inventory", specKey: "hotel-inventory", sections: [
    FormSectionDef(title: "Add Supply Item", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Category", kind: FormFieldKind.text, name: "category"),
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text, name: "unit"),
      FormFieldDef(label: "Stock", kind: FormFieldKind.number, name: "stockOnHand"),
      FormFieldDef(label: "Reorder Level", kind: FormFieldKind.number, name: "reorderLevel"),
      FormFieldDef(label: "Unit Cost", kind: FormFieldKind.number, name: "unitCost"),
    ]),
  ]),
  "/hotel-lost-found": FormDef(route: "/hotel-lost-found", specKey: "hotel-lost-and-found", sections: [
    FormSectionDef(title: "Log Lost Item", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Item Description", kind: FormFieldKind.text, name: "itemDescription"),
      FormFieldDef(label: "Room", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Category", kind: FormFieldKind.text, name: "category"),
      FormFieldDef(label: "Found Date", kind: FormFieldKind.date, name: "foundDate"),
      FormFieldDef(label: "Found By", kind: FormFieldKind.text, name: "foundBy"),
      FormFieldDef(label: "Found Location", kind: FormFieldKind.text, name: "foundLocation"),
      FormFieldDef(label: "Storage Location", kind: FormFieldKind.text, name: "storageLocation"),
    ]),
  ]),
  "/hotel-maintenance": FormDef(route: "/hotel-maintenance", specKey: "hotel-maintenance", sections: [
    FormSectionDef(title: "New Maintenance Request", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Room (optional)", kind: FormFieldKind.select, name: "hotelRoomId"),
      FormFieldDef(label: "Asset / Area", kind: FormFieldKind.text, name: "assetDescription"),
      FormFieldDef(label: "Issue Description", kind: FormFieldKind.text, name: "issueDescription"),
      FormFieldDef(label: "Priority", kind: FormFieldKind.select, name: "priority"),
      FormFieldDef(label: "Estimated Cost", kind: FormFieldKind.number, name: "estimatedCost"),
    ]),
  ]),
  "/hotel-menu": FormDef(route: "/hotel-menu", specKey: "hotel-restaurant-tables", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Category", kind: FormFieldKind.text, name: "category"),
      FormFieldDef(label: "Price", kind: FormFieldKind.number, name: "price"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
    ]),
  ]),
  "/hotel-payments": FormDef(route: "/hotel-payments", specKey: "hotel-finance-expenses", sections: [
    FormSectionDef(title: "Record Payment", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Booking", kind: FormFieldKind.select, name: "hotelBookingId"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "reference"),
    ]),
  ]),
  "/hotel-restaurant": FormDef(route: "/hotel-restaurant", specKey: "hotel-restaurant-orders", sections: [
    FormSectionDef(title: "New Order \u2014 Point of Sale", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Table", kind: FormFieldKind.select, name: "tableNumber"),
      FormFieldDef(label: "Server", kind: FormFieldKind.select, name: "serverName"),
      FormFieldDef(label: "Customer", kind: FormFieldKind.text, name: "customerName"),
    ]),
  ]),
  "/hotel-restaurant-tables": FormDef(route: "/hotel-restaurant-tables", specKey: "hotel-restaurant-tables", sections: [
    FormSectionDef(title: "Add Table", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Table Number", kind: FormFieldKind.text, name: "tableNumber"),
      FormFieldDef(label: "Capacity", kind: FormFieldKind.number, name: "capacity"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
    ]),
  ]),
  "/hotel-rooms": FormDef(route: "/hotel-rooms", specKey: "hotel-rooms", sections: [
    FormSectionDef(title: "{editing ? `Edit Room \$` : \"Add Room\"}", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Room Number", kind: FormFieldKind.text, name: "roomNumber"),
      FormFieldDef(label: "Room Type", kind: FormFieldKind.select, name: "hotelRoomTypeId"),
      FormFieldDef(label: "Floor", kind: FormFieldKind.select, name: "hotelFloorId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
    ]),
  ]),
  "/hotel-setup": FormDef(route: "/hotel-setup", specKey: "hotel-setup-amenities", sections: [
    FormSectionDef(title: "Add Rate", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Rate Name", kind: FormFieldKind.text, name: "rateName"),
      FormFieldDef(label: "Room Type", kind: FormFieldKind.select, name: "hotelRoomTypeId"),
      FormFieldDef(label: "Rate", kind: FormFieldKind.number, name: "rate"),
      FormFieldDef(label: "Start Date", kind: FormFieldKind.date, name: "startDate"),
      FormFieldDef(label: "End Date", kind: FormFieldKind.date, name: "endDate"),
    ]),
  ]),
  "/houses": FormDef(route: "/houses", specKey: "house", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "House Name", kind: FormFieldKind.text),
      FormFieldDef(label: "Capacity (birds)", kind: FormFieldKind.number),
      FormFieldDef(label: "Location", kind: FormFieldKind.text),
    ]),
  ]),
  "/inventory": FormDef(route: "/inventory", specKey: "inventoryitem", sections: [
    FormSectionDef(title: "Add Inventory Item", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Item Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "category"),
      FormFieldDef(label: "Crates (30 eggs)", kind: FormFieldKind.number, name: "crates"),
      FormFieldDef(label: "Loose Eggs", kind: FormFieldKind.number, name: "looseEggs"),
      FormFieldDef(label: "Total Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text, name: "unit"),
      FormFieldDef(label: "Unit Price", kind: FormFieldKind.number, name: "unitPrice"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.text, name: "supplier"),
      FormFieldDef(label: "Location", kind: FormFieldKind.text, name: "location"),
      FormFieldDef(label: "Entry Date", kind: FormFieldKind.date, name: "entryDate"),
      FormFieldDef(label: "Expiry Date", kind: FormFieldKind.date, name: "expiryDate"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/poultry-daily-closing": FormDef(route: "/poultry-daily-closing", specKey: "poultry-daily-closings", sections: [
    FormSectionDef(title: "Closing \u2014 {v && }", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Actual cash counted (physical)", kind: FormFieldKind.number),
      FormFieldDef(label: "Manager notes", kind: FormFieldKind.textarea),
    ]),
  ]),
  "/poultry-employee-loans": FormDef(route: "/poultry-employee-loans", specKey: "employee-loans", sections: [
    FormSectionDef(title: "New loan or advance", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Employee", kind: FormFieldKind.select, name: "poultryStaffId"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "loanType"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "principalAmount"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "disbursementDate"),
      FormFieldDef(label: "How will it be repaid?", kind: FormFieldKind.select, name: "repaymentMethod"),
      FormFieldDef(label: "Suggested amount per payroll", kind: FormFieldKind.number, name: "defaultPayrollDeduction"),
      FormFieldDef(label: "Purpose", kind: FormFieldKind.text, name: "purpose"),
      FormFieldDef(label: "Charge interest", kind: FormFieldKind.bool, name: "interestEnabled"),
      FormFieldDef(label: "Interest amount", kind: FormFieldKind.number, name: "interestAmount"),
      FormFieldDef(label: "Hand the money over now", kind: FormFieldKind.bool, name: "disburseNow"),
      FormFieldDef(label: "Pay from", kind: FormFieldKind.select, name: "poultryCashAccountId"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "referenceNumber"),
    ]),
  ]),
  "/reset-password": FormDef(route: "/reset-password", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Reset Code", kind: FormFieldKind.text, name: "token"),
      FormFieldDef(label: "New Password", kind: FormFieldKind.text, name: "password"),
      FormFieldDef(label: "Confirm Password", kind: FormFieldKind.text, name: "confirmPassword"),
    ]),
  ]),
  "/resources": FormDef(route: "/resources", sections: [
    FormSectionDef(title: "Add Vaccination Schedule", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Vaccine Name", kind: FormFieldKind.text, name: "vaccineName"),
      FormFieldDef(label: "Age (Weeks)", kind: FormFieldKind.number, name: "ageInWeeks"),
      FormFieldDef(label: "Age (Days)", kind: FormFieldKind.number, name: "ageInDays"),
      FormFieldDef(label: "Dosage", kind: FormFieldKind.text, name: "dosage"),
      FormFieldDef(label: "Route", kind: FormFieldKind.text, name: "route"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
    ]),
  ]),
  "/restaurant-crm": FormDef(route: "/restaurant-crm", specKey: "restaurant-crm-customers", sections: [
    FormSectionDef(title: "Add Feedback", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Customer Name", kind: FormFieldKind.text, name: "customerName"),
      FormFieldDef(label: "Overall Rating", kind: FormFieldKind.text, name: "rating"),
      FormFieldDef(label: "Food", kind: FormFieldKind.select, name: "foodRating"),
      FormFieldDef(label: "Service", kind: FormFieldKind.select, name: "serviceRating"),
      FormFieldDef(label: "Ambience", kind: FormFieldKind.select, name: "ambienceRating"),
      FormFieldDef(label: "Comment", kind: FormFieldKind.textarea, name: "comment"),
    ]),
  ]),
  "/restaurant-delivery": FormDef(route: "/restaurant-delivery", specKey: "restaurant-delivery-drivers", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Vehicle", kind: FormFieldKind.select, name: "vehicleType"),
      FormFieldDef(label: "Plate", kind: FormFieldKind.text, name: "vehiclePlate"),
      FormFieldDef(label: "License", kind: FormFieldKind.text, name: "licenseNumber"),
    ]),
  ]),
  "/restaurant-events": FormDef(route: "/restaurant-events", specKey: "restaurant-events", sections: [
    FormSectionDef(title: "New Event", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Event Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "eventType"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "eventDate"),
      FormFieldDef(label: "Guest Count", kind: FormFieldKind.number, name: "guestCount"),
      FormFieldDef(label: "Start Time", kind: FormFieldKind.text, name: "startTime"),
      FormFieldDef(label: "End Time", kind: FormFieldKind.text, name: "endTime"),
      FormFieldDef(label: "Contact Name", kind: FormFieldKind.text, name: "contactName"),
      FormFieldDef(label: "Contact Phone", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Contact Email", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "Price per Head (\$)", kind: FormFieldKind.number, name: "pricePerHead"),
      FormFieldDef(label: "Deposit Amount (\$)", kind: FormFieldKind.number, name: "depositAmount"),
      FormFieldDef(label: "Venue", kind: FormFieldKind.select, name: "venue"),
      FormFieldDef(label: "Special Requests", kind: FormFieldKind.textarea, name: "specialRequests"),
      FormFieldDef(label: "Dietary Notes", kind: FormFieldKind.textarea, name: "dietaryNotes"),
    ]),
  ]),
  "/restaurant-expenses": FormDef(route: "/restaurant-expenses", specKey: "restaurant-expenses", sections: [
    FormSectionDef(title: "Record Expense", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "expenseDate"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "categoryId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.text, name: "supplierName"),
    ]),
  ]),
  "/restaurant-floor-plan": FormDef(route: "/restaurant-floor-plan", specKey: "restaurant-floor-floors", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Table Number", kind: FormFieldKind.text, name: "tableNumber"),
      FormFieldDef(label: "Display Name", kind: FormFieldKind.text, name: "tableName"),
      FormFieldDef(label: "Capacity", kind: FormFieldKind.number, name: "capacity"),
      FormFieldDef(label: "Shape", kind: FormFieldKind.select, name: "shape"),
      FormFieldDef(label: "Area", kind: FormFieldKind.select, name: "floorId"),
    ]),
  ]),
  "/restaurant-gift-cards": FormDef(route: "/restaurant-gift-cards", specKey: "restaurant-gift-cards", sections: [
    FormSectionDef(title: "Issue Gift Card", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Card Type", kind: FormFieldKind.select, name: "cardType"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "amount"),
      FormFieldDef(label: "Purchaser Name", kind: FormFieldKind.text, name: "purchaserName"),
      FormFieldDef(label: "Purchaser Phone", kind: FormFieldKind.text, name: "purchaserPhone"),
      FormFieldDef(label: "Recipient Name", kind: FormFieldKind.text, name: "recipientName"),
      FormFieldDef(label: "Recipient Email", kind: FormFieldKind.text, name: "recipientEmail"),
      FormFieldDef(label: "Personal Message", kind: FormFieldKind.textarea, name: "message"),
      FormFieldDef(label: "Expiry Date", kind: FormFieldKind.date, name: "expiryDate"),
    ]),
  ]),
  "/restaurant-inventory": FormDef(route: "/restaurant-inventory", specKey: "restaurant-inventory-ingredients", sections: [
    FormSectionDef(title: "Log Waste", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Ingredient", kind: FormFieldKind.select, name: "ingredientId"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Reason", kind: FormFieldKind.text, name: "reason"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/restaurant-loyalty": FormDef(route: "/restaurant-loyalty", specKey: "restaurant-loyalty-accounts", sections: [
    FormSectionDef(title: "Enroll New Member", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Customer Name", kind: FormFieldKind.text),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text),
      FormFieldDef(label: "Customer ID (optional)", kind: FormFieldKind.number),
    ]),
  ]),
  "/restaurant-menu": FormDef(route: "/restaurant-menu", specKey: "restaurant-menu-items", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Item Name", kind: FormFieldKind.select, name: "name"),
      FormFieldDef(label: "Category", kind: FormFieldKind.select, name: "menuCategoryId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, name: "description"),
      FormFieldDef(label: "Image (optional)", kind: FormFieldKind.text),
      FormFieldDef(label: "Selling Price", kind: FormFieldKind.number, name: "price"),
      FormFieldDef(label: "Cost Price", kind: FormFieldKind.number, name: "costPrice"),
      FormFieldDef(label: "Margin", kind: FormFieldKind.text),
      FormFieldDef(label: "Prep Time (min)", kind: FormFieldKind.number, name: "prepTime"),
      FormFieldDef(label: "Calories", kind: FormFieldKind.number, name: "calories"),
      FormFieldDef(label: "Spicy Level", kind: FormFieldKind.text, name: "spicyLevel"),
      FormFieldDef(label: "SKU", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Allergens", kind: FormFieldKind.text, name: "allergens"),
      FormFieldDef(label: "Ingredient", kind: FormFieldKind.select, name: "ingredientId"),
      FormFieldDef(label: "Qty", kind: FormFieldKind.number),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text),
      FormFieldDef(label: "Waste %", kind: FormFieldKind.number),
    ]),
  ]),
  "/restaurant-online-orders": FormDef(route: "/restaurant-online-orders", specKey: "restaurant-online-settings", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Code", kind: FormFieldKind.text, name: "code"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "discountType"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Value", kind: FormFieldKind.number, name: "discountValue"),
      FormFieldDef(label: "Min Order", kind: FormFieldKind.number, name: "minOrderAmount"),
      FormFieldDef(label: "Max Uses (0=\u221e)", kind: FormFieldKind.number, name: "maxUses"),
      FormFieldDef(label: "Valid From", kind: FormFieldKind.text, name: "validFrom"),
      FormFieldDef(label: "Valid Until", kind: FormFieldKind.text, name: "validUntil"),
      FormFieldDef(label: "Channel Restriction", kind: FormFieldKind.select, name: "channelRestriction"),
    ]),
  ]),
  "/restaurant-pos": FormDef(route: "/restaurant-pos", specKey: "restaurant-orders", sections: [
    FormSectionDef(title: "Process Payment", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.text),
      FormFieldDef(label: "Amount Received", kind: FormFieldKind.number),
      FormFieldDef(label: "Tip (optional)", kind: FormFieldKind.number),
    ]),
  ]),
  "/restaurant-reservations": FormDef(route: "/restaurant-reservations", specKey: "restaurant-reservations", sections: [
    FormSectionDef(title: "Add to Waitlist", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Guest Name", kind: FormFieldKind.text, name: "guestName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "guestPhone"),
      FormFieldDef(label: "Party Size", kind: FormFieldKind.number, name: "partySize"),
      FormFieldDef(label: "Est. Wait (min)", kind: FormFieldKind.number, name: "estimatedWaitMins"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/restaurant-setup": FormDef(route: "/restaurant-setup", specKey: "restaurant-setup-profile", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Group Name", kind: FormFieldKind.select, name: "name"),
      FormFieldDef(label: "Description", kind: FormFieldKind.text, name: "description"),
      FormFieldDef(label: "Customer must select", kind: FormFieldKind.text, name: "isRequired"),
      FormFieldDef(label: "Min selections", kind: FormFieldKind.number, name: "minSelections"),
      FormFieldDef(label: "Max selections", kind: FormFieldKind.number, name: "maxSelections"),
    ]),
  ]),
  "/restaurant-staff": FormDef(route: "/restaurant-staff", specKey: "restaurant-staff", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "First Name", kind: FormFieldKind.text, name: "firstName"),
      FormFieldDef(label: "Last Name", kind: FormFieldKind.text, name: "lastName"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "phone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "email"),
      FormFieldDef(label: "Role", kind: FormFieldKind.text, name: "role"),
      FormFieldDef(label: "Pay Type", kind: FormFieldKind.select, name: "salaryType"),
      FormFieldDef(label: "Base Pay", kind: FormFieldKind.number, name: "basePay"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text, name: "notes"),
    ]),
  ]),
  "/sales": FormDef(route: "/sales", specKey: "sales", sections: [
    FormSectionDef(title: "Create New Sale", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Sale Date", kind: FormFieldKind.date, name: "saleDate"),
      FormFieldDef(label: "Product", kind: FormFieldKind.select),
      FormFieldDef(label: "Customer Name", kind: FormFieldKind.select),
      FormFieldDef(label: "Flock", kind: FormFieldKind.select, name: "flockId"),
      FormFieldDef(label: "Crates (30 eggs)", kind: FormFieldKind.number),
      FormFieldDef(label: "Loose Eggs", kind: FormFieldKind.number),
      FormFieldDef(label: "Total Eggs", kind: FormFieldKind.text),
      FormFieldDef(label: "Calculated Amount", kind: FormFieldKind.number, name: "totalAmount"),
      FormFieldDef(label: "Override Amount", kind: FormFieldKind.number),
      FormFieldDef(label: "Payment Method", kind: FormFieldKind.select, name: "paymentMethod"),
      FormFieldDef(label: "Payment status", kind: FormFieldKind.text, name: "paid"),
      FormFieldDef(label: "Egg Size (optional)", kind: FormFieldKind.text, name: "size"),
      FormFieldDef(label: "Receive into cash account", kind: FormFieldKind.select, name: "poultryCashAccountId"),
      FormFieldDef(label: "Description", kind: FormFieldKind.textarea, name: "saleDescription"),
    ]),
  ]),
  "/suppliers": FormDef(route: "/suppliers", specKey: "supplier", sections: [
    FormSectionDef(title: "Add new supplier", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Business / name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Phone", kind: FormFieldKind.text, name: "contactPhone"),
      FormFieldDef(label: "Email", kind: FormFieldKind.text, name: "contactEmail"),
      FormFieldDef(label: "City", kind: FormFieldKind.text, name: "city"),
      FormFieldDef(label: "Full address", kind: FormFieldKind.text, name: "address"),
    ]),
  ]),
  "/supplies": FormDef(route: "/supplies", specKey: "inventoryitem", sections: [
    FormSectionDef(title: "Add Supply Item", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Item Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "type"),
      FormFieldDef(label: "Quantity", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text, name: "unit"),
      FormFieldDef(label: "Cost", kind: FormFieldKind.number, name: "cost"),
      FormFieldDef(label: "Supplier", kind: FormFieldKind.select, name: "supplierId"),
      FormFieldDef(label: "Purchase Date", kind: FormFieldKind.textarea, name: "purchaseDate"),
    ]),
  ]),
  "/test-email-confirmation": FormDef(route: "/test-email-confirmation", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Email Address", kind: FormFieldKind.text),
      FormFieldDef(label: "Confirmation Token", kind: FormFieldKind.text),
    ]),
  ]),
  "/water-daily-closing": FormDef(route: "/water-daily-closing", specKey: "water-daily-closings", sections: [
    FormSectionDef(title: "{view && ( Closing: {activeFarmName ? ` \u2014 \$` : \"\"} )}", color: "indigo", columns: 1, fields: [
      FormFieldDef(label: "Actual cash counted (physical)", kind: FormFieldKind.number, name: "actualCashCounted"),
      FormFieldDef(label: "Manager notes", kind: FormFieldKind.textarea, name: "managerNotes"),
    ]),
  ]),
  "/water-employee-loans": FormDef(route: "/water-employee-loans", sections: [
    FormSectionDef(title: "New loan or advance", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Employee", kind: FormFieldKind.select, name: "waterStaffId"),
      FormFieldDef(label: "Type", kind: FormFieldKind.select, name: "loanType"),
      FormFieldDef(label: "Amount", kind: FormFieldKind.number, name: "principalAmount"),
      FormFieldDef(label: "Date", kind: FormFieldKind.date, name: "disbursementDate"),
      FormFieldDef(label: "How will it be repaid?", kind: FormFieldKind.select, name: "repaymentMethod"),
      FormFieldDef(label: "Suggested amount per payroll", kind: FormFieldKind.number, name: "defaultPayrollDeduction"),
      FormFieldDef(label: "Purpose", kind: FormFieldKind.text, name: "purpose"),
      FormFieldDef(label: "Charge interest", kind: FormFieldKind.bool, name: "interestEnabled"),
      FormFieldDef(label: "Interest amount", kind: FormFieldKind.number, name: "interestAmount"),
      FormFieldDef(label: "Hand the money over now", kind: FormFieldKind.bool, name: "disburseNow"),
      FormFieldDef(label: "Pay from", kind: FormFieldKind.select, name: "waterCashAccountId"),
      FormFieldDef(label: "Reference", kind: FormFieldKind.text, name: "referenceNumber"),
    ]),
  ]),
  "/water-products/[id]": FormDef(route: "/water-products/[id]", specKey: "water-products", sections: [
    FormSectionDef(title: "Details", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Name", kind: FormFieldKind.text, name: "name"),
      FormFieldDef(label: "Product type", kind: FormFieldKind.select, name: "productType"),
      FormFieldDef(label: "SKU", kind: FormFieldKind.text, name: "sku"),
      FormFieldDef(label: "Unit", kind: FormFieldKind.text, name: "unit"),
      FormFieldDef(label: "Size (ml)", kind: FormFieldKind.number, name: "sizeMl"),
      FormFieldDef(label: "Unit price", kind: FormFieldKind.number, name: "unitPrice"),
      FormFieldDef(label: "Notes", kind: FormFieldKind.textarea, name: "notes"),
      FormFieldDef(label: "Sachets per bag", kind: FormFieldKind.number, name: "sachetsPerBag"),
      FormFieldDef(label: "Bag price", kind: FormFieldKind.number, name: "bagPrice"),
      FormFieldDef(label: "Sachet price", kind: FormFieldKind.number, name: "sachetPrice"),
    ]),
  ]),
  "/water-sales": FormDef(route: "/water-sales", specKey: "water-sales", sections: [
    FormSectionDef(title: "New water sale", color: "indigo", columns: 2, fields: [
      FormFieldDef(label: "Customer", kind: FormFieldKind.select, name: "waterCustomerId"),
      FormFieldDef(label: "Items", kind: FormFieldKind.text),
      FormFieldDef(label: "Product", kind: FormFieldKind.select, name: "waterProductId"),
      FormFieldDef(label: "Selling Unit", kind: FormFieldKind.select, name: "sellingUnit"),
      FormFieldDef(label: "Qty", kind: FormFieldKind.number, name: "quantity"),
      FormFieldDef(label: "Unit Price", kind: FormFieldKind.number, name: "unitPrice"),
      FormFieldDef(label: "Line Total", kind: FormFieldKind.text),
      FormFieldDef(label: "Payment status", kind: FormFieldKind.select),
      FormFieldDef(label: "Notes", kind: FormFieldKind.text),
    ]),
  ]),
};
