// The Generic reports, one per `app/generic-reports/<name>/page.tsx`. The
// six written for the report shell (MRR, Subscription revenue, Customer
// payments, Unpaid customers, Expense report, Staff cost, Hosting cost) show
// Period + From/To; the older ones (P&L shows dates too) keep what they had.

import 'package:flutter/material.dart';

import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart' show openNavLink, sidebarLeading;
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../../web_nav.dart' show NavLink;
import '../generic_kit.dart';
import 'generic_report_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';
const _emerald700 = Tone.fg(0xFF047857);
const _rose600 = Tone.fg(0xFFE11D48);
const _rose700 = Tone.fg(0xFFBE123C);
const _slate400 = Tone.fg(0xFF94A3B8);

abstract class _Report extends StatefulWidget {
  const _Report({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
}

abstract class _ReportState<W extends _Report> extends State<W> with GenericReportState<W> {
  @override
  Session get session => widget.session;
  @override
  Company get company => widget.company;

  Future<dynamic> get(String leaf, [Map<String, dynamic>? query]) =>
      session.farmClient.get('$reportsBase/$leaf', query: query);

  void setRange(GenericRange r) => setState(() => range = r);

  /// A link to the Customer Balances page for one customer.
  Widget customerLink(Object? id, String name) => InkWell(
        onTap: () => openNavLink(
          Navigator.of(context),
          NavLink(gm.labels.customerBalance, '/generic-customer-balances?customerId=$id', 'generic-customer-balances'),
          session,
          company,
        ),
        child: Text(name, style: const TextStyle(fontSize: 13, color: _emerald700)),
      );
}

String _signed(num n, String text) => n > 0 ? '+$text' : text;

// ===================================================================== P&L

class GenericPeriodPnlScreen extends _Report {
  const GenericPeriodPnlScreen({super.key, required super.session, required super.company});
  @override
  State<GenericPeriodPnlScreen> createState() => _PnlState();
}

class _PnlState extends _ReportState<GenericPeriodPnlScreen> {
  Map<String, dynamic>? _data, _split;

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      get('period-pnl', rangeQuery),
      get('income-split', rangeQuery).then<Object?>((v) => v, onError: (_) => null),
    ]);
    _data = r[0] is Map ? Map<String, dynamic>.from(r[0] as Map) : null;
    _split = r[1] is Map ? Map<String, dynamic>.from(r[1] as Map) : null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _data, s = _split, l = gm.labels;
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/period-pnl',
      title: 'Period P&L',
      icon: Icons.attach_money,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        if (d != null)
          StatGrid([
            ReportStat(title: 'Total income', value: fmtMoney(d['totalIncome'])),
            ReportStat(title: 'Total expenses', value: fmtMoney(d['totalExpenses'])),
            ReportStat(title: 'Cost of goods sold', value: fmtMoney(d['costOfGoodsSold'])),
            ReportStat(title: 'Gross profit', value: fmtMoney(d['grossProfit']), accent: Accent.emerald),
            ReportStat(title: 'Net profit', value: fmtMoney(d['netProfit']), accent: Accent.emerald),
            ReportStat(title: 'Profit margin', value: fmtPct(tNum(d['profitMarginPct']))),
            ReportStat(title: 'Purchases paid', value: fmtMoney(d['totalPurchasesPaid'])),
            ReportStat(title: 'Sales count', value: '${tNum(d['salesCount']).toInt()}'),
          ]),
        // Where the income came from: only for a business that bills on a schedule.
        if (d != null && s != null && gm.isSubscriptionBusiness)
          StatGrid(columns: 1, [
            ReportStat(title: '${l.subscription} income', value: fmtMoney(s['subscriptionIncome']), accent: Accent.emerald),
            ReportStat(title: 'Other income', value: fmtMoney(s['otherIncome'])),
            ReportStat(
              title: 'Recurring share',
              value: tNum(s['totalIncome']) > 0 ? fmtPct(tNum(s['subscriptionIncome']) * 100 / tNum(s['totalIncome'])) : '—',
            ),
          ]),
      ],
    );
  }
}

// =============================================================== Cash flow

class GenericCashSummaryScreen extends _Report {
  const GenericCashSummaryScreen({super.key, required super.session, required super.company});
  @override
  State<GenericCashSummaryScreen> createState() => _CashState();
}

class _CashState extends _ReportState<GenericCashSummaryScreen> {
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async {
    final r = await get('cash-summary', rangeQuery);
    _report = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  @override
  Widget build(BuildContext context) {
    final rep = _report;
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/cash-summary',
      title: 'Cash summary',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: TColors.slate700,
      range: range,
      onRangeChange: setRange,
      showDates: false,
      onRun: run,
      loading: loading,
      children: [
        if (rep != null) ...[
          StatGrid(columns: 1, [ReportStat(title: 'Total cash at hand (now)', value: fmtMoney(rep['totalCashAtHand']))]),
          ReportTable(
            rows: reportRows(rep['accounts']),
            empty: 'No cash accounts.',
            columns: [
              RCol('Account', (a) => tStr(a['accountName']), bold: true),
              RCol('Type', (a) => tStr(a['accountType']), color: TColors.slate500),
              RCol('Cash in (period)', (a) => fmtMoney(a['periodCashIn']), right: true, color: _emerald700),
              RCol('Cash out (period)', (a) => fmtMoney(a['periodCashOut']), right: true, color: _rose700),
              RCol('Net (period)', (a) => fmtMoney(tNum(a['periodCashIn']) - tNum(a['periodCashOut'])), right: true, bold: true),
              RCol(
                'Current balance',
                (a) => Text(fmtMoney(a['currentBalance']),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tNum(a['currentBalance']) < 0 ? _rose700 : TColors.slate900)),
                right: true,
              ),
              RCol(
                'Status',
                (a) => a['isActive'] == true
                    ? reportBadge('Active', bg: const Tone.bg(0xFFD1FAE5), fg: const Tone.fg(0xFF065F46))
                    : reportBadge('Inactive'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ========================================================== Expense report

class GenericExpenseReportScreen extends _Report {
  const GenericExpenseReportScreen({super.key, required super.session, required super.company});
  @override
  State<GenericExpenseReportScreen> createState() => _ExpenseState();
}

class _ExpenseState extends _ReportState<GenericExpenseReportScreen> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async {
    final r = await get('expense-report', rangeQuery);
    _data = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = reportRows(_data?['byCategory']);
    final bySupplier = reportRows(_data?['bySupplier']);
    final trend = reportRows(_data?['trend']);
    final total = byCategory.fold<num>(0, (s, r) => s + tNum(r['totalAmount']));
    final count = byCategory.fold<num>(0, (s, r) => s + tNum(r['expenseCount']));
    final outstanding = bySupplier.fold<num>(0, (s, r) => s + tNum(r['outstanding']));
    final recurring = trend.fold<num>(0, (s, r) => s + tNum(r['recurringAmount']));
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/expenses-by-category',
      title: 'Expense report',
      description: 'Where the money went — by category, by supplier, and month by month.',
      icon: Icons.bar_chart,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: 'Total spent', value: fmtMoney(total), hint: '${count.toInt()} expense(s)'),
          ReportStat(
            title: 'Still unpaid',
            value: fmtMoney(outstanding),
            accent: outstanding > 0 ? Accent.rose : Accent.slate,
            hint: 'Bills with a balance',
          ),
          ReportStat(
            title: 'From recurring bills',
            value: fmtMoney(recurring),
            hint: total > 0 ? '${fmtPct(recurring * 100 / total)} of spend' : null,
          ),
          ReportStat(title: 'Categories used', value: '${byCategory.length}'),
        ]),
        ReportTable(
          title: 'By category',
          rows: byCategory,
          empty: 'No expenses in this period.',
          columns: [
            RCol('Category', (r) => tStr(r['categoryName'])),
            RCol('Count', (r) => '${tNum(r['expenseCount']).toInt()}', right: true),
            RCol('Amount', (r) => fmtMoney(r['totalAmount']), right: true, bold: true),
            RCol('Share', (r) => total > 0 ? shareCell(tNum(r['totalAmount']) * 100 / total, const Tone(0xFFF59E0B)) : '—', right: true),
          ],
        ),
        ReportTable(
          title: 'By supplier',
          rows: bySupplier,
          empty: 'No expenses in this period.',
          columns: [
            RCol('Supplier', (r) => Text(tStr(r['supplierName']),
                style: TextStyle(fontSize: 13, color: r['genericSupplierId'] != null ? TColors.slate900 : TColors.slate500))),
            RCol('Count', (r) => '${tNum(r['expenseCount']).toInt()}', right: true),
            RCol('Billed', (r) => fmtMoney(r['totalAmount']), right: true),
            RCol('Paid', (r) => fmtMoney(r['amountPaid']), right: true),
            RCol('Outstanding', (r) => tNum(r['outstanding']) > 0 ? fmtMoney(r['outstanding']) : '—', right: true, color: _rose600),
          ],
        ),
        ReportTable(
          title: 'Month by month',
          rows: trend,
          empty: 'No months in this range.',
          columns: [
            RCol('Month', (r) => fmtMonth(r['monthStart'])),
            RCol('Expenses', (r) => '${tNum(r['expenseCount']).toInt()}', right: true),
            RCol('Total', (r) => fmtMoney(r['totalAmount']), right: true, bold: true),
            RCol('Of which recurring', (r) => tNum(r['recurringAmount']) != 0 ? fmtMoney(r['recurringAmount']) : '—', right: true),
            RCol('Paid to people', (r) => tNum(r['staffAmount']) != 0 ? fmtMoney(r['staffAmount']) : '—', right: true),
          ],
        ),
      ],
    );
  }
}

// ============================================================= Staff cost

class GenericStaffCostScreen extends _Report {
  const GenericStaffCostScreen({super.key, required super.session, required super.company});
  @override
  State<GenericStaffCostScreen> createState() => _StaffCostState();
}

class _StaffCostState extends _ReportState<GenericStaffCostScreen> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    startReport(trailingMonthsRange(6));
  }

  @override
  Future<void> fetch() async {
    final r = await get('staff-cost', rangeQuery);
    _data = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  @override
  Widget build(BuildContext context) {
    final people = reportRows(_data?['byPerson']);
    final months = reportRows(_data?['byMonth']);
    final total = people.fold<num>(0, (s, p) => s + tNum(p['totalPaid']));
    final staffPayments = people.fold<num>(0, (s, p) => s + tNum(p['staffPayments']));
    final payroll = people.fold<num>(0, (s, p) => s + tNum(p['payrollPay']));
    final withPay = months.where((m) => tNum(m['totalPaid']) > 0).length;
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/staff-cost',
      title: 'Staff & contractor cost',
      description: 'Everything paid to people in the period — staff payments and payroll together — by person, by month and by role.',
      icon: Icons.groups_2_outlined,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: 'Total paid', value: fmtMoney(total), hint: '${people.length} person(s)'),
          ReportStat(title: 'Staff payments', value: fmtMoney(staffPayments)),
          ReportStat(title: 'Payroll', value: fmtMoney(payroll)),
          ReportStat(title: 'Average a month', value: fmtMoney(withPay > 0 ? total / withPay : 0), hint: '$withPay month(s) with pay'),
        ]),
        ReportTable(
          title: 'By person',
          rows: people,
          empty: 'Nobody was paid in this period.',
          columns: [
            RCol('Person', (r) => tStr(r['staffName'])),
            RCol('Role', (r) => tStr(r['staffRole']).isEmpty ? '—' : tStr(r['staffRole'])),
            RCol('Engaged as', (r) => tStr(r['workerType']).isEmpty ? '—' : tStr(r['workerType'])),
            RCol('Payments', (r) => '${tNum(r['paymentCount']).toInt()}', right: true),
            RCol('Staff payments', (r) => fmtMoney(r['staffPayments']), right: true),
            RCol('Payroll', (r) => fmtMoney(r['payrollPay']), right: true),
            RCol('Total', (r) => fmtMoney(r['totalPaid']), right: true, bold: true),
            RCol('Last paid', (r) => fmtDate(r['lastPaymentDate'])),
          ],
        ),
        ReportTable(
          title: 'By month',
          rows: months,
          empty: 'No months in this range.',
          columns: [
            RCol('Month', (r) => fmtMonth(r['monthStart'])),
            RCol('People paid', (r) => '${tNum(r['peoplePaid']).toInt()}', right: true),
            RCol('Staff payments', (r) => fmtMoney(r['staffPayments']), right: true),
            RCol('Payroll', (r) => fmtMoney(r['payrollPay']), right: true),
            RCol('Total', (r) => fmtMoney(r['totalPaid']), right: true, bold: true),
          ],
        ),
        ReportTable(
          title: 'By role',
          rows: reportRows(_data?['byRole']),
          empty: 'No roles to group by.',
          columns: [
            RCol('Role', (r) => tStr(r['staffRole'])),
            RCol('People', (r) => '${tNum(r['peopleCount']).toInt()}', right: true),
            RCol('Paid', (r) => fmtMoney(r['totalPaid']), right: true),
            RCol('Share', (r) => shareCell(tNum(r['pctOfTotal']), const Tone(0xFF0EA5E9)), right: true),
          ],
        ),
      ],
    );
  }
}

// =================================================== Subscription revenue

class GenericSubscriptionRevenueScreen extends _Report {
  const GenericSubscriptionRevenueScreen({super.key, required super.session, required super.company});
  @override
  State<GenericSubscriptionRevenueScreen> createState() => _SubRevenueState();
}

class _SubRevenueState extends _ReportState<GenericSubscriptionRevenueScreen> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    startReport(trailingMonthsRange(12));
  }

  @override
  Future<void> fetch() async {
    final r = await get('subscription-revenue', rangeQuery);
    _data = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  String _out(Map r) => tNum(r['outstanding']) > 0 ? fmtMoney(r['outstanding']) : '—';

  @override
  Widget build(BuildContext context) {
    final l = gm.labels;
    final months = reportRows(_data?['byMonth']);
    num sum(String k) => months.fold<num>(0, (s, m) => s + tNum(m[k]));
    final outstanding = sum('outstanding');
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/subscription-revenue',
      title: '${l.subscription} revenue',
      description: 'What was billed, what has been collected, and how it splits by ${l.plan.toLowerCase()} and by ${l.customer.toLowerCase()}.',
      icon: Icons.repeat,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: 'Invoiced', value: fmtMoney(sum('invoicedAmount')), hint: '${sum('invoiceCount').toInt()} ${l.invoicePlural.toLowerCase()}'),
          ReportStat(title: 'Collected', value: fmtMoney(sum('collectedAmount')), accent: Accent.emerald),
          ReportStat(title: 'Still owed', value: fmtMoney(outstanding), accent: outstanding > 0 ? Accent.rose : Accent.slate),
          ReportStat(title: 'MRR now', value: fmtMoney(months.isEmpty ? 0 : months.last['activeMrr']), hint: 'Latest month in range'),
        ]),
        ReportTable(
          title: 'By month',
          rows: months,
          empty: 'No months in this range.',
          columns: [
            RCol('Month', (r) => fmtMonth(r['monthStart'])),
            RCol(l.invoicePlural, (r) => '${tNum(r['invoiceCount']).toInt()}', right: true),
            RCol('Invoiced', (r) => fmtMoney(r['invoicedAmount']), right: true),
            RCol('Collected', (r) => fmtMoney(r['collectedAmount']), right: true),
            RCol('Outstanding', _out, right: true, color: _rose600),
            RCol('Active MRR', (r) => fmtMoney(r['activeMrr']), right: true),
            RCol('New', (r) => tNum(r['newCount']) != 0 ? '+${tNum(r['newCount']).toInt()}' : '—', right: true),
            RCol('Lost', (r) => tNum(r['lostCount']) != 0 ? '-${tNum(r['lostCount']).toInt()}' : '—', right: true),
          ],
        ),
        ReportTable(
          title: 'By ${l.plan.toLowerCase()}',
          rows: reportRows(_data?['byPlan']),
          empty: 'No ${l.planPlural.toLowerCase()} yet.',
          columns: [
            RCol(l.plan, (r) => tStr(r['serviceName'])),
            RCol('Billing', (r) => tStr(r['billingFrequency']).isEmpty ? '—' : tStr(r['billingFrequency'])),
            RCol('Active', (r) => '${tNum(r['activeSubscriptions']).toInt()}', right: true),
            RCol('MRR', (r) => fmtMoney(r['activeMrr']), right: true),
            RCol('Invoiced', (r) => fmtMoney(r['invoicedAmount']), right: true),
            RCol('Collected', (r) => fmtMoney(r['collectedAmount']), right: true),
            RCol('Outstanding', _out, right: true, color: _rose600),
          ],
        ),
        ReportTable(
          title: 'By ${l.customer.toLowerCase()}',
          rows: reportRows(_data?['byCustomer']),
          empty: 'No ${l.customerPlural.toLowerCase()} billed in this range.',
          columns: [
            RCol(l.customer, (r) => tStr(r['customerName'])),
            RCol('Active', (r) => '${tNum(r['activeSubscriptions']).toInt()}', right: true),
            RCol('MRR', (r) => fmtMoney(r['activeMrr']), right: true),
            RCol('Invoiced', (r) => fmtMoney(r['invoicedAmount']), right: true),
            RCol('Collected', (r) => fmtMoney(r['collectedAmount']), right: true),
            RCol('Outstanding', _out, right: true, color: _rose600),
            RCol('Last payment', (r) => fmtDate(r['lastPaymentDate'])),
          ],
        ),
      ],
    );
  }
}

// ==================================================================== MRR

class GenericMrrScreen extends _Report {
  const GenericMrrScreen({super.key, required super.session, required super.company});
  @override
  State<GenericMrrScreen> createState() => _MrrState();
}

class _MrrState extends _ReportState<GenericMrrScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    startReport(trailingMonthsRange(12));
  }

  @override
  Future<void> fetch() async => _rows = reportRows(await get('mrr', rangeQuery));

  @override
  Widget build(BuildContext context) {
    final l = gm.labels;
    final latest = _rows.isEmpty ? null : _rows.last;
    final first = _rows.isEmpty ? null : _rows.first;
    final growth = latest != null && first != null && tNum(first['activeMrr']) > 0
        ? (tNum(latest['activeMrr']) - tNum(first['activeMrr'])) / tNum(first['activeMrr']) * 100
        : null;
    final lost = tNum(latest?['lostMrr']);
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/mrr',
      title: 'Monthly recurring revenue',
      description: "Active, new and lost MRR month by month. Every figure is the same month grid the dashboard's MRR card uses.",
      icon: Icons.trending_up,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(
            title: 'MRR now',
            value: fmtMoney(latest?['activeMrr']),
            hint: latest == null ? null : fmtMonth(latest['monthStart']),
            accent: Accent.emerald,
          ),
          ReportStat(title: 'Active ${l.subscriptionPlural.toLowerCase()}', value: '${tNum(latest?['activeCount']).toInt()}'),
          ReportStat(title: 'New this month', value: fmtMoney(latest?['newMrr']), hint: '${tNum(latest?['newCount']).toInt()} added'),
          ReportStat(
            title: 'Lost this month',
            value: fmtMoney(lost),
            hint: '${tNum(latest?['lostCount']).toInt()} ended',
            accent: lost > 0 ? Accent.rose : Accent.slate,
          ),
        ]),
        if (growth != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: TColors.slate500), children: [
              TextSpan(
                  text: 'MRR moved from ${fmtMoney(first!['activeMrr'])} in ${fmtMonth(first['monthStart'])} to '
                      '${fmtMoney(latest!['activeMrr'])} in ${fmtMonth(latest['monthStart'])} — '),
              TextSpan(
                text: '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                style: TextStyle(color: growth >= 0 ? _emerald700 : _rose600),
              ),
              const TextSpan(text: '.'),
            ])),
          ),
        ReportTable(
          rows: _rows,
          empty: 'No months in this range.',
          columns: [
            RCol('Month', (r) => fmtMonth(r['monthStart'])),
            RCol('Active MRR', (r) => fmtMoney(r['activeMrr']), right: true),
            RCol('Active', (r) => '${tNum(r['activeCount']).toInt()}', right: true),
            RCol('New MRR', (r) => tNum(r['newMrr']) != 0 ? '+${fmtMoney(r['newMrr'])}' : '—', right: true, color: _emerald700),
            RCol('Lost MRR', (r) => tNum(r['lostMrr']) != 0 ? '-${fmtMoney(r['lostMrr'])}' : '—', right: true, color: _rose600),
            RCol(
              'Net change',
              (r) {
                final n = tNum(r['netMrrChange']);
                return Text(_signed(n, fmtMoney(n)),
                    style: TextStyle(fontSize: 13, color: n > 0 ? _emerald700 : n < 0 ? _rose600 : TColors.slate900));
              },
              right: true,
            ),
            RCol('Expansion', (_) => 'not tracked', right: true, color: _slate400),
            RCol('Contraction', (_) => 'not tracked', right: true, color: _slate400),
          ],
        ),
        Text(
          'Expansion and contraction MRR need a history of what each ${l.subscription.toLowerCase()} used to cost. This '
          'system keeps one current amount per ${l.subscription.toLowerCase()} and overwrites it, so a plan that went from '
          '50 to 80 in March cannot be told apart from one that was always 80. The columns are left blank rather than '
          'filled with a guess.',
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ],
    );
  }
}

// ======================================================= Customer payments

class GenericCustomerPaymentsReportScreen extends _Report {
  const GenericCustomerPaymentsReportScreen({super.key, required super.session, required super.company});
  @override
  State<GenericCustomerPaymentsReportScreen> createState() => _PaymentsState();
}

class _PaymentsState extends _ReportState<GenericCustomerPaymentsReportScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async => _rows = reportRows(await session.farmClient.get(
        '${genericBase(company)}/balances/customer-payments',
        query: {'farmId': company.farmId, 'from': range.from, 'to': range.to},
      ));

  @override
  Widget build(BuildContext context) {
    final l = gm.labels;
    final live = _rows.where((r) => r['status'] != 'Reversed').toList();
    final total = live.fold<num>(0, (s, r) => s + tNum(r['totalAmount']));
    final byMethod = <String, num>{};
    for (final r in live) {
      final m = tStr(r['paymentMethod']).isEmpty ? 'Unspecified' : tStr(r['paymentMethod']);
      byMethod[m] = (byMethod[m] ?? 0) + tNum(r['totalAmount']);
    }
    final top = (byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).firstOrNull;
    final reversed = _rows.length - live.length;
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/customer-payments',
      title: '${l.customer} payments',
      description: 'Every payment received in the period, what it was paid by, and how many ${l.invoicePlural.toLowerCase()} it settled.',
      icon: Icons.credit_card,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: 'Received', value: fmtMoney(total), accent: Accent.emerald, hint: '${live.length} payment(s)'),
          ReportStat(title: 'Reversed', value: '$reversed', hint: 'Excluded from the total', accent: reversed > 0 ? Accent.rose : Accent.slate),
          ReportStat(title: 'Most used', value: top?.key ?? '—', hint: top == null ? null : fmtMoney(top.value)),
          ReportStat(title: 'Average', value: fmtMoney(live.isEmpty ? 0 : total / live.length)),
        ]),
        ReportTable(
          rows: _rows,
          empty: 'No payments in this period.',
          columns: [
            RCol('Date', (r) => fmtDate(r['paymentDate'])),
            RCol('Payment', (r) => tStr(r['paymentNumber']).isEmpty ? tStr(r['paymentId']) : tStr(r['paymentNumber'])),
            RCol(
              l.customer,
              (r) => r['partyId'] != null
                  ? customerLink(r['partyId'], tStr(r['partyName']).isEmpty ? '#${r['partyId']}' : tStr(r['partyName']))
                  : (tStr(r['partyName']).isEmpty ? '—' : tStr(r['partyName'])),
            ),
            RCol('Method', (r) => tStr(r['paymentMethod']).isEmpty ? '—' : tStr(r['paymentMethod'])),
            RCol('Reference', (r) => tStr(r['reference']).isEmpty ? '—' : tStr(r['reference'])),
            RCol('Applied to', (r) => '${tNum(r['allocationCount']).toInt()} ${l.invoicePlural.toLowerCase()}', right: true),
            RCol(
              'Amount',
              (r) => Text(
                fmtMoney(r['totalAmount']),
                style: r['status'] == 'Reversed'
                    ? const TextStyle(fontSize: 13, color: _slate400, decoration: TextDecoration.lineThrough)
                    : const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              right: true,
            ),
            RCol('Status', (r) => reportBadge(tStr(r['status']), outline: r['status'] == 'Reversed')),
          ],
        ),
      ],
    );
  }
}

// ======================================================== Unpaid customers

/// Days since the oldest open document — the age of the debt.
int? ageDays(Object? oldest, [DateTime? now]) {
  final d = tStr(oldest).isEmpty ? null : DateTime.tryParse(tStr(oldest));
  if (d == null) return null;
  final days = (now ?? DateTime.now()).difference(d).inDays;
  return days < 0 ? 0 : days;
}

class GenericUnpaidCustomersScreen extends _Report {
  const GenericUnpaidCustomersScreen({super.key, required super.session, required super.company});
  @override
  State<GenericUnpaidCustomersScreen> createState() => _UnpaidState();
}

class _UnpaidState extends _ReportState<GenericUnpaidCustomersScreen> {
  List<Map<String, dynamic>> _rows = [];
  String _status = 'Overdue';

  @override
  void initState() {
    super.initState();
    // Opens with no dates: everything open, whenever it was raised.
    startReport((from: '', to: ''));
  }

  @override
  Future<void> fetch() async => _rows = reportRows(await session.farmClient.get(
        '${genericBase(company)}/balances/customer-balances',
        query: {'farmId': company.farmId, 'from': range.from, 'to': range.to, 'status': _status},
      ));

  @override
  Widget build(BuildContext context) {
    final l = gm.labels;
    final owed = _rows.fold<num>(0, (s, r) => s + tNum(r['totalBalance']));
    final overdue = _rows.fold<num>(0, (s, r) => s + tNum(r['overdueAmount']));
    int? oldest;
    for (final r in _rows) {
      final a = ageDays(r['oldestDocumentDate']);
      if (a != null && (oldest == null || a > oldest)) oldest = a;
    }
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/unpaid-customers',
      title: 'Unpaid ${l.customerPlural.toLowerCase()}',
      description: 'Open ${l.invoicePlural.toLowerCase()}, what is already late, and how to reach whoever owes it.',
      icon: Icons.warning_amber_outlined,
      range: range,
      onRangeChange: setRange,
      extraFilters: [
        FilterLabel(
          'Show',
          AppSelect<String>(
            value: _status,
            items: const [
              AppSelectItem(value: 'Overdue', label: 'Overdue only'),
              AppSelectItem(value: 'All', label: 'Everything open'),
              AppSelectItem(value: 'Unpaid', label: 'Not paid at all'),
              AppSelectItem(value: 'Partial', label: 'Part paid'),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'Overdue'),
          ),
        ),
      ],
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: '${l.customerPlural} owing', value: '${_rows.length}'),
          ReportStat(title: 'Total owed', value: fmtMoney(owed)),
          ReportStat(title: 'Already overdue', value: fmtMoney(overdue), accent: overdue > 0 ? Accent.rose : Accent.slate),
          ReportStat(title: 'Oldest debt', value: oldest == null ? '—' : '$oldest days'),
        ]),
        ReportTable(
          rows: _rows,
          empty: 'Nothing outstanding. Every ${l.invoice.toLowerCase()} in this range is settled.',
          columns: [
            RCol(l.customer, (r) => customerLink(r['partyId'], tStr(r['partyName']))),
            RCol('Contact', (r) {
              final phone = tStr(r['contactPhone']);
              if (phone.isEmpty) return tStr(r['contactEmail']).isEmpty ? '—' : tStr(r['contactEmail']);
              // The web's tel: link; the app has no dialer package, so it is shown, not tapped.
              return Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_outlined, size: 12, color: TColors.slate600),
                const SizedBox(width: 4),
                SelectableText(phone, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              ]);
            }),
            RCol('Open', (r) => '${tNum(r['openDocumentCount']).toInt()}', right: true),
            RCol('Owed', (r) => fmtMoney(r['totalBalance']), right: true),
            RCol('Overdue', (r) => tNum(r['overdueAmount']) > 0 ? fmtMoney(r['overdueAmount']) : '—', right: true, color: _rose600),
            RCol('Age', (r) {
              final a = ageDays(r['oldestDocumentDate']);
              return a == null ? '—' : '${a}d';
            }, right: true),
            RCol('Last payment', (r) => fmtDate(r['lastPaymentDate'])),
            RCol('Terms', (r) => tNum(r['paymentTermsDays']) != 0 ? '${tNum(r['paymentTermsDays']).toInt()}d' : '—', right: true),
          ],
        ),
      ],
    );
  }
}

// ============================================================ Hosting cost

class GenericHostingCostScreen extends _Report {
  const GenericHostingCostScreen({super.key, required super.session, required super.company});
  @override
  State<GenericHostingCostScreen> createState() => _HostingState();
}

class _HostingState extends _ReportState<GenericHostingCostScreen> {
  Map<String, dynamic>? _data;

  /// Null = the server's suggestion; a list = the owner's choice, even empty.
  List<int>? _chosen;

  @override
  void initState() {
    super.initState();
    startReport(trailingMonthsRange(12));
  }

  @override
  Future<void> fetch() async {
    final ids = _chosen;
    final r = await get('hosting-cost', {
      ...rangeQuery,
      if (ids != null && ids.isEmpty) 'useSuggested': 'false',
      if (ids != null && ids.isNotEmpty) 'categoryIds': ids,
    });
    _data = r is Map ? Map<String, dynamic>.from(r) : null;
    // The first load adopts the suggestion, so the ticks show what was used.
    if (ids == null) {
      _chosen = [
        for (final c in reportRows(_data?['categories']))
          if (c['isSuggested'] == true) tNum(c['genericExpenseCategoryId']).toInt(),
      ];
    }
  }

  void _toggle(int id) => setState(() {
        final cur = [...?_chosen];
        cur.contains(id) ? cur.remove(id) : cur.add(id);
        _chosen = cur;
      });

  @override
  Widget build(BuildContext context) {
    final months = reportRows(_data?['months']);
    final cats = reportRows(_data?['categories']);
    final hosting = months.fold<num>(0, (s, m) => s + tNum(m['hostingCost']));
    final revenue = months.fold<num>(0, (s, m) => s + tNum(m['totalRevenue']));
    final share = revenue > 0 ? hosting * 100 / revenue : 0;
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/hosting-cost',
      title: 'Hosting & cloud cost',
      description: 'What infrastructure costs each month, and how much of revenue it consumes.',
      icon: Icons.cloud_outlined,
      range: range,
      onRangeChange: setRange,
      onRun: run,
      loading: loading,
      children: [
        StatGrid([
          ReportStat(title: 'Total hosting', value: fmtMoney(hosting), hint: '${months.length} month(s)'),
          ReportStat(title: 'Average a month', value: fmtMoney(months.isEmpty ? 0 : hosting / months.length)),
          ReportStat(
            title: 'Share of revenue',
            value: fmtPct(share),
            hint: revenue > 0 ? 'of ${fmtMoney(revenue)}' : 'No revenue in range',
            accent: share > 30 ? Accent.rose : share > 15 ? Accent.amber : Accent.emerald,
          ),
          ReportStat(title: 'Categories counted', value: '${(_chosen ?? const []).length}'),
        ]),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Tone.bg(0xFFFFFFFF),
            border: Border.all(color: TColors.slate200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('WHICH CATEGORIES COUNT', style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: TColors.slate500)),
              const SizedBox(height: 8),
              if (cats.isEmpty)
                const Text('No expense categories yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
              else ...[
                for (final c in cats)
                  InkWell(
                    onTap: () => _toggle(tNum(c['genericExpenseCategoryId']).toInt()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: (_chosen ?? const []).contains(tNum(c['genericExpenseCategoryId']).toInt()),
                            onChanged: (_) => _toggle(tNum(c['genericExpenseCategoryId']).toInt()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tStr(c['categoryName']), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            Text(
                              '${fmtMoney(c['totalAmount'])} all time${c['isSuggested'] == true ? ' · suggested' : ''}',
                              style: const TextStyle(fontSize: 12, color: TColors.slate500),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Suggestions come from the category name. Change the ticks and press Run — unticking everything '
                  'reports zero rather than falling back to the guess.',
                  style: TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ],
            ],
          ),
        ),
        ReportTable(
          title: 'Month by month',
          rows: months,
          empty: 'No months in this range.',
          columns: [
            RCol('Month', (r) => fmtMonth(r['monthStart'])),
            RCol('Hosting', (r) => fmtMoney(r['hostingCost']), right: true),
            RCol('Bills', (r) => '${tNum(r['expenseCount']).toInt()}', right: true),
            RCol('Revenue', (r) => fmtMoney(r['totalRevenue']), right: true),
            RCol('% of revenue', (r) => Text(
                  tNum(r['totalRevenue']) > 0 ? fmtPct(tNum(r['pctOfRevenue'])) : '—',
                  style: TextStyle(fontSize: 13, color: tNum(r['pctOfRevenue']) > 30 ? _rose600 : TColors.slate900),
                ), right: true),
            RCol('% of costs', (r) => tNum(r['totalExpenses']) > 0 ? fmtPct(tNum(r['pctOfExpenses'])) : '—', right: true),
          ],
        ),
      ],
    );
  }
}

// ============================================================== Break-even

class GenericBreakEvenScreen extends _Report {
  const GenericBreakEvenScreen({super.key, required super.session, required super.company});
  @override
  State<GenericBreakEvenScreen> createState() => _BreakEvenState();
}

class _BreakEvenState extends _ReportState<GenericBreakEvenScreen> {
  Map<String, dynamic>? _data;
  int _months = 3;

  @override
  void initState() {
    super.initState();
    startReport((from: '', to: ''));
  }

  @override
  Future<void> fetch() async {
    final r = await get('break-even', {'months': '$_months'});
    _data = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Widget _line(String label, String value, String? note) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate700)),
              if (note != null) Text(note, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final l = gm.labels, d = _data;
    final need = tNum(d?['breakEvenCustomers']).toInt();
    final surplus = tNum(d?['customerSurplus']).toInt();
    final covered = d != null && surplus >= 0 && need > 0;
    final short = surplus < 0 ? -surplus : 0;
    final monthly = tNum(d?['monthlySurplus']);
    const body = TextStyle(fontSize: 13, color: TColors.slate600);
    return GenericReportShell(
      session: session,
      company: company,
      href: '/generic-reports/break-even',
      title: 'Break-even',
      description: 'How many paying ${l.customerPlural.toLowerCase()} it takes to cover a month.',
      icon: Icons.balance_outlined,
      extraFilters: [
        FilterLabel(
          'Average costs over',
          AppSelect<int>(
            value: _months,
            items: const [
              AppSelectItem(value: 1, label: 'The last complete month'),
              AppSelectItem(value: 3, label: 'The last 3 complete months'),
              AppSelectItem(value: 6, label: 'The last 6 complete months'),
              AppSelectItem(value: 12, label: 'The last 12 complete months'),
            ],
            onChanged: (v) => setState(() => _months = v ?? 3),
          ),
        ),
      ],
      onRun: run,
      loading: loading,
      children: [
        if (d != null) ...[
          StatGrid([
            ReportStat(
              title: '${l.customerPlural} needed',
              value: need == 0 ? '—' : '$need',
              hint: need == 0 ? 'Not enough data yet' : 'To cover a month',
            ),
            ReportStat(
              title: 'Paying now',
              value: '${tNum(d['activeCustomers']).toInt()}',
              hint: '${tNum(d['activeSubscriptions']).toInt()} ${l.subscriptionPlural.toLowerCase()}',
            ),
            ReportStat(
              title: covered ? 'Surplus' : 'Short by',
              value: '${covered ? surplus : short}',
              accent: covered ? Accent.emerald : Accent.rose,
              hint: covered ? '${l.customerPlural.toLowerCase()} above break-even' : 'more ${l.customerPlural.toLowerCase()} needed',
            ),
            ReportStat(
              title: 'Monthly surplus',
              value: fmtMoney(monthly),
              accent: monthly >= 0 ? Accent.emerald : Accent.rose,
              hint: 'MRR less monthly costs',
            ),
          ]),
          GenericCard(
            titleWidget: const Text('THE ARITHMETIC', style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: TColors.slate500)),
            children: [
              _line('Monthly costs', fmtMoney(d['monthlyFixedCosts']),
                  'Averaged over ${tNum(d['monthsAveraged']).toInt()} month(s): ${fmtDate(d['periodStart'])} – ${fmtDate(d['periodEnd'])}'),
              _line('Monthly recurring revenue', fmtMoney(d['monthlyRecurringRevenue']),
                  '${tNum(d['activeSubscriptions']).toInt()} active ${l.subscriptionPlural.toLowerCase()}'),
              _line('Average per ${l.customer.toLowerCase()}', fmtMoney(d['avgRevenuePerCustomer']),
                  'MRR ÷ ${tNum(d['activeCustomers']).toInt()} paying ${l.customerPlural.toLowerCase()}'),
              const Divider(),
              Row(children: [
                Expanded(
                  child: Text('${fmtMoney(d['monthlyFixedCosts'])} ÷ ${fmtMoney(d['avgRevenuePerCustomer'])}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                Text(need == 0 ? '—' : '$need ${l.customerPlural.toLowerCase()}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          GenericCard(
            titleWidget: const Text('WHAT THIS DOES AND DOES NOT COUNT',
                style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: TColors.slate500)),
            children: [
              Text.rich(TextSpan(style: body, children: [
                b('The current month is excluded.'),
                t(' Costs are averaged over complete months only — a part-finished month would understate the average '
                    'and make break-even look closer than it is.'),
              ])),
              const SizedBox(height: 10),
              Text.rich(TextSpan(style: body, children: [
                b('“Costs” means every approved operating expense'),
                t(', including recurring bills and anything paid to staff through an expense. There is no fixed/variable '
                    'flag on an expense here, and guessing one from category names would be a number you could not check.'),
              ])),
              const SizedBox(height: 10),
              Text.rich(TextSpan(style: body, children: [
                b('Only recurring revenue counts.'),
                t(' One-off fees are real income but they do not repeat, so including them would make next month look '
                    'covered when it is not. See the '),
              ])),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: _emerald700),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GenericMrrScreen(session: session, company: company),
                  )),
                  child: const Text('MRR report.'),
                ),
              ),
              if (need == 0)
                Text(
                  'There is no answer yet: it needs at least one active ${l.subscription.toLowerCase()} with a recurring '
                  'price. Add one and this fills in.',
                  style: const TextStyle(fontSize: 13, color: Tone.fg(0xFFB45309)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ====================================================== Sales by product

class GenericSalesByProductScreen extends _Report {
  const GenericSalesByProductScreen({super.key, required super.session, required super.company});
  @override
  State<GenericSalesByProductScreen> createState() => _ByProductState();
}

class _ByProductState extends _ReportState<GenericSalesByProductScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async => _rows = reportRows(await get('sales-by-product', rangeQuery));

  @override
  Widget build(BuildContext context) => GenericReportShell(
        session: session,
        company: company,
        href: '/generic-reports/sales-by-product',
        title: 'Sales by product',
        icon: Icons.shopping_cart_outlined,
        iconColor: const Tone.fg(0xFF0284C7),
        range: range,
        onRangeChange: setRange,
        showDates: false,
        onRun: run,
        loading: loading,
        children: [
          if (_rows.isEmpty)
            GenericCard(children: const [
              Center(child: Text('No sales in this period.', style: TextStyle(color: TColors.slate500))),
            ])
          else
            ReportTable(
              rows: _rows,
              empty: '',
              columns: [
                RCol('Product', (r) => tStr(r['productName']), bold: true),
                RCol('SKU', (r) => tStr(r['sku']).isEmpty ? '—' : tStr(r['sku'])),
                RCol('Quantity', (r) => '${tNum(r['totalQuantity'])}'.replaceAll(RegExp(r'\.0$'), ''), right: true),
                RCol('Revenue', (r) => fmtMoney(r['totalRevenue']), right: true),
                RCol('Cost', (r) => fmtMoney(r['totalCost']), right: true),
                RCol('Profit', (r) => fmtMoney(tNum(r['totalRevenue']) - tNum(r['totalCost'])), right: true, color: _emerald700, bold: true),
                RCol('Sales', (r) => '${tNum(r['salesCount']).toInt()}', right: true),
              ],
            ),
        ],
      );
}

// ===================================================== Sales by customer

class GenericSalesByCustomerScreen extends _Report {
  const GenericSalesByCustomerScreen({super.key, required super.session, required super.company});
  @override
  State<GenericSalesByCustomerScreen> createState() => _ByCustomerState();
}

class _ByCustomerState extends _ReportState<GenericSalesByCustomerScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    startReport(currentMonthRange());
  }

  @override
  Future<void> fetch() async => _rows = reportRows(await get('sales-by-customer', rangeQuery));

  @override
  Widget build(BuildContext context) => GenericReportShell(
        session: session,
        company: company,
        href: '/generic-reports/sales-by-customer',
        title: 'Sales by customer',
        icon: Icons.people_outline,
        iconColor: const Tone.fg(0xFF0891B2),
        range: range,
        onRangeChange: setRange,
        showDates: false,
        onRun: run,
        loading: loading,
        children: [
          if (_rows.isEmpty)
            GenericCard(children: const [
              Center(child: Text('No sales in this period.', style: TextStyle(color: TColors.slate500))),
            ])
          else
            ReportTable(
              rows: _rows,
              empty: '',
              columns: [
                RCol('Customer', (r) => tStr(r['customerName']), bold: true),
                RCol('Phone', (r) => tStr(r['phoneNumber']).isEmpty ? '—' : tStr(r['phoneNumber'])),
                RCol('Sales', (r) => '${tNum(r['salesCount']).toInt()}', right: true),
                RCol('Revenue', (r) => fmtMoney(r['totalRevenue']), right: true),
                RCol('Paid', (r) => fmtMoney(r['totalPaid']), right: true),
                RCol('Outstanding', (r) => Text(
                      fmtMoney(r['totalOutstanding']),
                      style: TextStyle(
                        fontSize: 13,
                        color: tNum(r['totalOutstanding']) > 0 ? _rose700 : TColors.slate900,
                        fontWeight: tNum(r['totalOutstanding']) > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ), right: true),
              ],
            ),
        ],
      );
}

// ======================================================= Inventory value

class GenericInventoryValueScreen extends _Report {
  const GenericInventoryValueScreen({super.key, required super.session, required super.company});
  @override
  State<GenericInventoryValueScreen> createState() => _InventoryState();
}

class _InventoryState extends _ReportState<GenericInventoryValueScreen> {
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    startReport((from: '', to: ''));
  }

  @override
  Future<void> fetch() async {
    final r = await get('inventory-value');
    _report = r is Map ? Map<String, dynamic>.from(r) : null;
  }

  @override
  Widget build(BuildContext context) {
    final rep = _report;
    final lead = sidebarLeading(context, session, company, href: '/generic-reports/inventory-value');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Inventory value')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to reports', style: TextStyle(fontSize: 13)),
            ),
          ),
          const GenericTitle(icon: Icons.inventory_2_outlined, iconColor: Tone.fg(0xFFEA580C), title: 'Inventory value'),
          const SizedBox(height: 14),
          if (loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else if (rep != null) ...[
            StatGrid(columns: 1, [
              ReportStat(title: 'Total cost value', value: fmtMoney(rep['totalCostValue'])),
              ReportStat(title: 'Total retail value', value: fmtMoney(rep['totalRetailValue']), accent: Accent.emerald),
              ReportStat(title: 'Products', value: '${tNum(rep['productCount']).toInt()}'),
            ]),
            ReportTable(
              title: 'By category',
              rows: reportRows(rep['byCategory']),
              empty: 'No tracked products.',
              columns: [
                RCol('Category', (r) => tStr(r['categoryName']), bold: true),
                RCol('Products', (r) => '${tNum(r['productCount']).toInt()}', right: true),
                RCol('Units', (r) => '${tNum(r['totalUnits'])}'.replaceAll(RegExp(r'\.0$'), ''), right: true),
                RCol('Cost value', (r) => fmtMoney(r['totalCostValue']), right: true),
                RCol('Retail value', (r) => fmtMoney(r['totalRetailValue']), right: true),
                RCol('Potential margin', (r) => fmtMoney(tNum(r['totalRetailValue']) - tNum(r['totalCostValue'])),
                    right: true, color: _emerald700, bold: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
