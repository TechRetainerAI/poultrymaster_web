// The Business Office (app/business-office/page.tsx inside the
// business-office-shell): what an admin and a staff member see, every button,
// and Administration's three tabs -- at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/screens/business_office/administration_screen.dart';
import 'package:poultrycore_mobile/screens/business_office_screen.dart';
import 'package:poultrycore_mobile/state/session.dart';

import 'support/harness.dart';

/// Tall, so the whole page is built and its sections can be read at once.
const tall = Size(390, 4200);

const _companies = [
  {'farmId': 'p1', 'name': 'Sunrise Farm', 'type': 'Poultry', 'role': 'Admin', 'ownerUserId': 'user-1', 'createdAt': '2026-01-01T00:00:00'},
  {'farmId': 'w1', 'name': 'Cool Spring Water', 'type': 'Water', 'role': 'Admin', 'ownerUserId': 'user-1', 'createdAt': '2026-02-01T00:00:00'},
];

FakeApi boApi({List companies = _companies}) => FakeApi()
  ..gets['/api/Companies/mine'] = companies
  ..gets['/api/Admin/organization/profile'] = {
    'businessOfficeName': 'Great Favour Holdings', 'businessOfficeCurrency': 'GHS', 'organizationCode': 'GFH24',
    'firstName': 'Ama', 'lastName': 'Mensah', 'email': 'ama@gf.test', 'phoneNumber': '0244', 'businessOfficeCountry': 'Ghana',
  }
  ..gets['/api/BusinessOffice/company-snapshot'] = {'metric1': 1200, 'metric2': 850.4, 'metric3': 2, 'metric4': 3450}
  ..gets['/api/Announcements'] = [
    {
      'announcementId': 7, 'title': 'Subscription renewal due', 'message': 'Renew before the 30th.', 'type': 'Payment',
      'isDismissible': true, 'requiresAck': true, 'orgOwnerUserId': 'user-1',
    },
  ]
  ..gets['/api/Poultry/lifecycle/tasks'] = [
    {
      'flockId': 4, 'flockName': 'Pen 1', 'batchCode': 'B3', 'milestoneId': 2, 'title': 'Move to layer house',
      'status': 'Overdue', 'daysUntilDue': -2, 'dueDate': '2026-10-20', 'ageUnit': 'Week', 'ageValue': 16, 'isEstimated': false,
    },
  ];

Future<(Session, List<bool>)> openOffice(WidgetTester tester, FakeApi api) async {
  final s = await sessionFor(api);
  await s.loadCompanies();
  final picked = <bool>[];
  await open(tester, BusinessOfficeScreen(session: s, onPicked: () => picked.add(true), onSignedOut: () {}), size: tall);
  return (s, picked);
}

void main() {
  testWidgets('admin: header, announcements, tiles, cards with today\'s numbers, Show currency, Open', (tester) async {
    final api = boApi();
    final (s, picked) = await openOffice(tester, api);

    expect(find.text('Welcome'), findsOneWidget, reason: 'no username stored in the fake session');
    expect(find.text('Select a company…'), findsOneWidget);
    expect(find.text('VISIBILITYCORE ANNOUNCEMENTS'), findsOneWidget);
    expect(find.text('Subscription renewal due'), findsOneWidget);
    expect(find.text('Action needed'), findsOneWidget);

    // Tiles: 2 companies, one Water, one Poultry.
    expect(find.text('Companies'), findsOneWidget);
    expect(find.text('Your companies'), findsOneWidget);

    // Cards: Poultry's four numbers; the money is bare until Show currency.
    expect(find.text('Eggs today'), findsOneWidget);
    expect(find.text('1,200'), findsWidgets);
    expect(find.text('850 kg'), findsOneWidget);
    expect(find.text('3,450'), findsWidgets);
    expect(find.text('GH₵ 3,450'), findsNothing);
    await tester.tap(find.text('Show currency'));
    await tester.pumpAndSettle();
    expect(find.text('GH₵ 3,450'), findsWidgets);
    expect(find.text('Hide currency'), findsOneWidget);

    // Acknowledge posts the receipt.
    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();
    final ack = api.writes.lastWhere((w) => w.url.path == '/api/Announcements/7/receipt');
    expect(ack.url.queryParameters['action'], 'Ack');
    expect(find.text('Acknowledged'), findsOneWidget);

    // Dismiss removes it.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Subscription renewal due'), findsNothing);
    expect(find.text('No new notifications.'), findsOneWidget);

    // Open on the Water card switches into it.
    final open = find.widgetWithText(FilledButton, 'Open');
    await tester.tap(open.last);
    // The card shows Opening… until the shell takes over; it never settles here.
    await tester.pump(const Duration(milliseconds: 500));
    expect(jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Companies/switch').body)['farmId'], 'w1');
    expect(picked, [true]);
    expect(s.active?.farmId, 'w1');
  });

  testWidgets('type filter and search narrow the cards', (tester) async {
    await openOffice(tester, boApi());
    await tester.enterText(find.byType(TextField).first, 'sunrise');
    await tester.pumpAndSettle();
    expect(find.text('Production today'), findsNothing, reason: "Water's card is filtered out");
    expect(find.text('Eggs today'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await pick(tester, 'All types', 'Water');
    expect(find.text('Production today'), findsOneWidget);
    expect(find.text('Eggs today'), findsNothing);
  });

  testWidgets('My Tasks lists the poultry reminders; Open switches in and asks for Flock Lifecycle', (tester) async {
    final api = boApi();
    final (s, picked) = await openOffice(tester, api);
    expect(find.text('My Tasks'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('Move to layer house'), findsOneWidget);
    expect(find.text('B3 (Pen 1) passed Week 16 · 2 days overdue'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Companies/switch').body)['farmId'], 'p1');
    expect(picked, [true]);
    expect(s.takePendingScreen(), isNotNull, reason: 'the shell opens Flock Lifecycle on arrival');
  });

  testWidgets('Create company: the dialog posts the company and emails the confirmation', (tester) async {
    final api = boApi()..writeAnswers['/api/Companies'] = {'farmId': 'n1', 'name': 'Hilltop Water'};
    await openOffice(tester, api);
    await tester.tap(find.text('Create company'));
    await tester.pumpAndSettle();
    expect(find.text('Create new company'), findsOneWidget);
    expect(find.textContaining('Created under'), findsOneWidget);
    await enter(tester, 'Company name *', 'Hilltop Water');
    await enter(tester, 'Contact email', 'hello@hilltop.test');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    final body = api.lastBody('/api/Companies');
    expect((body['Name'], body['Type'], body['Email']), ('Hilltop Water', 'Water', 'hello@hilltop.test'));
    expect(api.lastBody('/api/Email/send-welcome')['CompanyName'], 'Hilltop Water');
    expect(find.text('Created Hilltop Water'), findsOneWidget);
  });

  testWidgets('Post an announcement', (tester) async {
    final api = boApi();
    await openOffice(tester, api);
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text('Post an announcement'), findsOneWidget);
    await enter(tester, 'Title *', 'Stock count Friday');
    await pick(tester, 'Info', 'Warning');
    await tester.tap(find.widgetWithText(FilledButton, 'Post announcement'));
    await tester.pumpAndSettle();
    final body = api.lastBody('/api/Announcements');
    expect((body['title'], body['type'], body['audienceRole'], body['orgOwnerUserId']), ('Stock count Friday', 'Warning', 'All', 'user-1'));
    expect(find.text('Announcement posted'), findsOneWidget);
  });

  testWidgets('the sidebar: companies, New company, Administration, Billing, Logout', (tester) async {
    await openOffice(tester, boApi());
    await tester.tap(find.byTooltip('Open navigation menu').evaluate().isNotEmpty ? find.byTooltip('Open navigation menu') : find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('VisibilityCore'), findsOneWidget);
    expect(find.text('Sunrise Farm'), findsWidgets);
    expect(find.text('New company'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    await tester.tap(find.text('Administration'));
    await tester.pumpAndSettle();
    expect(find.byType(AdministrationScreen), findsOneWidget);
  });

  testWidgets('staff: no Post, no Access, no Manage users, no Administration', (tester) async {
    final staff = [
      for (final c in _companies) {...c, 'role': 'Staff', 'ownerUserId': 'someone-else'},
    ];
    await openOffice(tester, boApi(companies: staff));
    expect(find.text('Post'), findsNothing);
    expect(find.text('Access'), findsNothing);
    expect(find.text('Manage users'), findsNothing);
    expect(find.text('Create company'), findsNothing);
    expect(find.text("Today's sales"), findsNothing, reason: 'money tiles are admin-only');
    expect(find.text('All companies'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Administration'), findsNothing);
    expect(find.text('New company'), findsNothing);
  });

  group('Administration', () {
    testWidgets('Organization: the code, the profile and its save', (tester) async {
      final api = boApi();
      final s = await sessionFor(api);
      await s.loadCompanies();
      await open(tester, AdministrationScreen(session: s), size: tall);
      expect(find.text('GFH24'), findsOneWidget);
      expect(find.text('GH₵ — Ghana Cedi (GHS)'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final body = jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Admin/organization/profile').body);
      expect((body['businessOfficeName'], body['businessOfficeCurrency'], body['businessOfficeCountry']), ('Great Favour Holdings', 'GHS', 'Ghana'));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'gfh25');
      await tester.tap(find.text('Save new code'));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Admin/organization/code')['Code'], 'GFH25');
    });

    testWidgets('Employees: the org-wide list; Access grants a company at once', (tester) async {
      final api = boApi()
        ..gets['/api/Admin/organization/employees'] = [
          {
            'id': 'e1', 'firstName': 'Kofi', 'lastName': 'Asare', 'email': 'kofi@gf.test', 'userName': 'kofi', 'isAdmin': false,
            'companies': [
              {'farmId': 'p1', 'name': 'Sunrise Farm', 'type': 'Poultry', 'role': 'Staff'},
            ],
          },
        ];
      final s = await sessionFor(api);
      await s.loadCompanies();
      await open(tester, AdministrationScreen(session: s, initialTab: 'users'), size: tall);
      expect(find.text('Kofi Asare'), findsOneWidget);
      expect(find.text('1 company'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Access'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Manage access'), findsOneWidget);
      await tester.tap(find.text('Cool Spring Water'));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Admin/employees/e1/company-access'), {'FarmId': 'w1', 'Role': 'Staff'});
    });

    testWidgets('Companies: cards, Edit saves name/email/phone', (tester) async {
      final api = boApi();
      final s = await sessionFor(api);
      await s.loadCompanies();
      await open(tester, AdministrationScreen(session: s, initialTab: 'companies'), size: tall);
      expect(find.text('Sunrise Farm'), findsOneWidget);
      expect(find.text('New company'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit company').first);
      await tester.pumpAndSettle();
      expect(find.text("Company type can't be changed after creation."), findsOneWidget);
      await enter(tester, 'Company name *', 'Sunrise Poultry');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Companies/p1', 'PUT')['Name'], 'Sunrise Poultry');
    });
  });
}
