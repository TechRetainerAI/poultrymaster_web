// Poultry → Tools → Flock Closeout and Flock Lifecycle, against a fake API,
// at phone size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_closeout_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_closeout_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_lifecycle_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_lifecycle_screen.dart';

import 'support/harness.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Scrolls the page until [text] is built and on screen.
Future<void> seek(WidgetTester tester, String text, {bool up = false}) async {
  for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, Offset(0, up ? 300 : -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> pickVisible(WidgetTester tester, String shown, String option) async {
  await tester.ensureVisible(find.text(shown).first);
  await tester.pumpAndSettle();
  await pick(tester, shown, option);
}

Future<void> enterVisible(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.pumpAndSettle();
  await enter(tester, label, text);
}

Map<String, dynamic> lifetimeRow(int id, String name, String status,
        {String batch = 'B1', String breed = 'Isa Brown', num placed = 1000, num finalBirds = 900, num profit = 500, num mortality = 100}) =>
    {
      'flockId': id, 'flockName': name, 'breed': breed, 'status': status, 'batchId': batch == 'B1' ? 1 : 2,
      'batchCode': batch, 'batchName': 'Batch $batch', 'supplierId': null, 'houseId': 3, 'houseName': 'House 1',
      'startDate': '2026-01-01T00:00:00', 'closedDate': status == 'Closed' ? '2026-09-30T00:00:00' : null,
      'daysInProduction': 270, 'hasOpeningPosition': false, 'historyKnown': true, 'originallyPlaced': placed,
      'openingLiveBirds': placed, 'openingMortality': 0, 'recordedMortality': mortality, 'birdsSold': 0, 'birdsCulled': 0,
      'birdsTransferred': 0, 'finalBirds': finalBirds, 'trackedMortalityRate': mortality / placed, 'lifetimeMortalityRate': null,
      'totalEggs': 120000, 'productionDays': 200, 'eggRevenue': 4000, 'birdSaleRevenue': 0, 'otherRevenue': 0,
      'totalRevenue': 4000, 'feedConsumedKg': 12000, 'feedCost': 2500, 'medicationCost': 300, 'birdCost': 700,
      'birdCostRecorded': true, 'laborCost': 0, 'otherDirectCost': 0, 'totalCost': 3500, 'profit': profit,
      'profitPerOriginalBird': profit / placed, 'revenuePerOriginalBird': 4, 'feedKgPerDozenEggs': 1.2,
    };

Map<String, dynamic> closeoutContext({num live = 100}) => {
      'flock': {'flockId': 7, 'name': 'Flock A'},
      'position': {
        'flockId': 7, 'hasOpeningPosition': false, 'historyKnown': true, 'originallyPlaced': 1000, 'openingMortality': 0,
        'openingSold': 0, 'openingCulled': 0, 'openingTransferred': 0, 'openingOther': 0, 'openingLiveBirds': 1000,
        'recordedMortality': 900, 'productionRecordCount': 30, 'lastCountedBirds': live, 'lastCountDate': '2026-10-01T00:00:00',
        'correction': 0, 'birdsSold': 0, 'birdsCulled': 0, 'birdsTransferred': 0, 'currentLiveBirds': live,
      },
      'isClosed': false, 'ineligibleReason': null, 'houseName': 'House 1', 'businessDate': '2026-10-12T00:00:00',
      'earliestCloseDate': '2026-01-01T00:00:00', 'birdProductName': 'Spent Layer',
    };

Map<String, dynamic> task(int milestoneId, String status, {int days = 3, String unit = 'Week', String? action, int? taskId}) => {
      'flockId': 7, 'flockName': 'Flock A', 'batchId': 1, 'batchCode': 'B1', 'breed': 'Isa Brown',
      'flockStartDate': '2026-06-01', 'flockActive': true, 'isEstimated': false, 'assignmentId': 1, 'assignedVia': 'Batch',
      'templateId': 4, 'templateName': 'Our layer plan', 'ageAtStartDays': 0, 'currentAgeDays': 107,
      'milestoneId': milestoneId, 'title': 'Review housing $milestoneId', 'description': 'Check the perches',
      'category': 'Housing', 'ageUnit': unit, 'ageValue': 16, 'ageDays': 112, 'leadTimeDays': 3, 'actionType': action,
      'dueDate': '2026-10-15', 'dueWindowEnd': '2026-10-21', 'visibleFrom': '2026-10-12', 'daysUntilDue': days,
      'taskId': taskId, 'status': status, 'today': '2026-10-12',
    };

void main() {
  setUp(LookupLoader.clear);

  group('closeout and lifecycle rules', () {
    test('the wizard refuses an unbalanced or incomplete closeout in the web words', () {
      final ctx = closeoutContext();
      final d = CloseoutDraft(closedDate: '2026-10-12');
      expect(validateCloseoutDraft(d, ctx), [
        'Unresolved bird balance: 100 bird(s) are still unaccounted for. Sell, cull or transfer them, or record any unrecorded deaths as mortality on a production record, before closing.',
      ]);
      d.sales.add(CloseoutSale(quantity: 100, cashAccountId: null)..paymentTerms = 'PartPaid'..unitPrice = 5..amountPaid = 600);
      expect(validateCloseoutDraft(d, ctx), [
        'Sale 1: choose the cash account the money was received into.',
        'Sale 1: a sale on credit needs a customer, so the balance has someone to belong to.',
        'Sale 1: a part payment must be more than zero and less than the sale total (500.00).',
      ]);
      d.closedDate = '2026-10-13';
      expect(validateCloseoutDraft(d, ctx), contains('The closing date cannot be in the future.'));
    });

    test('groups re-derive ratios from their totals', () {
      final g = groupLifetimeSummaries([
        lifetimeRow(1, 'A', 'Closed', placed: 50, mortality: 25),
        lifetimeRow(2, 'B', 'Closed', placed: 5000, mortality: 50),
      ], 'batch');
      expect(g, hasLength(1));
      expect(g.first.trackedMortalityRate, closeTo(75 / 5050, 1e-9));
    });

    test('lifecycle wording', () {
      expect(formatAgeDays(107), '15w 2d');
      expect(formatAgeDays(112), '16w');
      expect(dueLabel(task(1, 'Due', days: 2)), 'Due this week');
      expect(dueLabel(task(1, 'Overdue', days: -3)), '3 days overdue');
      expect(taskSentence(task(1, 'Upcoming', days: 1)), 'B1 (Flock A) reaches Week 16 tomorrow');
      expect(validatePlan('', [(title: '', ageUnit: 'Week', ageValue: 0, leadTimeDays: 400)]), [
        'Give the lifecycle plan a name.',
        'Milestone 1: give it a title.',
        'Milestone 1: lead time must be between 0 and 365 days.',
      ]);
      expect(ageAtStartDays(18, 3), 129);
      expect([for (final t in sortTasks([task(1, 'Upcoming'), task(3, 'Completed'), task(2, 'Overdue')])) t['milestoneId']], [2, 1, 3]);
    });
  });

  group('Flock Closeout', () {
    FakeApi closeoutApi() => FakeApi()
      ..gets['/api/flock-closeout/lifetime'] = [
        lifetimeRow(7, 'Flock A', 'Active', finalBirds: 100),
        lifetimeRow(8, 'Flock B', 'Inactive', batch: 'B2', breed: 'Lohmann', finalBirds: 40),
        lifetimeRow(9, 'Flock C', 'Closed', profit: -200),
        lifetimeRow(10, 'Flock D', 'Pending'),
      ];

    testWidgets('three tabs over one read: open, closed and compare', (tester) async {
      final api = closeoutApi();
      await open(tester, FlockCloseoutScreen(session: await sessionFor(api), company: adminCompany), size: phone);

      expect(find.text('Open flocks'), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'Active + Inactive, not Pending');
      expect(find.text('140'), findsOneWidget, reason: 'birds standing in them');
      expect(find.text('Flock A'), findsOneWidget);
      expect(find.text('Flock D'), findsNothing);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Close flock'), findsNWidgets(2));

      await tester.enterText(find.byType(TextFormField).first, 'lohmann');
      await tester.pumpAndSettle();
      expect(find.text('Flock A'), findsNothing);
      await seek(tester, 'Flock B');
      expect(find.text('Flock B'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pumpAndSettle();

      await tapText(tester, 'Closed');
      expect(find.text('Flock C'), findsOneWidget);
      expect(find.text('Lifetime & reopen'), findsOneWidget);

      await tapText(tester, 'Compare');
      expect(find.text('Batch'), findsOneWidget);
      expect(find.text('1 flock · 1,000 birds placed'), findsOneWidget);
      await pickVisible(tester, 'Batch', 'Breed');
      expect(find.text('Isa Brown'), findsOneWidget);
      await pickVisible(tester, 'Closed flocks only', 'Include open flocks');
      expect(find.text('Lohmann'), findsOneWidget);
      expect(find.text('Ratios are worked out', findRichText: true), findsNothing);
    });

    testWidgets('the wizard reconciles, sells the last birds and closes in one post', (tester) async {
      final api = closeoutApi()
        ..gets['/api/flock-closeout/7/context'] = closeoutContext()
        ..gets['/api/Customer'] = [
          {'customerId': 31, 'name': 'Ama Mensah'},
        ]
        ..gets['/api/Poultry/cash-accounts'] = [
          {'poultryCashAccountId': 2, 'accountName': 'Main Cash Account', 'isActive': true},
          {'poultryCashAccountId': 3, 'accountName': 'MoMo', 'isActive': true},
        ]
        ..writeAnswers['/api/flock-closeout/7'] = {
          'success': true, 'message': 'Flock A closed.', 'saleIds': [55], 'warnings': ['House 1 had no other flock.'], 'errors': [],
        };
      await open(tester, FlockCloseoutScreen(session: await sessionFor(api), company: adminCompany), size: phone);

      await seek(tester, 'Close flock');
      await tester.tap(find.text('Close flock').first);
      await tester.pumpAndSettle();
      expect(find.text('Close Flock A'), findsOneWidget);
      expect(find.text('Where the birds went'.toUpperCase()), findsOneWidget);
      expect(find.text('Latest production record, 2026-10-01'), findsOneWidget);
      expect(find.textContaining('100 birds are still standing.'), findsOneWidget);

      await tapText(tester, 'Next');
      expect(find.text('100 still to account for'), findsOneWidget);
      await tapText(tester, 'Sale');
      expect(find.text('Balanced'), findsOneWidget, reason: 'a new sale takes the birds still standing');
      await enterVisible(tester, 'Price per bird', '5');
      expect(find.widgetWithText(TextFormField, '500'), findsOneWidget);
      await pickVisible(tester, 'Paid in full', 'On credit');
      expect(find.text('Payment method'), findsNothing, reason: 'credit takes no payment');
      await enterVisible(tester, 'Customer', 'Ama Mensah');

      await tapText(tester, 'Next');
      await pickVisible(tester, 'End of lay (spent layers)', 'Other');
      await tester.enterText(find.widgetWithText(TextFormField, 'Why is this flock closing?'), 'Sold to a neighbour');
      await tester.pumpAndSettle();
      expect(find.text('100 birds to Ama Mensah · On credit'), findsOneWidget);
      expect(find.textContaining('House 1 will be released'), findsOneWidget);

      await tapText(tester, 'Close flock & record sales');
      final body = api.lastBody('/api/flock-closeout/7');
      expect(body['reason'], 'Sold to a neighbour');
      expect(body['closedDate'], '2026-10-12');
      final sale = (body['sales'] as List).single as Map;
      expect(sale['quantity'], 100);
      expect(sale['totalAmount'], 500);
      expect(sale['customerId'], 31);
      expect(sale['paymentTerms'], 'Credit');
      expect(sale['paymentMethod'], isNull);
      expect(sale['poultryCashAccountId'], isNull);
      expect(api.writes.last.url.queryParameters['farmId'], 'farm-1');
      expect(find.text('Flock A closed.'), findsOneWidget);
      expect(find.textContaining('(#55)'), findsOneWidget);
      expect(find.text('House 1 had no other flock.'), findsOneWidget);
      await tapText(tester, 'Done');
      expect(find.text('Close Flock A'), findsNothing);
    });

    testWidgets('the lifetime page shows the figures, the history and reopens with the sales reversed', (tester) async {
      final api = closeoutApi()
        ..gets['/api/flock-closeout/9/history'] = [
          {
            'closeoutId': 4, 'flockId': 9, 'closedDate': '2026-09-30', 'reason': 'End of lay (spent layers)', 'closedBy': 'admin',
            'closedAt': '2026-09-30T10:00:00Z', 'correction': 0, 'liveBirdsAtCloseout': 900, 'disposedSold': 900,
            'disposedCulled': 0, 'disposedTransferred': 0, 'reopenedAt': null,
            'dispositions': [
              {'dispositionId': 1, 'disposition': 'Sale', 'quantity': 900, 'saleId': 77, 'totalAmount': 4500, 'customerName': 'Kofi', 'paid': false},
            ],
          },
        ]
        ..writeAnswers['/api/flock-closeout/9/reverse'] = {'success': true, 'message': 'Flock C reopened.', 'warnings': []};
      api.gets['/api/flock-closeout/lifetime'] = [lifetimeRow(9, 'Flock C', 'Closed', profit: -200)];
      await open(tester, FlockLifetimeScreen(session: await sessionFor(api), company: adminCompany, flockId: 9), size: phone);

      expect(find.text('Flock C'), findsWidgets);
      expect(find.text('Back to Flock Closeout'), findsOneWidget);
      expect(find.text('Close flock'), findsNothing, reason: 'already closed');
      expect(find.text('Profit'), findsWidgets);
      expect(find.text('Attributable cost'), findsOneWidget);
      expect(find.textContaining('Sale #77: 900 birds'), findsOneWidget);
      expect(find.textContaining('(balance outstanding)'), findsOneWidget);

      await tapText(tester, 'Reopen flock');
      expect(find.textContaining('Also reverse the closeout sales.', findRichText: true), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'Closed the wrong flock');
      await tester.pumpAndSettle();
      await tapText(tester, 'Reopen');
      final body = api.lastBody('/api/flock-closeout/9/reverse');
      expect(body['reason'], 'Closed the wrong flock');
      expect(body['reverseSales'], true);
    });

    testWidgets('without the view permission the page is locked', (tester) async {
      final api = closeoutApi()
        ..gets['/api/Iam/status'] = {'enforced': true}
        ..gets['/api/Iam/effective-permissions'] = {'grants': []};
      await open(tester, FlockCloseoutScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('You do not have access to Flock Closeout.'), findsOneWidget);
    });
  });

  group('Flock Lifecycle', () {
    FakeApi lifecycleApi() => FakeApi()
      ..gets['/api/Poultry/lifecycle/tasks'] = [
        task(1, 'Upcoming', days: 3, action: 'Closeout'),
        task(2, 'Overdue', days: -2, unit: 'Day'),
        task(3, 'Completed', taskId: 9),
      ]
      ..gets['/api/Poultry/lifecycle/summary'] = {
        'upcoming': 1, 'due': 0, 'overdue': 1, 'completedLast30': 1, 'skippedLast30': 0, 'estimatedFlocks': 0, 'assignedFlocks': 1,
        'today': '2026-10-12',
      }
      ..gets['/api/Poultry/lifecycle/templates'] = [
        {'templateId': 4, 'name': 'Our layer plan', 'breed': 'Lohmann', 'isActive': true, 'milestoneCount': 2, 'assignedBatches': 1, 'assignedFlocks': 0},
        {'templateId': 5, 'name': 'Old plan', 'breed': null, 'isActive': false, 'milestoneCount': 1, 'assignedBatches': 0, 'assignedFlocks': 0},
      ]
      ..gets['/api/Poultry/lifecycle/assignments'] = [
        {
          'assignmentId': 1, 'templateId': 4, 'templateName': 'Our layer plan', 'templateBreed': 'Lohmann', 'batchId': 1,
          'batchCode': 'B1', 'batchName': 'Spring', 'flockCount': 2, 'ageAtStartDays': 126, 'breedMismatch': true,
          'targetBreed': 'Isa Brown', 'assignedAt': '2026-10-01',
        },
      ]
      ..gets['/api/Flock'] = [
        {'flockId': 7, 'name': 'Flock A', 'batchName': 'Spring', 'breed': 'Isa Brown', 'closedDate': null},
        {'flockId': 8, 'name': 'Flock Z', 'batchName': 'Old', 'breed': 'Isa Brown', 'closedDate': '2026-05-01'},
      ]
      ..gets['/api/MainFlockBatch'] = [
        {'batchId': 1, 'batchCode': 'B1', 'batchName': 'Spring', 'breed': 'Isa Brown'},
      ];

    testWidgets('tasks: most urgent first, Complete, Skip with a reason, and the view filter', (tester) async {
      final api = lifecycleApi();
      await open(tester, FlockLifecycleScreen(session: await sessionFor(api), company: adminCompany), size: phone);

      await seek(tester, 'Review housing 2');
      expect(find.text('B1 (Flock A) passed Day 16'), findsOneWidget);
      expect(find.text('2 days overdue'), findsOneWidget);
      expect(find.text('Flock lifecycle'), findsNothing);
      expect(find.text('Flock closeout'), findsOneWidget, reason: 'the action link');
      expect(find.text('Our layer plan (via batch B1)'), findsNWidgets(3));

      await tester.tap(find.text('Complete').first);
      await tester.pumpAndSettle();
      final put = api.lastBody('/api/Poultry/lifecycle/tasks/status', 'PUT');
      expect(put['status'], 'Completed');
      expect(put['milestoneId'], 2);

      await tester.ensureVisible(find.text('Skip').first);
      await tester.tap(find.text('Skip').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip task'));
      await tester.pumpAndSettle();
      expect(find.text('Why is it being skipped? is required.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'Vet said not needed');
      await tester.tap(find.text('Skip task'));
      await tester.pumpAndSettle();
      final skip = api.lastBody('/api/Poultry/lifecycle/tasks/status', 'PUT');
      expect(skip['status'], 'Skipped');
      expect(skip['note'], 'Vet said not needed');

      await seek(tester, 'Needs attention', up: true);
      await pickVisible(tester, 'Needs attention', 'Everything');
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Poultry/lifecycle/tasks').url.queryParameters['view'], 'All');
      await pickVisible(tester, 'All flocks', 'Flock A · Spring');
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Poultry/lifecycle/tasks').url.queryParameters['flockId'], '7');
      expect(find.text('Flock Z · Old'), findsNothing, reason: 'closed flocks are not offered');

      await seek(tester, 'Coming up', up: true);
      await tester.ensureVisible(find.text('Overdue').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue').first);
      await tester.pumpAndSettle();
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Poultry/lifecycle/tasks').url.queryParameters['view'], 'Overdue');
    });

    testWidgets('plans: the editor checks the plan and saves its milestones', (tester) async {
      final api = lifecycleApi();
      await open(tester, FlockLifecycleScreen(session: await sessionFor(api), company: adminCompany), size: phone);

      await tapText(tester, 'Plans');
      expect(find.text('For Lohmann'), findsOneWidget);
      expect(find.text('Any breed · Inactive'), findsOneWidget);
      expect(find.text('2 milestones · used by 1 batch and 0 flocks directly'), findsOneWidget);

      await tapText(tester, 'New plan');
      await tapText(tester, 'Save plan');
      expect(find.text('Give the lifecycle plan a name.'), findsOneWidget);
      expect(find.text('Milestone 1: give it a title.'), findsOneWidget);

      await enterVisible(tester, 'Plan name *', 'Layer plan 2');
      await enterVisible(tester, 'Title * (Milestone 1)', 'Move to laying house');
      await enterVisible(tester, 'Age', '16');
      await pickVisible(tester, 'Weeks', 'Days');
      await pickVisible(tester, 'No link', 'Move house');
      await tapText(tester, 'Save plan');
      final body = api.lastBody('/api/Poultry/lifecycle/templates');
      expect(body['name'], 'Layer plan 2');
      expect(body['farmId'], 'farm-1');
      final m = (body['milestones'] as List).single as Map;
      expect(m['title'], 'Move to laying house');
      expect(m['ageValue'], 16);
      expect(m['ageUnit'], 'Day');
      expect(m['leadTimeDays'], 3);
      expect(m['actionType'], 'FlockTransfer');
    });

    testWidgets('assignments: the breed warning, and assigning a plan to one flock', (tester) async {
      final api = lifecycleApi();
      await open(tester, FlockLifecycleScreen(session: await sessionFor(api), company: adminCompany), size: phone);

      await tapText(tester, 'Assignments');
      expect(find.text('2 open flocks · age at start 18w'), findsOneWidget);
      expect(find.text('Plan written for Lohmann; this is Isa Brown.'), findsOneWidget);

      await tapText(tester, 'Assign plan');
      await pickVisible(tester, 'Choose a plan', 'Our layer plan (Lohmann)');
      await tapText(tester, 'One flock');
      await pickVisible(tester, 'Choose a flock', 'Flock A · Spring');
      expect(find.textContaining('This plan was written for Lohmann; this is Isa Brown.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, '0').first, '18');
      await tester.pumpAndSettle();
      await tapText(tester, 'Assign');
      final body = api.lastBody('/api/Poultry/lifecycle/assignments');
      expect(body['templateId'], 4);
      expect(body['flockId'], 7);
      expect(body['batchId'], isNull);
      expect(body['ageAtStartDays'], 126);
    });

    testWidgets('without the view permission the page is locked', (tester) async {
      final api = lifecycleApi()
        ..gets['/api/Iam/status'] = {'enforced': true}
        ..gets['/api/Iam/effective-permissions'] = {'grants': []};
      await open(
          tester,
          FlockLifecycleScreen(session: await sessionFor(api), company: Company(farmId: 'farm-1', name: 'T', type: CompanyType.poultry)),
          size: phone);
      expect(find.text('You do not have access to the Flock Lifecycle assistant.'), findsOneWidget);
    });
  });
}
