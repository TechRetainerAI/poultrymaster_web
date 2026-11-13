// Report 35 Part 3, A4 of the 9 Nov web pull: production records, checked against
// the web. The automatic loss rule tests are the web's own cases, ported one
// for one from lib/poultry/auto-loss-entries.test.ts. The screens run at phone
// width against a fake API: View by Day ("Show in table", no extra Meds), the
// Loss & Damage page's automatic rows, and the boxes total's own line.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/auto_loss_entries.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/loss_records_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/production/production_day_view.dart';

import 'support/harness.dart';

Map<String, Object?> _rec(Map<String, Object?> o) => {'id': 1, 'date': '2026-11-05T00:00:00', 'brokenEggs': 0, 'flockName': 'A', ...o};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

void main() {
  // --------------------------------------------------- auto-loss-entries.test.ts
  group('auto loss entries (the web\'s cases)', () {
    test('makes one Damage row per production record with broken eggs', () {
      final rows = fromProductionRecords([_rec({'id': 1, 'brokenEggs': 12}), _rec({'id': 2, 'brokenEggs': 0})]);
      expect(rows, hasLength(1));
      expect((rows[0].key, rows[0].lossType, rows[0].productName, rows[0].quantity), ('pr-1', 'Damage', 'Broken eggs', 12));
      expect(rows[0].href, contains('/production-records/1'));
    });
    test('describes a partial disposal', () {
      expect(fromProductionRecords([_rec({'brokenEggs': 10, 'brokenEggsDisposed': 4})]).single.reason, 'Flock A · 4 disposed, 6 kept');
    });
    test('maps driver-return losses and keeps their value', () {
      final r = fromProductionLosses([
        {'poultryProductionLossId': 7, 'farmId': 'f', 'sourceType': 'PoultryDriverReturn', 'lossDate': '2026-11-04', 'quantityLost': 60, 'estimatedValue': 90, 'productName': 'Fresh Eggs'},
      ]).single;
      expect((r.source, r.quantity, r.estimatedValue, r.href), ('DriverReturn', 60, 90, '/poultry-driver-returns'));
    });
    test('takes only Egg Loss ledger rows, as positive quantities', () {
      final rows = fromEggLossTransactions([
        {'poultryStockTransactionId': 1, 'txnType': 'Egg Loss', 'quantity': -30, 'productName': 'Large', 'note': 'Breakage: dropped tray', 'createdDate': '2026-11-05'},
        {'poultryStockTransactionId': 2, 'txnType': 'Adjustment', 'quantity': 8, 'createdDate': '2026-11-05'},
        {'poultryStockTransactionId': 3, 'txnType': 'Sale', 'quantity': -100, 'createdDate': '2026-11-05'},
      ]);
      expect(rows, hasLength(1));
      expect((rows[0].quantity, rows[0].productName, rows[0].reason), (30, 'Large eggs', 'Breakage: dropped tray'));
    });
    test("maps the server's rows to the same shape", () {
      final rows = fromAutoDamageApi([
        {'sourceType': 'ProductionRecord', 'sourceId': 9, 'lossDate': '2026-11-05', 'lossType': 'Damage', 'productName': 'Broken eggs', 'quantity': 10, 'flockName': 'A', 'brokenEggs': 10, 'disposed': 4},
        {'sourceType': 'DriverReturn', 'sourceId': 3, 'lossDate': '2026-11-04', 'lossType': 'Damage', 'productName': 'Fresh Eggs', 'quantity': 60, 'estimatedValue': 90},
        {'sourceType': 'EggSorting', 'sourceId': 5, 'lossDate': '2026-11-03', 'lossType': 'Damage', 'productName': 'Large eggs', 'quantity': 30, 'details': 'Breakage: dropped tray'},
      ]);
      expect((rows[0].key, rows[0].reason), ('pr-9', 'Flock A · 4 disposed, 6 kept'));
      expect(rows[0].href, contains('/production-records/9'));
      expect((rows[1].source, rows[1].estimatedValue, rows[1].href), ('DriverReturn', 90, '/poultry-driver-returns'));
      expect((rows[2].source, rows[2].reason), ('EggSorting', 'Breakage: dropped tray'));
    });
    test('filters by date range and sorts newest first', () {
      final rows = buildAutoLossEntries(
        records: [
          _rec({'id': 1, 'date': '2026-11-01', 'brokenEggs': 1}),
          _rec({'id': 2, 'date': '2026-11-05', 'brokenEggs': 2}),
          _rec({'id': 3, 'date': '2026-10-01', 'brokenEggs': 3}),
        ],
        fromDate: '2026-11-01',
      );
      expect([for (final r in rows) r.key], ['pr-2', 'pr-1']);
    });
  });

  // ------------------------------------------------------------ Loss & Damage
  group('Loss & Damage: automatic rows', () {
    FakeApi api() => FakeApi()
      ..gets['/api/Poultry/loss-records'] = [
        {'poultryLossRecordId': 3, 'lossDate': '2026-11-02', 'lossType': 'Spoilage', 'productName': 'Feed', 'quantity': 2, 'estimatedValue': 24, 'status': 'Pending'},
      ]
      ..gets['/api/Poultry/products'] = [];

    testWidgets('the server rows, newest first, read-only with Open <source>', (tester) async {
      final a = api()
        ..gets['/api/Poultry/loss-records/auto-damage'] = [
          {'sourceType': 'ProductionRecord', 'sourceId': 9, 'lossDate': '2026-11-05', 'lossType': 'Damage', 'productName': 'Broken eggs', 'quantity': 10, 'flockName': 'A', 'brokenEggs': 10, 'disposed': 4},
          {'sourceType': 'DriverReturn', 'sourceId': 3, 'lossDate': '2026-11-01', 'lossType': 'Damage', 'productName': 'Fresh Eggs', 'quantity': 60, 'estimatedValue': 90},
        ];
      await open(tester, LossRecordsScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.textContaining('are added automatically — change those at their source.'), findsOneWidget);
      expect(find.text('Automatic'), findsNWidgets(2));
      expect(find.text('Broken eggs · from production record'), findsOneWidget);
      expect(find.textContaining('Flock A · 4 disposed, 6 kept', findRichText: true), findsOneWidget);
      // Newest first: the 5 Nov automatic row, the 2 Nov manual one, then 1 Nov.
      final y = [
        tester.getTopLeft(find.byKey(const ValueKey('loss-auto-pr-9'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('loss-3'))).dy,
      ];
      expect(y[0] < y[1], isTrue);
      await see(tester, find.text('Fresh Eggs · from driver return'));
      expect(find.text('GHC 90.00'), findsOneWidget);
      expect(find.text('Open driver return'), findsOneWidget);
      // No Approve / Edit / Delete on an automatic row: only the manual one has them.
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('before 405: built from production records, losses and the ledger', (tester) async {
      final a = api()
        ..statuses['/api/Poultry/loss-records/auto-damage'] = 404
        ..gets['/api/ProductionRecord'] = [_rec({'id': 4, 'date': '2026-11-03', 'brokenEggs': 7})]
        ..gets['/api/Poultry/production-losses'] = []
        ..gets['/api/Poultry/stock/transactions'] = [
          {'poultryStockTransactionId': 8, 'txnType': 'Egg Loss', 'quantity': -5, 'productName': 'Large', 'createdDate': '2026-11-04'},
        ];
      await open(tester, LossRecordsScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.byKey(const ValueKey('loss-auto-pr-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('loss-auto-st-8')), findsOneWidget);
      expect(find.text('Large eggs · from egg sorting'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------- View by Day
  group('View by Day', () {
    final records = <Map>[
      {'id': 1, 'date': '2026-11-05T00:00:00', 'flockId': 1, 'production9AM': 100, 'production12PM': 50, 'production4PM': 20, 'brokenEggs': 2,
        'totalProduction': 170, 'feedKg': 12.5, 'noOfBirds': 200, 'mortality': 1, 'medication': 'Vitamins'},
      {'id': 2, 'date': '2026-11-04T00:00:00', 'flockId': 2, 'totalProduction': 90, 'feedKg': 5, 'noOfBirds': 100},
    ];

    testWidgets('the web\'s description and feed figures; no Meds; Show in table returns the day', (tester) async {
      String? shown;
      Map? edited;
      await open(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showProductionDayView(
                  ctx,
                  records: records,
                  extraPicks: const [],
                  flockLabel: (r) => 'Flock ${r['flockId']}',
                  batchLabel: (_) => 'B1',
                  onEdit: (r) => edited = r,
                  onShowInTable: (d) => shown = d,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        size: phone,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Every production record logged on the chosen day, for all flocks.'), findsOneWidget);
      expect(find.text('2026-11-05'), findsOneWidget, reason: 'opens on the latest day with records');
      expect(find.text('12.5 kg'), findsOneWidget, reason: 'Feed used, as the web formats it');
      expect(find.textContaining('Meds', findRichText: true), findsNothing, reason: 'the web\'s day view has no Meds');
      await tester.tap(find.byKey(const ValueKey('day-show-in-table')));
      await tester.pumpAndSettle();
      expect((shown, edited), ('2026-11-05', null));
    });

    testWidgets('Show in table is off on a day with no records', (tester) async {
      await open(
        tester,
        ProductionDayView(records: records, extraPicks: const [], flockLabel: (_) => 'F', batchLabel: (_) => 'B', canShowInTable: true),
        size: phone,
      );
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('No production records on this day.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('day-show-in-table'))).onPressed, isNull);
    });
  });
}
