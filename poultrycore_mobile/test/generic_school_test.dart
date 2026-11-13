// Report 36 Part 3: Generic School pages (Classes, Academic Terms, Student
// Attendance) against a fake API at phone width, checked against the web.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/school/generic_school_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final school = Company(farmId: 'g1', name: 'Hill School', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

FakeApi api() => FakeApi()
  ..gets['$base/classes'] = [
    {'genericClassId': 1, 'className': 'Primary 1', 'classLevel': 1, 'classTeacher': 'Mrs Owusu', 'capacity': 30, 'studentCount': 2, 'isActive': true},
    {'genericClassId': 2, 'className': 'Old class', 'isActive': false, 'studentCount': 0},
  ]
  ..gets['$base/academic-terms'] = [
    {'genericAcademicTermId': 4, 'termName': 'Term 1 2026', 'startDate': '2026-09-07T00:00:00', 'endDate': '2026-12-18T00:00:00', 'isCurrent': true, 'isActive': true},
  ]
  ..gets['$base/customers'] = [
    {'genericCustomerId': 10, 'customerName': 'Kofi', 'admissionNumber': 'A-01', 'classOrGrade': 'Primary 1', 'isActive': true},
    {'genericCustomerId': 11, 'customerName': 'Esi', 'classOrGrade': 'Primary 2', 'isActive': true},
    {'genericCustomerId': 12, 'customerName': 'Left', 'isActive': false},
  ]
  ..gets['$base/customer-attendance'] = [
    {'genericCustomerAttendanceId': 1, 'genericCustomerId': 11, 'status': 'Late'},
  ];

void main() {
  tearDown(invalidateGenericModules);

  test('term checks and the class list fall-back, as the web', () {
    expect(checkTerm('', '2026-01-01', '2026-02-01'), 'Term name is required');
    expect(checkTerm('T1', '', '2026-02-01'), 'Start and end dates are required');
    expect(checkTerm('T1', '2026-02-01', '2026-02-01'), 'End date must be after start date');
    expect(checkTerm('T1', '2026-01-01', '2026-02-01'), isNull);
    expect(attendanceClassNames([], [{'classOrGrade': 'B'}, {'classOrGrade': 'A'}, {'classOrGrade': 'B'}, {}]), ['A', 'B']);
    expect(attendanceClassNames([{'className': 'P1'}], [{'classOrGrade': 'B'}]), ['P1']);
  });

  testWidgets('the School menu shows for School businesses only', (tester) async {
    final groups = webNavGroups['generic']!;
    expect(gateGenericCatalog(groups, school).where((g) => g.title == 'School'), isEmpty, reason: 'hidden while loading');
    final a = FakeApi()
      ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true}
      ..gets['$base/business-template'] = {'genericIndustryTemplate': 'School'};
    await tester.runAsync(() async => loadGenericModules(await sessionFor(a), school));
    expect(gateGenericCatalog(groups, school).where((g) => g.title == 'School'), hasLength(1));
    invalidateGenericModules();
    a.gets['$base/business-template'] = {'genericIndustryTemplate': 'Retail'};
    await tester.runAsync(() async => loadGenericModules(await sessionFor(a), school));
    expect(gateGenericCatalog(groups, school).where((g) => g.title == 'School'), isEmpty, reason: 'a shop has no School menu');
    final links = [for (final s in groups.firstWhere((g) => g.title == 'School').subGroups) for (final l in s.links) l.href];
    expect(links, ['/generic-classes', '/generic-terms', '/generic-student-attendance']);
    for (final h in links) {
      expect(pageScreens[h], isNotNull, reason: h);
    }
  });

  testWidgets('Classes: table, name required, the body sent', (tester) async {
    final a = api();
    await open(tester, GenericClassesScreen(session: await sessionFor(a), company: school), size: phone);
    expect(find.text('Primary 1'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('school-add')));
    await tester.pumpAndSettle();
    expect(find.text('Define a class or grade level for your school.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('class-save')));
    await tester.pumpAndSettle();
    expect(find.text('Class name is required'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('class-name')), ' JSS 2 ');
    await tester.enterText(find.byKey(const ValueKey('class-level')), '8');
    await tester.tap(find.byKey(const ValueKey('class-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/classes');
    expect(b, {'genericClassId': 0, 'className': 'JSS 2', 'classLevel': 8, 'classTeacher': null, 'capacity': null, 'description': null, 'isActive': true});
  });

  testWidgets('Terms: the current term line, and an end before the start is refused', (tester) async {
    final a = api();
    await open(tester, GenericTermsScreen(session: await sessionFor(a), company: school), size: phone);
    expect(find.textContaining('Sep 7, 2026 — Dec 18, 2026'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('edit-Term 1 2026')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-Term 1 2026')));
    await tester.pumpAndSettle();
    expect(find.text('Edit term'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('term-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/academic-terms');
    expect((b['genericAcademicTermId'], b['startDate'], b['endDate'], b['isCurrent']), (4, '2026-09-07', '2026-12-18', true));
  });

  testWidgets('Student Attendance: marks, class filter, All Present, one post each', (tester) async {
    final a = api();
    await open(tester, GenericStudentAttendanceScreen(session: await sessionFor(a), company: school), size: phone);
    expect(find.text('2 students'), findsOneWidget, reason: 'inactive students are left out');
    expect(find.text('1 marked'), findsOneWidget, reason: 'the saved Late mark is loaded');
    expect(find.text('A-01 · Primary 1'), findsOneWidget);
    expect(find.text('Save attendance (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mark-10-Absent')));
    await tester.pump();
    expect(find.text('1 absent'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('att-class')));
    await tester.pumpAndSettle();
    expect(find.text('Old class'), findsNothing, reason: 'inactive classes are left out');
    await tester.tap(find.text('Primary 1').last);
    await tester.pumpAndSettle();
    expect(find.text('1 students'), findsOneWidget);
    await tester.tap(find.text('All Present'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('att-save')));
    await tester.pumpAndSettle();
    expect(a.writes, hasLength(1), reason: 'only the students shown are saved');
    final b = a.lastBody('$base/customer-attendance');
    expect((b['genericCustomerId'], b['status'], b['genericClassId']), (10, 'Present', 1));
    expect(find.text('Attendance saved for 1 students'), findsOneWidget);
  });
}
