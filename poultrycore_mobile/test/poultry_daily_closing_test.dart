// Poultry → Tools → Daily Closing, driven against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/daily_closing_screen.dart';

import 'support/harness.dart';

Map<String, dynamic> workspace(String date, {int blocking = 0, num revenue = 500, num eggs = 1200}) => {
      'farmId': 'farm-1', 'businessDate': '${date}T00:00:00', 'companyToday': '2026-10-02',
      'companyLocalTime': '2026-10-02T14:00:00', 'timeZoneId': 'Africa/Accra',
      'production': {
        'expectedFlocks': 3, 'reportedFlocks': 2, 'missingFlocks': 1, 'records': 2, 'eggsProduced': eggs,
        'eggsDamaged': 10, 'mortality': 2, 'feedKg': 85.5, 'awaitingPosting': 0, 'duplicateFlocks': 0,
      },
      'sales': {
        'count': 2, 'revenue': revenue, 'cashSales': 300, 'creditSales': 200, 'paymentsReceived': 50,
        'paymentsCount': 1, 'receivablesChange': 150,
      },
      'cash': {'moneyIn': 350, 'moneyOut': 100, 'netCashFlow': 250, 'reconciliations': 0},
      'expenses': {'count': 1, 'total': 100, 'cash': 100, 'credit': 0, 'nonCash': 0},
      'inventory': {
        'lowFeed': [
          {'itemId': 1, 'item': 'Layer Mash', 'quantity': 40, 'unit': 'kg', 'dailyUse': 20, 'daysRemaining': 2},
        ],
        'lowStock': [],
        'negativeStock': [],
      },
      'outstanding': {
        'unpostedBatches': 0, 'draftDriverReturns': 0, 'loadingsWithoutReturn': 0, 'previousDayClosed': false,
      },
      'checklist': [
        if (blocking > 0)
          {
            'key': 'missing', 'section': 'production', 'status': 'Blocking', 'title': '1 flock has no production',
            'description': 'Flock A', 'action': 'missing-production',
          },
        {
          'key': 'prev', 'section': 'outstanding', 'status': 'Warning', 'title': 'Previous day is not closed',
          'description': null, 'action': 'previous-day',
        },
        {
          'key': 'cash', 'section': 'cash', 'status': 'Complete', 'title': 'Cash recorded', 'description': null,
          'action': 'cash-count',
        },
      ],
      'counts': {'blocking': blocking, 'warning': 1, 'complete': 1},
    };

FakeApi closingApi({Map<String, dynamic>? day, bool enforced = false, List<String> grants = const []}) => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-02T00:00:00',
    'companyLocalDateTime': '2026-10-02T14:00:00',
    'utcNow': '2026-10-02T14:00:00Z',
  }
  ..gets['/api/Iam/status'] = {'enforced': enforced}
  ..gets['/api/Iam/effective-permissions'] = {
    'grants': [for (final g in grants) {'permissionKey': g}],
  }
  ..gets['/api/Poultry/daily-closings/day'] = day ??
      {'businessDate': '2026-10-02', 'closing': null, 'live': workspace('2026-10-02'), 'atClose': null, 'history': []};

/// The Day tab's vertical list (the tab view itself scrolls sideways).
final _dayList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

void main() {
  setUp(LookupLoader.clear);

  testWidgets('an open day: sections, checklist, close with warnings and notes', (tester) async {
    final api = closingApi();
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany), size: phone);

    expect(find.text('Not closed'), findsNWidgets(2), reason: 'the day, and the Previous day tile');
    expect(find.text('0 blocking · 1 warning · 1 complete'), findsOneWidget);
    expect(find.text('2 / 3 expected'), findsOneWidget);
    expect(find.text('GHC 500.00'), findsOneWidget);
    expect(find.text('+GHC 150.00'), findsOneWidget, reason: 'customer balances grew');
    expect(find.text('Layer Mash: about 2 days remaining (40 kg at 20/day)'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget, reason: 'warnings link; complete checks do not');
    expect(find.text('Policy'), findsOneWidget, reason: 'an admin holds the close right');
    expect(find.text('Submit for approval'), findsNothing);

    await tester.tap(find.text('Close Business Day'));
    await tester.pumpAndSettle();
    expect(find.text('Close October 2, 2026?'), findsOneWidget);
    expect(find.text('Closing with 1 warning'), findsOneWidget);
    expect(find.text('• Previous day is not closed'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'Feed ordered');
    await tester.tap(find.widgetWithText(FilledButton, 'Close Business Day').last);
    await tester.pumpAndSettle();

    expect(api.lastBody('/api/Poultry/daily-closings/close'),
        {'farmId': 'farm-1', 'businessDate': '2026-10-02', 'notes': 'Feed ordered'});
    expect(find.text('October 2, 2026 closed'), findsOneWidget);
  });

  testWidgets('a blocker disables Close; Review on "previous day" opens that day here', (tester) async {
    final api = closingApi(day: {
      'closing': null, 'live': workspace('2026-10-02', blocking: 1), 'atClose': null, 'history': [],
    });
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany));
    expect(find.text('1 blocking check must be resolved first.'), findsOneWidget);
    final close = find.widgetWithText(FilledButton, 'Close Business Day');
    expect(tester.widget<FilledButton>(close).onPressed, isNull);
    expect(find.text('Resolve'), findsOneWidget);
    expect(closingActionHref('missing-production', '2026-10-02'), '/poultry-farm-completeness?date=2026-10-02');
    expect(closingActionHref('previous-day', '2026-10-01'), '/poultry-daily-closing?date=2026-09-30');
    expect(closingActionHref('mystery', '2026-10-01'), isNull);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(api.requests.last.url.queryParameters['businessDate'], '2026-10-01');
  });

  testWidgets('without the close right: Submit for approval creates then submits', (tester) async {
    final api = closingApi(enforced: true)
      ..writeAnswers['/api/Poultry/daily-closings'] = {'poultryDailyClosingId': 41};
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: company));
    expect(find.text('Policy'), findsNothing);
    expect(find.text('Close Business Day'), findsNothing);

    await tester.tap(find.text('Submit for approval'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Poultry/daily-closings'), {'closingDate': '2026-10-02', 'farmId': 'farm-1'});
    expect(api.lastBody('/api/Poultry/daily-closings/41/submit'),
        {'actualCashCounted': 0, 'managerNotes': null, 'farmId': 'farm-1'});
  });

  testWidgets('a granted close right counts while IAM is enforced; Reject needs a reason', (tester) async {
    final api = closingApi(enforced: true, grants: [closeRight], day: {
      'closing': {
        'poultryDailyClosingId': 7, 'status': 'Submitted', 'isClosed': false, 'submittedBy': 'kofi', 'closeVersion': 0,
      },
      'live': workspace('2026-10-02'),
      'atClose': null,
      'history': [],
    });
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: company));
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Submitted by kofi — waiting for someone with the close right.'), findsOneWidget);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Counts wrong');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    final reject = api.writes.last;
    expect(reject.url.path, '/api/Poultry/daily-closings/7/reject');
    expect(reject.url.queryParameters['reason'], 'Counts wrong');
  });

  testWidgets('a closed day: summary, changes since closing, toggle, snapshot, reopen', (tester) async {
    final api = closingApi(day: {
      'closing': {
        'poultryDailyClosingId': 7, 'status': 'Approved', 'isClosed': true, 'closedBy': 'ama',
        'closedAtUtc': '2026-10-02T13:00:00Z', 'closeVersion': 2, 'warningsAtClose': 1, 'managerNotes': 'ok',
      },
      'live': workspace('2026-10-02', revenue: 650),
      'atClose': workspace('2026-10-02', revenue: 500),
      'history': [
        {
          'eventId': 3, 'eventType': 'Closed', 'actor': 'ama', 'closeVersion': 2, 'warningCount': 1,
          'occurredAtUtc': '2026-10-02T13:00:00Z', 'hasSnapshot': true,
        },
      ],
    })
      ..gets['/api/Poultry/daily-closings/events/3/snapshot'] = workspace('2026-10-02', revenue: 500);
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany), size: phone);

    expect(find.text('closed 2 times'), findsOneWidget);
    expect(find.text('Closed by ama · 2 Oct 2026, 13:00 · “ok”'), findsOneWidget);
    expect(find.text('Changed since closing'), findsOneWidget);
    expect(find.text('+GHC 150.00'), findsWidgets);
    expect(find.text('Close Business Day'), findsNothing);
    await tester.scrollUntilVisible(find.text('CLOSING CHECKLIST (CURRENT)'), 200, scrollable: _dayList);

    await tester.scrollUntilVisible(find.text('Current corrected state'), 200, scrollable: _dayList);
    await tester.tap(find.text('Current corrected state'));
    await tester.pumpAndSettle();
    expect(find.text('GHC 650.00'), findsWidgets);

    await tester.scrollUntilVisible(find.text('View as closed'), 200, scrollable: _dayList);
    await tester.tap(find.text('View as closed'));
    await tester.pumpAndSettle();
    expect(find.text('October 2, 2026 as closed (v2) by ama'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Reopen Day'), -300, scrollable: _dayList);
    await tester.drag(_dayList, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen Day'));
    await tester.pumpAndSettle();
    expect(find.text('Reopen October 2, 2026?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Late sale');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reopen Day'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Poultry/daily-closings/7/reopen'), {'reason': 'Late sale'});
  });

  testWidgets('policy: a level dropdown, a threshold and the switch all save', (tester) async {
    final api = closingApi()
      ..gets['/api/Poultry/daily-closings/policy'] = {
        'missingProduction': 'Blocking', 'unpostedProduction': 'Blocking', 'impossibleBirdCounts': 'Blocking',
        'pendingDriverReturns': 'Warning', 'negativeStock': 'Blocking', 'cashDifference': 'Warning',
        'cashDifferenceTolerance': 5, 'requireCashCount': false, 'lowFeedDays': 3, 'unusualMortalityPct': 1.5,
        'isCustomised': false,
      };
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany));
    await tester.tap(find.text('Policy'));
    await tester.pumpAndSettle();
    expect(find.text('Closing policy'), findsOneWidget);

    // Missing flock production: Blocking → Warning.
    await tester.tap(find.text('Blocking').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warning').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Low feed below (days)', '4.5');
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Save policy'));
    await tester.pumpAndSettle();

    final body = api.lastBody('/api/Poultry/daily-closings/policy', 'PUT');
    expect(body['missingProduction'], 'Warning');
    expect(body['unpostedProduction'], 'Blocking');
    expect(body['lowFeedDays'], 4.5);
    expect(body['cashDifferenceTolerance'], 5);
    expect(body['requireCashCount'], true);
    expect(body['farmId'], 'farm-1');
    expect(find.text('Closing policy saved'), findsOneWidget);
  });

  testWidgets('previous closings list opens a day', (tester) async {
    final api = closingApi()
      ..gets['/api/Poultry/daily-closings/history'] = [
        {
          'poultryDailyClosingId': 5, 'closingDate': '2026-09-30T00:00:00', 'status': 'Approved', 'isClosed': true,
          'closedBy': 'ama', 'closedAtUtc': '2026-09-30T18:00:00Z', 'revenue': 900, 'netCashFlow': -20,
          'warningsAtClose': 2, 'eggsProduced': 3400, 'reopenCount': 1, 'lastReopenReason': 'typo',
        },
      ];
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany), size: phone);
    await tester.tap(find.text('Previous closings'));
    await tester.pumpAndSettle();
    expect(find.text('September 30, 2026'), findsOneWidget);
    expect(find.text('Closed by ama · 30 Sep 2026, 18:00'), findsOneWidget);
    expect(find.text('GHC 900.00'), findsOneWidget);
    expect(find.text('GHC -20.00'), findsOneWidget);
    expect(find.text('3,400'), findsOneWidget);
    expect(find.text('1× — typo'), findsOneWidget);

    await tester.tap(find.text('Open day'));
    await tester.pumpAndSettle();
    expect(api.requests.lastWhere((r) => r.url.path.endsWith('/day')).url.queryParameters['businessDate'], '2026-09-30');
  });
}
