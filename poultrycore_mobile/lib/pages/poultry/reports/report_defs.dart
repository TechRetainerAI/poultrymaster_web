// The Advanced Poultry Reports, one definition each: summary cards, table
// columns, filters, and the optional breakdown / analysis. A port of the web's
// `lib/reports/poultry-report-defs.ts`, card for card and column for column.

import 'report_format.dart';

typedef SummaryFn = String Function(Map s, FmtCtx c);
typedef CellFn = String Function(Map r, FmtCtx c);

/// green | rose | indigo, or null for the neutral amber rail.
typedef AccentFn = String? Function(Map s);

class CardDef {
  const CardDef(this.label, this.value, {this.accent, this.accentOf, this.note});
  final String label;
  final SummaryFn value;
  final String? accent;
  final AccentFn? accentOf;

  /// A scope caveat printed under the value.
  final String? note;

  String? accentFor(Map s) => accentOf?.call(s) ?? accent;
}

class ColumnDef {
  const ColumnDef(this.header, this.cell, {this.right = false, this.badge = false, this.total});
  final String header;
  final CellFn cell;
  final bool right;
  final bool badge;

  /// This column's cell in the pinned totals row; none prints "—".
  final String Function(List<Map> rows, FmtCtx c)? total;
}

class BreakdownBar {
  const BreakdownBar(this.label, this.value, this.percent);
  final String label;
  final SummaryFn value;
  final num? Function(Map s) percent;
}

class BreakdownGroup {
  const BreakdownGroup({required this.title, required this.green, this.total, required this.items});
  final String title;

  /// Emerald bars when true, rose when false.
  final bool green;
  final SummaryFn? total;
  final List<BreakdownBar> Function(Map s) items;
}

class AnalysisDef {
  const AnalysisDef(this.title, this.items);
  final String title;
  final List<AnalysisItem> Function(Map s, String Function(num) fmt) items;
}

class ReportFilters {
  const ReportFilters({
    this.flock = false,
    this.customer = false,
    this.supplier = false,
    this.category = false,
    this.includeClosedFlocks = false,
  });
  final bool flock, customer, supplier, category, includeClosedFlocks;
}

class PoultryReportDef {
  const PoultryReportDef({
    required this.slug,
    required this.title,
    required this.description,
    this.filters = const ReportFilters(),
    required this.cards,
    required this.columns,
    this.breakdown,
    this.analysis,
    this.tableAsCards = false,
    this.cardRowLabel,
  });
  final String slug;
  final String title;
  final String description;
  final ReportFilters filters;
  final List<CardDef> cards;
  final List<ColumnDef> columns;
  final List<BreakdownGroup>? breakdown;
  final AnalysisDef? analysis;

  /// Rows as Revenue / Expenses-details scorecards instead of a table.
  final bool tableAsCards;
  final String? cardRowLabel;
}

/// reportTotalsRow: the pinned totals, or null when no column defines one.
List<String>? reportTotalsRow(List<ColumnDef> columns, List<Map> rows, FmtCtx c) {
  if (rows.isEmpty || !columns.any((x) => x.total != null)) return null;
  return [for (final x in columns) x.total == null ? '—' : x.total!(rows, c)];
}

/// sumOf: adds one numeric field across the rows.
String Function(List<Map>, FmtCtx) sumOf(String field) =>
    (rows, c) => c.number(rows.fold<num>(0, (t, r) => t + toNum(r[field])));

String? _profitAccent(Object? n) => toNum(n) >= 0 ? 'green' : 'rose';
num? _pctOf(Object? part, Object? whole) => toNum(whole) == 0 ? null : toNum(part) / toNum(whole) * 100;

List<BreakdownBar> _bars(Object? list) => [
      for (final b in buckets(list)) BreakdownBar(b.label, (s, c) => c.money(b.amount), (s) => b.sharePercent),
    ];

// Column helpers keep the table definitions readable.
ColumnDef _text(String h, String f, {bool badge = false}) => ColumnDef(h, (r, c) => c.text(r[f]), badge: badge);
ColumnDef _date(String h, String f) => ColumnDef(h, (r, c) => c.date(r[f]));
ColumnDef _number(String h, String f, {bool total = false}) =>
    ColumnDef(h, (r, c) => c.number(r[f]), right: true, total: total ? sumOf(f) : null);
ColumnDef _money(String h, String f) => ColumnDef(h, (r, c) => c.money(r[f]), right: true);
ColumnDef _pct(String h, String f) => ColumnDef(h, (r, c) => c.pct(r[f]), right: true);
ColumnDef _yesNo(String h, String f) => ColumnDef(h, (r, c) => r[f] == true ? 'Yes' : 'No');

CardDef _cNum(String l, String f, {String? accent}) => CardDef(l, (s, c) => c.number(s[f]), accent: accent);
CardDef _cMoney(String l, String f, {String? accent, String? note}) =>
    CardDef(l, (s, c) => c.money(s[f]), accent: accent, note: note);
CardDef _cPct(String l, String f, {String? accent}) => CardDef(l, (s, c) => c.pct(s[f]), accent: accent);
CardDef _cText(String l, String f) => CardDef(l, (s, c) => c.text(s[f]));
CardDef _cDay(String l, String day, String count) => CardDef(l, (s, c) => '${c.date(s[day])} (${c.number(s[count])})');
CardDef _cProfit(String l, String f) => CardDef(l, (s, c) => c.money(s[f]), accentOf: (s) => _profitAccent(s[f]));

const _revenueBreakdownTitle = 'Revenue breakdown';

List<BreakdownGroup> _plBreakdown() => [
      BreakdownGroup(
        title: _revenueBreakdownTitle,
        green: true,
        total: (s, c) => c.money(s['totalRevenue']),
        items: (s) => [
          BreakdownBar('Egg sales', (s, c) => c.money(s['eggRevenue']), (s) => _pctOf(s['eggRevenue'], s['totalRevenue'])),
          BreakdownBar('Bird sales', (s, c) => c.money(s['birdSalesRevenue']),
              (s) => _pctOf(s['birdSalesRevenue'], s['totalRevenue'])),
          BreakdownBar(
              'Other revenue', (s, c) => c.money(s['otherRevenue']), (s) => _pctOf(s['otherRevenue'], s['totalRevenue'])),
        ],
      ),
      BreakdownGroup(
        title: 'Expense breakdown',
        green: false,
        total: (s, c) => c.money(s['totalExpenses']),
        items: (s) => [
          BreakdownBar('Feed', (s, c) => c.money(s['feedCost']), (s) => _pctOf(s['feedCost'], s['totalExpenses'])),
          BreakdownBar('Medicine & vaccines', (s, c) => c.money(s['medicineVaccineCost']),
              (s) => _pctOf(s['medicineVaccineCost'], s['totalExpenses'])),
          BreakdownBar('Labour', (s, c) => c.money(s['laborCost']), (s) => _pctOf(s['laborCost'], s['totalExpenses'])),
          BreakdownBar(
              'Other expenses', (s, c) => c.money(s['otherExpenses']), (s) => _pctOf(s['otherExpenses'], s['totalExpenses'])),
        ],
      ),
    ];

final Map<String, PoultryReportDef> poultryReportDefs = {
  'farm-summary': PoultryReportDef(
    slug: 'farm-summary',
    title: 'Poultry Farm Summary Report',
    description: 'High-level snapshot of poultry operations for the selected period.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cNum('Total eggs produced', 'totalEggsProduced'),
      _cNum('Saleable eggs', 'saleableEggs', accent: 'green'),
      _cNum('Broken / rejected', 'brokenRejectedEggs', accent: 'rose'),
      _cNum('Active flocks', 'activeFlocks'),
      _cNum('Active birds', 'activeBirds'),
      _cNum('Deaths', 'deaths', accent: 'rose'),
      _cNum('Feed consumed (kg)', 'feedConsumedKg'),
      _cMoney('Sales revenue', 'salesRevenue', accent: 'green'),
      _cMoney('Expenses', 'expenses', accent: 'rose'),
      _cProfit('Estimated profit', 'estimatedProfit'),
      _cMoney('Cash collected', 'cashCollected'),
      _cMoney('Customer receivables', 'customerReceivables'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _number('Starting birds', 'startingBirds'),
      _number('Current birds', 'currentBirds'),
      _number('Eggs', 'eggsProduced'),
      _number('Broken/rej.', 'brokenRejectedEggs'),
      _pct('Prod. %', 'eggProductionPercent'),
      _number('Feed (kg)', 'feedConsumedKg'),
      _number('Deaths', 'deaths'),
      _money('Sales', 'salesRevenue'),
      _money('Expenses', 'expensesAllocated'),
      _money('Profit/Loss', 'estimatedProfit'),
    ],
  ),
  'daily-egg-production': PoultryReportDef(
    slug: 'daily-egg-production',
    title: 'Poultry Daily Egg Production Report',
    description: 'Egg production by day and flock, including collection times and breakages.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cNum('Total eggs', 'totalEggs', accent: 'green'),
      _cNum('Avg eggs / day', 'averageEggsPerDay'),
      _cDay('Best day', 'bestProductionDay', 'bestProductionDayEggs'),
      _cDay('Lowest day', 'lowestProductionDay', 'lowestProductionDayEggs'),
      _cNum('Total broken eggs', 'totalBrokenEggs', accent: 'rose'),
      _cPct('Avg production %', 'averageProductionPercent'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _number('Age (wks)', 'ageInWeeks'),
      _number('1st Pick', 'morningEggs'),
      _number('2nd Pick', 'middayEggs'),
      _number('3rd Pick', 'eveningEggs'),
      _number('4th Pick', 'fourthPickEggs'),
      _number('5th Pick', 'fifthPickEggs'),
      _number('6th Pick', 'sixthPickEggs'),
      _number('Total eggs', 'totalEggs'),
      _number('Broken', 'brokenEggs'),
      _number('Saleable', 'saleableEggs'),
      _pct('Prod. %', 'eggProductionPercent'),
      _text('Notes', 'notes'),
    ],
  ),
  'flock-production-summary': PoultryReportDef(
    slug: 'flock-production-summary',
    title: 'Poultry Flock Production Summary Report',
    description: 'Compare production performance across flocks.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cNum('Active flocks', 'activeFlocks'),
      _cText('Best producing flock', 'bestProducingFlock'),
      _cText('Lowest producing flock', 'lowestProducingFlock'),
      _cNum('Total eggs', 'totalEggs', accent: 'green'),
      _cNum('Avg eggs / flock', 'averageEggsPerFlock'),
      _cPct('Avg production %', 'averageProductionPercent'),
    ],
    columns: [
      ColumnDef('Flock', (r, c) => c.text(r['flockName']),
          total: (rows, c) => 'Total — ${rows.length} flock${rows.length == 1 ? '' : 's'}'),
      _number('Age (wks)', 'flockAgeWeeks'),
      _number('Birds placed', 'birdsPlaced', total: true),
      _number('Current birds', 'currentBirds', total: true),
      _number('Total eggs', 'totalEggs', total: true),
      _number('Avg daily', 'averageDailyEggs', total: true),
      _number('Peak daily', 'peakDailyEggs'),
      _number('Broken', 'brokenEggs', total: true),
      _pct('Prod. %', 'productionPercent'),
      _number('Feed (kg)', 'feedConsumedKg', total: true),
      _number('Deaths', 'deaths', total: true),
      _text('Status', 'status', badge: true),
    ],
  ),
  'hen-day-production': PoultryReportDef(
    slug: 'hen-day-production',
    title: 'Poultry Hen-Day Production Report',
    description: 'Production relative to live birds (eggs ÷ live birds × 100).',
    filters: const ReportFilters(flock: true),
    cards: [
      _cPct('Avg hen-day %', 'averageHenDayPercent', accent: 'green'),
      _cPct('Highest hen-day %', 'highestHenDayPercent'),
      _cPct('Lowest hen-day %', 'lowestHenDayPercent', accent: 'rose'),
      _cNum('Flocks below target', 'flocksBelowTarget'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _number('Live birds', 'liveBirds'),
      _number('Eggs', 'eggsProduced'),
      _pct('Hen-day %', 'henDayPercent'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'mortality': PoultryReportDef(
    slug: 'mortality',
    title: 'Poultry Mortality Report',
    description: 'Bird deaths, daily and cumulative mortality percentages.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cNum('Total deaths', 'totalDeaths', accent: 'rose'),
      _cNum('Avg daily deaths', 'averageDailyDeaths'),
      _cDay('Highest mortality day', 'highestMortalityDay', 'highestMortalityDayDeaths'),
      _cPct('Cumulative mortality %', 'cumulativeMortalityPercent', accent: 'rose'),
      _cNum('Flocks with high mortality', 'flocksWithHighMortality'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _number('Opening birds', 'openingBirds'),
      _number('Deaths', 'deaths'),
      _number('Closing birds', 'closingBirds'),
      _pct('Daily mort. %', 'dailyMortalityPercent'),
      _pct('Cumulative %', 'cumulativeMortalityPercent'),
      _text('Notes', 'notes'),
    ],
  ),
  'birds-on-hand': PoultryReportDef(
    slug: 'birds-on-hand',
    title: 'Poultry Birds on Hand Report',
    description: 'Current bird count and reconciliation by flock.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cNum('Total birds placed', 'totalBirdsPlaced'),
      _cNum('Current live birds', 'currentLiveBirds', accent: 'green'),
      _cNum('Total deaths', 'totalDeaths', accent: 'rose'),
      _cNum('Total culls', 'totalCulls'),
      _cNum('Sold / transferred out', 'totalBirdsSoldTransferred'),
      _cNum('Bird variance', 'birdVariance'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _number('Placed', 'birdsPlaced'),
      _number('Transfers in', 'transfersIn'),
      _number('Deaths', 'deaths'),
      _number('Culls', 'culls'),
      _number('Sold', 'birdsSold'),
      _number('Transfers out', 'transfersOut'),
      _number('Expected', 'expectedBirdsOnHand'),
      _number('Recorded', 'currentRecordedBirds'),
      _number('Variance', 'variance'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'feed-usage': PoultryReportDef(
    slug: 'feed-usage',
    title: 'Poultry Feed Usage Report',
    description: 'Feed consumed by flock, date and feed type.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cNum('Total feed consumed (kg)', 'totalFeedConsumedKg'),
      _cNum('Avg feed / day (kg)', 'averageFeedPerDayKg'),
      _cNum('Avg feed / bird (kg)', 'averageFeedPerBirdKg'),
      _cText('Highest feed flock', 'highestFeedConsumingFlock'),
      _cNum('Feed wastage (kg)', 'feedWastageKg'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _text('Feed type', 'feedType'),
      _number('Issued (kg)', 'feedIssuedKg'),
      _number('Returned (kg)', 'feedReturnedKg'),
      _number('Consumed (kg)', 'feedConsumedKg'),
      _number('Live birds', 'liveBirds'),
      _number('Feed/bird', 'feedPerBirdKg'),
      _number('Eggs', 'eggsProduced'),
      _number('Feed/egg', 'feedPerEggKg'),
    ],
  ),
  'feed-inventory-balance': PoultryReportDef(
    slug: 'feed-inventory-balance',
    title: 'Poultry Feed Inventory Balance Report',
    description: 'Current feed stock position and estimated days remaining.',
    cards: [
      _cNum('Total feed stock (kg)', 'totalFeedStockKg'),
      _cMoney('Feed stock value', 'totalFeedStockValue'),
      _cNum('Low-stock items', 'lowStockItems'),
      _cNum('Out-of-stock items', 'outOfStockItems', accent: 'rose'),
      _cNum('Est. days remaining', 'estimatedDaysRemaining'),
    ],
    columns: [
      _text('Feed item', 'feedItem'),
      _text('Category', 'category'),
      _number('Issued (kg)', 'issuedKg'),
      _number('Current (kg)', 'currentStockKg'),
      _money('Unit cost', 'unitCost'),
      _money('Stock value', 'stockValue'),
      _number('Days left', 'estimatedDaysRemaining'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'feed-cost-per-egg': PoultryReportDef(
    slug: 'feed-cost-per-egg',
    title: 'Poultry Feed Cost Per Egg Report',
    description: 'How feed cost relates to egg production, by flock.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cMoney('Total feed cost', 'totalFeedCost', accent: 'rose'),
      _cNum('Total eggs', 'totalEggs'),
      _cMoney('Avg feed cost / egg', 'averageFeedCostPerEgg'),
      _cMoney('Avg feed cost / crate', 'averageFeedCostPerCrate'),
      _cText('Most expensive flock', 'mostExpensiveFlock'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _number('Feed (kg)', 'feedConsumedKg'),
      _money('Avg unit cost', 'averageFeedUnitCost'),
      _money('Total feed cost', 'totalFeedCost'),
      _number('Eggs', 'eggsProduced'),
      _money('Cost / egg', 'feedCostPerEgg'),
      _money('Cost / crate', 'feedCostPerCrate'),
      _pct('Prod. %', 'productionPercent'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'egg-stock-balance': PoultryReportDef(
    slug: 'egg-stock-balance',
    title: 'Poultry Egg Stock Balance Report',
    description: 'Egg inventory on hand, in eggs and crate equivalents.',
    cards: [
      _cNum('Total eggs in stock', 'totalEggsInStock', accent: 'green'),
      _cNum('Total crates', 'totalCrates'),
      _cNum('Loose eggs', 'looseEggs'),
      _cNum('Saleable eggs', 'saleableEggs'),
      _cNum('Broken / rejected', 'brokenRejectedEggs', accent: 'rose'),
      _cMoney('Stock value', 'stockValue'),
    ],
    columns: [
      _text('Product / grade', 'productGrade'),
      _number('Opening', 'openingStock'),
      _number('Produced', 'productionAdded'),
      _number('Sold', 'salesRemoved'),
      _number('Losses/adj.', 'lossesAdjustments'),
      _number('Current (eggs)', 'currentStockEggs'),
      _number('Crates', 'currentStockCrates'),
      _number('Loose', 'looseEggs'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'egg-sales': PoultryReportDef(
    slug: 'egg-sales',
    title: 'Poultry Egg Sales Report',
    description:
        'Egg sales by date, customer and product. Paid/unpaid cover sales made in the selected period — for all-time receivables use the Customer Balance report.',
    filters: const ReportFilters(flock: true, customer: true),
    cards: [
      _cMoney('Total sales revenue', 'totalSalesRevenue', accent: 'green'),
      _cNum('Total eggs sold', 'totalEggsSold'),
      _cMoney('Paid in period', 'totalPaid', accent: 'green'),
      _cMoney('Unpaid in period', 'totalUnpaid', accent: 'rose'),
      _cText('Top customer', 'topCustomer'),
    ],
    columns: [
      _date('Date', 'date'),
      _number('Sale #', 'saleId'),
      _text('Customer', 'customer'),
      _text('Product', 'productGrade'),
      _number('Qty', 'quantitySold'),
      _money('Unit price', 'unitPrice'),
      _money('Total', 'totalAmount'),
      _money('Paid', 'amountPaid'),
      _money('Balance', 'balance'),
      _text('Status', 'paymentStatus', badge: true),
    ],
  ),
  'customer-balance': PoultryReportDef(
    slug: 'customer-balance',
    title: 'Poultry Customer Balance Report',
    description: 'Customer receivables from poultry sales — all-time outstanding up to the end date, not just the selected period.',
    filters: const ReportFilters(customer: true),
    cards: [
      _cNum('Customers with balance', 'customersWithBalance'),
      _cMoney('Total receivables (all time)', 'totalReceivables', accent: 'rose'),
      _cMoney('Overdue amount', 'overdueAmount'),
      _cText('Highest owing customer', 'highestOwingCustomer'),
    ],
    columns: [
      _text('Customer', 'customer'),
      _text('Phone', 'contactPhone'),
      _money('Total sales', 'totalSales'),
      _money('Total paid', 'totalPaid'),
      _money('Balance', 'currentBalance'),
      _money('Overdue', 'overdueAmount'),
      _number('Open sales', 'openSaleCount'),
      _date('Last sale', 'lastSaleDate'),
      _date('Last payment', 'lastPaymentDate'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'supplier-balance': PoultryReportDef(
    slug: 'supplier-balance',
    title: 'Poultry Supplier Balance Report',
    description:
        'What the farm owes suppliers on raw-material purchases and flock batches — all-time outstanding up to the end date, not just the selected period.',
    filters: const ReportFilters(supplier: true),
    cards: [
      _cNum('Suppliers owed', 'suppliersWithBalance'),
      _cMoney('Total payables (all time)', 'totalPayables', accent: 'rose'),
      _cMoney('Overdue amount', 'overdueAmount'),
      _cText('Largest payable', 'highestOwedSupplier'),
    ],
    columns: [
      _text('Supplier', 'supplier'),
      _text('Phone', 'contactPhone'),
      _money('Total purchases', 'totalPurchases'),
      _money('Total paid', 'totalPaid'),
      _money('Balance', 'currentBalance'),
      _money('Overdue', 'overdueAmount'),
      _number('Open purchases', 'openPurchaseCount'),
      _date('Oldest purchase', 'oldestPurchaseDate'),
      _date('Last payment', 'lastPaymentDate'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'expense-summary': PoultryReportDef(
    slug: 'expense-summary',
    title: 'Poultry Expense Summary Report',
    description: 'Poultry farm expenses by category and flock.',
    filters: const ReportFilters(flock: true, supplier: true, category: true),
    cards: [
      _cMoney('Total expenses', 'totalExpenses', accent: 'rose'),
      _cMoney('Paid expenses', 'paidExpenses'),
      _cMoney('Unpaid expenses', 'unpaidExpenses'),
      _cText('Largest category', 'largestExpenseCategory'),
      _cMoney('Avg daily expense', 'averageDailyExpense'),
    ],
    columns: [
      _date('Date', 'date'),
      _number('Ref #', 'expenseId'),
      _text('Category', 'category'),
      _text('Description', 'description'),
      _text('Flock', 'flockName'),
      _text('Supplier', 'supplier'),
      _money('Amount', 'amount'),
      _text('Method', 'paymentMethod'),
      _text('Source', 'sourceType'),
    ],
  ),
  'cash-movement': PoultryReportDef(
    slug: 'cash-movement',
    title: 'Poultry Cash Movement Report',
    description: 'Cash inflows and outflows for poultry operations.',
    cards: [
      _cMoney('Opening cash balance', 'openingCashBalance'),
      _cMoney('Total inflows', 'totalInflows', accent: 'green'),
      _cMoney('Total outflows', 'totalOutflows', accent: 'rose'),
      _cProfit('Net cash movement', 'netCashMovement'),
      _cMoney('Closing cash', 'endingBalance', note: 'Not your account balances'),
    ],
    columns: [
      _date('Date', 'date'),
      ColumnDef('Type', (r, c) => c.text(flowGroupLabel(r['flowGroup']))),
      ColumnDef('Category', (r, c) => c.text(categoryLabel(r['category']))),
      _text('Source', 'sourceType'),
      _text('Reference', 'reference'),
      _text('Description', 'description'),
      _money('Inflow', 'inflow'),
      _money('Outflow', 'outflow'),
      _money('Balance', 'balanceAfter'),
    ],
  ),
  'cash-flow-detail': PoultryReportDef(
    slug: 'cash-flow-detail',
    title: 'Poultry Cash Flow Detail',
    description: 'Where cash came from, what it went on, and how the period compares.',
    cards: [
      _cMoney('Opening cash', 'openingBalance', note: 'Start of period'),
      _cMoney('Money in', 'moneyIn', accent: 'green'),
      _cMoney('Money out', 'moneyOut', accent: 'rose'),
      _cMoney('Closing cash', 'cashAtHand', note: 'Not your account balances'),
      CardDef(
        'From trading',
        (s, c) => c.money(toNum(s['operatingIn']) - toNum(s['operatingOut'])),
        accentOf: (s) => _profitAccent(toNum(s['operatingIn']) - toNum(s['operatingOut'])),
        note: 'Operating only, excludes capital',
      ),
    ],
    analysis: AnalysisDef('Analysis', buildCashFlowAnalysis),
    breakdown: [
      BreakdownGroup(
          title: 'Money in by source', green: true, total: (s, c) => c.money(s['moneyIn']), items: (s) => _bars(s['moneyInByCategory'])),
      BreakdownGroup(
          title: 'Money out by category',
          green: false,
          total: (s, c) => c.money(s['moneyOut']),
          items: (s) => _bars(s['moneyOutByCategory'])),
    ],
    columns: [
      _date('Date', 'date'),
      ColumnDef('Type', (r, c) => c.text(flowGroupLabel(r['flowGroup']))),
      ColumnDef('Category', (r, c) => c.text(categoryLabel(r['category']))),
      _text('Reference', 'reference'),
      _text('Description', 'description'),
      ColumnDef('In', (r, c) => toNum(r['inflow']) != 0 ? c.money(r['inflow']) : '—', right: true),
      ColumnDef('Out', (r, c) => toNum(r['outflow']) != 0 ? c.money(r['outflow']) : '—', right: true),
      _money('Running cash', 'runningBalance'),
    ],
  ),
  'profit-loss-by-flock': PoultryReportDef(
    slug: 'profit-loss-by-flock',
    title: 'Poultry Profit and Loss by Flock Report',
    description: 'Revenue, expenses and profit attributed to each flock.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    tableAsCards: true,
    cardRowLabel: 'Flock',
    cards: [
      _cMoney('Total revenue', 'totalRevenue', accent: 'green'),
      _cMoney('Total expenses', 'totalExpenses', accent: 'rose'),
      _cProfit('Net profit', 'netProfit'),
      _cText('Most profitable flock', 'mostProfitableFlock'),
      _cText('Least profitable flock', 'leastProfitableFlock'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _money('Egg revenue', 'eggRevenue'),
      _money('Feed cost', 'feedCost'),
      _money('Medicine', 'medicineVaccineCost'),
      _money('Labour', 'laborCost'),
      _money('Other exp.', 'otherExpenses'),
      _money('Total revenue', 'totalRevenue'),
      _money('Total cost', 'totalCost'),
      _money('Net profit', 'netProfit'),
      _money('Profit/egg', 'profitPerEgg'),
      _text('Status', 'status', badge: true),
    ],
    breakdown: _plBreakdown(),
  ),
  // Kept as the slug's catalogue record; the route renders the P&L statement.
  'profit-loss': PoultryReportDef(
    slug: 'profit-loss',
    title: 'Poultry Profit and Loss Report',
    description: 'Company-wide revenue, expenses and net profit for the selected period.',
    tableAsCards: true,
    cards: [
      _cMoney('Total revenue', 'totalRevenue', accent: 'green'),
      _cMoney('Total expenses', 'totalExpenses', accent: 'rose'),
      _cProfit('Net profit', 'netProfit'),
    ],
    columns: [
      _money('Egg revenue', 'eggRevenue'),
      _money('Bird sales', 'birdSalesRevenue'),
      _money('Other rev.', 'otherRevenue'),
      _money('Total revenue', 'totalRevenue'),
      _money('Feed cost', 'feedCost'),
      _money('Medicine', 'medicineVaccineCost'),
      _money('Labour', 'laborCost'),
      _money('Other exp.', 'otherExpenses'),
      _money('Total cost', 'totalCost'),
      _money('Net profit', 'netProfit'),
      _text('Status', 'status', badge: true),
    ],
    breakdown: _plBreakdown(),
  ),
  'cost-per-egg': PoultryReportDef(
    slug: 'cost-per-egg',
    title: 'Poultry Cost Per Egg Report',
    description: 'Total allocated cost per egg, by flock.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cNum('Total eggs produced', 'totalEggsProduced'),
      _cMoney('Total direct costs', 'totalDirectCosts'),
      _cMoney('Total allocated costs', 'totalAllocatedCosts', accent: 'rose'),
      _cMoney('Avg cost / egg', 'averageCostPerEgg'),
      _cMoney('Avg cost / crate', 'averageCostPerCrate'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _number('Eggs', 'eggsProduced'),
      _money('Feed cost', 'feedCost'),
      _money('Medicine', 'medicineVaccineCost'),
      _money('Labour', 'laborCost'),
      _money('Other', 'otherAllocatedCost'),
      _money('Total cost', 'totalCost'),
      _money('Cost / egg', 'costPerEgg'),
      _money('Cost / crate', 'costPerCrate'),
      _money('Margin / egg', 'marginPerEgg'),
    ],
  ),
  'vaccination-schedule': PoultryReportDef(
    slug: 'vaccination-schedule',
    title: 'Poultry Vaccination Schedule Report',
    description: 'Recorded and upcoming vaccinations.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cNum('Upcoming', 'upcoming'),
      _cNum('Due today', 'dueToday'),
      _cNum('Overdue / missed', 'overdueMissed', accent: 'rose'),
      _cNum('Completed', 'completed', accent: 'green'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _text('Vaccine', 'vaccine'),
      _text('Disease', 'disease'),
      _date('Scheduled', 'scheduledDate'),
      _date('Actual', 'actualDate'),
      _text('Administered by', 'administeredBy'),
      _text('Status', 'status', badge: true),
      _text('Notes', 'notes'),
    ],
  ),
  'medicine-usage': PoultryReportDef(
    slug: 'medicine-usage',
    title: 'Poultry Medicine Usage Report',
    description: 'Medicines used by flock and date.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cMoney('Total medicine cost', 'totalMedicineCost'),
      _cNum('Number of treatments', 'numberOfTreatments'),
      _cText('Most used medicine', 'mostUsedMedicine'),
      _cNum('Flocks under treatment', 'flocksUnderTreatment'),
      _cNum('Expiring medicine', 'expiringMedicine'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _text('Medicine', 'medicine'),
      _text('Dosage', 'dosage'),
      _number('Qty used', 'quantityUsed'),
      _money('Total cost', 'totalCost'),
      _text('Administered by', 'administeredBy'),
      _text('Notes', 'notes'),
    ],
  ),
  'missing-daily-records': PoultryReportDef(
    slug: 'missing-daily-records',
    title: 'Poultry Missing Daily Records Report',
    description: 'Active flocks missing required daily records.',
    filters: const ReportFilters(flock: true),
    cards: [
      _cNum('Active flocks', 'activeFlocks'),
      _cNum('Missing production records', 'missingProductionRecords', accent: 'rose'),
      _cNum('Missing feed records', 'missingFeedRecords', accent: 'rose'),
      _cNum('Missing health records', 'missingHealthRecords'),
      _cNum('Complete flock-days', 'completeFlockDays', accent: 'green'),
    ],
    columns: [
      _date('Date', 'date'),
      _text('Flock', 'flockName'),
      _yesNo('Production?', 'hasProductionRecord'),
      _yesNo('Feed?', 'hasFeedUsage'),
      _yesNo('Bird update?', 'hasMortalityUpdate'),
      _yesNo('Health note?', 'hasHealthNote'),
      _text('Missing', 'missingItems'),
      _text('Status', 'status', badge: true),
    ],
  ),
  'end-of-flock': PoultryReportDef(
    slug: 'end-of-flock',
    title: 'Poultry End-of-Flock Report',
    description: 'Final lifecycle performance for each flock.',
    filters: const ReportFilters(flock: true, includeClosedFlocks: true),
    cards: [
      _cNum('Birds placed', 'birdsPlaced'),
      _cNum('Birds remaining', 'birdsRemaining'),
      _cNum('Total eggs', 'totalEggs', accent: 'green'),
      _cNum('Total feed (kg)', 'totalFeedConsumedKg'),
      _cMoney('Total revenue', 'totalRevenue', accent: 'green'),
      _cMoney('Total cost', 'totalCost', accent: 'rose'),
      _cProfit('Net profit', 'netProfit'),
      _cPct('Mortality %', 'mortalityPercent', accent: 'rose'),
      _cMoney('Feed cost / egg', 'feedCostPerEgg'),
      _cMoney('Profit / bird', 'profitPerBird'),
    ],
    columns: [
      _text('Flock', 'flockName'),
      _date('Placed', 'placementDate'),
      _number('Age (wks)', 'flockAgeWeeks'),
      _number('Birds placed', 'birdsPlaced'),
      _number('Deaths', 'totalDeaths'),
      _number('Remaining', 'finalBirdsRemaining'),
      _number('Eggs', 'totalEggsProduced'),
      _number('Feed (kg)', 'totalFeedConsumedKg'),
      _money('Revenue', 'totalRevenue'),
      _money('Cost', 'totalCost'),
      _money('Net profit', 'netProfit'),
      _pct('Mort. %', 'mortalityPercent'),
      _text('Status', 'status', badge: true),
    ],
  ),
};
