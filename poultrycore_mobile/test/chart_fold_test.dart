// Folding a dashboard chart card by tapping its header (user, 2026-11-09).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/water/water_dashboard_charts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

final now = DateTime(2026, 11, 4, 10);

void main() {
  setUp(ChartFolds.reset);

  testWidgets('tap a header: the card folds to one line, tap again: it opens; remembered per module', (tester) async {
    final api = FakeApi();
    final session = await sessionFor(api);
    Future<void> show(Widget charts) => open(tester, Scaffold(body: ListView(children: [charts])), size: const Size(360, 3200));

    await show(PoultryDashboardCharts(session: session, company: company, now: () => now));
    expect(find.text('No expenses in the last 12 months'), findsOneWidget);

    await tester.tap(find.text('Where the money goes'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses in the last 12 months'), findsNothing, reason: 'the pie is folded away');
    expect(find.textContaining('Expenses by category'), findsNothing, reason: 'the subtitle folds too');
    expect(find.text('Where the money goes'), findsOneWidget, reason: 'the title stays, to open it again');
    expect(find.text('No sales in the last 12 months'), findsOneWidget, reason: 'the other cards stay open');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('chart_cards_folded'), ['poultry|Where the money goes']);

    // Water has a card with the same title: it stays open.
    final water = Company(farmId: 'w1', name: 'Pure Water', type: CompanyType.water, role: 'Admin');
    await show(WaterDashboardCharts(session: session, company: water, now: () => now));
    expect(find.text('No approved expenses in the last 12 months'), findsOneWidget);

    // Back in Poultry (and after the app forgets its memory), the card is still folded.
    ChartFolds.reset();
    await show(PoultryDashboardCharts(session: session, company: company, now: () => now));
    expect(find.text('No expenses in the last 12 months'), findsNothing);

    await tester.tap(find.text('Where the money goes'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses in the last 12 months'), findsOneWidget);
    expect(prefs.getStringList('chart_cards_folded'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
