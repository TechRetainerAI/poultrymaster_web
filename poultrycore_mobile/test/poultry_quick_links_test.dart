// Poultry Quick Links (migration 318), at phone width: the default bar, the
// user's own bar, "Customise…", Save and Reset to defaults, and that every
// default link opens a native screen.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';
import 'package:poultrycore_mobile/widgets/quick_links_dialog.dart';

import 'support/harness.dart';

final _groups = webNavGroups['poultry']!;

const _defaults = [
  'Production Records', 'Egg sorting', 'Raw Materials', 'Sales', 'Payments received', 'Customer Balances', 'Expenses', 'Cash Flow',
  'Profit & Loss', 'Daily Closing',
];

Future<void> _openSidebar(WidgetTester tester, Session s) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showModuleSidebar(context, session: s, company: company),
      child: const Text('menu'),
    )))),
    size: phone,
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Quick Links'));
  await tester.pumpAndSettle();
}

void main() {
  test('catalogue and resolver follow the web', () {
    expect([for (final l in defaultQuickLinks(_groups)) l.label], _defaults);
    final cat = quickLinkCatalogue(_groups);
    expect(cat.first.group, 'Shortcuts');
    expect(cat.where((c) => c.link.href == '/egg-production').single.link.label, 'Egg sorting', reason: 'first occurrence wins');
    expect(cat.any((c) => c.group.startsWith('Reports') || c.group.startsWith('System') || c.group.startsWith('Tools')), isFalse);
    expect(cat.any((c) => c.group == 'Operations · Production' && c.link.href == '/feed-usage'), isTrue);
    expect(resolveQuickLinks(_groups, null).length, 10);
    expect(resolveQuickLinks(_groups, []), isEmpty, reason: 'a cleared bar stays empty');
    expect([for (final l in resolveQuickLinks(_groups, ['/cash-flow', '/gone', '/sales'])) l.label], ['Cash Flow', 'Sales']);
    for (final l in defaultQuickLinks(_groups)) {
      expect(pageScreens.containsKey(l.href), isTrue, reason: '${l.href} opens a native screen');
    }
  });

  testWidgets('defaults, then customise and save in catalogue order', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    a.writeAnswers['/api/UserQuickLinks'] = {'customised': true, 'hrefs': ['/production-records', '/feed-usage']};
    await _openSidebar(tester, await sessionFor(a));
    for (final l in _defaults) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('Customise…'), findsOneWidget);

    await tester.ensureVisible(find.text('Customise…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customise…'));
    await tester.pumpAndSettle();
    expect(find.text('Your Quick Links'), findsOneWidget);
    expect(find.text('10 of 20 chosen'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'feed usage');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ql-/feed-usage')));
    await tester.pumpAndSettle();
    expect(find.text('11 of 20 chosen'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final w = a.writes.single;
    final b = jsonDecode(w.body) as Map;
    expect((w.method, b['userId'], b['farmId']), ('PUT', 'user-1', 'farm-1'));
    final hrefs = b['hrefs'] as List;
    expect(hrefs.first, '/production-records');
    expect(hrefs.last, '/feed-usage', reason: 'catalogue order, not tick order');
    expect(hrefs.length, 11);
    expect(find.text('Feed Usage'), findsWidgets);
    expect(find.text('Daily Closing'), findsNothing, reason: 'the bar is what the server saved');
  });

  testWidgets('a cleared bar shows only Customise…, and Reset brings the defaults back', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': true, 'hrefs': []};
    await _openSidebar(tester, await sessionFor(a));
    expect(find.text('Production Records'), findsNothing);
    expect(find.text('Customise…'), findsOneWidget);

    await tester.tap(find.text('Customise…'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 20 chosen'), findsOneWidget);
    expect(find.text('An empty bar is allowed — the menu stays hidden.'), findsOneWidget);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect((a.writes.single.method, a.writes.single.url.path), ('DELETE', '/api/UserQuickLinks'));
    expect(a.writes.single.url.queryParameters, {'userId': 'user-1', 'farmId': 'farm-1'});
    expect(find.text('Production Records'), findsOneWidget);
  });
}
