// Restaurant → System (2026-10-20): the menu as the web's sidebar systemItems,
// Users & Permissions → Add as staff on a Restaurant company, and Billing's
// companies grouped by business type.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/shared/billing_screen.dart';
import 'package:poultrycore_mobile/pages/shared/staff_employee_link.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final restaurant = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');

void main() {
  test('System menu: Account, My Account, Companies, Billing; the rest stay on the All pages sheet', () {
    final groups = webNavGroups['restaurant']!;
    final system = groups.firstWhere((g) => g.title == 'System');
    expect([for (final l in system.subGroups.single.links) l.label], ['Account', 'My Account', 'Companies', 'Billing']);
    final more = groups.firstWhere((g) => g.title == 'More pages');
    expect([for (final l in more.subGroups.single.links) l.label],
        ['Users & Permissions', 'Alerts', 'Activity Log', 'Terms & Conditions', 'QR Codes']);
    expect(staffPagePath(CompanyType.restaurant), '/restaurant-staff');
  });

  test('Billing groups companies by type, in the web order', () {
    final g = billingCompanyGroups([
      {'companyName': 'A', 'businessType': 'Restaurant'},
      {'companyName': 'B', 'businessType': 'Poultry'},
      {'companyName': 'C', 'companyFamily': 'Water', 'businessType': 'Sachet'},
      {'companyName': 'D'},
      {'companyName': 'E', 'businessType': 'Poultry'},
    ]);
    expect([for (final (f, rows) in g) '$f:${rows.length}'], ['Poultry:2', 'Water:1', 'Restaurant:1', 'Other:1']);
  });

  testWidgets('Users & Permissions → Add as staff on Restaurant opens New staff and links the row', (tester) async {
    final api = FakeApi()..writeAnswers['/api/Restaurant/staff'] = {'staffId': 12};
    final s = await sessionFor(api);
    final extra = staffLinkRecordExtras['admin-company-employees']!.single;
    final row = <String, dynamic>{'id': 'u-9', 'firstName': 'Efua', 'lastName': 'Mensah', 'phoneNumber': '055', '_staffPage': '/restaurant-staff'};
    await open(tester, Builder(builder: (_) => extra.builder(s, restaurant, row)), size: const Size(360, 3000));
    expect(find.text('Efua'), findsOneWidget);
    await tester.tap(find.text('Add Member'));
    await tester.pumpAndSettle();
    final staff = api.lastBody('/api/Restaurant/staff');
    expect((staff['firstName'], staff['lastName'], staff['phone'], staff['role']), ('Efua', 'Mensah', '055', 'Waiter'));
    final link = api.lastBody('/api/StaffUserLink', 'PUT');
    expect((link['staffId'], link['userId']), (12, 'u-9'));
  });
}
