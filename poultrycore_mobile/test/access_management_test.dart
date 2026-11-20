// Business Office → Administration → Access (iam-panel.tsx and its four
// views), driven at phone width against a FakeApi.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/screens/business_office/administration_screen.dart';

import 'support/harness.dart';

/// Phone width, tall enough that every section is built.
const tallPhone = Size(360, 3600);

const _companies = [
  {'farmId': 'p1', 'name': 'Sunrise Farm', 'type': 'Poultry', 'role': 'Admin', 'ownerUserId': 'user-1'},
  {'farmId': 'w1', 'name': 'Cool Spring Water', 'type': 'Water', 'role': 'Admin', 'ownerUserId': 'user-1'},
];

Map<String, Object?> _perm(String resource, String label, String action, {bool danger = false}) => {
      'permissionKey': 'poultry.$resource.$action', 'module': 'poultry', 'resource': resource, 'action': action,
      'permissionGroup': 'Flocks', 'resourceLabel': label, 'description': null, 'companyType': 'Poultry',
      'isDangerous': danger, 'sortOrder': 1,
    };

FakeApi iamApi() => FakeApi()
  ..gets['/api/Companies/mine'] = _companies
  ..gets['/api/Iam/status'] = {'enforced': false, 'denyUnmapped': false}
  ..gets['/api/Iam/catalog'] = [
    _perm('flocks', 'Flocks', 'view'),
    _perm('flocks', 'Flocks', 'create'),
    _perm('flocks', 'Flocks', 'delete', danger: true),
  ]
  ..gets['/api/Iam/roles'] = [
    {
      'roleId': 1, 'roleKey': 'sys-accountant', 'name': 'Accountant', 'description': 'Money pages', 'companyType': null,
      'isSystem': true, 'isSuperuser': false, 'isActive': true, 'permissionCount': 40, 'assignedUserCount': 2,
    },
    {
      'roleId': 9, 'roleKey': null, 'name': 'Feed Store Manager', 'description': null, 'companyType': 'Poultry',
      'isSystem': false, 'isSuperuser': false, 'isActive': true, 'permissionCount': 1, 'assignedUserCount': 0,
    },
  ]
  ..gets['/api/Iam/roles/9/permissions'] = ['poultry.flocks.view']
  ..gets['/api/Admin/organization/employees'] = [
    {'id': 'e1', 'firstName': 'Kofi', 'lastName': 'Asare', 'email': 'kofi@gf.test', 'userName': 'kofi'},
  ]
  ..gets['/api/Iam/user-roles'] = [
    {'id': 31, 'roleId': 1, 'name': 'Accountant', 'isSystem': true, 'isSuperuser': false, 'isOrgWide': true, 'assignedAt': '2026-10-01'},
  ]
  ..gets['/api/Iam/overrides'] = []
  ..gets['/api/Iam/effective-permissions'] = {
    'userId': 'e1',
    'grants': [
      {'permissionKey': 'poultry.flocks.view', 'source': 'role:Accountant'},
    ],
  }
  ..gets['/api/Iam/sessions'] = [
    {'sessionId': 's-1', 'userId': 'e1', 'device': 'Chrome on Windows', 'ipAddress': '10.0.0.4', 'createdAt': '2026-10-20T08:00:00Z',
      'lastSeenAt': '2026-10-25T08:00:00Z', 'isActive': true},
  ]
  ..gets['/api/Iam/policy'] = {
    'ownerUserId': 'user-1', 'passwordMinLength': 8, 'passwordRequireUpper': false, 'passwordRequireDigit': true,
    'passwordRequireSymbol': false, 'passwordExpiryDays': 0, 'sessionIdleMinutes': 0, 'sessionMaxHours': 0,
    'requireMfaForAdmins': false, 'dormantAfterDays': 90, 'accessReviewDays': 180, 'updatedAt': '2026-10-01',
  }
  ..gets['/api/Iam/access-review'] = [
    {'userId': 'e1', 'firstName': 'Kofi', 'lastName': 'Asare', 'email': 'kofi@gf.test', 'roleCount': 1, 'overrideCount': 0,
      'lastSeenAt': null, 'lastReviewedAt': null, 'lastDecision': null, 'isDormant': true, 'reviewIsStale': true},
  ]
  ..gets['/api/Iam/access-audit'] = [
    {'id': 1, 'occurredAt': '2026-10-24T10:00:00Z', 'entity': 'UserRole', 'operation': 'Insert',
      'detail': 'Assigned Accountant', 'subjectName': 'Kofi Asare', 'actorName': 'Ama Mensah'},
  ];

Future<FakeApi> openAccess(WidgetTester tester, [FakeApi? given]) async {
  final api = given ?? iamApi();
  final s = await sessionFor(api);
  await s.loadCompanies();
  await open(tester, AdministrationScreen(session: s, initialTab: 'iam'), size: tallPhone);
  return api;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Access tab sits between Employees and Companies; banner and scope picker', (tester) async {
    await openAccess(tester);
    expect(find.text('Access'), findsWidgets);
    expect(find.text('Roles, what each one can do, and who holds them.'), findsOneWidget);
    expect(find.text('All companies'), findsOneWidget);
    expect(find.textContaining('to what someone can already do'), findsOneWidget);
    for (final t in ['Roles', 'Permission Matrix', 'People', 'Security']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('no catalog: says the database is not set up', (tester) async {
    await openAccess(tester, iamApi()..statuses['/api/Iam/catalog'] = 404);
    expect(find.text('Access management is not set up on this database yet'), findsOneWidget);
  });

  testWidgets('Roles: cards, New role, Duplicate copies, Delete', (tester) async {
    final api = await openAccess(tester);
    expect(find.text('Accountant'), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('40 permissions'), findsOneWidget);
    expect(find.text('Poultry only'), findsOneWidget);
    // Built-ins cannot be renamed or deleted.
    expect(find.byTooltip('Delete role'), findsOneWidget);

    await tapText(tester, 'New role');
    await enter(tester, 'Name', 'Egg Collector');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Iam/roles')['name'], 'Egg Collector');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Duplicate').first);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate role'), findsOneWidget);
    expect(find.text('Accountant (copy)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Iam/roles')['copyFromRoleId'], 1);

    await tester.tap(find.byTooltip('Delete role'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Iam/roles/9'), isTrue);
  });

  testWidgets('Matrix: built-in is read-only; a custom role toggles and saves the whole set', (tester) async {
    final api = await openAccess(tester);
    await tapText(tester, 'Permission Matrix');
    expect(find.textContaining('Built-in role — duplicate it'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);

    await pick(tester, 'Accountant', 'Feed Store Manager');
    expect(find.text('GRANT ON EVERYTHING VISIBLE'), findsOneWidget);
    expect(find.text('Approve ·'), findsOneWidget); // not applicable
    await tester.tap(find.byKey(const ValueKey('iam-poultry.flocks.create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final put = api.writes.lastWhere((w) => w.method == 'PUT' && w.url.path == '/api/Iam/roles/9/permissions');
    expect((jsonDecode(put.body)['permissionKeys'] as List).toSet(), {'poultry.flocks.view', 'poultry.flocks.create'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('People: roles, assign, exception with reason, sessions, effective', (tester) async {
    final api = await openAccess(tester);
    await tapText(tester, 'People');
    expect(find.text('Choose someone to see and change what they can do'), findsOneWidget);
    await tapText(tester, 'Kofi Asare');
    expect(find.text('Roles across all companies'), findsOneWidget);
    expect(find.text('All companies'), findsWidgets);
    expect(find.text('Chrome on Windows'), findsOneWidget);
    expect(find.text('Flocks: View'), findsOneWidget);

    await tapText(tester, 'Assign role');
    await pick(tester, 'Choose a role', 'Feed Store Manager');
    await pick(tester, 'Every company in the organization', 'Sunrise Farm only');
    await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Iam/assignments'), {'userId': 'e1', 'roleId': 9, 'farmId': 'p1', 'expiresAt': null});

    await tapText(tester, 'Add exception');
    await tester.tap(find.text('Poultry · poultry.flocks.delete'));
    await tester.pumpAndSettle();
    await pick(tester, 'Select a reason', 'Temporary access');
    await tester.tap(find.widgetWithText(FilledButton, 'Save exception'));
    await tester.pumpAndSettle();
    final o = api.lastBody('/api/Iam/overrides');
    expect((o['permissionKey'], o['effect'], o['reason']), ('poultry.flocks.delete', 'Allow', 'Temporary access'));

    await tapText(tester, 'Sign out everywhere');
    expect(api.lastBody('/api/Iam/sessions/revoke-all'), {'userId': 'e1'});
    await tester.tap(find.byTooltip('Remove Accountant'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Iam/assignments/31'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Security: review, policy save, change history', (tester) async {
    final api = await openAccess(tester);
    await tapText(tester, 'Security');
    expect(find.text('Dormant'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    await tapText(tester, 'Still needed');
    expect(api.lastBody('/api/Iam/access-review'), {'userId': 'e1', 'decision': 'Confirmed'});

    await tapText(tester, 'Policy');
    expect(find.text('Save policy'), findsNothing);
    await enter(tester, 'Minimum length', '10');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save policy');
    expect(api.lastBody('/api/Iam/policy', 'PUT')['passwordMinLength'], 10);

    await tapText(tester, 'Change History');
    expect(find.text('Assigned Accountant'), findsOneWidget);
    expect(find.text('Insert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
