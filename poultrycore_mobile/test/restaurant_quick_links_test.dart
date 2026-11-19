// Restaurant → Quick Links (2026-10-21): Tills & Shifts and Daily Closing, the
// two Quick Links pages that were not native yet, against a fake API at 360 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_daily_closing_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_tills_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
final staff = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Staff');
const tall = Size(360, 3400);
const fin = '/api/Restaurant/finance';

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> enterUnder(WidgetTester tester, String label, String text) async {
  final l = find.byWidgetPredicate((w) => w is Text && RegExp('^${RegExp.escape(label)}' r'( \*)?$').hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(EditableText));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('every Quick Link is native now, and the helpers', () async {
    final quick = webNavGroups['restaurant']!.firstWhere((g) => g.title == 'Quick Links').subGroups.single.links;
    expect([for (final l in quick) l.label], ['Sales', 'Tills & Shifts', 'Expenses', 'Cash Flow', 'Profit & Loss', 'Daily Closing']);
    for (final l in quick) {
      expect(pageScreens.containsKey(l.href), isTrue, reason: l.href);
    }
    expect(tillNum('12.345'), 12.35);
    expect(tillNum('abc'), 0);
    expect(mergeShifts([
      {'shiftId': 1},
    ], [
      {'shiftId': 1},
      {'shiftId': 2},
    ]).map((s) => s['shiftId']), [1, 2]);
    expect(closingNice('2026-10-21T00:00:00'), 'Wed, 21 Oct 2026');
    expect(closingNice(null), '—');
    expect(dayTakings({'takingsCash': 10, 'takingsCard': 5, 'takingsMobile': 2, 'takingsGiftCard': 1, 'takingsOther': 0}), 18);
    final pdf = await zReportPdf({'tillName': 'Front', 'shiftNumber': 'S-1', 'status': 'Closed', 'openingFloat': 50}, [
      {'section': 'Drawer', 'label': 'Cash sales', 'txnCount': 3, 'amount': 120},
    ], const FarmMoney());
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  testWidgets('Tills & Shifts: figures, open a shift with a float, close and count with a drop, the Z-report', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    final api = FakeApi()
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 1, 'name': 'Front Till', 'accountType': 'Till', 'isActive': true, 'currentBalance': 80},
        {'cashAccountId': 2, 'name': 'Bar Till', 'accountType': 'Till', 'isActive': true, 'currentBalance': 0},
        {'cashAccountId': 3, 'name': 'Cash Box', 'accountType': 'Cash', 'defaultFor': 'Cash', 'isActive': true, 'currentBalance': 500},
        {'cashAccountId': 4, 'name': 'Bank', 'accountType': 'Bank', 'isActive': true, 'currentBalance': 2000},
      ]
      ..gets['$fin/shifts'] = [
        {'shiftId': 7, 'shiftNumber': 'S-7', 'cashAccountId': 1, 'tillName': 'Front Till', 'status': 'Open', 'openedAt': '2026-10-21T08:00:00Z',
          'openedBy': 'Kofi', 'openingFloat': 50, 'cashSales': 30, 'currentBalance': 80, 'dropAmount': 0},
      ]
      ..gets['$fin/shifts/7/z-report'] = [
        {'section': 'Drawer', 'label': 'Cash sales', 'txnCount': 2, 'amount': 30},
        {'section': 'Takings', 'label': 'Card', 'txnCount': 1, 'amount': 15},
      ]
      ..writeAnswers['$fin/shifts/7/close'] = {'variance': -5, 'closingBalance': 50};
    await open(tester, RestaurantTillsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Open shifts'), findsOneWidget);
    expect(find.textContaining('S-7 · opened'), findsOneWidget);
    expect(find.text('No shift open'), findsOneWidget);
    expect(find.text('Cash sales this shift'), findsOneWidget);

    // Open a shift on the Bar Till with a float from the cash box (the default).
    await tester.tap(filled('Open shift'));
    await tester.pumpAndSettle();
    expect(find.text('Open shift — Bar Till'), findsOneWidget);
    await enterUnder(tester, 'Float to add', '40');
    await enterUnder(tester, 'Notes', 'Morning');
    await tester.tap(filled('Open shift').last);
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/shifts'), {'tillAccountId': 2, 'openingFloat': 40, 'floatFromAccountId': 3, 'notes': 'Morning'});

    // Close & count: 75 counted against 80 expected is short 5; leave the float in.
    await tester.tap(filled('Close & count'));
    await tester.pumpAndSettle();
    expect(find.text('Close & count — Front Till'), findsOneWidget);
    await enterUnder(tester, 'Cash counted', '75');
    expect(find.textContaining('Short by'), findsOneWidget);
    await tester.tap(find.textContaining('Leave the float'));
    await tester.pump();
    await tester.tap(filled('Close shift'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/shifts/7/close'), {'countedCash': 75, 'dropAmount': 25, 'dropToAccountId': 3, 'notes': null});

    // The Z-report follows (the fake still lists the shift as open, so it is an X-read).
    expect(find.text('X-read (shift still open)'), findsOneWidget);
    expect(find.text('Cash sales (2)'), findsOneWidget);
    expect(find.text('Card (1)'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(filled('Print'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(shared, ['Z-report_S-7.pdf']);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    // New till.
    await tester.tap(find.text('New till'));
    await tester.pumpAndSettle();
    await enterUnder(tester, 'Name', 'Patio Till');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/accounts'), {'name': 'Patio Till', 'accountType': 'Till', 'farmId': 'farm-1'});
  });

  testWidgets('Daily Closing: the day, warnings, open closing, close it, the closed days, reopen with a reason', (tester) async {
    final api = FakeApi()
      ..gets['$fin/daily-closing/preview'] = {
        'closingDate': '2026-10-21', 'isClosed': false, 'lastClosedDate': '2026-10-19', 'orderCount': 12, 'netSales': 640, 'discounts': 10,
        'taxCollected': 30, 'serviceCharge': 20, 'deliveryFees': 5, 'refunds': 15, 'tips': 8, 'takingsCash': 300, 'takingsCard': 200,
        'takingsMobile': 100, 'takingsGiftCard': 20, 'takingsOther': 0, 'expenses': 90, 'moneyIn': 600, 'moneyOut': 110, 'cashVariance': -5,
        'openShifts': 0, 'openOrders': 2, 'unpaidOrders': 1,
      }
      ..gets['$fin/daily-closing'] = [
        {'closingId': 9, 'closingDate': '2026-10-19', 'status': 'Closed', 'orderCount': 10, 'netSales': 500, 'moneyIn': 480, 'moneyOut': 60,
          'cashVariance': 0, 'closedBy': 'Ama', 'closedAt': '2026-10-19T22:00:00Z'},
        {'closingId': 8, 'closingDate': '2026-10-18', 'status': 'Reopened', 'orderCount': 9, 'netSales': 420, 'moneyIn': 400, 'moneyOut': 50,
          'cashVariance': -2, 'reopenReason': 'Wrong amount', 'closedAt': '2026-10-18T22:00:00Z'},
      ];
    await open(tester, RestaurantDailyClosingScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('ORDERS'), findsWidgets);
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('2 orders are not finished'), findsOneWidget);
    expect(find.text('1 order has money still owing.'), findsOneWidget);
    expect(find.textContaining('Closing it locks this day and everything since'), findsOneWidget);
    expect(find.text('Reopened: Wrong amount'), findsOneWidget);
    expect(find.text('Reopen'), findsOneWidget, reason: 'only the most recent closed day');

    // Open closing shows the full figures, and closes the day from there.
    await tester.tap(find.text('Open closing').first);
    await tester.pumpAndSettle();
    expect(find.text('Net sales (12 orders)'), findsOneWidget);
    expect(find.text('Gift cards (no cash)'), findsOneWidget);
    expect(find.text('Other'), findsNothing, reason: 'no other takings');
    await tester.tap(filled('Close this day').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('After this, no payment'), findsOneWidget);
    await enterUnder(tester, 'Notes (optional)', 'All good');
    await tester.tap(filled('Close the day'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/daily-closing'), {'closingDate': rTodayForTest(api), 'notes': 'All good'});

    // Reopen the most recent closed day.
    await tester.ensureVisible(find.text('Reopen'));
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(filled('Reopen')).onPressed, isNull, reason: 'a reason is needed');
    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('AppSelect<String>')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrong date').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Reopen'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/daily-closing/reopen'), {'closingDate': '2026-10-19', 'reason': 'Wrong date'});
  });

  testWidgets('Daily Closing: an open till blocks closing; staff cannot see the page', (tester) async {
    final api = FakeApi()
      ..gets['$fin/daily-closing/preview'] = {'closingDate': '2026-10-21', 'isClosed': false, 'openShifts': 1, 'orderCount': 0}
      ..gets['$fin/daily-closing'] = [];
    await open(tester, RestaurantDailyClosingScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('1 till shift is still open. '), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Close this day'), matching: find.byType(FilledButton))).onPressed, isNull);
    expect(find.text('No closings yet.'), findsOneWidget);

    await open(tester, RestaurantDailyClosingScreen(session: await sessionFor(FakeApi()), company: staff), size: tall);
    expect(find.text('You do not have access to Daily Closing.'), findsOneWidget);
  });
}

/// The day the screen reviewed: the date the preview was asked for.
String rTodayForTest(FakeApi api) =>
    api.requests.lastWhere((r) => r.url.path == '$fin/daily-closing/preview').url.queryParameters['date']!;
