// Poultry → Trackers → Broken eggs tracker and Dead birds tracker (372-381),
// against a fake API, at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/trackers/byproduct_tracker_screen.dart';

import 'support/harness.dart';

const path = '/api/Poultry/stock/byproduct-tracker';
const tallPhone = Size(360, 2400);

Map<String, dynamic> move(int id, String date, String category, String type, num qty, {int? flockId, String? no, int? saleId}) => {
      'txnId': id, 'date': date, 'category': category, 'txnType': type, 'quantity': qty,
      'flockId': flockId, 'flockName': flockId == null ? null : 'Flock A', 'batchCode': flockId == null ? null : 'B-01',
      'saleId': saleId, 'revenue': 0, 'manualMovementId': null, 'movementNo': no, 'note': null,
    };

Map<String, dynamic> data() => {
      'role': 'BrokenEggs',
      'onHand': 42,
      'flocks': [
        {'flockId': 7, 'flockName': 'Flock A', 'batchCode': 'B-01', 'opening': 10, 'generated': 30, 'sold': 12, 'disposed': 5,
          'internalUse': 0, 'manualIn': 0, 'manualOut': 0, 'reversals': 0, 'closing': 23, 'revenue': 24},
        {'flockId': null, 'flockName': null, 'batchCode': null, 'opening': 0, 'generated': 8, 'sold': 0, 'disposed': 0,
          'internalUse': 0, 'manualIn': 0, 'manualOut': 0, 'reversals': 0, 'closing': 8, 'revenue': 0},
      ],
      'movements': [
        move(1, '2026-10-01', 'Generated', 'Broken Egg Prod', 30, flockId: 7),
        move(2, '2026-10-03', 'Sold', 'Sale', -12, flockId: 7, saleId: 55),
        move(3, '2026-10-04', 'Disposed', 'Disposal', -5, flockId: 7, no: 'MSM-0004'),
        move(4, '2026-10-05', 'Generated', 'Sorting Breakage', 8),
      ],
    };

void main() {
  setUp(LookupLoader.clear);

  test('the running balance starts at the opening, newest first, and corrections are named', () {
    final rows = byproductLedger(rowsFrom(data()['movements']), 10, flock: '7');
    expect([for (final r in rows) r.$2], [23, 28, 40]);
    expect(byproductLedger(rowsFrom(data()['movements']), 10, flock: '7', category: 'Disposed').single.$2, 23);
    expect(byproductCategoryText(move(9, '2026-10-06', 'Generated', 'Broken Egg Prod', -2)), 'Correction');
    expect(byproductCategoryText(move(9, '2026-10-06', 'ManualIn', 'Breakage In', 2)), 'Added by hand');
  });

  testWidgets('Broken eggs: totals, flocks, movements and every filter', (tester) async {
    final api = FakeApi()..gets[path] = data();
    await open(tester, ByproductTrackerScreen(session: await sessionFor(api), company: company, role: ByproductRole.brokenEggs),
        size: tallPhone);
    final q = api.requests.lastWhere((r) => r.url.path == path).url.queryParameters;
    expect((q['role'], q['farmId']), ('BrokenEggs', 'farm-1'));
    expect(find.text('BROKEN EGGS RECORDED'), findsOneWidget);
    expect(find.text('38'), findsWidgets, reason: '30 + 8 recorded over both rows');
    expect(find.text('Flock A · B-01'), findsOneWidget);
    expect(find.text('Pooled (no flock)'), findsWidgets);
    expect(find.textContaining('Egg sorting'), findsWidgets);

    // Flock: only the pooled row and its movement.
    await pick(tester, 'All flocks', 'Pooled (no flock)');
    expect(find.text('Flock A · B-01'), findsNothing);
    expect(find.textContaining('In 8 · Out 0'), findsOneWidget);

    // Movement: back to all flocks, disposals only.
    await pick(tester, 'Pooled (no flock)', 'All flocks');
    await pick(tester, 'All movements', 'Disposed');
    expect(find.textContaining('In 0 · Out 5'), findsOneWidget);
    expect(find.text('MSM-0004'), findsOneWidget);

    // Period: All Time reloads from 2000-01-01.
    await pick(tester, 'Last 30 Days', 'All Time');
    expect(api.requests.lastWhere((r) => r.url.path == path).url.queryParameters['fromDate'], '2000-01-01');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dead birds: its own title, role and links', (tester) async {
    final api = FakeApi()..gets[path] = {...data(), 'role': 'DeadBirds'};
    await open(tester, ByproductTrackerScreen(session: await sessionFor(api), company: company, role: ByproductRole.deadBirds),
        size: tallPhone);
    expect(api.requests.lastWhere((r) => r.url.path == path).url.queryParameters['role'], 'DeadBirds');
    expect(find.text('Dead birds tracker'), findsWidgets);
    expect(find.text('DEATHS RECORDED'), findsOneWidget);
    expect(find.text('Birds tracker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<Map> rowsFrom(Object? v) => [for (final r in v as List) r as Map];
