// Hotel's System menu at phone width (hotel-nav-config.ts `system`, with the
// sidebar's prepended Account row): Account, Companies and Billing, each
// opened from inside a Hotel company with Hotel data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/shared/account_screen.dart';
import 'package:poultrycore_mobile/pages/shared/billing_screen.dart';
import 'package:poultrycore_mobile/pages/shared/companies_screen.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/all_pages_sheet.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');

FakeApi _api() => FakeApi()
  ..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []}
  ..gets['/api/Authentication/get-current-user'] = {
    'Id': 'user-1', 'UserName': 'ama@palm.test', 'Email': 'ama@palm.test', 'FarmName': 'Palm Hotel', 'FarmId': 'h1',
    'FirstName': 'Ama', 'LastName': 'Owusu', 'TwoFactorEnabled': false,
  }
  ..gets['/api/Companies/mine'] = [
    {'farmId': 'h1', 'name': 'Palm Hotel', 'type': 'Hotel', 'role': 'Admin', 'ownerUserId': 'user-1', 'createdAt': '2026-09-01T00:00:00'},
    {'farmId': 'r1', 'name': 'Palm Grill', 'type': 'Restaurant', 'role': 'Admin', 'ownerUserId': 'user-1', 'createdAt': '2026-09-02T00:00:00'},
  ]
  ..gets['/api/PlatformBilling/summary'] = {
    'pendingTierChanges': [],
    'account': {'marketCode': 'GH', 'currencyCode': 'GHS', 'status': 'Active', 'billingCycle': 'monthly', 'cancelAtPeriodEnd': false},
    'companies': [
      {'farmId': 'h1', 'companyName': 'Palm Hotel', 'businessType': 'Hotel', 'metricType': 'RoomCount', 'metricValue': 24, 'tierName': 'Growth',
        'monthlyAmount': 300, 'currencyCode': 'GHS', 'pricingStatus': 'Priced', 'participationStatus': 'Active'},
    ],
    'preview': {'subtotal': 300, 'eligibleCompanyCount': 1, 'discountPercent': 0, 'discountAmount': 0, 'taxAmount': 0, 'total': 300,
      'currencyCode': 'GHS', 'hasUnpricedCompanies': false, 'periodStart': '2026-10-01T00:00:00Z', 'periodEnd': '2026-10-31T00:00:00Z'},
  }
  ..gets['/api/PlatformBilling/invoices'] = []
  ..gets['/api/PlatformBilling/payments'] = [];

Future<void> _openWith(WidgetTester tester, Session s, void Function(BuildContext) show) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => show(context), child: const Text('menu'))))),
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

Future<Session> _session() async {
  final s = await sessionFor(_api());
  await s.loadCompanies();
  return s;
}

void main() {
  testWidgets('drawer: System holds Account, Companies, Billing in order', (tester) async {
    final s = await _session();
    await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: hotel));
    await _tap(tester, find.text('System'));
    const rows = ['Account', 'Companies', 'Billing'];
    for (final r in rows) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    final y = [for (final r in rows) tester.getTopLeft(find.text(r)).dy];
    expect(y, [...y]..sort());
  });

  testWidgets('Account opens the profile for the Hotel', (tester) async {
    final s = await _session();
    await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: hotel));
    await _tap(tester, find.text('System'));
    await _tap(tester, find.text('Account'));
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Ama Owusu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Companies lists the Hotel with its mark', (tester) async {
    final s = await _session();
    await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: hotel));
    await _tap(tester, find.text('System'));
    await _tap(tester, find.text('Companies'));
    expect(find.byType(CompaniesScreen), findsOneWidget);
    expect(find.text('Palm Hotel'), findsWidgets);
    expect(find.text('Palm Grill'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Billing groups the Hotel under its own type', (tester) async {
    final s = await _session();
    await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: hotel));
    await _tap(tester, find.text('System'));
    await _tap(tester, find.text('Billing'));
    expect(find.byType(BillingScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Hotel'), 300, scrollable: find.byType(Scrollable).last);
    await _tap(tester, find.text('Hotel'));
    expect(find.text('Palm Hotel'), findsWidgets);
    expect(find.byIcon(Icons.bed_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More sheet: SYSTEM has the same three rows', (tester) async {
    final s = await _session();
    await _openWith(tester, s, (c) => showAllPages(c, s, hotel));
    await _tap(tester, find.text('SYSTEM'));
    for (final r in ['Account', 'Companies', 'Billing']) {
      expect(find.text(r), findsWidgets, reason: r);
    }
    await _tap(tester, find.text('Billing').last);
    expect(find.byType(BillingScreen), findsOneWidget);
  });
}
