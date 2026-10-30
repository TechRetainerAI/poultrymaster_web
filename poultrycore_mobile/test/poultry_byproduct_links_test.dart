// Error.txt item 14: Inventory links to the byproduct trackers, the Byproduct
// Inventory & Disposition report, and the Staff <-> Employee link (362).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/list_screen.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/inventory_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_defs.dart';
import 'package:poultrycore_mobile/pages/registry.dart';
import 'package:poultrycore_mobile/pages/shared/staff_employee_link.dart';

import 'support/harness.dart';

void main() {
  setUp(LookupLoader.clear);

  test('byproducts link to their own trackers; the report is defined', () {
    expect(productLink({'poultryProductId': 7, 'name': 'Broken Eggs', 'isRawEggProduct': true}).href, '/broken-eggs-tracker');
    expect(productLink({'poultryProductId': 8, 'name': 'Dead Birds (system)', 'isBirdProduct': true}).label, 'Dead Birds Tracker');
    final def = poultryReportDefs['byproduct-inventory']!;
    expect((def.title, def.filters.flock, def.filters.category, def.columns.length), ('Byproduct Inventory & Disposition', true, true, 14));
    expect(suggestUserName(const EmployeePrefill(firstName: 'Ama ', lastName: "O'Neil")), 'ama_oneil');
  });

  testWidgets('Staff: linked rows carry the Employee badge', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/staff'] = [
        {'poultryStaffId': 1, 'firstName': 'Kofi', 'lastName': 'Mensah', 'role': 'FarmHand', 'isActive': true},
        {'poultryStaffId': 2, 'firstName': 'Esi', 'lastName': 'Boateng', 'role': 'Cleaner', 'isActive': true},
      ]
      ..gets['/api/StaffUserLink'] = [
        {'staffId': 1, 'userId': 'u-1'},
      ];
    final s = await sessionFor(api);
    await open(tester, ListScreen(spec: PageRegistry.of('poultry-staff')!, session: s, company: company), size: phone);
    expect(find.text('Employee'), findsOneWidget);
  });

  testWidgets('Employees: Add as staff opens New staff prefilled and links the new row', (tester) async {
    final api = FakeApi()..writeAnswers['/api/Poultry/staff'] = {'poultryStaffId': 9};
    final s = await sessionFor(api);
    final extra = staffLinkRecordExtras['admin-company-employees']!.single;
    final row = <String, dynamic>{'id': 'u-5', 'firstName': 'Yaw', 'lastName': 'Asare', '_staffPage': '/poultry-staff'};
    expect(extra.when!(row), isTrue);
    expect(extra.when!({...row, '_isStaff': true}), isFalse);
    await open(tester, Builder(builder: (_) => extra.builder(s, company, row)), size: const Size(360, 3000));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((api.lastBody('/api/Poultry/staff')['firstName'], api.lastBody('/api/Poultry/staff')['lastName']), ('Yaw', 'Asare'));
    final link = api.lastBody('/api/StaffUserLink', 'PUT');
    expect((link['staffId'], link['userId']), (9, 'u-5'));
  });
}
