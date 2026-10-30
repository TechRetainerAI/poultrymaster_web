// Poultry → Tools → Treatment Campaigns and Inventory Restock Forecast, against
// a fake API, at phone size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/days_of_supply_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/treatment_campaign_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/treatment_campaigns_screen.dart';

import 'support/harness.dart';

const base = '/api/Poultry/treatment-campaigns';

/// Scrolls the page until [text] is built, then onto the screen.
Future<void> seek(WidgetTester tester, String text, {bool up = false}) async {
  for (final dir in [up, !up]) {
    for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, Offset(0, dir ? 300 : -300));
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await seek(tester, text);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> pickOption(WidgetTester tester, String shown, String option) async {
  await seek(tester, shown);
  await pick(tester, shown, option);
}

Future<void> type(WidgetTester tester, Key key, String text) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byKey(key), matching: find.byType(TextFormField)).first, text);
  await tester.pumpAndSettle();
}

Future<void> typeIn(WidgetTester tester, String label, String text) async {
  await seek(tester, label);
  await enter(tester, label, text);
  await tester.pumpAndSettle();
}

Map<String, dynamic> campaign({String status = 'InProgress', String lifecycle = 'Open', int posted = 1}) => {
      'poultryTreatmentCampaignId': 5, 'name': 'Coccidiosis — Houses 2 to 4', 'poultryRawMaterialItemId': 11,
      'itemName': 'Amprolium', 'unitOfMeasure': 'L', 'reason': 'Vet diagnosis', 'startDate': '2026-10-10',
      'endDate': '2026-10-14', 'plannedDays': 5, 'doseInstructions': '1 ml per litre', 'doseQuantity': 0.5,
      'doseBasis': 'Per1000Birds', 'doseSource': 'Product', 'eggWithdrawalDays': 7, 'meatWithdrawalDays': null,
      'withdrawalNotes': null, 'notes': null, 'lifecycle': lifecycle, 'status': status, 'companyToday': '2026-10-12',
      'flockCount': 2, 'postedDays': posted, 'totalQuantity': 1.5, 'totalCost': 30, 'lastPostedDate': '2026-10-10',
      'eggWithdrawalUntil': '2026-10-17', 'meatWithdrawalUntil': null, 'createdBy': 'admin', 'createdAtUtc': '2026-10-09T10:00:00Z',
    };

FakeApi api0() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-12'}
  ..gets[base] = [
    campaign(),
    {...campaign(status: 'Completed', lifecycle: 'Completed'), 'poultryTreatmentCampaignId': 6, 'name': 'Newcastle vaccine'},
  ]
  ..gets['$base/products'] = [
    {
      'poultryRawMaterialItemId': 11, 'itemName': 'Amprolium', 'unitOfMeasure': 'L', 'isActive': true, 'availableQuantity': 10,
      'costRecognitionMethod': 'EXPENSE_WHEN_CONSUMED', 'doseQuantity': 0.5, 'doseBasis': 'Per1000Birds',
      'eggWithdrawalDays': 7, 'meatWithdrawalDays': null, 'withdrawalNotes': 'Per label',
    },
    {'poultryRawMaterialItemId': 12, 'itemName': 'Old drug', 'unitOfMeasure': 'L', 'isActive': false, 'availableQuantity': 1},
  ]
  ..gets['$base/flock-options'] = [
    {'flockId': 7, 'flockName': 'Flock A', 'houseName': 'House 2', 'birds': 2000},
    {'flockId': 8, 'flockName': 'Flock B', 'houseName': 'House 3', 'birds': 1000},
  ]
  ..gets['$base/5'] = campaign()
  ..gets['$base/5/flocks'] = [
    {'flockId': 7, 'flockName': 'Flock A', 'houseName': 'House 2', 'birdsAtCreation': 2000, 'doseQuantity': null, 'postedDays': 1, 'totalQuantity': 1},
    {'flockId': 8, 'flockName': 'Flock B', 'houseName': 'House 3', 'birdsAtCreation': 1000, 'doseQuantity': 0.6, 'postedDays': 1, 'totalQuantity': 0.5},
  ]
  ..gets['$base/5/days'] = [
    {
      'poultryTreatmentCampaignPostId': 41, 'businessDate': '2026-10-10', 'flockCount': 2, 'totalQuantity': 1.5, 'totalCost': 30,
      'status': 'Posted', 'notes': 'Morning water', 'postedBy': 'admin', 'postedAtUtc': '2026-10-10T08:00:00Z',
    },
  ]
  ..gets['$base/days/41/lines'] = [
    {'poultryTreatmentCampaignPostLineId': 1, 'flockId': 7, 'flockName': 'Flock A', 'productionRecordId': 900, 'actualQuantity': 1, 'suggestedQuantity': 1, 'totalCost': 20},
  ]
  ..gets['$base/5/day-grid'] = [
    {'flockId': 7, 'flockName': 'Flock A', 'houseName': 'House 2', 'isClosed': false, 'recordCount': 1, 'birds': 2000,
      'doseQuantity': 0.5, 'doseBasis': 'Per1000Birds', 'suggestedQuantity': 1, 'thisItemQuantity': 0, 'postedQuantity': null},
    {'flockId': 8, 'flockName': 'Flock B', 'houseName': 'House 3', 'isClosed': false, 'recordCount': 0, 'birds': 1000,
      'doseQuantity': 0.6, 'doseBasis': 'Per1000Birds', 'suggestedQuantity': 0.6, 'thisItemQuantity': 0, 'postedQuantity': null},
  ]
  ..writeAnswers[base] = {'poultryTreatmentCampaignId': 5};

void main() {
  setUp(LookupLoader.clear);

  group('treatment rules', () {
    test('suggestions are plain arithmetic on the farm dose, never a stand-in', () {
      expect(suggestQuantity(0.5, 'Per1000Birds', 2000), 1);
      expect(suggestQuantity(0.01, 'PerBird', 300), 3);
      expect(suggestQuantity(2, 'PerFlock', null), 2);
      expect(suggestQuantity(2, 'PerBird', null), isNull);
      expect(suggestQuantity(null, 'PerBird', 100), isNull);
      expect(describeDose(0.5, 'Per1000Birds', 'L'), '0.5 L per 1,000 birds per day');
      expect(recordableDays('2026-10-10', '2026-10-14', '2026-10-12'), ['2026-10-10', '2026-10-11', '2026-10-12']);
      expect(daysInclusive('2026-10-12', '2026-10-10'), 0);
      expect(parseQty('abc'), isNull);
      final rows = [(state: 'ok', actualText: '12')];
      expect(dayPostBlocker((actual: 12, remaining: -2), rows, alreadyPosted: false, campaignOpen: true, inWindow: true),
          'That is more than the stock on hand.');
      expect(dayPostBlocker((actual: 1, remaining: 1), rows, alreadyPosted: true, campaignOpen: true, inWindow: true),
          'This day is already recorded. Reverse it in Treatment days to record it again.');
    });
  });

  testWidgets('list: scheduled and in progress first, All shows the rest', (tester) async {
    final api = api0();
    await open(tester, TreatmentCampaignsScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('Coccidiosis — Houses 2 to 4'), findsOneWidget);
    expect(find.text('Newcastle vaccine'), findsNothing);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Eggs until October 17, 2026'), findsOneWidget);
    expect(find.text('1 of 5'), findsOneWidget);
    await tapText(tester, 'All');
    expect(find.text('Newcastle vaccine'), findsOneWidget);
  });

  testWidgets('new campaign: the product brings its own figures; flocks, own dose and the post body', (tester) async {
    final api = api0();
    await open(tester, NewTreatmentCampaignScreen(session: await sessionFor(api), company: company), size: phone);

    expect(find.text('Give the campaign a name.'), findsOneWidget);
    await typeIn(tester, 'Campaign name', 'Coccidiosis — Houses 2 to 4');
    expect(find.text('Choose the medication product.'), findsOneWidget);
    expect(find.text('Old drug — 1 L in stock'), findsNothing, reason: 'inactive items are not offered');
    await pickOption(tester, 'Choose a product', 'Amprolium — 10 L in stock');
    expect(find.text('Dose and withdrawal filled from your saved settings for Amprolium. Change them for this campaign if needed.'),
        findsOneWidget);
    expect(find.text('per 1,000 birds per day'), findsOneWidget);
    expect(find.text('Choose at least one flock.'), findsOneWidget);

    await pickOption(tester, 'per 1,000 birds per day', 'per bird per day');
    expect(find.textContaining('the system has no built-in doses'), findsOneWidget, reason: 'changed, so no longer the product setting');
    await pickOption(tester, 'per bird per day', 'per 1,000 birds per day');

    await seek(tester, 'Flock A');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('flock-7')), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    await seek(tester, 'Flock B');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('flock-8')), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    await type(tester, const ValueKey('own-dose-8'), '0.6');
    expect(find.text('Suggested / day: 1 L'), findsOneWidget);
    expect(find.text('Suggested / day: 0.6 L'), findsOneWidget);
    await seek(tester, 'SUGGESTED PER DAY');
    expect(find.text('1.6 L'), findsNWidgets(2), reason: 'per day, and for the 1 day');
    expect(find.text('Flocks (2 selected)'), findsOneWidget);

    await typeIn(tester, 'Meat withdrawal (days)', '1.5');
    // The box takes whole numbers only, so the web's "must be whole numbers"
    // state cannot be typed into: the point is dropped.
    expect(find.widgetWithText(TextFormField, '15'), findsOneWidget);
    await typeIn(tester, 'Meat withdrawal (days)', '3');
    await seek(tester, 'Save this dose and withdrawal as Amprolium\'s default for future campaigns');
    await tester.tap(find.text("Save this dose and withdrawal as Amprolium's default for future campaigns"));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create campaign'));
    await tester.pumpAndSettle();
    final body = api.lastBody(base);
    expect(body['name'], 'Coccidiosis — Houses 2 to 4');
    expect(body['itemId'], 11);
    expect(body['startDate'], '2026-10-12');
    expect(body['endDate'], '2026-10-12');
    expect(body['doseQuantity'], 0.5);
    expect(body['doseBasis'], 'Per1000Birds');
    expect(body['doseSource'], 'User');
    expect(body['eggWithdrawalDays'], 7);
    expect(body['meatWithdrawalDays'], 3);
    expect(body['withdrawalNotes'], 'Per label');
    expect(body['saveAsProductDefault'], true);
    expect(body['farmId'], 'farm-1');
    expect(body['flocks'], [
      {'flockId': 7, 'doseQuantity': null, 'notes': null},
      {'flockId': 8, 'doseQuantity': 0.6, 'notes': null},
    ]);
    expect(find.textContaining('Campaign created'), findsOneWidget);
    await seek(tester, 'Record treatment');
    expect(find.text('Record treatment'), findsOneWidget, reason: 'opens the new campaign');
  });

  testWidgets('one campaign: record a day from suggestions, with notes', (tester) async {
    final api = api0();
    await open(tester, TreatmentCampaignScreen(session: await sessionFor(api), company: company, campaignId: 5), size: phone);

    expect(find.textContaining('0.5 L per 1,000 birds per day (product setting)', findRichText: true), findsOneWidget);
    expect(find.textContaining('7 days — until October 17, 2026', findRichText: true), findsOneWidget);
    await seek(tester, 'Day 3 · October 12, 2026');
    expect(find.text('Day 3 · October 12, 2026'), findsOneWidget, reason: 'today is the default day');
    expect(api.requests.lastWhere((r) => r.url.path == '$base/5/day-grid').url.queryParameters['date'], '2026-10-12');
    expect(find.text('Type the quantity actually given to each flock.'), findsOneWidget);

    await pickOption(tester, 'Day 3 · October 12, 2026', 'Day 1 · October 10, 2026 — recorded');
    expect(find.text('This day is already recorded. Reverse it in Treatment days to record it again.'), findsOneWidget);
    await pickOption(tester, 'Day 1 · October 10, 2026 — recorded', 'Day 2 · October 11, 2026');

    await tapText(tester, 'Fill Actual from suggestions');
    await seek(tester, 'Flock B');
    expect(find.text('No production record — '), findsOneWidget);
    expect(find.text('1 L to 1 flock · 9 L left'), findsOneWidget);
    await type(tester, const ValueKey('line-notes-7'), 'Morning');

    await tester.tap(find.text("Record Today's Treatment"));
    await tester.pumpAndSettle();
    expect(find.text('Record this treatment?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'Given in morning water');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    final body = api.lastBody('$base/5/days');
    expect(body['businessDate'], '2026-10-11');
    expect(body['notes'], 'Given in morning water');
    expect(body['lines'], [
      {'flockId': 7, 'actualQuantity': 1, 'suggestedQuantity': 1, 'notes': 'Morning'},
    ]);
    expect(find.textContaining('Treatment recorded'), findsOneWidget);
  });

  testWidgets('one campaign: treatment days, reverse, complete and cancel', (tester) async {
    final api = api0();
    await open(tester, TreatmentCampaignScreen(session: await sessionFor(api), company: company, campaignId: 5), size: phone);

    await tapText(tester, 'Treatment days (1)');
    await tapText(tester, 'October 10, 2026');
    expect(find.textContaining('“Morning water”'), findsOneWidget);
    expect(find.text('1 L (suggested 1 L) · GHC 20.00'), findsOneWidget);
    await tapText(tester, 'Reverse');
    await reasonOther(tester, 'Wrong day');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$base/days/41/reversal')['reason'], 'Wrong day');

    await tapText(tester, 'Flocks (2)');
    expect(find.text('Campaign dose'), findsOneWidget);
    expect(find.text('0.6 L per 1,000 birds per day'), findsOneWidget);

    await seek(tester, 'Mark completed', up: true);
    await tester.tap(find.text('Mark completed').first);
    await tester.pumpAndSettle();
    expect(find.text('Mark this campaign completed?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark completed'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '$base/5/completion' && w.method == 'PUT'), isTrue);

    await tester.tap(find.text('Cancel campaign').first);
    await tester.pumpAndSettle();
    await reasonOther(tester, 'Vet stopped it');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel campaign'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$base/5/cancellation', 'PUT')['reason'], 'Vet stopped it');
  });

  testWidgets('a closed campaign takes no more treatment', (tester) async {
    final api = api0()..gets['$base/5'] = {...campaign(status: 'Cancelled', lifecycle: 'Cancelled'), 'cancelledBy': 'admin', 'cancelReason': 'Vet stopped it'};
    await open(tester, TreatmentCampaignScreen(session: await sessionFor(api), company: company, campaignId: 5), size: phone);
    expect(find.text('Mark completed'), findsNothing);
    expect(find.textContaining('Cancelled by admin'), findsOneWidget);
    await seek(tester, 'This campaign is cancelled — no more treatment can be recorded on it.');
    expect(find.text("Record Today's Treatment"), findsNothing);
  });

  testWidgets('Inventory Restock Forecast: the new name, Restock to the new purchases page', (tester) async {
    final api = FakeApi()..gets['/api/Poultry/stock-supply'] = [];
    await open(tester, DaysOfSupplyScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('Inventory Restock Forecast'), findsOneWidget);
    expect(find.text('Days of Supply'), findsNothing);
  });
}
