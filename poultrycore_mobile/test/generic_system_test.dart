// Generic's System menu at phone width. On the web Generic has no nav config:
// its System block is sidebar.tsx's shared systemItems list (Users &
// Permissions, Account, Alerts, Companies, Billing, Activity Log, Terms). The
// pages are shared, so Generic opens the same native screens as the others;
// what is Generic's own is the Employees "Add as staff" link to /generic-staff.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/list_screen.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/registry.dart';
import 'package:poultrycore_mobile/pages/shared/account_screen.dart';
import 'package:poultrycore_mobile/pages/shared/activity_log_screen.dart';
import 'package:poultrycore_mobile/pages/shared/billing_screen.dart';
import 'package:poultrycore_mobile/pages/shared/companies_screen.dart';
import 'package:poultrycore_mobile/pages/shared/staff_employee_link.dart';
import 'package:poultrycore_mobile/pages/shared/terms_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/all_pages_sheet.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Gym', type: CompanyType.generic, role: 'Admin');

const _rows = ['Users & Permissions', 'Account', 'Alerts', 'Companies', 'Billing', 'Activity Log', 'Terms & Conditions'];

FakeApi _api() => FakeApi()
  ..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []}
  ..gets['/api/AuditLogs'] = []
  ..gets['/api/Admin/company-employees'] = []
  ..gets['/api/StaffUserLink'] = []
  ..gets['/api/Authentication/get-current-user'] = {
    'Id': 'user-1', 'UserName': 'kofi@gym.test', 'Email': 'kofi@gym.test', 'FarmName': 'Kofi Gym', 'FarmId': 'g1',
    'FirstName': 'Kofi', 'LastName': 'Asante', 'TwoFactorEnabled': false,
  }
  ..gets['/api/Companies/mine'] = [
    {'farmId': 'g1', 'name': 'Kofi Gym', 'type': 'Generic', 'role': 'Admin', 'ownerUserId': 'user-1', 'createdAt': '2026-09-01T00:00:00'},
  ]
  ..gets['/api/PlatformBilling/summary'] = {
    'pendingTierChanges': [],
    'account': {'marketCode': 'GH', 'currencyCode': 'GHS', 'status': 'Active', 'billingCycle': 'monthly', 'cancelAtPeriodEnd': false},
    'companies': [
      {'farmId': 'g1', 'companyName': 'Kofi Gym', 'businessType': 'Generic', 'metricType': 'Members', 'metricValue': 80, 'tierName': 'Starter',
        'monthlyAmount': 150, 'currencyCode': 'GHS', 'pricingStatus': 'Priced', 'participationStatus': 'Active'},
    ],
    'preview': {'subtotal': 150, 'eligibleCompanyCount': 1, 'discountPercent': 0, 'discountAmount': 0, 'taxAmount': 0, 'total': 150,
      'currencyCode': 'GHS', 'hasUnpricedCompanies': false, 'periodStart': '2026-10-01T00:00:00Z', 'periodEnd': '2026-10-31T00:00:00Z'},
  }
  ..gets['/api/PlatformBilling/invoices'] = []
  ..gets['/api/PlatformBilling/payments'] = [];

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<Session> _session([FakeApi? api]) async {
  final s = await sessionFor(api ?? _api());
  await s.loadCompanies();
  return s;
}

Future<void> _openSystem(WidgetTester tester, Session s) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showAllPages(context, s, generic),
      child: const Text('menu'),
    )))),
    size: phone,
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('SYSTEM'));
}

void main() {
  setUp(LookupLoader.clear);

  test('System is the web systemItems list, in order; the old rows moved out', () {
    final groups = webNavGroups['generic']!;
    final system = groups.firstWhere((g) => g.title == 'System');
    expect([for (final l in system.subGroups.single.links) l.label], _rows);
    final more = groups.firstWhere((g) => g.title == 'More pages');
    expect(more.subGroups.single.links.map((l) => l.href), contains('/generic-stock-adjustments'));
    expect(staffPagePath(CompanyType.generic), '/generic-staff');
  });

  testWidgets('More sheet: SYSTEM shows every row', (tester) async {
    await _openSystem(tester, await _session());
    for (final r in _rows) {
      expect(find.text(r), findsWidgets, reason: r);
    }
  });

  testWidgets('Alerts opens the alerts dialog, not a page', (tester) async {
    await _openSystem(tester, await _session());
    await _tap(tester, find.text('Alerts').last);
    expect(find.text('System Alerts and Notifications'), findsOneWidget);
  });

  for (final (row, screen) in [
    ('Account', AccountScreen),
    ('Companies', CompaniesScreen),
    ('Billing', BillingScreen),
    ('Activity Log', ActivityLogScreen),
    ('Terms & Conditions', TermsScreen),
  ]) {
    testWidgets('$row opens its own screen', (tester) async {
      await _openSystem(tester, await _session());
      await _tap(tester, find.text(row).last);
      expect(find.byType(screen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Users & Permissions opens the employees list', (tester) async {
    await _openSystem(tester, await _session());
    await _tap(tester, find.text('Users & Permissions').last);
    expect(find.byType(ListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employees: Add as staff opens New staff member prefilled and links it', (tester) async {
    final api = _api()..writeAnswers['/api/generic-company/g1/staff'] = {'genericStaffId': 4};
    final s = await _session(api);
    final extra = staffLinkRecordExtras['admin-company-employees']!.single;
    final row = <String, dynamic>{'id': 'u-7', 'firstName': 'Abena', 'lastName': 'Mensah', '_staffPage': '/generic-staff'};
    expect(extra.when!(row), isTrue);
    await open(tester, Builder(builder: (_) => extra.builder(s, generic, row)), size: const Size(360, 3000));
    expect(find.text('New staff member'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = api.lastBody('/api/generic-company/g1/staff');
    expect((body['firstName'], body['lastName'], body['role'], body['salaryType']), ('Abena', 'Mensah', 'Other', 'Monthly'));
    final link = api.lastBody('/api/StaffUserLink', 'PUT');
    expect((link['staffId'], link['userId']), (4, 'u-7'));
  });

  testWidgets('Generic Staff: linked rows carry the Employee badge', (tester) async {
    final api = _api()
      ..gets['/api/generic-company/g1/staff'] = [
        {'genericStaffId': 4, 'firstName': 'Abena', 'lastName': 'Mensah', 'role': 'Cashier', 'isActive': true},
        {'genericStaffId': 5, 'firstName': 'Yaw', 'lastName': 'Boateng', 'role': 'Cleaner', 'isActive': true},
      ]
      ..gets['/api/StaffUserLink'] = [{'staffId': 4, 'userId': 'u-7'}];
    final s = await _session(api);
    await open(tester, ListScreen(spec: PageRegistry.of('generic-staff')!, session: s, company: generic), size: phone);
    expect(find.text('Employee'), findsOneWidget);
  });
}
