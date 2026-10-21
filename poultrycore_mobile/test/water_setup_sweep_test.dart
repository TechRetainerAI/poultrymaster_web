// Water Setup sweep (2026-10-20): what the web changed after the app's 8 Oct
// pass, plus Financial Settings' permission gate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/shared/setup_admin_routes.dart';
import 'package:poultrycore_mobile/pages/shared/staff_employee_link.dart';
import 'package:poultrycore_mobile/pages/water/water_financial_settings_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final waterStaffUser = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water, role: 'Staff');
final waterAdmin = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water, role: 'Admin');

List<String> hrefs(List<NavGroup> groups) => [
      for (final g in groups)
        for (final s in g.subGroups)
          for (final l in s.links) l.href,
    ];

void main() {
  setUp(LookupLoader.clear);

  test('Setup pages are admin-only; Staff and Users & Permissions keep their own gate', () {
    final all = webNavGroups['water']!;
    expect(isSetupAdminRoute('/water-products/12'), isTrue);
    expect(isSetupAdminRoute('/water-staff'), isFalse);
    final staffMenu = hrefs(gateSetupLinks(all, waterStaffUser));
    for (final r in ['/water-setup', '/water-company-setup', '/water-financial-settings', '/water-drivers', '/water-products', '/water-customers', '/water-machines']) {
      expect(staffMenu, isNot(contains(r)), reason: r);
    }
    expect(staffMenu, containsAll(['/water-staff', '/employees', '/companies', '/water-sales']));
    expect(hrefs(gateSetupLinks(all, waterAdmin)), hrefs(all));
  });

  test('Staff pages keep their own buttons beside Make employee', () {
    expect([for (final x in recordExtras['poultry-staff']!) x.label], ['Attendance', 'Make employee']);
    expect([for (final x in recordExtras['water-staff']!) x.label], ['Make employee']);
    expect(staffPagePath(CompanyType.water), '/water-staff');
  });

  testWidgets('Financial Settings without the view key is a locked card', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/financial-settings/cost-recognition'] = {'deferralAvailable': false}
      ..gets['/api/Water/financial-settings/items'] = [];
    await open(tester, WaterFinancialSettingsScreen(session: await sessionFor(api), company: waterStaffUser), size: phone);
    expect(find.text('You do not have access to financial settings.'), findsOneWidget);
  });

  testWidgets('Employees → Add as staff on Water opens the Water staff form and links the new row', (tester) async {
    final api = FakeApi()..writeAnswers['/api/Water/staff'] = {'waterStaffId': 4};
    final s = await sessionFor(api);
    final extra = staffLinkRecordExtras['admin-company-employees']!.single;
    final row = <String, dynamic>{'id': 'u-7', 'firstName': 'Abena', 'lastName': 'Owusu', 'phoneNumber': '024', '_staffPage': '/water-staff'};
    await open(tester, Builder(builder: (_) => extra.builder(s, waterAdmin, row)), size: const Size(360, 3000));
    expect(find.text('Abena'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final staff = api.lastBody('/api/Water/staff');
    expect((staff['firstName'], staff['lastName'], staff['phoneNumber']), ('Abena', 'Owusu', '024'));
    final link = api.lastBody('/api/StaffUserLink', 'PUT');
    expect((link['staffId'], link['userId']), (4, 'u-7'));
  });
}
