import '../models/company.dart';
import 'generated_pages.dart';
import 'page_spec.dart';
import 'poultry/poultry_labels.dart';
import 'web_nav.dart';
import 'web_page_design.dart';

/// Specs for the web's pages, keyed by the module key used in navigation.
///
/// This grows one page at a time. Every entry here is a page that really loads
/// its data; a module key with no entry still shows the "not built yet" screen,
/// so the app never pretends a page exists before it does.
///
/// Endpoints and field names are taken from the live dev API, not from the
/// swagger alone — several endpoints declare no response schema, and a few
/// (MainFlockBatch) reject requests that omit userId.
class PageRegistry {
  const PageRegistry._();

  /// Generated specs first, hand-written ones layered over them — so tuning a
  /// page here (better title field, friendlier labels) replaces the generated
  /// version without having to delete it.
  static final Map<String, PageSpec> _specs = {
    for (final s in generatedPages) s.key: s,
    for (final s in _all) s.key: s,
  };

  static PageSpec? of(String key) => _specs[key];
  static bool has(String key) => _specs.containsKey(key);
  static int get count => _specs.length;

  /// Which web page a spec is reached from. The design data is keyed by web
  /// route, the specs by API path, and the nav is the only thing that knows
  /// the two are the same page.
  static final Map<String, String> _hrefBySpec = {
    for (final groups in webNavGroups.values)
      for (final g in groups)
        for (final sub in g.subGroups)
          for (final l in sub.links)
            if (l.specKey != null) l.specKey!: l.href,
  };

  /// What the web page itself says it is called and shows — preferred over
  /// anything derived from an endpoint name.
  static PageDesign? designFor(String specKey) {
    final href = _hrefBySpec[specKey];
    return href == null ? null : webPageDesigns[href];
  }

  /// Whether this page was hand-tuned rather than generated.
  static bool isCurated(String key) => _all.any((s) => s.key == key);

  static String moduleOf(CompanyType type) => switch (type) {
        CompanyType.poultry => 'poultry',
        CompanyType.water => 'water',
        CompanyType.generic => 'generic',
        CompanyType.restaurant => 'restaurant',
        CompanyType.hotel => 'hotel',
        CompanyType.unknown => '',
      };

  /// Every page available for a company type, curated ones first, then the
  /// rest alphabetically. This is what "More" lists.
  static List<PageSpec> forCompany(CompanyType type) {
    final module = moduleOf(type);
    if (module.isEmpty) return const [];

    final curated = <PageSpec>[];
    final rest = <PageSpec>[];
    for (final s in _specs.values) {
      final belongs = s.module == module ||
          (s.module.isEmpty && s.key.startsWith(module)) ||
          (s.module.isEmpty && module == 'poultry' && !s.key.contains('-'));
      if (!belongs) continue;
      (isCurated(s.key) ? curated : rest).add(s);
    }
    curated.sort((a, b) => a.title.compareTo(b.title));
    rest.sort((a, b) => a.title.compareTo(b.title));
    return [...curated, ...rest];
  }

  static final List<PageSpec> _all = [
    // ---------------- Poultry ----------------
    // Flock Groups (/flocks) lists FLOCKS, from /api/Flock — as the web page
    // does. This key used to point at the batch list, while the Flock
    // Purchases (Batches) link pointed at the flocks: the two were swapped.
    const PageSpec(
      key: 'flocks', module: 'poultry',
      title: 'Flock Groups',
      path: '/api/Flock',
      needsUserId: true,
      titleField: 'name',
      searchFields: ['name', 'breed', 'batchName'],
      subtitleFields: [
        FieldSpec('quantity', 'Birds', kind: FieldKind.number),
        FieldSpec('breed', 'Breed'),
        FieldSpec('startDate', 'Started', kind: FieldKind.date),
      ],
      fields: [
        FieldSpec('batchName', 'Flock batch'),
        FieldSpec('breed', 'Breed'),
        FieldSpec('quantity', 'Number of birds', kind: FieldKind.number),
        FieldSpec('startDate', 'Start date', kind: FieldKind.date),
        FieldSpec('hasArrived', 'Has arrived', kind: FieldKind.boolean),
        FieldSpec('active', 'Active', kind: FieldKind.boolean),
        FieldSpec('inactivationReason', 'Inactivation reason'),
        FieldSpec('notes', 'Notes'),
      ],
      // The web's bird totals (app/flocks/page.tsx): arrived flocks only.
      // Its fourth tile, Total Birds Sold, is hard-coded to 0 there, so it is
      // left out rather than shown as a figure.
      summaries: [
        SummaryDef(label: 'Total Birds', op: SummaryOp.sum, field: 'quantity',
            where: {'hasArrived': true}),
        SummaryDef(label: 'Total Active Birds', op: SummaryOp.sum, field: 'quantity',
            tone: SummaryTone.positive, where: {'hasArrived': true, 'active': true}),
        SummaryDef(label: 'Total Inactive Birds', op: SummaryOp.sum, field: 'quantity',
            where: {'hasArrived': true, 'active': false}),
      ],
      emptyMessage: 'No flocks have been created for this farm.',
    ),
    // Users & Permissions (/employees): the web lists /Admin/employees on the
    // Login API, and creates/edits/deletes there too (EmployeeFormScreen).
    const PageSpec(
      key: 'admin-company-employees', module: 'poultry',
      title: 'Users & Permissions',
      path: '/api/Admin/employees',
      source: 'login',
      titleField: 'userName',
      searchFields: ['userName', 'firstName', 'lastName', 'email', 'phoneNumber'],
      subtitleFields: [
        FieldSpec('firstName', 'First name'),
        FieldSpec('lastName', 'Last name'),
        FieldSpec('email', 'Email'),
      ],
      fields: [
        FieldSpec('firstName', 'First name'),
        FieldSpec('lastName', 'Last name'),
        FieldSpec('email', 'Email'),
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('isAdmin', 'Administrator', kind: FieldKind.boolean),
        FieldSpec('createdDate', 'Created', kind: FieldKind.date),
      ],
      emptyMessage: 'No employees yet.',
    ),
    // Drivers (/poultry-drivers): the web lists employees-with-driver-role
    // plus legacy standalone drivers from /list-for-farm, and edits/deletes
    // through /drivers/{id}.
    const PageSpec(
      key: 'poultry-drivers', module: 'poultry',
      title: 'Drivers',
      path: '/api/Poultry/drivers/list-for-farm',
      writePath: '/api/Poultry/drivers',
      resolve: {
        'defaultVehicleName': ('defaultVehicleId', 'poultry-drivers.defaultVehicleId', vehicleOptionLabel),
      },
      titleField: 'driverName',
      statusField: 'isActive',
      searchFields: ['driverName', 'phoneNumber', 'licenseNumber'],
      subtitleFields: [
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('licenseNumber', 'License'),
      ],
      fields: [
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('licenseNumber', 'License'),
        FieldSpec('defaultVehicleName', 'Default vehicle'),
        FieldSpec('basePay', 'Base pay', kind: FieldKind.money),
        FieldSpec('commissionPerCrate', 'Commission per crate', kind: FieldKind.money),
        FieldSpec('isActive', 'Active', kind: FieldKind.boolean),
        FieldSpec('notes', 'Notes'),
      ],
      emptyMessage: 'No drivers yet. Add one to assign a vehicle.',
    ),
    // Vehicles (/poultry-vehicles): the web table's columns.
    const PageSpec(
      key: 'poultry-vehicles', module: 'poultry',
      title: 'Vehicles',
      path: '/api/Poultry/vehicles',
      titleField: 'vehicleName',
      statusField: 'status',
      searchFields: ['vehicleName', 'vehicleType', 'registrationNumber'],
      subtitleFields: [
        FieldSpec('vehicleType', 'Type'),
        FieldSpec('registrationNumber', 'Reg #'),
      ],
      fields: [
        FieldSpec('vehicleType', 'Type'),
        FieldSpec('registrationNumber', 'Reg #'),
        FieldSpec('capacityCrates', 'Capacity (crates)', kind: FieldKind.number),
        FieldSpec('fuelType', 'Fuel'),
        FieldSpec('status', 'Status'),
        FieldSpec('notes', 'Notes'),
      ],
      emptyMessage: 'No vehicles yet.',
    ),
    // Routes (/poultry-routes): the web table's columns, with the default
    // vehicle shown by name.
    PageSpec(
      key: 'poultry-routes', module: 'poultry',
      title: 'Routes',
      path: '/api/Poultry/routes',
      titleField: 'routeName',
      searchFields: ['routeName', 'areaCovered'],
      resolve: const {
        'defaultVehicleName': ('defaultVehicleId', 'poultry-routes.defaultVehicleId', null),
      },
      subtitleFields: const [
        FieldSpec('areaCovered', 'Area'),
        FieldSpec('defaultVehicleName', 'Default vehicle'),
      ],
      fields: const [
        FieldSpec('areaCovered', 'Area'),
        FieldSpec('defaultVehicleName', 'Default vehicle'),
        FieldSpec('expectedCustomers', 'Expected customers', kind: FieldKind.number),
        FieldSpec('expectedCratesSold', 'Expected crates', kind: FieldKind.number),
        FieldSpec('notes', 'Notes'),
      ],
      emptyMessage: 'No routes yet.',
    ),
    // Feed Formulas (/poultry-feed-formulas): the web's card shows the
    // finished feed and how many ingredients the formula has.
    const PageSpec(
      key: 'poultry-feed-formulas', module: 'poultry',
      title: 'Feed Formulas',
      path: '/api/Poultry/feed-formulas',
      titleField: 'formulaName',
      statusField: 'isActive',
      searchFields: ['formulaName', 'finishedFeedItemName'],
      subtitleFields: [
        FieldSpec('finishedFeedItemName', 'Finished feed'),
        FieldSpec('lineCount', 'Ingredients', kind: FieldKind.number),
      ],
      fields: [
        FieldSpec('finishedFeedItemName', 'Finished feed'),
        FieldSpec('defaultOutputUnit', 'Default output unit'),
        FieldSpec('lineCount', 'Ingredients', kind: FieldKind.number),
        FieldSpec('isActive', 'Active', kind: FieldKind.boolean),
        FieldSpec('notes', 'Notes'),
      ],
      emptyMessage: 'No feed formulas yet.',
    ),
    // Products (/poultry-products): the web's columns.
    const PageSpec(
      key: 'poultry-products', module: 'poultry',
      title: 'Products',
      path: '/api/Poultry/products',
      titleField: 'name',
      statusField: 'isActive',
      searchFields: ['name', 'sku', 'productType'],
      subtitleFields: [
        FieldSpec('productType', 'Type'),
        FieldSpec('unitPrice', 'Price', kind: FieldKind.money),
        FieldSpec('stockOnHand', 'In stock', kind: FieldKind.number),
      ],
      fields: [
        FieldSpec('productType', 'Type'),
        FieldSpec('unit', 'Unit'),
        FieldSpec('unitPrice', 'Price', kind: FieldKind.money),
        FieldSpec('stockOnHand', 'In stock', kind: FieldKind.number),
        FieldSpec('size', 'Size'),
        FieldSpec('sku', 'SKU'),
        FieldSpec('isActive', 'Active', kind: FieldKind.boolean),
      ],
      emptyMessage: 'No products yet.',
    ),
    // ---------------- Restaurant ----------------
    // Customers & CRM (/restaurant-crm), Customers tab, with the web's stat
    // cards worked out from the rows (the web reads /crm/customers/stats).
    const PageSpec(
      key: 'restaurant-crm-customers', module: 'restaurant',
      title: 'Customers & CRM',
      path: '/api/Restaurant/crm/customers',
      titleField: 'name',
      statusField: 'segment',
      searchFields: ['name', 'phone', 'email'],
      subtitleFields: [
        FieldSpec('phone', 'Phone'),
        FieldSpec('totalVisits', 'Visits', kind: FieldKind.number),
        FieldSpec('totalSpent', 'Spent', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('segment', 'Segment'),
        FieldSpec('phone', 'Phone'),
        FieldSpec('email', 'Email'),
        FieldSpec('dateOfBirth', 'Birthday', kind: FieldKind.date),
        FieldSpec('anniversary', 'Anniversary', kind: FieldKind.date),
        FieldSpec('dietaryPreferences', 'Dietary preferences'),
        FieldSpec('allergies', 'Allergies'),
        FieldSpec('totalVisits', 'Total visits', kind: FieldKind.number),
        FieldSpec('totalSpent', 'Total spent', kind: FieldKind.money),
        FieldSpec('avgTicket', 'Average ticket', kind: FieldKind.money),
        FieldSpec('lastVisit', 'Last visit', kind: FieldKind.date),
        FieldSpec('notes', 'Notes'),
      ],
      summaries: [
        SummaryDef(label: 'Total', op: SummaryOp.count),
        SummaryDef(label: 'New', op: SummaryOp.count, where: {'segment': 'New'}),
        SummaryDef(label: 'Regular', op: SummaryOp.count, where: {'segment': 'Regular'}),
        SummaryDef(label: 'VIP', op: SummaryOp.count, where: {'segment': 'VIP'}),
        SummaryDef(label: 'Lifetime Value', op: SummaryOp.sum, field: 'totalSpent', money: true),
      ],
      emptyMessage: 'No customers yet.',
    ),
    // Suppliers (/restaurant-suppliers). Rows come back with raw lowercase
    // column names, hence `contactname` / `isactive`.
    const PageSpec(
      key: 'restaurant-setup-suppliers', module: 'restaurant',
      title: 'Suppliers',
      path: '/api/Restaurant/setup/suppliers',
      titleField: 'name',
      searchFields: ['name', 'email', 'phone', 'category', 'address'],
      subtitleFields: [
        FieldSpec('category', 'Category'),
        FieldSpec('phone', 'Phone'),
      ],
      fields: [
        FieldSpec('category', 'Category'),
        FieldSpec('contactname', 'Contact person'),
        FieldSpec('phone', 'Phone'),
        FieldSpec('email', 'Email'),
        FieldSpec('address', 'Address'),
        FieldSpec('isactive', 'Active', kind: FieldKind.boolean),
      ],
      emptyMessage: 'No suppliers yet.',
    ),
    const PageSpec(
      key: 'flock', module: 'poultry',
      title: 'Flock Purchases (Batches)',
      path: '/api/MainFlockBatch',
      needsUserId: true, // 400s without it
      titleField: 'batchName',
      statusField: 'status',
      searchFields: ['batchName', 'batchCode', 'breed'],
      subtitleFields: [
        FieldSpec('batchCode', 'Code'),
        FieldSpec('numberOfBirds', 'Birds', kind: FieldKind.number),
        FieldSpec('breed', 'Breed'),
      ],
      fields: [
        FieldSpec('batchCode', 'Batch code'),
        FieldSpec('breed', 'Breed'),
        FieldSpec('numberOfBirds', 'Number of birds', kind: FieldKind.number),
        FieldSpec('startDate', 'Start date', kind: FieldKind.date),
        FieldSpec('costPerChick', 'Cost per chick', kind: FieldKind.money),
        FieldSpec('totalCost', 'Total cost', kind: FieldKind.money),
        FieldSpec('amountPaid', 'Amount paid', kind: FieldKind.money),
        FieldSpec('supplierType', 'Supplier type'),
      ],
      emptyMessage: 'No flock batches have been created for this farm.',
    ),
    const PageSpec(
      key: 'production-records', module: 'poultry',
      title: 'Production records',
      // Matching the web's own tiles on /production-records.
      summaries: [
        SummaryDef(
            label: 'Total eggs',
            op: SummaryOp.sum,
            field: 'eggCount',
            tone: SummaryTone.positive,
            crates: 30),
        SummaryDef(
            label: 'Avg / record', op: SummaryOp.average, field: 'eggCount'),
        SummaryDef(label: 'Feed (kg)', op: SummaryOp.sum, field: 'feedKg'),
        SummaryDef(
            label: 'Total deaths',
            op: SummaryOp.sum,
            field: 'mortality',
            tone: SummaryTone.negative,
            sub: 'all logs'),
        SummaryDef(
            label: 'Birds left',
            op: SummaryOp.latest,
            field: 'noOfBirdsLeft',
            tone: SummaryTone.positive),
        SummaryDef(label: 'Records', op: SummaryOp.count),
      ],
      path: '/api/ProductionRecord',
      needsUserId: true,
      titleField: 'date',
      searchFields: ['date'],
      subtitleFields: [
        FieldSpec('eggCount', 'Eggs', kind: FieldKind.number),
        FieldSpec('mortality', 'Mortality', kind: FieldKind.number),
        FieldSpec('feedKg', 'Feed', kind: FieldKind.number, suffix: 'kg'),
      ],
      // The full record, not a subset. A production log carries six pick
      // times plus broken eggs and the flock it belongs to; listing only
      // eight fields made the detail and the form look far emptier than the
      // data actually is.
      fields: [
        FieldSpec('date', 'Date', kind: FieldKind.date),
        FieldSpec('flockId', 'Flock', kind: FieldKind.number),
        FieldSpec('ageInWeeks', 'Age (weeks)', kind: FieldKind.number),
        FieldSpec('ageInDays', 'Age (days)', kind: FieldKind.number),
        FieldSpec('noOfBirds', 'Birds', kind: FieldKind.number),
        FieldSpec('mortality', 'Mortality', kind: FieldKind.number),
        FieldSpec('noOfBirdsLeft', 'Birds left', kind: FieldKind.number),
        FieldSpec('feedKg', 'Feed (kg)', kind: FieldKind.number),
        FieldSpec('medication', 'Medication'),
        FieldSpec('production9AM', '1st pick (9am)', kind: FieldKind.number),
        FieldSpec('production12PM', '2nd pick (12pm)', kind: FieldKind.number),
        FieldSpec('production4PM', '3rd pick (4pm)', kind: FieldKind.number),
        FieldSpec('production4thPick', '4th pick', kind: FieldKind.number),
        FieldSpec('production5thPick', '5th pick', kind: FieldKind.number),
        FieldSpec('production6thPick', '6th pick', kind: FieldKind.number),
        FieldSpec('brokenEggs', 'Broken eggs', kind: FieldKind.number),
        FieldSpec('totalProduction', 'Total production', kind: FieldKind.number),
        FieldSpec('eggCount', 'Egg count', kind: FieldKind.number),
      ],
    ),
    const PageSpec(
      key: 'sales', module: 'poultry',
      title: 'Sales',
      path: '/api/Sale',
      needsUserId: true,
      titleField: 'customerName',
      statusField: 'status',
      searchFields: ['customerName', 'productName'],
      subtitleFields: [
        FieldSpec('saleDate', 'Date', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('saleDate', 'Sale date', kind: FieldKind.date),
        FieldSpec('customerName', 'Customer'),
        FieldSpec('productName', 'Product'),
        FieldSpec('quantity', 'Quantity', kind: FieldKind.number),
        FieldSpec('unitPrice', 'Unit price', kind: FieldKind.money),
        FieldSpec('totalAmount', 'Total amount', kind: FieldKind.money),
        FieldSpec('amountPaid', 'Amount paid', kind: FieldKind.money),
        FieldSpec('paymentMethod', 'Payment method'),
      ],
    ),
    const PageSpec(
      key: 'expenses', module: 'poultry',
      title: 'Expenses',
      path: '/api/Expense',
      needsUserId: true,
      titleField: 'description',
      searchFields: ['description', 'category', 'supplier'],
      subtitleFields: [
        FieldSpec('expenseDate', 'Date', kind: FieldKind.date),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
        FieldSpec('category', 'Category'),
      ],
      fields: [
        FieldSpec('expenseDate', 'Date', kind: FieldKind.date),
        FieldSpec('category', 'Category'),
        FieldSpec('description', 'Description'),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
        FieldSpec('amountPaid', 'Amount paid', kind: FieldKind.money),
        FieldSpec('paymentMethod', 'Payment method'),
        FieldSpec('supplier', 'Supplier'),
      ],
    ),
    const PageSpec(
      key: 'raw-materials', module: 'poultry',
      title: 'Raw materials',
      path: '/api/Poultry/raw-material-items',
      titleField: 'itemName',
      searchFields: ['itemName', 'category'],
      subtitleFields: [
        FieldSpec('currentQuantity', 'In stock', kind: FieldKind.number),
        FieldSpec('unit', 'Unit'),
      ],
      fields: [
        FieldSpec('itemName', 'Item'),
        FieldSpec('category', 'Category'),
        FieldSpec('currentQuantity', 'Current quantity', kind: FieldKind.number),
        FieldSpec('unit', 'Unit'),
        FieldSpec('reorderLevel', 'Reorder level', kind: FieldKind.number),
      ],
    ),
    const PageSpec(
      key: 'loans', module: 'poultry',
      title: 'Loans',
      path: '/api/Poultry/loans',
      titleField: 'lenderName',
      statusField: 'status',
      searchFields: ['lenderName'],
      subtitleFields: [
        FieldSpec('principal', 'Principal', kind: FieldKind.money),
        FieldSpec('outstanding', 'Outstanding', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('lenderName', 'Lender'),
        FieldSpec('principal', 'Principal', kind: FieldKind.money),
        FieldSpec('outstanding', 'Outstanding', kind: FieldKind.money),
        FieldSpec('interestRate', 'Interest rate'),
        FieldSpec('startDate', 'Start date', kind: FieldKind.date),
        FieldSpec('dueDate', 'Due date', kind: FieldKind.date),
      ],
    ),
    const PageSpec(
      key: 'employee-loans', module: 'poultry',
      title: 'Employee advances',
      path: '/api/Poultry/employee-loans',
      itemsAt: 'items',
      titleField: 'employeeName',
      statusField: 'status',
      searchFields: ['employeeName'],
      subtitleFields: [
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('employeeName', 'Employee'),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
        FieldSpec('issueDate', 'Issued', kind: FieldKind.date),
      ],
    ),
    const PageSpec(
      key: 'owner-money', module: 'poultry',
      title: 'Owner money',
      path: '/api/Poultry/owner-money',
      titleField: 'description',
      searchFields: ['description', 'type'],
      subtitleFields: [
        FieldSpec('date', 'Date', kind: FieldKind.date),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('date', 'Date', kind: FieldKind.date),
        FieldSpec('type', 'Type'),
        FieldSpec('description', 'Description'),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'assets', module: 'poultry',
      title: 'Capital assets',
      path: '/api/Poultry/assets',
      titleField: 'assetName',
      statusField: 'status',
      searchFields: ['assetName', 'category'],
      subtitleFields: [
        FieldSpec('purchaseCost', 'Cost', kind: FieldKind.money),
        FieldSpec('category', 'Category'),
      ],
      fields: [
        FieldSpec('assetName', 'Asset'),
        FieldSpec('category', 'Category'),
        FieldSpec('purchaseCost', 'Purchase cost', kind: FieldKind.money),
        FieldSpec('purchaseDate', 'Purchased', kind: FieldKind.date),
        FieldSpec('usefulLifeYears', 'Useful life (years)', kind: FieldKind.number),
      ],
    ),

    // ---------------- Water ----------------
    const PageSpec(
      key: 'water-sales', module: 'water',
      title: 'Sales',
      path: '/api/Water/sales',
      titleField: 'customerName',
      statusField: 'status',
      searchFields: ['customerName'],
      subtitleFields: [
        FieldSpec('saleDate', 'Date', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('saleDate', 'Date', kind: FieldKind.date),
        FieldSpec('customerName', 'Customer'),
        FieldSpec('quantity', 'Quantity', kind: FieldKind.number),
        FieldSpec('unitPrice', 'Unit price', kind: FieldKind.money),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
        FieldSpec('amountPaid', 'Paid', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'water-customers', module: 'water',
      title: 'Customers',
      path: '/api/Water/customers',
      titleField: 'customerName',
      searchFields: ['customerName', 'phoneNumber'],
      subtitleFields: [
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('customerName', 'Name'),
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('location', 'Location'),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'water-expenses', module: 'water',
      title: 'Expenses',
      path: '/api/Water/expenses',
      titleField: 'description',
      statusField: 'status',
      searchFields: ['description', 'categoryName'],
      subtitleFields: [
        FieldSpec('expenseDate', 'Date', kind: FieldKind.date),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('expenseDate', 'Date', kind: FieldKind.date),
        FieldSpec('categoryName', 'Category'),
        FieldSpec('description', 'Description'),
        FieldSpec('amount', 'Amount', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'water-cash-accounts', module: 'water',
      title: 'Cash accounts',
      path: '/api/Water/cash-accounts',
      titleField: 'accountName',
      searchFields: ['accountName'],
      subtitleFields: [
        FieldSpec('currentBalance', 'Balance', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('accountName', 'Account'),
        FieldSpec('accountType', 'Type'),
        FieldSpec('currentBalance', 'Current balance', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'water-staff', module: 'water',
      title: 'Staff',
      path: '/api/Water/staff',
      titleField: 'fullName',
      statusField: 'status',
      searchFields: ['fullName', 'role'],
      subtitleFields: [
        FieldSpec('role', 'Role'),
        FieldSpec('phoneNumber', 'Phone'),
      ],
      fields: [
        FieldSpec('fullName', 'Name'),
        FieldSpec('role', 'Role'),
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('dateJoined', 'Joined', kind: FieldKind.date),
      ],
    ),
    const PageSpec(
      key: 'water-maintenance', module: 'water',
      title: 'Maintenance',
      path: '/api/Water/maintenance-logs',
      titleField: 'assetName',
      statusField: 'status',
      searchFields: ['assetName', 'assetType'],
      subtitleFields: [
        FieldSpec('serviceDate', 'Date', kind: FieldKind.date),
        FieldSpec('repairCost', 'Cost', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('assetName', 'Asset'),
        FieldSpec('assetType', 'Type'),
        FieldSpec('serviceDate', 'Service date', kind: FieldKind.date),
        FieldSpec('repairCost', 'Repair cost', kind: FieldKind.money),
        FieldSpec('notes', 'Notes'),
      ],
    ),

    // ---------------- Restaurant ----------------
    const PageSpec(
      key: 'restaurant-orders', module: 'restaurant',
      title: 'Orders',
      path: '/api/Restaurant/orders',
      titleField: 'orderNumber',
      statusField: 'status',
      searchFields: ['orderNumber', 'customerName'],
      subtitleFields: [
        FieldSpec('orderDate', 'Date', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('orderNumber', 'Order'),
        FieldSpec('customerName', 'Customer'),
        FieldSpec('orderDate', 'Date', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
        FieldSpec('channel', 'Channel'),
      ],
    ),
    const PageSpec(
      key: 'restaurant-menu', module: 'restaurant',
      title: 'Menu',
      path: '/api/Restaurant/menu/items',
      titleField: 'itemName',
      searchFields: ['itemName', 'categoryName'],
      subtitleFields: [
        FieldSpec('price', 'Price', kind: FieldKind.money),
        FieldSpec('categoryName', 'Category'),
      ],
      fields: [
        FieldSpec('itemName', 'Item'),
        FieldSpec('categoryName', 'Category'),
        FieldSpec('price', 'Price', kind: FieldKind.money),
        FieldSpec('isAvailable', 'Available', kind: FieldKind.boolean),
      ],
    ),

    // ---------------- Hotel ----------------
    const PageSpec(
      key: 'hotel-rooms', module: 'hotel',
      title: 'Rooms',
      path: '/api/Hotel/rooms',
      titleField: 'roomNumber',
      statusField: 'status',
      searchFields: ['roomNumber', 'roomType'],
      subtitleFields: [
        FieldSpec('roomType', 'Type'),
        FieldSpec('rate', 'Rate', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('roomNumber', 'Room'),
        FieldSpec('roomType', 'Type'),
        FieldSpec('rate', 'Rate', kind: FieldKind.money),
        FieldSpec('floor', 'Floor'),
      ],
    ),
    const PageSpec(
      key: 'hotel-bookings', module: 'hotel',
      title: 'Bookings',
      path: '/api/Hotel/bookings',
      titleField: 'guestName',
      statusField: 'status',
      searchFields: ['guestName', 'roomNumber'],
      subtitleFields: [
        FieldSpec('checkInDate', 'Check-in', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('guestName', 'Guest'),
        FieldSpec('roomNumber', 'Room'),
        FieldSpec('checkInDate', 'Check-in', kind: FieldKind.date),
        FieldSpec('checkOutDate', 'Check-out', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
    ),

    // ---------------- Generic ----------------
    const PageSpec(
      key: 'generic-sales', module: 'generic',
      title: 'Sales',
      path: '/api/generic-company/{farmId}/sales',
      needsFarmId: false,
      titleField: 'customerName',
      statusField: 'status',
      searchFields: ['customerName'],
      subtitleFields: [
        FieldSpec('saleDate', 'Date', kind: FieldKind.date),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('saleDate', 'Date', kind: FieldKind.date),
        FieldSpec('customerName', 'Customer'),
        FieldSpec('totalAmount', 'Total', kind: FieldKind.money),
      ],
    ),
    const PageSpec(
      key: 'generic-products', module: 'generic',
      title: 'Products',
      path: '/api/generic-company/{farmId}/products',
      needsFarmId: false,
      titleField: 'productName',
      searchFields: ['productName', 'category'],
      subtitleFields: [
        FieldSpec('sellingPrice', 'Price', kind: FieldKind.money),
        FieldSpec('stockQuantity', 'Stock', kind: FieldKind.number),
      ],
      fields: [
        FieldSpec('productName', 'Product'),
        FieldSpec('category', 'Category'),
        FieldSpec('sellingPrice', 'Selling price', kind: FieldKind.money),
        FieldSpec('stockQuantity', 'Stock', kind: FieldKind.number),
      ],
    ),
    const PageSpec(
      key: 'generic-customers', module: 'generic',
      title: 'Customers',
      path: '/api/generic-company/{farmId}/customers',
      needsFarmId: false,
      titleField: 'customerName',
      searchFields: ['customerName', 'phoneNumber'],
      subtitleFields: [
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
      ],
      fields: [
        FieldSpec('customerName', 'Name'),
        FieldSpec('phoneNumber', 'Phone'),
        FieldSpec('balance', 'Balance', kind: FieldKind.money),
      ],
    ),
  ];
}
