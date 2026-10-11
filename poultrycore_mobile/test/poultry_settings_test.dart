// Poultry Settings (the web's System menu), at phone width: Account, Alerts,
// Billing, Activity Log, Resources, Help Center and Terms & Conditions.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/shared/account_screen.dart';
import 'package:poultrycore_mobile/pages/shared/activity_log_screen.dart';
import 'package:poultrycore_mobile/pages/shared/billing_screen.dart';
import 'package:poultrycore_mobile/pages/shared/help_screen.dart';
import 'package:poultrycore_mobile/pages/shared/resources_screen.dart';
import 'package:poultrycore_mobile/pages/shared/terms_screen.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 250));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option, {Finder? within}) async {
  final label = within == null ? find.text(shown) : find.descendant(of: within, matching: find.text(shown));
  final sel = find.ancestor(of: label.first, matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

final _summary = {
  'pendingTierChanges': [
    {'farmId': 'farm-1', 'companyName': 'Test Farm', 'fromTierName': 'Starter', 'toTierName': 'Growth', 'effectiveDate': '2026-11-01T00:00:00Z'},
  ],
  'account': {'marketCode': 'GH', 'currencyCode': 'GHS', 'status': 'Active', 'billingCycle': 'monthly', 'cancelAtPeriodEnd': false},
  'companies': [
    {'farmId': 'farm-1', 'companyName': 'Test Farm', 'businessType': 'Poultry', 'metricType': 'ActiveBirdCount', 'metricValue': 1200, 'tierName': 'Growth',
      'monthlyAmount': 150, 'currencyCode': 'GHS', 'pricingStatus': 'Priced', 'participationStatus': 'Active'},
    {'farmId': 'farm-2', 'companyName': 'Water Co', 'businessType': 'Water', 'metricValue': 0, 'currencyCode': 'GHS', 'pricingStatus': 'PricingNotConfigured',
      'participationStatus': 'Active'},
  ],
  'preview': {'subtotal': 150, 'eligibleCompanyCount': 1, 'discountPercent': 0, 'discountAmount': 0, 'taxAmount': 0, 'total': 150, 'currencyCode': 'GHS',
    'hasUnpricedCompanies': true, 'periodStart': '2026-10-01T00:00:00Z', 'periodEnd': '2026-10-31T00:00:00Z'},
};

void main() {
  test('every Settings row opens a native screen', () {
    for (final h in ['/profile', '/business-office/billing', '/billing', '/audit-logs', '/resources', '/help', '/terms']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(friendlyAction('POST'), 'Created');
    expect(prettyAuditData('{"a":1}'), '{\n  "a": 1\n}');
    expect(resourceAge({'ageInWeeks': 2, 'ageInDays': 14}), '2 weeks, 14 days');
    expect(billingMoney(1234.5, 'GHS'), 'GHS 1,234.50');
  });

  testWidgets('Alerts opens "System Alerts and Notifications"', (tester) async {
    final s = await sessionFor(FakeApi());
    await open(
      tester,
      Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showModuleSidebar(context, session: s, company: company), child: const Text('menu')))),
      size: phone,
    );
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('System'));
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    for (final l in ['Account', 'Alerts', 'Billing', 'Activity Log', 'Resources', 'Help Center', 'Terms & Conditions']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    await tester.ensureVisible(find.text('Alerts'));
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('System Alerts and Notifications'), findsOneWidget);
    expect(find.text('No alerts'), findsOneWidget);
  });

  testWidgets('Billing: notices, hero, companies, market change and explain', (tester) async {
    final a = FakeApi()
      ..gets['/api/PlatformBilling/summary'] = _summary
      ..gets['/api/PlatformBilling/invoices'] = [
        {'id': 1, 'invoiceNumber': 'INV-0001', 'currencyCode': 'GHS', 'periodStart': '2026-09-01', 'periodEnd': '2026-09-30', 'totalAmount': 150, 'balance': 0, 'status': 'Paid'},
      ]
      ..gets['/api/PlatformBilling/payments'] = []
      ..gets['/api/PlatformBilling/market-preview'] = {'marketName': 'Nigeria', 'marketActive': true, 'preview': {'currencyCode': 'NGN', 'total': 90000}}
      ..gets['/api/PlatformBilling/explain'] = {'companyName': 'Test Farm', 'billingProfileName': 'Poultry layers', 'metricValue': 1200, 'tierName': 'Growth',
        'marketName': 'Ghana', 'monthlyAmount': 150, 'currencyCode': 'GHS', 'pricingStatus': 'Priced', 'evaluatedAtUtc': '2026-10-01T08:00:00Z'};
    await open(tester, BillingScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.textContaining('now qualifies for', findRichText: true), findsOneWidget);
    await see(tester, find.text('Pay this period'));
    final pay = tester.widget<FilledButton>(find.ancestor(of: find.text('Pay this period'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(pay.onPressed, isNull, reason: 'a company is not priced yet');
    expect(find.text('Checkout opens once pricing is configured for all your business types.'), findsOneWidget);

    await tap(tester, find.text('Switch to annual billing'));
    expect(jsonDecode(a.writes.last.body), {'userId': 'user-1', 'cycle': 'annual'});
    expect(a.writes.last.url.path, '/api/PlatformBilling/billing-cycle');

    await tap(tester, find.text('Change billing market'));
    expect(find.textContaining('Estimated new total', findRichText: true), findsOneWidget);
    await choose(tester, 'Nigeria — NGN', 'United States — USD', within: find.byType(AlertDialog));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Relocated');
    await tester.tap(find.text('Confirm request'));
    await tester.pumpAndSettle();
    expect(jsonDecode(a.writes.last.body), {'userId': 'user-1', 'marketCode': 'US', 'reason': 'Relocated'});

    await see(tester, find.text('Pricing pending'));
    await tester.tap(find.byTooltip('Why this price?').first);
    await tester.pumpAndSettle();
    expect(find.text('How this plan is calculated'), findsOneWidget);
    expect(find.text('Poultry layers'), findsOneWidget);
  });

  testWidgets('Account: profile, edit and save, 2FA', (tester) async {
    final a = FakeApi()
      ..gets['/api/Authentication/get-current-user'] = {'Id': 'user-1', 'UserName': 'ama@farm.com', 'Email': 'ama@farm.com', 'FarmName': 'Test Farm', 'FarmId': 'farm-1',
        'FirstName': 'Ama', 'LastName': 'Owusu', 'TwoFactorEnabled': false};
    await open(tester, AccountScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('Ama Owusu'), findsOneWidget);
    await tap(tester, find.text('Edit'));
    await tester.enterText(find.byType(TextField).first, 'Akosua');
    await tap(tester, find.text('Save'));
    final w = a.writes.firstWhere((w) => w.url.path == '/api/Authentication/update-profile');
    expect((w.method, (jsonDecode(w.body) as Map)['firstName']), ('PUT', 'Akosua'));
    expect(find.text('Profile Updated Successfully!'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await see(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '/api/Authentication/enable-2fa');
    expect(find.text('2FA Enabled!'), findsOneWidget);
  });

  testWidgets('Activity Log: filters, cards and View data', (tester) async {
    final a = FakeApi()
      ..gets['/api/AuditLogs'] = [
        {'id': '1', 'userName': 'ama', 'action': 'POST', 'resource': 'Sales', 'ipAddress': '10.0.0.1', 'details': 'Sale 4', 'status': 'Success',
          'timestamp': '2026-10-05T09:00:00Z', 'data': '{"total":50}'},
        {'id': '2', 'userName': 'kofi', 'action': 'DELETE', 'resource': 'Expenses', 'ipAddress': '10.0.0.2', 'status': 'Failed', 'timestamp': '2026-10-06T09:00:00Z'},
      ];
    await open(tester, ActivityLogScreen(session: await sessionFor(a), company: company), size: phone);
    expect(a.requests.first.url.queryParameters, {'page': '1', 'pageSize': '500', 'farmId': 'farm-1'});
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await choose(tester, 'All actions', 'Deleted', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Created'), findsNothing);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('View data'));
    expect(find.text('Audit log data'), findsOneWidget);
    expect(find.text('{\n  "total": 50\n}'), findsOneWidget);
  });

  testWidgets('Resources: tabs, add, edit and delete stay in the page', (tester) async {
    final a = FakeApi();
    await open(tester, ResourcesScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Newcastle Disease'), findsOneWidget);
    await tester.tap(find.text('Add Schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, 'Gumboro booster');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Schedule')));
    await tester.pumpAndSettle();
    expect(find.text('Gumboro booster'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to delete "Newcastle Disease"? This action cannot be undone.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Newcastle Disease'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('res-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('Starter Feed'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Feed Formulation'), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Formulation updated'), findsOneWidget);
    expect(a.requests, isEmpty, reason: 'nothing goes to the server, as on the web');
  });

  testWidgets('Help Center and Terms', (tester) async {
    final s = await sessionFor(FakeApi());
    await open(tester, HelpCenterScreen(session: s, company: company), size: phone);
    await see(tester, find.text('18 answers'));
    await see(tester, find.byKey(const ValueKey('faq-cat-Flocks')));
    await tester.tap(find.byKey(const ValueKey('faq-cat-Flocks')));
    await tester.pumpAndSettle();
    await see(tester, find.text('3 answers'));
    await see(tester, find.text('Collapse all'));
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('Expand all'), findsOneWidget);

    await open(tester, TermsScreen(session: s, company: company), size: phone);
    expect(find.text('Agreement Overview'), findsOneWidget);
    await see(tester, find.text('Updates to Terms'));
  });
}
