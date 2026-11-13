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
      expect(validatePlan('', [(title: '', ageUnit: 'Week', ageValue: 0, leadTimeDays: 400, repeatEveryDays: null)]), [
        'Give the lifecycle plan a name.',
        'Milestone 1: give it a title.',
        'Milestone 1: lead time must be between 0 and 365 days.',
      ]);
      expect(ageAtStartDays(18, 3), 129);
      // 387: repeats.
      expect(validatePlan('P', [(title: 'ND', ageUnit: 'Week', ageValue: 8, leadTimeDays: 3, repeatEveryDays: 4000)]),
          ['Milestone 1 (ND): repeat every 1 to 3650 days, or not at all.']);
      expect(repeatLabel(91), 'every 13 weeks');
      expect(repeatLabel(7), 'every week');
      expect(repeatLabel(10), 'every 10 days');
      expect(repeatLabel(null), isNull);
      expect(repeatToParts(91), (value: 13, unit: 'Week'));
      expect(repeatFromParts(13, 'Week'), 91);
      expect(taskAgeLabel({'ageUnit': 'Week', 'ageValue': 16, 'occurrence': 2, 'ageDays': 294}), 'Week 42');
      expect(taskAgeLabel({'ageUnit': 'Week', 'ageValue': 16, 'occurrence': 1, 'ageDays': 200}), 'Day 200');
      expect(taskKey({'flockId': 7, 'milestoneId': 3, 'occurrence': 2}), '7-3-2');
      expect(lifecycleCategorySuggestions.first, 'Vaccination');
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
      await reasonOther(tester, 'Closed the wrong flock');
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

    // ------------------------------------------ Report 34 part 2 (401 / 402 / 403)

    test('a close-out sale priced per kg: weight × price, and the same checks as the database', () {
      final s = CloseoutSale(quantity: 100)
        ..pricingBasis = 'PerKg'
        ..liveWeightKg = 250
        ..pricePerKg = 30;
      expect(saleTotal(s), 7500);
      expect(s.pricingFields, {'pricingBasis': 'PerKg', 'liveWeightKg': 250, 'pricePerKg': 30});
      expect(CloseoutSale().pricingFields, isEmpty, reason: 'nothing chosen, nothing sent');
      final d = CloseoutDraft(closedDate: '2026-10-12', reason: 'All birds sold')
        ..sales.add(CloseoutSale(quantity: 100, cashAccountId: 2)
          ..pricingBasis = 'PerKg'
          ..pricePerKg = 30);
      expect(validateCloseoutDraft(d, closeoutContext()), contains('Sale 1: a sale priced per kg needs the total live weight in kg.'));
    });

    FakeApi broilerCloseout() => closeoutApi()
      ..gets['/api/flock-closeout/7/context'] = {
        ...closeoutContext(),
        'flock': {'flockId': 7, 'name': 'Flock A', 'flockType': 'Broiler'},
        'birdProductName': 'Chicken',
      }
      ..gets['/api/Poultry/cash-accounts'] = [
        {'poultryCashAccountId': 2, 'accountName': 'Main Cash Account', 'isActive': true},
      ]
      ..writeAnswers['/api/flock-closeout/7'] = {'success': true, 'message': 'Flock A closed.', 'saleIds': [56], 'warnings': [], 'errors': []};

    testWidgets('a broiler flock: market reasons, per-kg sales, and the withdrawal warning to tick', (tester) async {
      final api = broilerCloseout()
        ..gets['/api/Sale/meat-withdrawal'] = [
          {'flockId': 7, 'flockName': 'Flock A', 'itemName': 'Amprolium', 'lastDoseDate': '2026-10-05', 'withdrawalUntil': '2026-10-14'},
          {'flockId': 99, 'flockName': 'Other', 'itemName': 'Other drug', 'lastDoseDate': '2026-10-05', 'withdrawalUntil': '2026-10-14'},
        ];
      await open(tester, FlockCloseoutScreen(session: await sessionFor(api), company: adminCompany), size: phone);
      await seek(tester, 'Close flock');
      await tester.tap(find.text('Close flock').first);
      await tester.pumpAndSettle();

      await tapText(tester, 'Next');
      expect(find.textContaining('Broiler sales are recorded as ordinary Chicken sales, priced per bird or per kg.', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('closeout-withdrawal')), findsNothing, reason: 'only while birds are being sold');
      await tapText(tester, 'Sale');
      expect(find.byKey(const ValueKey('closeout-withdrawal')), findsOneWidget);
      expect(find.text('• Amprolium: meat withdrawal until 14/10/2026'), findsOneWidget);
      expect(find.textContaining('Other drug'), findsNothing, reason: "another flock's medicine");

      await pickVisible(tester, 'Per bird', 'Per kg');
      expect(find.text('Live weight (kg)'), findsOneWidget);
      expect(find.text('Price per bird'), findsNothing);
      await enterVisible(tester, 'Price per kg', '30');
      await enterVisible(tester, 'Live weight (kg)', '250');
      expect(find.text('2.50 kg a bird'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '7500'), findsOneWidget);

      await tapText(tester, 'Next');
      expect(find.text('Sent to market (grow-out complete)'), findsOneWidget, reason: 'the first broiler reason');
      expect(find.textContaining('This flock is inside a meat withdrawal period: tick the box on the Dispose step to record the sales anyway.'),
          findsOneWidget);
      final close = find.widgetWithText(FilledButton, 'Close flock & record sales');
      await tester.ensureVisible(close);
      expect(tester.widget<FilledButton>(close).onPressed, isNull);

      await tapText(tester, 'Back');
      await tapText(tester, 'I have checked these birds can be sold. Record the sales anyway.');
      await tapText(tester, 'Next');
      await tapText(tester, 'Close flock & record sales');
      final body = api.lastBody('/api/flock-closeout/7');
      expect(body['reason'], 'Sent to market (grow-out complete)');
      final sale = (body['sales'] as List).single as Map;
      expect((sale['pricingBasis'], sale['liveWeightKg'], sale['pricePerKg'], sale['totalAmount']), ('PerKg', 250, 30, 7500));
    });

    testWidgets('a broiler flock lifetime page shows Broiler performance instead of Production', (tester) async {
      final api = closeoutApi()
        ..gets['/api/flock-closeout/9/history'] = []
        ..gets['/api/flock-closeout/broiler-kpis'] = [
          {
            'flockId': 9, 'flockName': 'Flock C', 'flockType': 'Broiler', 'status': 'Closed', 'ageInDays': 42, 'birdsStarted': 1000,
            'deaths': 50, 'liveabilityPct': 95, 'birdsSold': 950, 'birdsSoldWeighed': 900, 'kgSoldWeighed': 2200, 'kgSoldEstimated': 100,
            'liveBirds': 0, 'latestWeighDate': '2026-09-25T00:00:00', 'kgProduced': 2300, 'kgIsEstimated': true, 'avgLiveWeightKg': 2.42,
            'feedKg': 4200, 'fcr': 1.826, 'epef': 300.4, 'costPerKg': 2.17, 'revenuePerKg': 8.7, 'profitPerKg': 6.53, 'missing': null,
          },
        ];
      api.gets['/api/flock-closeout/lifetime'] = [lifetimeRow(9, 'Flock C', 'Closed')];
      await open(tester, FlockLifetimeScreen(session: await sessionFor(api), company: adminCompany, flockId: 9), size: phone);
      await seek(tester, 'Broiler performance');
      expect(find.text('Broiler performance'), findsOneWidget);
      expect(find.text('Production'), findsNothing);
      expect(find.text('42 days'), findsOneWidget);
      expect(find.text('95.00%'), findsOneWidget);
      expect(find.text('50 died of 1,000'), findsOneWidget);
      expect(find.text('1.826'), findsOneWidget);
      expect(find.text('2,300 kg'), findsNWidgets(2), reason: 'kg produced, and kg sold (2,200 weighed + 100 estimated)');
      expect(find.text('Partly estimated'), findsOneWidget);
      expect(find.text('Last weigh-in 2026-09-25'), findsOneWidget);
      expect(find.text('50 birds sold without a weight'), findsOneWidget);
      expect(find.textContaining('Part of the kg is estimated'), findsOneWidget);
      expect(api.requests.any((r) => r.url.path == '/api/flock-closeout/broiler-kpis' && r.url.queryParameters['flockId'] == '9'), isTrue);
    });

    testWidgets('a layer flock keeps its Production panel', (tester) async {
      final api = closeoutApi()
        ..gets['/api/flock-closeout/9/history'] = []
        ..gets['/api/flock-closeout/broiler-kpis'] = [
          {'flockId': 9, 'flockName': 'Flock C', 'flockType': 'Layer', 'feedKg': 0, 'kgSoldWeighed': 0, 'birdsSold': 0, 'birdsSoldWeighed': 0},
        ];
      api.gets['/api/flock-closeout/lifetime'] = [lifetimeRow(9, 'Flock C', 'Closed')];
      await open(tester, FlockLifetimeScreen(session: await sessionFor(api), company: adminCompany, flockId: 9), size: phone);
      await seek(tester, 'Production');
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Broiler performance'), findsNothing);
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
      await reasonOther(tester, 'Vet said not needed');
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
      await seek(tester, 'For Lohmann');
      expect(find.text('Any breed · Inactive'), findsOneWidget);
      expect(find.text('2 milestones · used by 1 batch and 0 flocks directly'), findsOneWidget);

      await seek(tester, 'New plan', up: true);
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

    testWidgets('387: the national schedule panel, its badge and note, Add missing national plans, a repeat saved', (tester) async {
      final api = lifecycleApi()
        ..gets['/api/Poultry/lifecycle/templates'] = [
          {'templateId': 6, 'name': 'Commercial Layers', 'isActive': true, 'isDefault': true, 'milestoneCount': 12, 'assignedBatches': 0, 'assignedFlocks': 0},
        ]
        ..gets['/api/Poultry/lifecycle/templates/6'] = {
          'templateId': 6, 'name': 'Commercial Layers', 'isActive': true, 'isDefault': true,
          'milestones': [
            {'milestoneId': 1, 'ageUnit': 'Week', 'ageValue': 8, 'title': 'Newcastle booster', 'category': 'Vaccination', 'leadTimeDays': 3, 'repeatEveryDays': 91},
          ],
        }
        ..writeAnswers['/api/Poultry/lifecycle/ensure-defaults'] = {'plansCreated': 0, 'alreadyApplied': true};
      await open(tester, FlockLifecycleScreen(session: await sessionFor(api), company: adminCompany), size: phone);
      expect(api.writes.any((w) => w.url.path == '/api/Poultry/lifecycle/ensure-defaults' && w.url.queryParameters['force'] == null), isTrue,
          reason: 'seeded once, quietly, on load');
      expect(find.textContaining('The Ghana national vaccination schedule is ready as two plans'), findsOneWidget);

      await tapText(tester, 'Plans');
      await seek(tester, 'Ghana national vaccination schedule');
      expect(find.text('National schedule'), findsOneWidget);
      await tapText(tester, 'Add missing national plans');
      expect(api.writes.any((w) => w.url.queryParameters['force'] == 'true'), isTrue);
      expect(find.text('Nothing to add — Both national vaccination plans are already here.'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit plan').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('national-plan-note')), findsOneWidget);
      await seek(tester, 'Repeats every 13 weeks after this age, until the flock is closed.');
      await tapText(tester, 'Save plan');
      final m = (api.lastBody('/api/Poultry/lifecycle/templates/6', 'PUT')['milestones'] as List).single as Map;
      expect(m['repeatEveryDays'], 91, reason: 'the repeat rides back as days');
    });

    testWidgets('387: a repeated task shows Repeat N and completes its own occurrence', (tester) async {
      final api = lifecycleApi()
        ..gets['/api/Poultry/lifecycle/tasks'] = [
          {...task(4, 'Overdue', days: -1), 'title': 'Newcastle booster', 'occurrence': 2, 'ageDays': 294, 'repeatEveryDays': 91},
        ];
      await open(tester, FlockLifecycleScreen(session: await sessionFor(api), company: adminCompany), size: phone);
      await seek(tester, 'Newcastle booster');
      expect(find.text('↻ Repeat 2'), findsOneWidget);
      expect(find.text('Repeats every 13 weeks'), findsOneWidget);
      expect(find.text('B1 (Flock A) passed Week 42'), findsOneWidget);
      await tapText(tester, 'Complete');
      final b = api.lastBody('/api/Poultry/lifecycle/tasks/status', 'PUT');
      expect((b['milestoneId'], b['occurrence'], b['status']), (4, 2, 'Completed'));
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
