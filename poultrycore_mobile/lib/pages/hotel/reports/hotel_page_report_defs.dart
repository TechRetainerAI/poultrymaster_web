// app/hotel-reports/<slug>/page.tsx: the sixteen Hotel reports that own their
// pages on the web (the original seventeen, less Guest Ledger which moved into
// the registry). Each page loads whole lists and filters them by date in the
// browser, so the loaders here do the same. They render through the shared
// report shell; the web's tiles, charts, side tables and main table are the
// summary, panel and columns below, and the PDF / CSV carry the same table the
// web exports.

import 'package:flutter/material.dart';

import '../../../design/ui/inputs.dart';
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../../restaurant/reports/restaurant_report_kit.dart';

const _violet = Color(0xFF7C3AED);
const _red = Color(0xFFEF4444);
const _green = Color(0xFF059669);
const _blue700 = Color(0xFF1D4ED8);

/// `r.camelKey ?? r.lowercasekey`, as every page reads its rows.
Object? _v(Map r, String k) => r[k] ?? r[k.toLowerCase()];
String _s(Map r, String k) => tStr(_v(r, k));
num _n(Map r, String k) => tNum(_v(r, k));
String _day(Map r, String k) => d10(_v(r, k));
String _or(String s) => s.isEmpty ? '-' : s;
bool _inRange(String d, RRange r) => d.compareTo(r.from) >= 0 && d.compareTo(r.to) <= 0;
String _guest(Map b) => '${_s(b, 'guestFirstName')} ${_s(b, 'guestLastName')}'.trim();
String _status(Map r) => tStr(r['status']).toLowerCase();

/// A coloured pill, as the pages' rounded-full status spans.
Widget _pill(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );

const _bBlue = (Color(0xFFDBEAFE), Color(0xFF1D4ED8));
const _bGreen = (Color(0xFFDCFCE7), Color(0xFF15803D));
const _bSlate = (Color(0xFFF1F5F9), Color(0xFF334155));
const _bRed = (Color(0xFFFEE2E2), Color(0xFFB91C1C));
const _bAmber = (Color(0xFFFEF3C7), Color(0xFFB45309));
const _bIndigo = (Color(0xFFE0E7FF), Color(0xFF4338CA));

Widget _badge(String text, (Color, Color) tone) => _pill(text, tone.$1, tone.$2);

/// A titled table inside the panel (By Category, Check-ins, …), drawn as the
/// shell's own table so it reads the same on a phone.
Widget _table(String title, List<RCol> cols, List<Map> rows, RFmt f, {String? empty}) => ReportTableCard(
      def: RDef(load: (c, r) async => const RLoad([]), columns: cols, tableTitle: title, emptyText: empty),
      rows: rows,
      fmt: f,
    );

Widget _gap(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
    ]);

String _mmdd(String d) => d.length >= 10 ? d.substring(5, 10) : d;

RCol _money(String key, String label, num Function(Map r) v, {Color? color, bool bold = false}) => RCol(
      key,
      label,
      (r, f) => f.num_(v(r)),
      numeric: true,
      render: color == null ? null : (r, f) => coloured(f.num_(v(r)), color, bold: bold),
    );

// ===========================================================================
// FINANCIAL
// ===========================================================================

final _revenueSummary = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/reports/daily-closings')).where((x) => _inRange(_day(x, 'closingDate'), r)).toList()
      ..sort((a, b) => _day(b, 'closingDate').compareTo(_day(a, 'closingDate')));
    return RLoad(rows);
  },
  summary: (r, f) {
    final rev = sumOf(r.rows, (x) => _n(x, 'totalRevenue'));
    final exp = sumOf(r.rows, (x) => _n(x, 'totalExpenses'));
    final occ = r.rows.isEmpty ? 0 : sumOf(r.rows, (x) => _n(x, 'occupancyRate')) / r.rows.length;
    return [
      (label: 'Total Revenue', value: f.money(rev)),
      (label: 'Total Expenses', value: f.money(exp)),
      (label: 'Net Profit', value: f.money(rev - exp)),
      (label: 'Avg Occupancy', value: f.pct(occ)),
    ];
  },
  panel: (r, f) {
    if (r.rows.isEmpty) return null;
    final asc = r.rows.reversed.toList();
    return reportCard(
      'Revenue vs Expenses',
      null,
      BarChartRows(items: [for (final x in asc) _mmdd(_day(x, 'closingDate'))], series: [
        ('Revenue', _violet, [for (final x in asc) _n(x, 'totalRevenue')], f.money),
        ('Expenses', _red, [for (final x in asc) _n(x, 'totalExpenses')], f.money),
      ]),
    );
  },
  tableTitle: 'Daily Closings ({n})',
  emptyText: 'No closings found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'closingDate')),
    _money('revenue', 'Revenue', (r) => _n(r, 'totalRevenue'), color: emerald700),
    _money('expenses', 'Expenses', (r) => _n(r, 'totalExpenses'), color: red600),
    RCol('net', 'Net', (r, f) => f.num_(_n(r, 'totalRevenue') - _n(r, 'totalExpenses')), numeric: true, render: (r, f) {
      final net = _n(r, 'totalRevenue') - _n(r, 'totalExpenses');
      return coloured(f.num_(net), net >= 0 ? emerald700 : red700, bold: true);
    }),
    RCol('occ', 'Occupancy %', (r, f) => f.pct(_n(r, 'occupancyRate')), numeric: true),
    RCol('rooms', 'Rooms Occupied', (r, f) => '${_n(r, 'roomsOccupied')}/${_n(r, 'totalRooms')}', numeric: true),
    RCol('adr', 'ADR', (r, f) => f.num_(_n(r, 'adr')), numeric: true),
    RCol('revpar', 'RevPAR', (r, f) => f.num_(_n(r, 'revPar')), numeric: true),
  ],
);

final _expenseReport = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/finance/expenses')).where((x) => _inRange(_day(x, 'expenseDate'), r)).toList()
      ..sort((a, b) => _n(b, 'amount').compareTo(_n(a, 'amount')));
    return RLoad(rows);
  },
  summary: (r, f) {
    final total = sumOf(r.rows, (x) => _n(x, 'amount'));
    return [
      (label: 'Total Expenses', value: f.money(total)),
      (label: 'Categories', value: '${_expenseCategories(r.rows).length}'),
      (label: 'Avg per Expense', value: f.money(r.rows.isEmpty ? 0 : total / r.rows.length)),
    ];
  },
  panel: (r, f) {
    final cats = _expenseCategories(r.rows);
    if (cats.isEmpty) return null;
    return _table('By Category', [
      RCol('category', 'Category', (x, f) => tStr(x['category'])),
      RCol('count', 'Count', (x, f) => '${x['count']}', numeric: true),
      _money('total', 'Total Amount', (x) => tNum(x['total']), color: red600),
    ], cats, f);
  },
  tableTitle: 'Expense Details ({n})',
  emptyText: 'No expenses found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'expenseDate')),
    RCol('category', 'Category', (r, f) => _s(r, 'category')),
    RCol('description', 'Description', (r, f) => _s(r, 'description')),
    RCol('vendor', 'Vendor', (r, f) => _or(_s(r, 'vendor'))),
    _money('amount', 'Amount', (r) => _n(r, 'amount'), color: red600, bold: true),
  ],
);

/// Expenses grouped by category, largest total first.
List<Map> _expenseCategories(List<Map> rows) {
  final m = <String, Map<String, num>>{};
  for (final x in rows) {
    final cat = _s(x, 'category').isEmpty ? 'Uncategorized' : _s(x, 'category');
    final e = m.putIfAbsent(cat, () => {'count': 0, 'total': 0});
    e['count'] = e['count']! + 1;
    e['total'] = e['total']! + _n(x, 'amount');
  }
  return [for (final e in m.entries) {'category': e.key, ...e.value}]..sort((a, b) => tNum(b['total']).compareTo(tNum(a['total'])));
}

final _billingReport = RDef(
  presets: false,
  load: (c, r) async {
    final res = await Future.wait([c.list('/api/Hotel/billing/payments'), c.list('/api/Hotel/bookings')]);
    final bookings = {for (final b in res[1]) _n(b, 'hotelBookingId'): b};
    final rows = [
      for (final p in res[0])
        if (_inRange(_day(p, 'paymentDate'), r))
          {
            ...p,
            '_guest': bookings[_n(p, 'hotelBookingId')] == null ? '' : _guest(bookings[_n(p, 'hotelBookingId')]!),
            '_ref': bookings[_n(p, 'hotelBookingId')] == null ? '' : _s(bookings[_n(p, 'hotelBookingId')]!, 'bookingRef'),
          },
    ]..sort((a, b) => _day(b, 'paymentDate').compareTo(_day(a, 'paymentDate')));
    return RLoad(rows);
  },
  summary: (r, f) {
    final m = _byMethod(r.rows);
    return [
      (label: 'Total Payments', value: f.money(sumOf(r.rows, (x) => _n(x, 'amount')))),
      (label: 'Cash', value: f.money(m['Cash'] ?? 0)),
      (label: 'MoMo', value: f.money(m['MoMo'] ?? m['Mobile Money'] ?? m['momo'] ?? 0)),
      (label: 'Bank', value: f.money(m['Bank'] ?? m['Bank Transfer'] ?? m['bank'] ?? 0)),
    ];
  },
  panel: (r, f) {
    final m = _byMethod(r.rows).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (m.isEmpty) return null;
    return _table('By Payment Method', [
      RCol('method', 'Method', (x, f) => tStr(x['method'])),
      _money('total', 'Total', (x) => tNum(x['total']), color: emerald700, bold: true),
    ], [for (final e in m) {'method': e.key, 'total': e.value}], f);
  },
  tableTitle: 'Payment Details ({n})',
  emptyText: 'No payments found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'paymentDate')),
    RCol('ref', 'Booking Ref', (r, f) => _or(tStr(r['_ref']))),
    RCol('guest', 'Guest', (r, f) => _or(tStr(r['_guest']))),
    _money('amount', 'Amount', (r) => _n(r, 'amount'), color: emerald700, bold: true),
    RCol('method', 'Method', (r, f) => _or(_s(r, 'paymentMethod'))),
    RCol('reference', 'Reference', (r, f) => _or(_s(r, 'reference'))),
    RCol('by', 'Received By', (r, f) => _or(_s(r, 'receivedBy'))),
  ],
);

Map<String, num> _byMethod(List<Map> rows) {
  final m = <String, num>{};
  for (final x in rows) {
    final k = _s(x, 'paymentMethod').isEmpty ? 'Other' : _s(x, 'paymentMethod');
    m[k] = (m[k] ?? 0) + _n(x, 'amount');
  }
  return m;
}

Widget _runStatus(String status) => switch (status.toLowerCase()) {
      'approved' => _badge('Approved', _bBlue),
      'paid' => _badge('Paid', _bGreen),
      'cancelled' => _badge('Cancelled', _bRed),
      _ => _badge(status.isEmpty ? 'Draft' : status, _bSlate),
    };

final _payrollReport = RDef(
  presets: false,
  load: (c, r) async => RLoad(await c.list('/api/Hotel/payroll-runs')),
  summary: (r, f) => [
    (label: 'Total Runs', value: '${r.rows.length}'),
    (label: 'Total Gross', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalGross')))),
    (label: 'Total Deductions', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalDeductions')))),
    (label: 'Total Net', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalNet')))),
  ],
  tableTitle: 'Payroll Runs ({n})',
  emptyText: 'No payroll runs found.',
  columns: [
    RCol('period', 'Period', (r, f) => '${_day(r, 'periodStart')} - ${_day(r, 'periodEnd')}'),
    RCol('status', 'Status', (r, f) => tStr(r['status']).isEmpty ? 'Draft' : tStr(r['status']), render: (r, f) => _runStatus(tStr(r['status']))),
    _money('gross', 'Gross', (r) => _n(r, 'totalGross'), color: emerald700),
    _money('deductions', 'Deductions', (r) => _n(r, 'totalDeductions'), color: red600),
    _money('net', 'Net', (r) => _n(r, 'totalNet'), color: _blue700, bold: true),
    RCol('account', 'Cash Account', (r, f) => _or(_s(r, 'cashAccountName'))),
    RCol('createdBy', 'Created By', (r, f) => _or(_s(r, 'createdBy'))),
    RCol('approvedBy', 'Approved By', (r, f) => _or(_s(r, 'approvedBy'))),
  ],
);

/// Staff loan movements post four source types; the page groups them.
String _sourceGroup(String src) => src.startsWith('EmployeeLoan') ? 'StaffLoans' : src;
const _sourceLabel = {'StaffLoans': 'Staff loans'};

final _cashFlowReport = RDef(
  presets: false,
  filters: [
    RFilter('account', 'Account', (meta) => [
          ('all', 'All Accounts'),
          for (final a in (meta is Map ? meta['accounts'] as List<Map>? ?? const <Map>[] : const <Map>[]))
            ('${_n(a, 'hotelCashAccountId')}', _s(a, 'accountName')),
        ]),
    RFilter('source', 'Source', (_) => const [
          ('all', 'All Sources'),
          ('Payment', 'Payments'),
          ('Expense', 'Expenses'),
          ('Order', 'Restaurant'),
          ('Payroll', 'Payroll'),
          ('StaffLoans', 'Staff loans'),
        ]),
  ],
  load: (c, r) async {
    final res = await Future.wait([c.list('/api/Hotel/finance/cash-accounts'), c.list('/api/Hotel/finance/cash-transactions')]);
    final account = r.extra['account'] ?? 'all', source = r.extra['source'] ?? 'all';
    final rows = [
      for (final t in res[1])
        if (_inRange(_day(t, 'txnDate'), r) &&
            (account == 'all' || '${_n(t, 'hotelCashAccountId')}' == account) &&
            (source == 'all' || _sourceGroup(_s(t, 'sourceType')) == source))
          t,
    ];
    return RLoad(rows, {'accounts': res[0]});
  },
  summary: (r, f) {
    final inflow = sumOf(r.rows.where(_isCredit), (t) => _n(t, 'amount'));
    final outflow = sumOf(r.rows.where((t) => _s(t, 'txnType') == 'Debit'), (t) => _n(t, 'amount'));
    return [
      (label: 'Total Inflow', value: f.money(inflow)),
      (label: 'Total Outflow', value: f.money(outflow)),
      (label: 'Net Cash Flow', value: f.money(inflow - outflow)),
      (label: 'Transactions', value: '${r.rows.length}'),
    ];
  },
  panel: (r, f) {
    final byDay = <String, (num, num)>{};
    for (final t in r.rows) {
      final d = _day(t, 'txnDate'), e = byDay[d] ?? (0, 0);
      byDay[d] = _isCredit(t) ? (e.$1 + _n(t, 'amount'), e.$2) : (e.$1, e.$2 + _n(t, 'amount'));
    }
    final days = byDay.keys.toList()..sort();
    final accounts = [
      for (final a in (r.meta as Map?)?['accounts'] as List<Map>? ?? const <Map>[])
        if (r.rows.any((t) => _n(t, 'hotelCashAccountId') == _n(a, 'hotelCashAccountId')))
          () {
            final txns = r.rows.where((t) => _n(t, 'hotelCashAccountId') == _n(a, 'hotelCashAccountId'));
            final inn = sumOf(txns.where(_isCredit), (t) => _n(t, 'amount'));
            final out = sumOf(txns.where((t) => _s(t, 'txnType') == 'Debit'), (t) => _n(t, 'amount'));
            return {'name': _s(a, 'accountName'), 'purpose': _s(a, 'purpose'), 'in': inn, 'out': out, 'net': inn - out, 'balance': _n(a, 'currentBalance')};
          }(),
    ];
    final sources = [
      for (final src in const ['Payment', 'Expense', 'Order', 'Payroll', 'StaffLoans'])
        if (r.rows.any((t) => _sourceGroup(_s(t, 'sourceType')) == src))
          {
            'source': _sourceLabel[src] ?? src,
            'count': r.rows.where((t) => _sourceGroup(_s(t, 'sourceType')) == src).length,
            'total': sumOf(r.rows.where((t) => _sourceGroup(_s(t, 'sourceType')) == src), (t) => _n(t, 'amount')),
          },
    ];
    final parts = <Widget>[
      if (days.length > 1)
        reportCard(
          'Daily Cash Flow',
          null,
          BarChartRows(items: days, series: [
            ('Inflow', _green, [for (final d in days) byDay[d]!.$1], f.money),
            ('Outflow', const Color(0xFFDC2626), [for (final d in days) byDay[d]!.$2], f.money),
          ]),
        ),
      if (accounts.isNotEmpty)
        _table('By Account', [
          RCol('name', 'Account', (x, f) => tStr(x['name']), render: (x, f) => Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(x['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                if (tStr(x['purpose']).isNotEmpty) toneBadge(tStr(x['purpose']), 'muted'),
              ])),
          _money('in', 'In', (x) => tNum(x['in']), color: emerald700),
          _money('out', 'Out', (x) => tNum(x['out']), color: red700),
          RCol('net', 'Net', (x, f) => f.num_(x['net']), numeric: true,
              render: (x, f) => coloured(f.num_(x['net']), tNum(x['net']) >= 0 ? emerald700 : red700, bold: true)),
          _money('balance', 'Balance', (x) => tNum(x['balance']), color: TColors.violet700, bold: true),
        ], accounts, f),
      if (sources.isNotEmpty)
        _table('By Source', [
          RCol('source', 'Source', (x, f) => tStr(x['source'])),
          RCol('count', 'Count', (x, f) => '${x['count']}', numeric: true),
          RCol('total', 'Total', (x, f) => f.num_(x['total']), numeric: true),
        ], sources, f),
    ];
    return parts.isEmpty ? null : _gap(parts);
  },
  tableTitle: 'Transaction Log ({n})',
  emptyText: 'No transactions found for the selected filters.',
  columns: [
    RCol('date', 'Date', (t, f) => _day(t, 'txnDate')),
    RCol('account', 'Account', (t, f) => _or(_s(t, 'accountName'))),
    RCol('type', 'Type', (t, f) => _s(t, 'txnType'),
        render: (t, f) => _isCredit(t) ? _badge('↙ In', (const Color(0xFFD1FAE5), emerald700)) : _badge('↗ Out', _bRed)),
    RCol('description', 'Description', (t, f) => _or(_s(t, 'description'))),
    RCol('source', 'Source', (t, f) => _s(t, 'sourceType'), render: (t, f) => toneBadge(_or(_s(t, 'sourceType')), 'muted')),
    RCol('reference', 'Reference', (t, f) => _or(_s(t, 'reference'))),
    RCol('amount', 'Amount', (t, f) => f.num_(_n(t, 'amount')), numeric: true,
        render: (t, f) => coloured('${_isCredit(t) ? '+' : '-'}${f.num_(_n(t, 'amount'))}', _isCredit(t) ? emerald700 : red700, bold: true)),
    RCol('balance', 'Balance After', (t, f) => f.num_(_n(t, 'balanceAfter')), numeric: true),
    RCol('by', 'By', (t, f) => _s(t, 'createdBy').isEmpty ? 'System' : _s(t, 'createdBy')),
  ],
);

bool _isCredit(Map t) => _s(t, 'txnType') == 'Credit';

// ===========================================================================
// OPERATIONS
// ===========================================================================

int _nights(Map b) {
  final ci = DateTime.tryParse(_day(b, 'checkInDate')), co = DateTime.tryParse(_day(b, 'checkOutDate'));
  if (ci == null || co == null) return 1;
  final n = co.difference(ci).inDays;
  return n < 1 ? 1 : n;
}

Widget _bookingStatus(String status) => switch (status.toLowerCase()) {
      'confirmed' => _badge('Confirmed', _bBlue),
      'checkedin' => _badge('Checked In', _bGreen),
      'checkedout' => _badge('Checked Out', _bSlate),
      'cancelled' => _badge('Cancelled', _bRed),
      'pending' => _badge('Pending', _bAmber),
      _ => _badge(status, (const Color(0xFFF1F5F9), const Color(0xFF475569))),
    };

final _bookingsReport = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/bookings')).where((x) => _inRange(_day(x, 'checkInDate'), r)).toList()
      ..sort((a, b) => _day(b, 'checkInDate').compareTo(_day(a, 'checkInDate')));
    return RLoad(rows);
  },
  summary: (r, f) => [
    (label: 'Total Bookings', value: '${r.rows.length}'),
    (label: 'Confirmed', value: '${r.rows.where((x) => _status(x) == 'confirmed').length}'),
    (label: 'Checked In', value: '${r.rows.where((x) => _status(x) == 'checkedin').length}'),
    (label: 'Cancelled', value: '${r.rows.where((x) => _status(x) == 'cancelled').length}'),
    (label: 'Total Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalAmount')))),
  ],
  tableTitle: 'Bookings ({n})',
  emptyText: 'No bookings found for this period.',
  columns: [
    RCol('ref', 'Booking Ref', (r, f) => _or(_s(r, 'bookingRef'))),
    RCol('guest', 'Guest', (r, f) => _or(_guest(r))),
    RCol('room', 'Room', (r, f) => _or(_s(r, 'roomNumber'))),
    RCol('in', 'Check-in', (r, f) => _day(r, 'checkInDate')),
    RCol('out', 'Check-out', (r, f) => _day(r, 'checkOutDate')),
    RCol('nights', 'Nights', (r, f) => '${_nights(r)}', numeric: true),
    RCol('rate', 'Rate', (r, f) => f.num_(_n(r, 'nightlyRate')), numeric: true),
    _money('total', 'Total', (r) => _n(r, 'totalAmount'), color: emerald700, bold: true),
    RCol('status', 'Status', (r, f) => tStr(r['status']), render: (r, f) => _bookingStatus(tStr(r['status']))),
  ],
);

final _guestReport = RDef(
  presets: false,
  load: (c, r) async {
    final res = await Future.wait([c.list('/api/Hotel/guests'), c.list('/api/Hotel/bookings')]);
    final stats = <num, (int, num, String)>{};
    for (final b in res[1]) {
      final gid = _n(b, 'hotelGuestId');
      if (gid == 0) continue;
      final e = stats[gid] ?? (0, 0, '');
      final ci = _day(b, 'checkInDate');
      stats[gid] = (e.$1 + 1, e.$2 + _n(b, 'totalAmount'), ci.compareTo(e.$3) > 0 ? ci : e.$3);
    }
    final rows = [
      for (final g in res[0])
        () {
          final e = stats[_n(g, 'hotelGuestId')] ?? (0, 0, '');
          return {...g, '_bookings': e.$1, '_spent': e.$2, '_last': e.$3.isNotEmpty ? e.$3 : _day(g, 'lastStayDate')};
        }(),
    ]..sort((a, b) => tNum(b['_bookings']).compareTo(tNum(a['_bookings'])));
    return RLoad(rows);
  },
  summary: (r, f) {
    final repeat = r.rows.where((g) => tNum(g['_bookings']) > 1).length;
    return [
      (label: 'Total Guests', value: '${r.rows.length}'),
      (label: 'VIP Guests', value: '${r.rows.where((g) => _v(g, 'isVIP') == true).length}'),
      (label: 'Repeat Guests', value: '$repeat'),
      (label: 'New Guests', value: '${r.rows.length - repeat}'),
    ];
  },
  tableTitle: 'Guest List ({n})',
  emptyText: 'No guests found.',
  columns: [
    RCol('name', 'Name', (g, f) => _or('${_s(g, 'firstName')} ${_s(g, 'lastName')}'.trim())),
    RCol('email', 'Email', (g, f) => _or(_s(g, 'email'))),
    RCol('phone', 'Phone', (g, f) => _or(_s(g, 'phone'))),
    RCol('vip', 'VIP', (g, f) => _v(g, 'isVIP') == true ? 'Yes' : 'No',
        render: (g, f) => _v(g, 'isVIP') == true ? _badge('VIP', _bAmber) : const Text('-', style: TextStyle(fontSize: 12))),
    RCol('bookings', 'Bookings', (g, f) => '${g['_bookings']}', numeric: true),
    RCol('last', 'Last Stay', (g, f) => _or(d10(g['_last']))),
    _money('spent', 'Total Spent', (g) => tNum(g['_spent']), color: emerald700, bold: true),
  ],
);

final _occupancyReport = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/reports/daily-closings')).where((x) => _inRange(_day(x, 'closingDate'), r)).toList()
      ..sort((a, b) => _day(a, 'closingDate').compareTo(_day(b, 'closingDate')));
    return RLoad(rows);
  },
  summary: (r, f) {
    num avg(String k) => r.rows.isEmpty ? 0 : sumOf(r.rows, (x) => _n(x, k)) / r.rows.length;
    return [
      (label: 'Avg Occupancy', value: f.pct(avg('occupancyRate'))),
      (label: 'Avg ADR', value: f.num_(avg('adr'))),
      (label: 'Avg RevPAR', value: f.num_(avg('revPar'))),
      (label: 'Total Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard(
          'Occupancy Trend',
          null,
          BarChartRows(items: [for (final x in r.rows) _mmdd(_day(x, 'closingDate'))], series: [
            ('Occupancy %', _violet, [for (final x in r.rows) _n(x, 'occupancyRate')], (v) => f.pct(v)),
          ]),
        ),
  tableTitle: 'Occupancy Data ({n})',
  emptyText: 'No occupancy data found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'closingDate')),
    RCol('occ', 'Occupancy %', (r, f) => f.pct(_n(r, 'occupancyRate')), numeric: true),
    RCol('occupied', 'Rooms Occupied', (r, f) => '${_n(r, 'roomsOccupied')}', numeric: true),
    RCol('total', 'Total Rooms', (r, f) => '${_n(r, 'totalRooms')}', numeric: true),
    RCol('adr', 'ADR', (r, f) => f.num_(_n(r, 'adr')), numeric: true),
    RCol('revpar', 'RevPAR', (r, f) => f.num_(_n(r, 'revPar')), numeric: true),
    _money('revenue', 'Revenue', (r) => _n(r, 'totalRevenue'), color: emerald700, bold: true),
  ],
);

Widget _priority(String p) => switch (p.toLowerCase()) {
      'high' || 'urgent' => _badge(p, _bRed),
      'medium' || 'normal' => _badge(p, _bAmber),
      'low' => _badge(p, _bGreen),
      _ => _badge(p, (const Color(0xFFF1F5F9), const Color(0xFF475569))),
    };

Widget _maintenanceStatus(String s) => switch (s.toLowerCase()) {
      'open' => _badge('Open', _bRed),
      'inprogress' => _badge('In Progress', _bAmber),
      'completed' => _badge('Completed', _bGreen),
      _ => _badge(s, (const Color(0xFFF1F5F9), const Color(0xFF475569))),
    };

final _maintenanceReport = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/maintenance')).where((x) => _inRange(_day(x, 'createdAt'), r)).toList()
      ..sort((a, b) => _day(b, 'createdAt').compareTo(_day(a, 'createdAt')));
    return RLoad(rows);
  },
  summary: (r, f) => [
    (label: 'Total Requests', value: '${r.rows.length}'),
    (label: 'Open', value: '${r.rows.where((x) => _status(x) == 'open').length}'),
    (label: 'In Progress', value: '${r.rows.where((x) => _status(x) == 'inprogress').length}'),
    (label: 'Completed', value: '${r.rows.where((x) => _status(x) == 'completed').length}'),
    (label: 'Est. Cost Total', value: f.money(sumOf(r.rows, (x) => _n(x, 'estimatedCost')))),
  ],
  tableTitle: 'Maintenance Requests ({n})',
  emptyText: 'No maintenance requests found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'createdAt')),
    RCol('room', 'Room', (r, f) => _or(_s(r, 'roomNumber'))),
    RCol('asset', 'Asset', (r, f) => _or(_s(r, 'assetDescription'))),
    RCol('issue', 'Issue', (r, f) => _or(_s(r, 'issueDescription'))),
    RCol('priority', 'Priority', (r, f) => tStr(r['priority']), render: (r, f) => _priority(tStr(r['priority']))),
    RCol('status', 'Status', (r, f) => tStr(r['status']), render: (r, f) => _maintenanceStatus(tStr(r['status']))),
    RCol('cost', 'Est. Cost', (r, f) => f.num_(_n(r, 'estimatedCost')), numeric: true),
    RCol('completed', 'Completed', (r, f) => _or(_day(r, 'completedAt'))),
  ],
);

// ===========================================================================
// RESTAURANT & BAR
// ===========================================================================

Widget _orderStatus(String s) => switch (s.toLowerCase()) {
      'placed' => _badge('Placed', _bAmber),
      'preparing' => _badge('Preparing', _bBlue),
      'ready' => _badge('Ready', _bIndigo),
      'served' => _badge('Served', _bGreen),
      'cancelled' => _badge('Cancelled', _bRed),
      _ => _badge(s, (const Color(0xFFF1F5F9), const Color(0xFF475569))),
    };

final _restaurantSales = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/restaurant/orders')).where((x) => _inRange(_day(x, 'orderTime'), r)).toList()
      ..sort((a, b) => _s(b, 'orderTime').compareTo(_s(a, 'orderTime')));
    return RLoad(rows);
  },
  summary: (r, f) {
    final total = sumOf(r.rows, (x) => _n(x, 'totalAmount'));
    return [
      (label: 'Total Orders', value: '${r.rows.length}'),
      (label: 'Total Revenue', value: f.money(total)),
      (label: 'Avg Order Value', value: f.money(r.rows.isEmpty ? 0 : total / r.rows.length)),
      (label: 'Served', value: '${r.rows.where((x) => _status(x) == 'served').length}'),
    ];
  },
  panel: (r, f) {
    final byDay = <String, num>{};
    for (final x in r.rows) {
      byDay[_day(x, 'orderTime')] = (byDay[_day(x, 'orderTime')] ?? 0) + _n(x, 'totalAmount');
    }
    if (byDay.isEmpty) return null;
    final days = byDay.keys.toList()..sort();
    return reportCard(
      'Daily Order Totals',
      null,
      BarChartRows(items: [for (final d in days) _mmdd(d)], series: [('Revenue', _violet, [for (final d in days) byDay[d]!], f.money)]),
    );
  },
  tableTitle: 'Orders ({n})',
  emptyText: 'No orders found for this period.',
  columns: [
    RCol('date', 'Date', (r, f) => _day(r, 'orderTime')),
    RCol('order', 'Order #', (r, f) => _s(r, 'hotelRestaurantOrderId'), render: (r, f) => Text('#${_s(r, 'hotelRestaurantOrderId')}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900))),
    RCol('table', 'Table', (r, f) => _or(_s(r, 'tableNumber'))),
    RCol('server', 'Server', (r, f) => _or(_s(r, 'serverName'))),
    RCol('subtotal', 'Subtotal', (r, f) => f.num_(_n(r, 'subTotal')), numeric: true),
    _money('total', 'Total', (r) => _n(r, 'totalAmount'), color: emerald700, bold: true),
    RCol('status', 'Status', (r, f) => tStr(r['status']), render: (r, f) => _orderStatus(tStr(r['status']))),
  ],
);

String _menuName(Map m) => tStr(m['name']).isNotEmpty ? tStr(m['name']) : _s(m, 'itemName');
String _menuCategory(Map m) => tStr(m['category']).isNotEmpty ? tStr(m['category']) : _s(m, 'categoryName');
bool _available(Map m) => _v(m, 'isAvailable') != false;

final _menuPerformance = RDef(
  presets: false,
  load: (c, r) async {
    final rows = (await c.list('/api/Hotel/restaurant/menu'))
      ..sort((a, b) {
        final cat = _menuCategory(a).toLowerCase().compareTo(_menuCategory(b).toLowerCase());
        return cat != 0 ? cat : _menuName(a).toLowerCase().compareTo(_menuName(b).toLowerCase());
      });
    return RLoad(rows);
  },
  summary: (r, f) {
    final available = r.rows.where(_available).length;
    return [
      (label: 'Total Items', value: '${r.rows.length}'),
      (label: 'Available', value: '$available'),
      (label: 'Unavailable', value: '${r.rows.length - available}'),
      (label: 'Avg Price', value: f.money(r.rows.isEmpty ? 0 : sumOf(r.rows, (m) => tNum(m['price'])) / r.rows.length)),
    ];
  },
  tableTitle: 'Menu Items ({n})',
  emptyText: 'No menu items found.',
  columns: [
    RCol('name', 'Name', (m, f) => _or(_menuName(m))),
    RCol('category', 'Category', (m, f) => _or(_menuCategory(m))),
    _money('price', 'Price', (m) => tNum(m['price']), color: emerald700, bold: true),
    RCol('available', 'Available', (m, f) => _available(m) ? 'Yes' : 'No',
        render: (m, f) => _available(m) ? _badge('Yes', _bGreen) : _badge('No', _bRed)),
  ],
);

// ===========================================================================
// PERIODIC
// ===========================================================================

/// Bookings, payments, expenses and closings: what the periodic pages load.
Future<List<List<Map>>> _periodic(RCtx c, {bool staff = false}) => Future.wait([
      c.list('/api/Hotel/bookings'),
      c.list('/api/Hotel/billing/payments'),
      c.list('/api/Hotel/finance/expenses'),
      c.list('/api/Hotel/reports/daily-closings'),
      if (staff) c.list('/api/Hotel/staff'),
    ]);

num _paid(Map p) => _v(p, 'amount') != null ? _n(p, 'amount') : _n(p, 'totalAmount');

/// The guest on a booking or payment: guest… names, else first / last name.
String _who(Map b) {
  String pick(String a, String b2) => _s(b, a).isNotEmpty ? _s(b, a) : _s(b, b2);
  return '${pick('guestFirstName', 'firstName')} ${pick('guestLastName', 'lastName')}'.trim();
}

/// A day's revenue and expenses: the daily closing when there is one,
/// otherwise the payments and expenses dated that day.
(num, num) _dayTotals(String d, List<Map> payments, List<Map> expenses, List<Map> closings) {
  final closing = closings.where((c) => _day(c, 'closingDate') == d).firstOrNull;
  if (closing != null) return (_n(closing, 'totalRevenue'), _n(closing, 'totalExpenses'));
  return (
    sumOf(payments.where((p) => _day(p, 'paymentDate') == d), _paid),
    sumOf(expenses.where((x) => _day(x, 'expenseDate') == d), (x) => _n(x, 'amount')),
  );
}

final _dailyReport = RDef(
  showTable: false,
  dateControl: (r, set) => TCard(
    padding: const EdgeInsets.all(12),
    child: reportDateBox(r.date, (v) => set(r.copyWith(date: v))),
  ),
  load: (c, r) async {
    final [bookings, payments, expenses, closings] = await _periodic(c);
    final ins = bookings.where((b) => _day(b, 'checkInDate') == r.date).toList();
    final outs = bookings.where((b) => _day(b, 'checkOutDate') == r.date).toList();
    final pays = payments.where((p) => _day(p, 'paymentDate') == r.date).toList();
    final (rev, exp) = _dayTotals(r.date, payments, expenses, closings);
    num rate(Map b) => _v(b, 'totalAmount') != null ? _n(b, 'totalAmount') : _n(b, 'ratePerNight');
    // The export's one table: a row per check-in, check-out and payment.
    final rows = <Map>[
      for (final b in ins) {'section': 'Check-In', 'detail': _who(b), 'room': _or(_s(b, 'roomNumber')), 'amount': rate(b).toStringAsFixed(2), 'method': ''},
      for (final b in outs) {'section': 'Check-Out', 'detail': _who(b), 'room': _or(_s(b, 'roomNumber')), 'amount': '', 'method': ''},
      for (final p in pays)
        {'section': 'Payment', 'detail': _or(_who(p)), 'room': '', 'amount': _paid(p).toStringAsFixed(2), 'method': _or(_s(p, 'paymentMethod'))},
    ];
    return RLoad(rows, {'ins': ins, 'outs': outs, 'pays': pays, 'rev': rev, 'exp': exp, 'rate': [for (final b in ins) rate(b)]});
  },
  summary: (r, f) {
    final m = r.meta as Map;
    return [
      (label: 'Revenue', value: f.money(m['rev'])),
      (label: 'Expenses', value: f.money(m['exp'])),
      (label: 'Net', value: f.money(tNum(m['rev']) - tNum(m['exp']))),
      (label: 'Check-ins', value: '${(m['ins'] as List).length}'),
      (label: 'Check-outs', value: '${(m['outs'] as List).length}'),
    ];
  },
  panel: (r, f) {
    final m = r.meta as Map;
    final ins = m['ins'] as List<Map>, outs = m['outs'] as List<Map>, pays = m['pays'] as List<Map>;
    final rates = m['rate'] as List<num>;
    final guest = RCol('guest', 'Guest', (x, f) => _or(_who(x)));
    final room = RCol('room', 'Room', (x, f) => _or(_s(x, 'roomNumber')));
    return _gap([
      _table('Check-ins (${ins.length})', [guest, room, _money('rate', 'Rate', (x) => tNum(x['_rate']), color: emerald700)],
          [for (final (i, b) in ins.indexed) {...b, '_rate': rates[i]}], f,
          empty: 'No check-ins for this date.'),
      _table('Check-outs (${outs.length})', [guest, room], outs, f, empty: 'No check-outs for this date.'),
      _table('Payments (${pays.length})', [
        guest,
        _money('amount', 'Amount', _paid, color: emerald700, bold: true),
        RCol('method', 'Method', (x, f) => _or(_s(x, 'paymentMethod'))),
      ], pays, f, empty: 'No payments for this date.'),
    ]);
  },
  columns: [
    RCol('section', 'Section', (r, f) => tStr(r['section'])),
    RCol('detail', 'Detail', (r, f) => tStr(r['detail'])),
    RCol('room', 'Room', (r, f) => tStr(r['room'])),
    RCol('amount', 'Amount', (r, f) => tStr(r['amount']), numeric: true),
    RCol('method', 'Method', (r, f) => tStr(r['method'])),
  ],
);

String _addDays(String d, int n) => isoDay((DateTime.tryParse(d) ?? DateTime.now()).add(Duration(days: n)));

final _weekColumns = [
  RCol('date', 'Date', (r, f) => tStr(r['date'])),
  _money('revenue', 'Revenue', (r) => tNum(r['revenue']), color: emerald700),
  _money('expenses', 'Expenses', (r) => tNum(r['expenses']), color: red600),
  RCol('checkIns', 'Check-ins', (r, f) => '${r['checkIns']}', numeric: true),
  RCol('checkOuts', 'Check-outs', (r, f) => '${r['checkOuts']}', numeric: true),
  _money('payments', 'Payments Total', (r) => tNum(r['payments']), color: emerald700, bold: true),
];

final _weeklyReport = RDef(
  showTable: false,
  // The week starts on this Monday; the picker moves the start, and the week
  // is the seven days from it.
  initialRange: (r) {
    final now = DateTime.now();
    final monday = isoDay(DateTime(now.year, now.month, now.day - (now.weekday - 1)));
    return r.copyWith(from: monday, to: _addDays(monday, 6));
  },
  dateControl: (r, set) => TCard(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      Expanded(child: reportDateBox(r.from, (v) => set(r.copyWith(from: v, to: _addDays(v, 6))))),
      const SizedBox(width: 10),
      Text('to ${r.to}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
    ]),
  ),
  load: (c, r) async {
    final [bookings, payments, expenses, closings] = await _periodic(c);
    final rows = <Map>[
      for (var i = 0; i < 7; i++)
        () {
          final d = _addDays(r.from, i);
          final (rev, exp) = _dayTotals(d, payments, expenses, closings);
          return {
            'date': d,
            'revenue': rev,
            'expenses': exp,
            'checkIns': bookings.where((b) => _day(b, 'checkInDate') == d).length,
            'checkOuts': bookings.where((b) => _day(b, 'checkOutDate') == d).length,
            'payments': sumOf(payments.where((p) => _day(p, 'paymentDate') == d), _paid),
          };
        }(),
    ];
    return RLoad(rows, {'bookings': bookings.where((b) => _inRange(_day(b, 'checkInDate'), r)).length});
  },
  summary: (r, f) {
    final rev = sumOf(r.rows, (x) => tNum(x['revenue'])), exp = sumOf(r.rows, (x) => tNum(x['expenses']));
    return [
      (label: 'Total Revenue', value: f.money(rev)),
      (label: 'Total Expenses', value: f.money(exp)),
      (label: 'Net Profit', value: f.money(rev - exp)),
      (label: 'Bookings', value: '${(r.meta as Map)['bookings']}'),
    ];
  },
  panel: (r, f) => _table('Daily Breakdown', _weekColumns, [
    ...r.rows,
    {
      'date': 'Total',
      for (final k in const ['revenue', 'expenses', 'checkIns', 'checkOuts', 'payments']) k: sumOf(r.rows, (x) => tNum(x[k])),
    },
  ], f),
  columns: _weekColumns,
);

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

RRange _month(RRange r, int year, int month) =>
    r.copyWith(from: isoDay(DateTime(year, month, 1)), to: isoDay(DateTime(year, month + 1, 0)));

final _monthWeekColumns = [
  RCol('week', 'Week', (r, f) => tStr(r['week'])),
  _money('revenue', 'Revenue', (r) => tNum(r['revenue']), color: emerald700),
  _money('expenses', 'Expenses', (r) => tNum(r['expenses']), color: red600),
  RCol('bookings', 'Bookings', (r, f) => '${r['bookings']}', numeric: true),
  _money('payments', 'Payments', (r) => tNum(r['payments']), color: emerald700),
];

final _monthMetricColumns = [
  RCol('metric', 'Metric', (r, f) => tStr(r['metric'])),
  RCol('value', 'Value', (r, f) => tStr(r['value']), numeric: true),
];

final _monthlyReport = RDef(
  showTable: false,
  initialRange: (r) => _month(r, DateTime.now().year, DateTime.now().month),
  dateControl: (r, set) {
    final start = DateTime.tryParse(r.from) ?? DateTime.now();
    final now = DateTime.now().year;
    return TCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: AppSelect<int>(
            value: start.month,
            items: [for (final (i, m) in _monthNames.indexed) AppSelectItem(value: i + 1, label: m)],
            onChanged: (m) => set(_month(r, start.year, m ?? start.month)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: AppSelect<int>(
            value: start.year,
            items: [for (var y = now - 5; y <= now + 1; y++) AppSelectItem(value: y, label: '$y')],
            onChanged: (y) => set(_month(r, y ?? start.year, start.month)),
          ),
        ),
      ]),
    );
  },
  load: (c, r) async {
    final [bookings, payments, expenses, closings, staff] = await _periodic(c, staff: true);
    final mClosings = closings.where((x) => _inRange(_day(x, 'closingDate'), r)).toList();
    final mBookings = bookings.where((x) => _inRange(_day(x, 'checkInDate'), r)).toList();
    final mPayments = payments.where((x) => _inRange(_day(x, 'paymentDate'), r)).toList();
    final mExpenses = expenses.where((x) => _inRange(_day(x, 'expenseDate'), r)).toList();
    final rev = mClosings.isNotEmpty ? sumOf(mClosings, (x) => _n(x, 'totalRevenue')) : sumOf(mPayments, _paid);
    final exp = mClosings.isNotEmpty ? sumOf(mClosings, (x) => _n(x, 'totalExpenses')) : sumOf(mExpenses, (x) => _n(x, 'amount'));
    final start = DateTime.parse(r.from);
    int week(String d) => (DateTime.parse(d).difference(start).inDays ~/ 7) + 1;
    final weeks = <int, Map<String, num>>{};
    Map<String, num> w(String d) => weeks.putIfAbsent(week(d), () => {'revenue': 0, 'expenses': 0, 'bookings': 0, 'payments': 0});
    for (final x in mClosings) {
      final e = w(_day(x, 'closingDate'));
      e['revenue'] = e['revenue']! + _n(x, 'totalRevenue');
      e['expenses'] = e['expenses']! + _n(x, 'totalExpenses');
    }
    for (final x in mBookings) {
      final e = w(_day(x, 'checkInDate'));
      e['bookings'] = e['bookings']! + 1;
    }
    for (final x in mPayments) {
      final e = w(_day(x, 'paymentDate'));
      e['payments'] = e['payments']! + _paid(x);
    }
    final weekRows = [for (final k in weeks.keys.toList()..sort()) {'week': 'Week $k', ...weeks[k]!}];
    final meta = {
      'rev': rev,
      'exp': exp,
      'bookings': mBookings.length,
      'staff': staff.length,
      'payments': sumOf(mPayments, _paid),
      'weeks': weekRows.isNotEmpty,
      'empty': mBookings.isEmpty && mPayments.isEmpty && mExpenses.isEmpty,
    };
    final rows = weekRows.isNotEmpty
        ? weekRows
        : <Map>[
            {'metric': 'Total Revenue', 'value': rev.toStringAsFixed(2)},
            {'metric': 'Total Expenses', 'value': exp.toStringAsFixed(2)},
            {'metric': 'Net Profit', 'value': (rev - exp).toStringAsFixed(2)},
            {'metric': 'Total Bookings', 'value': '${mBookings.length}'},
            {'metric': 'Staff Count', 'value': '${staff.length}'},
          ];
    return RLoad(rows, meta);
  },
  columnsFor: (r) => (r.meta as Map?)?['weeks'] == true ? _monthWeekColumns : _monthMetricColumns,
  summary: (r, f) {
    final m = r.meta as Map;
    return [
      (label: 'Total Revenue', value: f.money(m['rev'])),
      (label: 'Total Expenses', value: f.money(m['exp'])),
      (label: 'Net Profit', value: f.money(tNum(m['rev']) - tNum(m['exp']))),
      (label: 'Total Bookings', value: '${m['bookings']}'),
      (label: 'Staff Count', value: '${m['staff']}'),
    ];
  },
  panel: (r, f) {
    final m = r.meta as Map;
    if (m['weeks'] == true) {
      return _table('Week-by-Week Breakdown', _monthWeekColumns, [
        ...r.rows,
        {'week': 'Total', 'revenue': m['rev'], 'expenses': m['exp'], 'bookings': m['bookings'], 'payments': m['payments']},
      ], f);
    }
    return _gap([
      _table('Monthly Totals', _monthMetricColumns, r.rows, f),
      if (m['empty'] == true)
        const Text('No data found for this month.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate400)),
    ]);
  },
  columns: _monthWeekColumns,
);

// ===========================================================================
// HOUSEKEEPING & INVENTORY
// ===========================================================================

Widget _taskStatus(String s) => switch (s.toLowerCase()) {
      'pending' => _badge('Pending', _bAmber),
      'inprogress' => _badge('InProgress', _bBlue),
      'completed' => _badge('Completed', _bGreen),
      'inspected' => _badge('Inspected', _bIndigo),
      _ => _badge(s, _bSlate),
    };

final _housekeepingReport = RDef(
  presets: false,
  load: (c, r) async => RLoad((await c.list('/api/Hotel/housekeeping')).where((x) => _inRange(_day(x, 'createdAt'), r)).toList()),
  summary: (r, f) => [
    (label: 'Total Tasks', value: '${r.rows.length}'),
    (label: 'Pending', value: '${r.rows.where((x) => _status(x) == 'pending').length}'),
    (label: 'InProgress', value: '${r.rows.where((x) => _status(x) == 'inprogress').length}'),
    (label: 'Completed', value: '${r.rows.where((x) => _status(x) == 'completed').length}'),
  ],
  tableTitle: 'Housekeeping Tasks ({n})',
  emptyText: 'No housekeeping tasks found for this period.',
  columns: [
    RCol('room', 'Room', (t, f) => _or(_s(t, 'roomNumber'))),
    RCol('type', 'Type/Description', (t, f) => _or(_s(t, 'taskType').isNotEmpty ? _s(t, 'taskType') : _s(t, 'description'))),
    RCol('assigned', 'Assigned To', (t, f) => _or(_s(t, 'assignedTo'))),
    RCol('status', 'Status', (t, f) => tStr(t['status']), render: (t, f) => _taskStatus(tStr(t['status']))),
    RCol('priority', 'Priority', (t, f) => _or(_s(t, 'priority'))),
    RCol('notes', 'Notes', (t, f) => _or(_s(t, 'notes'))),
    RCol('created', 'Created', (t, f) => _day(t, 'createdAt')),
  ],
);

String _itemName(Map i) => tStr(i['name']).isNotEmpty ? tStr(i['name']) : _s(i, 'itemName');
String _itemCategory(Map i) => tStr(i['category']).isNotEmpty ? tStr(i['category']) : _s(i, 'categoryName');
bool _low(Map i) => _n(i, 'stockOnHand') <= _n(i, 'reorderLevel');
num _value(Map i) => _n(i, 'stockOnHand') * _n(i, 'unitCost');

final _inventoryReport = RDef(
  presets: false,
  load: (c, r) async => RLoad(await c.list('/api/Hotel/inventory')),
  summary: (r, f) => [
    (label: 'Total Items', value: '${r.rows.length}'),
    (label: 'Low Stock', value: '${r.rows.where(_low).length}'),
    (label: 'Total Value', value: f.money(sumOf(r.rows, _value))),
    (label: 'Categories', value: '${{for (final i in r.rows) _itemCategory(i).isEmpty ? 'Uncategorized' : _itemCategory(i)}.length}'),
  ],
  tableTitle: 'Inventory Items ({n})',
  emptyText: 'No inventory items found.',
  columns: [
    RCol('name', 'Name', (i, f) => _or(_itemName(i))),
    RCol('category', 'Category', (i, f) => _or(_itemCategory(i))),
    RCol('unit', 'Unit', (i, f) => _or(tStr(i['unit']).isNotEmpty ? tStr(i['unit']) : _s(i, 'unitOfMeasure'))),
    RCol('stock', 'Stock', (i, f) => '${_n(i, 'stockOnHand')}', numeric: true,
        render: (i, f) => _low(i) ? coloured('${_n(i, 'stockOnHand')}', red600, bold: true) : coloured('${_n(i, 'stockOnHand')}', TColors.slate900)),
    RCol('reorder', 'Reorder Level', (i, f) => '${_n(i, 'reorderLevel')}', numeric: true),
    RCol('cost', 'Unit Cost', (i, f) => f.num_(_n(i, 'unitCost')), numeric: true),
    _money('value', 'Value', _value, color: emerald700, bold: true),
  ],
);

/// The own-page reports, by slug.
final hotelPageReportDefs = <String, RDef>{
  'revenue-summary': _revenueSummary,
  'expense-report': _expenseReport,
  'billing-report': _billingReport,
  'payroll-report': _payrollReport,
  'cash-flow-report': _cashFlowReport,
  'bookings-report': _bookingsReport,
  'guest-report': _guestReport,
  'occupancy-report': _occupancyReport,
  'maintenance-report': _maintenanceReport,
  'restaurant-sales': _restaurantSales,
  'menu-performance': _menuPerformance,
  'daily-report': _dailyReport,
  'weekly-report': _weeklyReport,
  'monthly-report': _monthlyReport,
  'housekeeping-report': _housekeepingReport,
  'inventory-report': _inventoryReport,
};
