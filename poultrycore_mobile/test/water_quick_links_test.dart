// Water Quick Links at phone width, as the web draws them: the default bar
// (water-nav-config.ts), the catalogue (quick-links.ts), "Customise…" in the
// drawer, and the phone "More" sheet's Quick Links section ending in
// "Customise Quick Links" (mobile-bottom-nav.tsx).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/all_pages_sheet.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';
import 'package:poultrycore_mobile/widgets/quick_links_dialog.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Water Co', type: CompanyType.water, role: 'Admin');
final _groups = webNavGroups['water']!;

const _defaults = ['Water Production', 'Batch Production', 'Deliveries', 'Sales', 'Payments', 'Expenses', 'Daily Closing'];

Future<void> _openWith(WidgetTester tester, Session s, void Function(BuildContext) show) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => show(context),
      child: const Text('menu'),
    )))),
    size: phone,
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('defaults and catalogue follow the web', () {
    expect([for (final l in defaultQuickLinks(_groups)) l.label], _defaults);
    final cat = quickLinkCatalogue(_groups);
    expect(cat.first.group, 'Shortcuts');
    expect(cat.any((c) => c.group.startsWith('Reports') || c.group.startsWith('System') || c.group.startsWith('Tools')), isFalse);
    expect(cat.any((c) => c.group == 'Operations · Production' && c.link.href == '/water-maintenance'), isTrue);
    expect(resolveQuickLinks(_groups, []), isEmpty);
  });

  testWidgets('drawer: defaults, Customise… and Save', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    a.writeAnswers['/api/UserQuickLinks'] = {'customised': true, 'hrefs': ['/water-maintenance']};
    final s = await sessionFor(a);
    await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: water));
    await _tap(tester, find.text('Quick Links'));
    for (final l in _defaults) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    await _tap(tester, find.text('Customise…'));
    expect(find.text('7 of 20 chosen'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'maintenance');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ql-/water-maintenance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final w = a.writes.single;
    final b = jsonDecode(w.body) as Map;
    expect((w.method, w.url.path, b['farmId']), ('PUT', '/api/UserQuickLinks', 'farm-1'));
    expect((b['hrefs'] as List).length, 8);
    expect(find.text('Daily Closing'), findsNothing, reason: 'the bar is what the server saved');
  });

  testWidgets('More sheet: Quick Links section with Customise Quick Links', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': true, 'hrefs': ['/water-deliveries', '/water-sales']};
    a.writeAnswers['/api/UserQuickLinks'] = {'customised': true, 'hrefs': ['/water-sales']};
    final s = await sessionFor(a);
    await _openWith(tester, s, (c) => showAllPages(c, s, water));
    await _tap(tester, find.text('QUICK LINKS'));
    expect(find.text('Customise Quick Links'), findsOneWidget);
    expect(find.text('Daily Closing'), findsNothing, reason: "the user's own bar, not the defaults");

    await _tap(tester, find.text('Customise Quick Links'));
    expect(find.text('Your Quick Links'), findsOneWidget);
    expect(find.text('2 of 20 chosen'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(a.writes.single.method, 'PUT');
    expect(find.text('Customise Quick Links'), findsOneWidget, reason: 'back on the sheet');
  });

  testWidgets('More sheet: a cleared bar keeps only the customise row', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': true, 'hrefs': []};
    final s = await sessionFor(a);
    await _openWith(tester, s, (c) => showAllPages(c, s, water));
    await _tap(tester, find.text('QUICK LINKS'));
    expect(find.text('Customise Quick Links'), findsOneWidget);
    expect(find.text('Water Production'), findsNothing);
  });
}
