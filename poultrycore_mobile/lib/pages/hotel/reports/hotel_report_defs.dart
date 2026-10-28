// components/hotel/reports/registry.tsx: the eleven Hotel reports that render
// through the shared report shell (migration 299, plus Employee Loans from
// 325), as data. The web's recharts charts read as BarChartRows / shareBars,
// as on the Restaurant reports.

import 'package:flutter/material.dart';

import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../../restaurant/reports/restaurant_report_kit.dart';

const _violet = Color(0xFF6D28D9);
const _violetLight = Color(0xFFC4B5FD);

/// A label / value pair, for the report whose answer is a set of figures.
final _metricColumns = [
  RCol('metric', 'Metric', (r, f) => tStr(r['metric'])),
  RCol('value', 'Value', (r, f) => tStr(r['value']), numeric: true),
];

num _n(Map r, String k) => tNum(r[k]);

/// Rows of label / value, the web's border-b lists inside a card.
Widget _lines(List<(String, Widget)> rows, {Set<int> bold = const {}}) => Column(
  children: [
    for (final (i, (l, v)) in rows.indexed)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: i < rows.length - 1 ? const Border(bottom: BorderSide(color: TColors.slate200)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(l, style: TextStyle(fontSize: 13.5, fontWeight: bold.contains(i) ? FontWeight.w600 : FontWeight.w400)),
            ),
            const SizedBox(width: 8),
            v,
          ],
        ),
      ),
  ],
);

Widget _txt(String s, {bool bold = false}) => Text(
  s,
  style: TextStyle(
    fontSize: 13.5,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);

Widget _note(String text, {bool amber = false}) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: amber ? TColors.amber50 : Colors.white,
    border: Border.all(color: amber ? TColors.amber200 : TColors.slate200),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(text, style: TextStyle(fontSize: 13, color: amber ? TColors.amber900 : TColors.slate600)),
);

Future<RLoad> _range(RCtx c, RRange r, String path) async => RLoad(await c.list('/api/Hotel/reports/$path', {'from': r.from, 'to': r.to}));

Map? _maxBy(List<Map> rows, num Function(Map) f, {bool Function(Map)? where}) {
  Map? best;
  for (final x in rows) {
    if (where != null && !where(x)) continue;
    if (best == null || f(x) > f(best)) best = x;
  }
  return best;
}

// ===========================================================================
// REVENUE MANAGEMENT
// ===========================================================================

final _performanceKpis = RDef(
  load: (c, r) async => RLoad(const [], await c.map('/api/Hotel/reports/performance-kpis', {'from': r.from, 'to': r.to})),
  summary: (r, f) {
    final k = r.meta;
    if (k is! Map || k.isEmpty) return [];
    return [
      (label: 'Occupancy', value: f.pct(k['occupancyPct'])),
      (label: 'ADR', value: f.money(k['adr'])),
      (label: 'RevPAR', value: f.money(k['revpar'])),
      (label: 'GOPPAR', value: f.money(k['goppar'])),
    ];
  },
  panel: (r, f) {
    final k = r.meta;
    if (k is! Map || k.isEmpty) return null;
    // ADR and RevPAR are room revenue over rooms: a closing that recorded a
    // total but no room split reads zero, and saying so beats inventing it.
    final splitMissing = _n(k, 'roomRevenue') == 0 && _n(k, 'totalRevenue') > 0;
    final goppar = _n(k, 'goppar'), occ = _n(k, 'occupancyPct');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (splitMissing) ...[
          _note(
            'ADR and RevPAR read zero because the daily closings in this period recorded a total revenue figure but no room revenue '
            'split. TRevPAR and GOPPAR below are unaffected, since they use total revenue. Fill in the room / F&B / other split on '
            'daily closing and these will populate.',
            amber: true,
          ),
          const SizedBox(height: 12),
        ],
        reportCard(
          'Revenue',
          null,
          _lines(
            [
              ('Rooms', _txt(f.money(k['roomRevenue']))),
              ('Food & beverage', _txt(f.money(k['fnbRevenue']))),
              ('Other', _txt(f.money(k['otherRevenue']))),
              ('Total revenue', _txt(f.money(k['totalRevenue']), bold: true)),
              ('Less operating expenses', _txt('- ${f.money(k['totalExpenses'])}')),
              ('Gross operating profit', _txt(f.money(k['grossOperatingProfit']), bold: true)),
            ],
            bold: {3, 5},
          ),
        ),
        const SizedBox(height: 12),
        reportCard(
          'Per available room',
          'All four divide by the same ${f.int_(k['availableRoomNights'])} available room nights.',
          _lines([
            ('RevPAR — rooms revenue', toneBadge(f.money(k['revpar']), 'muted')),
            ('TRevPAR — total revenue', toneBadge(f.money(k['trevpar']), 'muted')),
            ('GOPPAR — operating profit', toneBadge(f.money(goppar), goppar > 0 ? 'good' : 'bad')),
            (
              'Occupancy',
              toneBadge(
                f.pct(occ),
                occ >= 70
                    ? 'good'
                    : occ >= 50
                    ? 'warn'
                    : 'bad',
              ),
            ),
            ('No-shows (night audit)', toneBadge(f.int_(k['noshowCount']), 'muted')),
          ]),
        ),
      ],
    );
  },
  columns: _metricColumns,
  tableTitle: 'Every figure for this period',
  emptyText: 'No daily closings in this period. These figures come from daily closing, so close a day to populate them.',
  // deriveHotelMetricRows: the single object as rows, once the currency is known.
  rows: (meta, f) {
    if (meta is! Map || meta.isEmpty || _n(meta, 'daysCounted') == 0) return const [];
    final k = meta;
    return [
      {'metric': 'Days closed in period', 'value': f.int_(k['daysCounted'])},
      {'metric': 'Available room nights', 'value': f.int_(k['availableRoomNights'])},
      {'metric': 'Occupied room nights', 'value': f.int_(k['occupiedRoomNights'])},
      {'metric': 'Occupancy', 'value': f.pct(k['occupancyPct'])},
      {'metric': 'Rooms revenue', 'value': f.money(k['roomRevenue'])},
      {'metric': 'Food & beverage revenue', 'value': f.money(k['fnbRevenue'])},
      {'metric': 'Other revenue', 'value': f.money(k['otherRevenue'])},
      {'metric': 'Total revenue', 'value': f.money(k['totalRevenue'])},
      {'metric': 'Operating expenses', 'value': f.money(k['totalExpenses'])},
      {'metric': 'Gross operating profit', 'value': f.money(k['grossOperatingProfit'])},
      {'metric': 'ADR — rooms revenue / occupied rooms', 'value': f.money(k['adr'])},
      {'metric': 'RevPAR — rooms revenue / available rooms', 'value': f.money(k['revpar'])},
      {'metric': 'TRevPAR — total revenue / available rooms', 'value': f.money(k['trevpar'])},
      {'metric': 'GOPPAR — operating profit / available rooms', 'value': f.money(k['goppar'])},
      {'metric': 'No-shows recorded on night audit', 'value': f.int_(k['noshowCount'])},
    ];
  },
);

final _sourceOfBusiness = RDef(
  load: (c, r) => _range(c, r, 'source-of-business'),
  summary: (r, f) {
    final rev = sumOf(r.rows, (x) => _n(x, 'revenueTotal'));
    final nights = sumOf(r.rows, (x) => _n(x, 'roomNights'));
    return [
      (label: 'Revenue', value: f.money(rev)),
      (label: 'Room nights', value: f.int_(nights)),
      (label: 'Blended ADR', value: nights > 0 ? f.money(rev / nights) : f.money(0)),
      (label: 'Top channel', value: r.rows.isEmpty ? '—' : tStr(r.rows.first['sourceLabel'])),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard(
          'Revenue by channel',
          'Where the business actually comes from',
          shareBars([for (final x in r.rows) (tStr(x['sourceLabel']), _n(x, 'revenueTotal'))], fmt: (v) => f.money(v)),
        ),
  columns: [
    RCol('s', 'Channel', (r, f) => tStr(r['sourceLabel'])),
    RCol('b', 'Bookings', (r, f) => f.int_(r['bookingCount']), numeric: true),
    RCol('n', 'Room nights', (r, f) => f.int_(r['roomNights']), numeric: true),
    RCol('g', 'Guests', (r, f) => f.int_(r['guestCount']), numeric: true, secondary: true),
    RCol('adr', 'ADR', (r, f) => f.money(r['adr']), numeric: true),
    RCol('lead', 'Avg lead', (r, f) => '${f.num_(r['avgLeadDays'], 1)} d', numeric: true, secondary: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
    RCol('sh', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Channels',
  tableHint: 'ADR is revenue over room nights, so a long stay and a short one are not weighted the same.',
  emptyText: 'No bookings starting in this period.',
);

/// Revenue against bookings per bucket: the web's two-axis bar chart.
Widget _revenueBookings(List<Map> rows, String labelKey, RFmt f) => BarChartRows(
  items: [for (final x in rows) tStr(x[labelKey])],
  series: [
    ('Revenue', _violet, [for (final x in rows) _n(x, 'revenueTotal')], (v) => f.money(v)),
    ('Bookings', _violetLight, [for (final x in rows) _n(x, 'bookingCount')], (v) => f.int_(v)),
  ],
);

final _bookingPace = RDef(
  load: (c, r) => _range(c, r, 'booking-pace'),
  summary: (r, f) {
    final total = sumOf(r.rows, (x) => _n(x, 'bookingCount'));
    final sameDay = _n(r.rows.where((x) => x['leadBucket'] == 'Same day').firstOrNull ?? const {}, 'bookingCount');
    final far = sumOf(r.rows.where((x) => _n(x, 'bucketOrder') >= 4), (x) => _n(x, 'bookingCount'));
    return [
      (label: 'Bookings made', value: f.int_(total)),
      (label: 'Revenue booked', value: f.money(sumOf(r.rows, (x) => _n(x, 'revenueTotal')))),
      (label: 'Same-day share', value: total > 0 ? f.pct(sameDay / total * 100) : f.pct(0)),
      (label: '31+ days ahead', value: total > 0 ? f.pct(far / total * 100) : f.pct(0)),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard(
          'How far ahead people book',
          'Counted by the date the booking was MADE, not the date of the stay',
          _revenueBookings(r.rows, 'leadBucket', f),
        ),
  columns: [
    RCol('b', 'Booked ahead', (r, f) => tStr(r['leadBucket'])),
    RCol('n', 'Bookings', (r, f) => f.int_(r['bookingCount']), numeric: true),
    RCol('rn', 'Room nights', (r, f) => f.int_(r['roomNights']), numeric: true),
    RCol('adr', 'ADR', (r, f) => f.money(r['adr']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
    RCol('sh', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Lead time',
  emptyText: 'No bookings were made in this period.',
);

final _roomTypePerformance = RDef(
  load: (c, r) => _range(c, r, 'room-type-performance'),
  summary: (r, f) {
    final best = _maxBy(r.rows, (x) => _n(x, 'revpar'));
    return [
      (label: 'Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'revenueTotal')))),
      (label: 'Room types', value: f.int_(r.rows.length)),
      (label: 'Best RevPAR', value: best == null ? '—' : '${tStr(best['typeLabel'])} — ${f.money(best['revpar'])}'),
      (label: 'Types with no sales', value: f.int_(r.rows.where((x) => _n(x, 'roomNights') == 0).length)),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard(
          'RevPAR and ADR by room type',
          "RevPAR is measured against that type's own room count, not the whole property",
          BarChartRows(
            items: [for (final x in r.rows) tStr(x['typeLabel'])],
            series: [
              ('ADR', _violetLight, [for (final x in r.rows) _n(x, 'adr')], (v) => f.money(v)),
              ('RevPAR', _violet, [for (final x in r.rows) _n(x, 'revpar')], (v) => f.money(v)),
            ],
          ),
        ),
  columns: [
    RCol('t', 'Room type', (r, f) => tStr(r['typeLabel'])),
    RCol('rooms', 'Rooms', (r, f) => f.int_(r['roomsInType']), numeric: true, secondary: true),
    RCol('b', 'Bookings', (r, f) => f.int_(r['bookingCount']), numeric: true, secondary: true),
    RCol('n', 'Room nights', (r, f) => f.int_(r['roomNights']), numeric: true),
    RCol(
      'occ',
      'Occupancy',
      (r, f) => f.pct(r['occupancyPct']),
      numeric: true,
      render: (r, f) {
        final o = _n(r, 'occupancyPct');
        return coloured(
          f.pct(o),
          o >= 70
              ? emerald700
              : o < 30
              ? red700
              : TColors.slate900,
          bold: o >= 70,
        );
      },
    ),
    RCol('adr', 'ADR', (r, f) => f.money(r['adr']), numeric: true),
    RCol('rp', 'RevPAR', (r, f) => f.money(r['revpar']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
  ],
  tableTitle: 'Room types',
  emptyText: 'No room types configured, or no bookings in this period.',
);

final _lengthOfStay = RDef(
  load: (c, r) => _range(c, r, 'length-of-stay'),
  summary: (r, f) {
    final nights = sumOf(r.rows, (x) => _n(x, 'roomNights'));
    final bookings = sumOf(r.rows, (x) => _n(x, 'bookingCount'));
    final best = _maxBy(r.rows, (x) => _n(x, 'revenueTotal'));
    return [
      (label: 'Bookings', value: f.int_(bookings)),
      (label: 'Room nights', value: f.int_(nights)),
      (label: 'Average stay', value: bookings > 0 ? '${f.num_(nights / bookings, 1)} nights' : '—'),
      (label: 'Most valuable length', value: best == null ? '—' : tStr(best['losBucket'])),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Stay length distribution', 'Bookings and revenue by how many nights', _revenueBookings(r.rows, 'losBucket', f)),
  columns: [
    RCol('l', 'Stay length', (r, f) => tStr(r['losBucket'])),
    RCol('n', 'Bookings', (r, f) => f.int_(r['bookingCount']), numeric: true),
    RCol('rn', 'Room nights', (r, f) => f.int_(r['roomNights']), numeric: true),
    RCol('adr', 'ADR', (r, f) => f.money(r['adr']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
    RCol('sh', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Length of stay',
  emptyText: 'No bookings starting in this period.',
);

final _cancellations = RDef(
  load: (c, r) => _range(c, r, 'cancellations'),
  summary: (r, f) {
    final n = sumOf(r.rows, (x) => _n(x, 'cancelledCount'));
    final booked = sumOf(r.rows, (x) => _n(x, 'bookedCount'));
    final worst = _maxBy(r.rows, (x) => _n(x, 'cancelRatePct'));
    return [
      (label: 'Value lost', value: f.money(sumOf(r.rows, (x) => _n(x, 'valueLost')))),
      (label: 'Bookings cancelled', value: f.int_(n)),
      (label: 'Overall cancel rate', value: booked > 0 ? f.pct(n / booked * 100) : f.pct(0)),
      (label: 'Worst channel', value: worst == null ? '—' : '${tStr(worst['sourceLabel'])} — ${f.pct(worst['cancelRatePct'])}'),
    ];
  },
  panel: (r, f) => _note(
    'This covers cancellations only. No-shows are not a booking status in this system — the only no-show figure '
    'recorded is the nightly count on the night audit, and it is shown in the Performance & KPIs report where it actually lives.',
  ),
  columns: [
    RCol('s', 'Channel', (r, f) => tStr(r['sourceLabel'])),
    RCol('n', 'Cancelled', (r, f) => f.int_(r['cancelledCount']), numeric: true),
    RCol('bk', 'Of bookings', (r, f) => f.int_(r['bookedCount']), numeric: true, secondary: true),
    RCol(
      'rate',
      'Cancel rate',
      (r, f) => f.pct(r['cancelRatePct']),
      numeric: true,
      render: (r, f) {
        final v = _n(r, 'cancelRatePct');
        return coloured(
          f.pct(v),
          v >= 30
              ? red700
              : v >= 15
              ? amber700
              : TColors.slate900,
          bold: v >= 30,
        );
      },
    ),
    RCol('rn', 'Nights lost', (r, f) => f.int_(r['nightsLost']), numeric: true, secondary: true),
    RCol('lead', 'Avg lead', (r, f) => '${f.num_(r['avgLeadDays'], 1)} d', numeric: true, secondary: true),
    RCol('v', 'Value lost', (r, f) => f.money(r['valueLost']), numeric: true),
    RCol('sh', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Cancellations by channel',
  emptyText: 'No bookings were cancelled in this period.',
);

// ===========================================================================
// FINANCIAL
// ===========================================================================

String _ageTone(String b) => b == 'Current'
    ? 'good'
    : b == '1-30 days'
    ? 'warn'
    : 'bad';

final _guestLedger = RDef(
  load: (c, r) async => RLoad(await c.list('/api/Hotel/reports/guest-ledger')),
  summary: (r, f) {
    final over = r.rows.where((x) => x['ageBucket'] != 'Current');
    final over90 = r.rows.where((x) => x['ageBucket'] == 'Over 90 days');
    return [
      (label: 'Total owed', value: f.money(sumOf(r.rows, (x) => _n(x, 'balanceDue')))),
      (label: 'Open invoices', value: f.int_(r.rows.length)),
      (label: 'Overdue', value: f.money(sumOf(over, (x) => _n(x, 'balanceDue')))),
      (label: 'Over 90 days', value: f.money(sumOf(over90, (x) => _n(x, 'balanceDue')))),
    ];
  },
  panel: (r, f) {
    if (r.rows.isEmpty) return null;
    const buckets = ['Current', '1-30 days', '31-60 days', '61-90 days', 'Over 90 days'];
    final totals = [
      for (final b in buckets)
        if (r.rows.any((x) => x['ageBucket'] == b))
          (b, sumOf(r.rows.where((x) => x['ageBucket'] == b), (x) => _n(x, 'balanceDue')), r.rows.where((x) => x['ageBucket'] == b).length),
    ];
    return reportCard(
      'Ageing',
      'Aged from the due date, or the issue date where no due date was set.',
      _lines([for (final (b, amount, count) in totals) ('$b ($count)', toneBadge(f.money(amount), _ageTone(b)))]),
    );
  },
  columns: [
    RCol('i', 'Invoice', (r, f) => tStr(r['invoiceRef'])),
    RCol('g', 'Guest', (r, f) => tStr(r['guestLabel'])),
    RCol('d', 'Issued', (r, f) => d10(r['issuedOn']), secondary: true),
    RCol('du', 'Due', (r, f) => tStr(r['dueOn']).isEmpty ? '—' : d10(r['dueOn']), secondary: true),
    RCol('t', 'Invoice total', (r, f) => f.money(r['totalAmount']), numeric: true, secondary: true),
    RCol('p', 'Paid', (r, f) => f.money(r['paidAmount']), numeric: true, secondary: true),
    RCol('b', 'Balance', (r, f) => f.money(r['balanceDue']), numeric: true),
    RCol('days', 'Days out', (r, f) => f.int_(r['daysOutstanding']), numeric: true),
    RCol('age', 'Age', (r, f) => tStr(r['ageBucket']), render: (r, f) => toneBadge(tStr(r['ageBucket']), _ageTone(tStr(r['ageBucket'])))),
  ],
  tableTitle: 'Unpaid invoices, oldest first',
  emptyText: 'Nothing outstanding — every invoice is settled.',
);

final _ancillaryRevenue = RDef(
  load: (c, r) => _range(c, r, 'ancillary-revenue'),
  summary: (r, f) {
    final top = r.rows.firstOrNull;
    return [
      (label: 'Ancillary revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'revenueTotal')))),
      (label: 'Charges posted', value: f.int_(sumOf(r.rows, (x) => _n(x, 'chargeCount')))),
      (label: 'Charge types', value: f.int_(r.rows.length)),
      (label: 'Biggest earner', value: top == null ? '—' : '${tStr(top['chargeLabel'])} — ${f.money(top['revenueTotal'])}'),
    ];
  },
  columns: [
    RCol('c', 'Charge type', (r, f) => tStr(r['chargeLabel'])),
    RCol('n', 'Charges', (r, f) => f.int_(r['chargeCount']), numeric: true),
    RCol('q', 'Quantity', (r, f) => f.int_(r['qtyTotal']), numeric: true, secondary: true),
    RCol('s', 'Stays touched', (r, f) => f.int_(r['staysTouched']), numeric: true, secondary: true),
    RCol('a', 'Average', (r, f) => f.money(r['avgCharge']), numeric: true, secondary: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
    RCol('sh', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Charges beyond the room',
  emptyText: 'No stay charges posted in this period.',
);

// ===========================================================================
// OPERATIONS
// ===========================================================================

final _housekeepingProductivity = RDef(
  load: (c, r) => _range(c, r, 'housekeeping-productivity'),
  summary: (r, f) {
    final tasks = sumOf(r.rows, (x) => _n(x, 'tasksTotal'));
    final timed = sumOf(r.rows, (x) => _n(x, 'timedCount'));
    final weighted = timed > 0 ? sumOf(r.rows, (x) => _n(x, 'avgMinutes') * _n(x, 'timedCount')) / timed : 0;
    final best = _maxBy(r.rows, (x) => _n(x, 'roomsPerShift'), where: (x) => _n(x, 'timedCount') > 0);
    return [
      (label: 'Tasks', value: f.int_(tasks)),
      (label: 'Timed tasks', value: '${f.int_(timed)} of ${f.int_(tasks)}'),
      (label: 'Average per room', value: timed > 0 ? f.mins(weighted) : 'not measured'),
      (
        label: 'Fastest attendant',
        value: best != null && _n(best, 'roomsPerShift') > 0
            ? '${tStr(best['attendantLabel'])} — ${f.num_(best['roomsPerShift'], 1)}/shift'
            : '—',
      ),
    ];
  },
  panel: (r, f) => _note(
    "Rooms per shift projects each attendant's average onto an eight-hour shift. The industry benchmark for a full "
    'clean is roughly 12–16 rooms per attendant per shift. Only tasks carrying both a start and a completion time are counted, so a '
    'task still open does not drag an average down.',
  ),
  columns: [
    RCol('a', 'Attendant', (r, f) => tStr(r['attendantLabel'])),
    RCol('t', 'Tasks', (r, f) => f.int_(r['tasksTotal']), numeric: true),
    RCol('c', 'Completed', (r, f) => f.int_(r['tasksCompleted']), numeric: true, secondary: true),
    RCol('tc', 'Timed', (r, f) => f.int_(r['timedCount']), numeric: true, secondary: true),
    RCol('avg', 'Avg per room', (r, f) => _n(r, 'timedCount') > 0 ? f.mins(r['avgMinutes']) : '—', numeric: true),
    RCol('fast', 'Fastest', (r, f) => _n(r, 'timedCount') > 0 ? f.mins(r['fastestMinutes']) : '—', numeric: true, secondary: true),
    RCol('slow', 'Slowest', (r, f) => _n(r, 'timedCount') > 0 ? f.mins(r['slowestMinutes']) : '—', numeric: true, secondary: true),
    RCol(
      'rps',
      'Rooms / shift',
      (r, f) => _n(r, 'timedCount') > 0 ? f.num_(r['roomsPerShift'], 1) : '—',
      numeric: true,
      render: (r, f) {
        if (_n(r, 'timedCount') == 0) return coloured('—', TColors.slate400);
        final v = _n(r, 'roomsPerShift');
        return coloured(f.num_(v, 1), v >= 12 ? emerald700 : amber700, bold: v >= 12);
      },
    ),
    RCol('insp', 'Inspected', (r, f) => f.int_(r['inspectedCount']), numeric: true, secondary: true),
  ],
  tableTitle: 'Attendants',
  emptyText: 'No housekeeping tasks scheduled in this period.',
);

final _loyalty = RDef(
  load: (c, r) => _range(c, r, 'loyalty'),
  summary: (r, f) => [
    (label: 'Members', value: f.int_(sumOf(r.rows, (x) => _n(x, 'memberCount')))),
    (label: 'Active', value: f.int_(sumOf(r.rows, (x) => _n(x, 'activeMembers')))),
    (label: 'Points earned', value: f.int_(sumOf(r.rows, (x) => _n(x, 'earnedInPeriod')))),
    (label: 'Points redeemed', value: f.int_(sumOf(r.rows, (x) => _n(x, 'redeemedInPeriod')))),
  ],
  columns: [
    RCol('t', 'Tier', (r, f) => tStr(r['tierLabel'])),
    RCol('m', 'Members', (r, f) => f.int_(r['memberCount']), numeric: true),
    RCol('a', 'Active', (r, f) => f.int_(r['activeMembers']), numeric: true, secondary: true),
    RCol('bal', 'Points balance', (r, f) => f.int_(r['pointsBalance']), numeric: true),
    RCol('lt', 'Lifetime points', (r, f) => f.int_(r['lifetimePoints']), numeric: true, secondary: true),
    RCol('e', 'Earned', (r, f) => f.int_(r['earnedInPeriod']), numeric: true),
    RCol('rd', 'Redeemed', (r, f) => f.int_(r['redeemedInPeriod']), numeric: true),
    RCol('sh', 'Share of members', (r, f) => f.pct(r['sharePct']), numeric: true, secondary: true),
  ],
  tableTitle: 'Tiers',
  tableHint: 'Member counts and balances are all-time; earned and redeemed are movements inside the selected period.',
  emptyText: 'No loyalty members yet.',
);

// ===========================================================================
// STAFF LOANS & ADVANCES (migration 325)
// ===========================================================================

final _staffLoans = RDef(
  load: (c, r) async => RLoad(await c.list('/api/Hotel/employee-loans/staff-report', {'fromDate': r.from, 'toDate': r.to})),
  summary: (r, f) => [
    (label: 'Owed by staff now', value: f.money(sumOf(r.rows, (x) => _n(x, 'outstanding')))),
    (label: 'Advanced in period', value: f.money(sumOf(r.rows, (x) => _n(x, 'disbursedInPeriod')))),
    (label: 'Repaid in period', value: f.money(sumOf(r.rows, (x) => _n(x, 'repaidCashInPeriod') + _n(x, 'repaidPayrollInPeriod')))),
    (label: 'Staff owing', value: f.int_(r.rows.where((x) => _n(x, 'outstanding') > 0).length)),
  ],
  panel: (r, f) {
    final owing = r.rows.where((x) => _n(x, 'outstanding') > 0).take(12).toList();
    if (owing.isEmpty) return null;
    return reportCard(
      'Who owes the most',
      'Outstanding balance per staff member, largest first.',
      BarChartRows(
        items: [for (final x in owing) tStr(x['staffName'])],
        series: [
          ('Owed', _violet, [for (final x in owing) _n(x, 'outstanding')], (v) => f.money(v)),
        ],
      ),
    );
  },
  columns: [
    RCol('s', 'Staff', (r, f) => '${tStr(r['staffName'])}${r['staffIsActive'] == false ? ' (inactive)' : ''}'),
    RCol('d', 'Department', (r, f) => tStr(r['department']).isEmpty ? '—' : tStr(r['department']), secondary: true),
    RCol('a', 'Active loans', (r, f) => f.int_(r['activeLoans']), numeric: true, secondary: true),
    RCol('o', 'Owed now', (r, f) => f.money(r['outstanding']), numeric: true),
    RCol('g', 'Advanced', (r, f) => f.money(r['disbursedInPeriod']), numeric: true),
    RCol('rc', 'Repaid in cash', (r, f) => f.money(r['repaidCashInPeriod']), numeric: true, secondary: true),
    RCol('rp', 'Repaid via payroll', (r, f) => f.money(r['repaidPayrollInPeriod']), numeric: true, secondary: true),
    RCol('i', 'Interest', (r, f) => f.money(r['interestInPeriod']), numeric: true, secondary: true),
    RCol('l', 'Last repayment', (r, f) => tStr(r['lastRepaymentDate']).isEmpty ? '—' : d10(r['lastRepaymentDate']), secondary: true),
  ],
  tableTitle: 'Staff loans and advances',
  tableHint: 'Owed now is today’s balance; the other amounts are for the selected dates.',
  emptyText: 'No staff loans or advances yet.',
);

/// HOTEL_REPORT_REGISTRY.
final hotelReportDefs = <String, RDef>{
  'performance-kpis': _performanceKpis,
  'source-of-business': _sourceOfBusiness,
  'booking-pace': _bookingPace,
  'room-type-performance': _roomTypePerformance,
  'length-of-stay': _lengthOfStay,
  'cancellations': _cancellations,
  'guest-ledger': _guestLedger,
  'ancillary-revenue': _ancillaryRevenue,
  'housekeeping-productivity': _housekeepingProductivity,
  'loyalty-report': _loyalty,
  'staff-loans': _staffLoans,
};
