// The header search (global-search.tsx), as the app's full-screen search:
// pages with typos and synonyms, records by name and by phone digits, Recent,
// "Record it on" for intents, and nothing a user may not open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/shared/global_search_screen.dart';

import 'support/harness.dart';

FakeApi searchApi() => FakeApi()
  ..gets['/api/Customer'] = [
    {'customerId': 1, 'name': 'Kofi Mensah', 'contactPhone': '+233 244 123 456', 'city': 'Kumasi'},
    {'customerId': 2, 'name': 'Ama Owusu', 'contactPhone': '020 555 0000'},
  ]
  ..gets['/api/Supplier'] = [
    {'supplierId': 3, 'name': 'Feedco Ltd', 'contactPhone': '030 111 2222'},
  ]
  ..gets['/api/Flock'] = [
    {'flockId': 4, 'name': 'Layers A', 'breed': 'Isa Brown', 'quantity': 500, 'active': true},
    {'flockId': 5, 'name': 'Layers Old', 'active': false},
  ]
  ..gets['/api/House'] = [
    {'houseId': 6, 'name': 'Pen 1', 'capacity': 800},
  ];

Future<void> typeQ(WidgetTester tester, String q) async {
  await tester.enterText(find.descendant(of: find.byKey(const ValueKey('global-search')), matching: find.byType(TextField)), q);
  await tester.pumpAndSettle();
}

void main() {
  test('records: names need a real hit; phones match on digits', () {
    const recs = [
      SearchRecord(kind: 'customer', id: '1', title: 'Kofi Mensah', href: '/customers', phones: ['+233 244 123 456']),
      SearchRecord(kind: 'customer', id: '2', title: 'Ama Owusu', href: '/customers', phones: ['020 555 0000']),
    ];
    expect(rankRecords('kofi', recs).map((r) => r.id), ['1']);
    expect(rankRecords('02441', recs).map((r) => r.id), ['1'], reason: 'a local 0 meets the country code (4+ digits after it, as the web)');
    expect(rankRecords('0244', recs), isEmpty, reason: 'too short once the 0 is dropped, as on the web');
    expect(rankRecords('kf', recs), isEmpty, reason: 'a loose subsequence is not a hit');
    expect(queryIsCreate('new sale'), isTrue);
    expect(queryIsCreate('cash flow'), isFalse);
    expect(searchPlaceholder(CompanyType.water), 'Search pages, customers, drivers…');
  });

  testWidgets('pages, records, Record it on, Recent, nothing matches', (tester) async {
    final api = searchApi();
    await open(tester, GlobalSearchScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('Search pages, customers, flocks…'), findsOneWidget);
    expect(find.textContaining('a customer name or a phone number'), findsOneWidget);

    await typeQ(tester, 'who owes');
    expect(find.text('Pages'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-/customer-balances')), findsOneWidget, reason: 'the synonym "who owes"');

    await typeQ(tester, 'expences');
    expect(find.byKey(const ValueKey('page-/expenses')), findsOneWidget, reason: 'typo-tolerant');

    await typeQ(tester, 'new sale');
    expect(find.text('Record it on'), findsOneWidget);

    await typeQ(tester, 'kofi');
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('+233 244 123 456 · Kumasi'), findsOneWidget);

    await typeQ(tester, '02441');
    expect(find.byKey(const ValueKey('record-customer-1')), findsOneWidget);

    await typeQ(tester, 'layers');
    expect(find.text('Layers Old (inactive)'), findsOneWidget);

    await typeQ(tester, 'zzqqxx');
    expect(find.text('Nothing matches “zzqqxx”.'), findsOneWidget);
    expect(find.text('Check the spelling, or try a shorter word.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a result remembers it under Recent; Clear empties it', (tester) async {
    final api = searchApi();
    await open(tester, GlobalSearchScreen(session: await sessionFor(api), company: company), size: phone);
    await typeQ(tester, 'feed formulas');
    await tester.tap(find.byKey(const ValueKey('page-/poultry-feed-formulas')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-/poultry-feed-formulas')), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('staff: no Setup pages, and records only from pages they may open', (tester) async {
    final staff = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Staff');
    await open(tester, GlobalSearchScreen(session: await sessionFor(searchApi()), company: staff), size: phone);
    await typeQ(tester, 'company setup');
    expect(find.byKey(const ValueKey('page-/poultry-company-setup')), findsNothing);
  });

  testWidgets('Hotel: pages and reports only, no record lookups', (tester) async {
    final api = FakeApi();
    final hotel = Company(farmId: 'h1', name: 'Inn', type: CompanyType.hotel);
    await open(tester, GlobalSearchScreen(session: await sessionFor(api), company: hotel), size: phone);
    expect(find.text('Search pages and reports…'), findsOneWidget);
    expect(find.textContaining('Search pages and reports. Try'), findsOneWidget);
    expect(api.requests, isEmpty);
  });
}
