// Poultry → Tools → Flock Alerts, Farm Alerts and Receive Purchase, against a
// fake API, at phone size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_alerts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_alerts_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_alerts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase_receipt_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase_receipts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';

import 'support/harness.dart';

Future<void> seek(WidgetTester tester, String text) async {
  for (final down in [true, false]) {
    for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, down ? -300 : 300));
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

Future<void> typeKey(WidgetTester tester, Key key, String text) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byKey(key), matching: find.byType(TextFormField)).first, text);
  await tester.pumpAndSettle();
}

const alertsBase = '/api/Poultry/flock-alerts';
const receiptsBase = '/api/Poultry/purchase-receipts';

Map<String, dynamic> alert(int id, String status, String severity, {String flock = 'Flock A'}) => {
      'alertId': id, 'flockId': 7, 'flockName': flock, 'houseName': 'House 1', 'businessDate': '2026-10-12T00:00:00',
      'status': status, 'severity': severity, 'peakSeverity': severity, 'activeSignalCount': 1, 'consecutiveDays': 2,
      'noteCount': 0, 'acknowledgedAtUtc': null,
      'signals': [
        {
          'signalKey': 'mortality', 'label': 'Mortality spike', 'isActive': true, 'severity': severity,
          'explanation': ['Today: 9 deaths', 'Normal: 2 a day', 'Alert levels: warning 2.5×', 'Result: 4.5×'],
          'evidence': {'schema': 'poultry.flock-anomaly.v1'},
        },
      ],
    };

Map<String, dynamic> setting() => {
      'signalKey': 'mortality', 'label': 'Mortality spike', 'metricLabel': 'Mortality rate', 'metricUnit': 'birds',
      'direction': 'up', 'guardField': 'currentDeaths', 'guardLabel': 'Min deaths', 'enabled': true, 'method': 'ratio',
      'baselineDays': 14, 'minBaselineDays': 5, 'informationThreshold': null, 'warningThreshold': 2.5, 'criticalThreshold': 4,
      'guardMinimum': 3, 'baselineFloor': 1, 'isCustomised': false,
    };

void main() {
  setUp(LookupLoader.clear);

  group('rules', () {
    test('alerts: the order, the summary and the settings checks', () {
      final sorted = sortAlerts([alert(1, 'Resolved', 'Critical'), alert(2, 'Open', 'Warning'), alert(3, 'Open', 'Critical')]);
      expect([for (final a in sorted) a['alertId']], [3, 2, 1]);
      final s = summarizeAlerts(sorted);
      expect((s.active, s.critical, s.warning), (2, 1, 1));
      expect(thresholdExample(setting()), 'For example, a flock that normally loses 2 birds a day: Warning at 5 birds a day, Critical at 8 birds a day.');
      expect(validateSetting({...setting(), 'criticalThreshold': 2}), 'Critical must be higher than Warning, and both above zero.');
      expect(eventText({'eventType': 'SeverityChanged', 'signalKey': 'mortality', 'details': {'fromSeverity': 'Warning', 'toSeverity': 'Critical'}},
          {'mortality': 'Mortality spike'}), 'Mortality spike: Warning → Critical');
    });

    test('receipts: additional costs by value, the last line takes the pennies; payment fills in order', () {
      final p = previewReceipt([
        const ReceiptLineDraft(itemId: 1, quantity: 3, unitCost: 10),
        const ReceiptLineDraft(itemId: 2, quantity: 1, unitCost: 10, method: 'EXPENSE_WHEN_CONSUMED'),
      ], 1, 35);
      expect(p.total, 41);
      expect(p.lines[0].allocatedAdditional, 0.75);
      expect(p.lines[1].allocatedAdditional, 0.25);
      expect(p.lines[0].paidNow, 30.75);
      expect(p.expenseNow, 30.75);
      expect(p.deferredToConsumption, 10.25);
      expect(p.status, 'Part paid');
      expect(validateReceipt(supplierChosen: false, purchaseDate: '2026-10-13', today: '2026-10-12', lines: const [], additionalCosts: 0, amountPaid: 0), [
        'Choose the supplier you bought from.',
        'The purchase date (2026-10-13) is in the future. Goods can only be received on or before today (2026-10-12).',
        'Add at least one item to the receipt.',
      ]);
    });
  });

  group('Flock Alerts', () {
    FakeApi api0() => FakeApi()
      ..gets[alertsBase] = [alert(1, 'Acknowledged', 'Warning', flock: 'Flock B'), alert(2, 'Open', 'Critical')]
      ..gets['$alertsBase/2'] = {
        'alert': alert(2, 'Open', 'Critical'),
        'events': [
          {'eventId': 1, 'alertId': 2, 'eventType': 'Detected', 'details': {'severity': 'Critical'}, 'actor': 'system', 'atUtc': '2026-10-12T06:00:00Z'},
        ],
      }
      ..gets['$alertsBase/settings'] = [setting()]
      ..gets['$alertsBase/evaluation'] = [
        {'flockId': 7, 'flockName': 'Flock A', 'houseName': 'House 1', 'businessDate': '2026-10-12', 'signalKey': 'mortality',
          'signalLabel': 'Mortality spike', 'metricUnit': 'birds', 'status': 'Fired', 'severity': 'Critical', 'severityRank': 3,
          'currentValue': 9, 'baselineMean': 2, 'observed': 4.5, 'method': 'ratio', 'explanation': ['Today: 9 deaths']},
        {'flockId': 7, 'flockName': 'Flock A', 'houseName': 'House 1', 'businessDate': '2026-10-12', 'signalKey': 'eggs',
          'signalLabel': 'Egg production decline', 'metricUnit': '%', 'status': 'InsufficientBaseline', 'severity': null, 'severityRank': 0,
          'currentValue': 80, 'baselineMean': null, 'observed': null, 'method': 'pctchange', 'explanation': ['Only 2 days of records']},
      ];

    testWidgets('alerts worst first, the filters, an alert acknowledged with a note', (tester) async {
      final api = api0();
      await open(tester, FlockAlertsScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('1 critical · 1 warning · 0 information'), findsOneWidget);
      final first = tester.getTopLeft(find.text('Flock A · House 1')).dy;
      expect(first < tester.getTopLeft(find.text('Flock B · House 1')).dy, isTrue, reason: 'Open before Acknowledged');
      expect(find.text('Today: 9 deaths · Normal: 2 a day'), findsNWidgets(2));

      await tapText(tester, 'Resolved');
      expect(api.requests.lastWhere((r) => r.url.path == alertsBase).url.queryParameters['status'], 'Resolved');
      await tapText(tester, 'Needs attention');

      await tapText(tester, 'Flock A · House 1');
      expect(find.text('Why it fired'), findsOneWidget);
      await seek(tester, 'Detected — Critical');
      await tapText(tester, 'Resolve');
      expect(find.textContaining('Say what was found or done before resolving.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Checked the drinkers');
      await tapText(tester, 'Acknowledge');
      expect(api.lastBody('$alertsBase/2/acknowledge')['note'], 'Checked the drinkers');
    });

    testWidgets('re-check, daily checks and a setting saved', (tester) async {
      final api = api0();
      await open(tester, FlockAlertsScreen(session: await sessionFor(api), company: company), size: phone);
      await tapText(tester, 'Re-check');
      final scan = api.lastBody('$alertsBase/scan');
      expect(DateTime.parse(scan['to']).difference(DateTime.parse(scan['from'])).inDays, 13);

      await tapText(tester, 'Daily checks');
      expect(find.text('Not enough history'), findsOneWidget);
      expect(find.text('9 vs 2 birds · 4.5×'), findsOneWidget);
      await tapText(tester, 'Egg production decline');
      expect(find.text('Only 2 days of records'), findsOneWidget);

      await tapText(tester, 'Alerts');
      await tapText(tester, 'Alert settings');
      expect(find.text('Only alert if at least this many birds died'), findsOneWidget);
      await typeKey(tester, const ValueKey('setting-mortality-criticalThreshold'), '5');
      expect(find.textContaining('Critical at 10 birds a day'), findsOneWidget);
      await tapText(tester, 'Advanced — how “normal” is worked out');
      await pickOption(tester, 'Times normal (×)', 'Percent above or below normal (%)');
      expect(find.text('Warning (%)'), findsOneWidget);
      await tapText(tester, 'Save');
      final body = api.lastBody('$alertsBase/settings', 'PUT');
      expect(body['criticalThreshold'], 5);
      expect(body['method'], 'pctchange');
      expect(body['farmId'], 'farm-1');
    });
  });

  testWidgets('Farm Alerts: the status line, the four tiles and the three cards', (tester) async {
    final api = FakeApi()
      ..gets['/api/ActivityChecks'] = {
        'businessDate': '2026-10-12', 'companyToday': '2026-10-12',
        'checks': [
          {'key': 'poultry.production.daily', 'status': 'Incomplete', 'severity': 'Warning', 'expectedCount': 4, 'completedCount': 3,
            'outstandingCount': 1, 'counters': {'backlogDates': 0, 'backlogFlockDays': 2}, 'items': []},
          {'key': 'poultry.eggs.unsorted', 'status': 'Incomplete', 'outstandingCount': 1, 'counters': {'eggs': 600}},
        ],
      }
      ..gets[alertsBase] = [alert(2, 'Open', 'Critical')]
      ..gets['/api/Poultry/stock-supply'] = [
        {'poultryRawMaterialItemId': 1, 'itemName': 'Layer Mash', 'unitOfMeasure': 'kg', 'currentQuantity': 50, 'avgDailyUsage': 25,
          'daysOfSupply': 2, 'status': 'Critical', 'severityRank': 1, 'warningDays': 7, 'estimatedStockout': '2026-10-14'},
        {'poultryRawMaterialItemId': 2, 'itemName': 'Salt', 'unitOfMeasure': 'kg', 'currentQuantity': 50, 'status': 'Healthy', 'severityRank': 5},
      ];
    await open(tester, FarmAlertsScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('6 things need your attention.'), findsOneWidget, reason: '1 today + 2 earlier + 1 unsorted day + 1 alert + 1 stock');
    expect(find.text('3 missing'), findsOneWidget);
    expect(find.text('Today 3 / 4 recorded · 2 earlier'), findsOneWidget);
    expect(find.text('600 eggs'), findsOneWidget);
    expect(find.text('1 alert'), findsOneWidget);
    expect(find.text('1 running low'), findsOneWidget);

    await tapText(tester, 'Complete Missing Production');
    expect(find.text('Farm Completeness'), findsWidgets, reason: 'the compact card leads to the full page');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await seek(tester, '50 kg in stock · using about 25 kg a day · Estimated stock-out: Oct 14');
    expect(find.textContaining('Layer Mash', findRichText: true), findsOneWidget);
    expect(find.textContaining('· 1 critical', findRichText: true), findsOneWidget);
    expect(find.textContaining('1 healthy', findRichText: true), findsOneWidget);
    expect(find.text('50 kg in stock · using about 25 kg a day · Estimated stock-out: Oct 14'), findsOneWidget);
  });

  group('Receive Purchase', () {
    FakeApi api0() => FakeApi()
      ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-12'}
      ..gets[receiptsBase] = [
        {'poultryPurchaseReceiptId': 3, 'receiptNumber': 'PR-0003', 'supplierName': 'Agro Ltd', 'purchaseDate': '2026-10-10',
          'referenceNo': 'INV-9', 'totalCost': 500, 'amountPaid': 200, 'balance': 300, 'paymentStatus': 'Part paid', 'isOverdue': true,
          'status': 'Posted', 'itemSummary': 'Maize', 'deferredCost': 100, 'lineCount': 1},
        {'poultryPurchaseReceiptId': 2, 'receiptNumber': 'PR-0002', 'supplierName': 'Feeds Co', 'purchaseDate': '2026-10-01',
          'totalCost': 80, 'amountPaid': 80, 'balance': 0, 'paymentStatus': 'Paid', 'status': 'Posted', 'itemSummary': 'Salt', 'deferredCost': 0},
      ]
      ..gets['$receiptsBase/3'] = {
        'poultryPurchaseReceiptId': 3, 'receiptNumber': 'PR-0003', 'supplierName': 'Agro Ltd', 'purchaseDate': '2026-10-10',
        'totalCost': 500, 'amountPaid': 200, 'balance': 300, 'paymentStatus': 'Part paid', 'status': 'Posted', 'amountPaidAtReceipt': 200,
        'cashAccountName': 'Main Cash Account', 'paymentMethod': 'Cash', 'poultrySupplierPaymentId': 12, 'deferredCost': 100, 'lineCount': 1,
        'lines': [
          {'poultryPurchaseReceiptLineId': 1, 'itemName': 'Maize', 'quantity': 10, 'unitCost': 50, 'lineTotal': 500, 'allocatedAdditionalCost': 0,
            'recognitionLabel': 'Expensed as paid', 'consumedQuantity': 2, 'balance': 300},
        ],
      }
      ..gets['/api/Poultry/raw-material-items'] = [
        {'poultryRawMaterialItemId': 5, 'itemName': 'Maize', 'unitOfMeasure': 'kg', 'purchaseUnitOfMeasure': 'Bag', 'isActive': true,
          'effectiveCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED'},
      ]
      ..gets['/api/Poultry/cash-accounts'] = [
        {'poultryCashAccountId': 2, 'accountName': 'Main Cash Account', 'isActive': true, 'currentBalance': 1000},
      ]
      ..gets['/api/Supplier'] = [
        {'supplierId': 9, 'name': 'Agro Ltd'},
      ]
      ..writeAnswers[receiptsBase] = {'poultryPurchaseReceiptId': 3, 'receiptNumber': 'PR-0004', 'lineCount': 1, 'totalCost': 520, 'paymentStatus': 'Part paid'}
      ..writeAnswers['$receiptsBase/3/reverse'] = {'linesReversed': 1};

    testWidgets('the list: tiles, the status filter and a receipt opened and reversed', (tester) async {
      final api = api0();
      await open(tester, PurchaseReceiptsScreen(session: await sessionFor(api), company: adminCompany), size: phone);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('GHC 300.00'), findsWidgets, reason: 'owed to suppliers');
      expect(find.text('PR-0002 · Feeds Co'), findsOneWidget);
      await pickOption(tester, 'All receipts', 'With a balance');
      expect(find.text('PR-0002 · Feeds Co'), findsNothing);

      await tapText(tester, 'PR-0003 · Agro Ltd');
      expect(find.textContaining('paid on receipt from Main Cash Account (Cash) — supplier payment #12'), findsOneWidget);
      expect(find.text('2 used'), findsOneWidget);
      await tapText(tester, 'Reverse receipt');
      await reasonOther(tester, 'Wrong supplier');
      await tester.tap(find.widgetWithText(FilledButton, 'Reverse receipt'));
      await tester.pumpAndSettle();
      expect(api.lastBody('$receiptsBase/3/reverse')['reason'], 'Wrong supplier');
    });

    testWidgets('receive: a known supplier, one line with transport, part paid; the full post body', (tester) async {
      final api = api0();
      await open(tester, PurchaseReceiptsScreen(session: await sessionFor(api), company: adminCompany), size: phone);
      await tapText(tester, 'Receive purchase');
      await seek(tester, 'Paid in full');

      Future<void> save() async {
        await seek(tester, 'Cancel');
        final button = find.widgetWithText(FilledButton, 'Receive purchase');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await save();
      expect(find.text('Choose the supplier you bought from.'), findsOneWidget, reason: 'the checks show on Save');

      await seek(tester, 'Supplier *');
      await tester.enterText(find.byType(TextFormField).first, 'Agro Ltd');
      await tester.pumpAndSettle();
      await pickOption(tester, 'Pick item', 'Maize (kg)');
      expect(find.text('Expensed as paid'), findsOneWidget);
      await typeKey(tester, const ValueKey('qty-1'), '10');
      await typeKey(tester, const ValueKey('cost-1'), '50');
      await typeKey(tester, const ValueKey('upu-1'), '50');
      expect(find.text('Adds 500 kg to stock.'), findsOneWidget);
      await seek(tester, 'Amount');
      await enter(tester, 'Amount', '20');
      await tester.pumpAndSettle();
      await tapText(tester, 'Part payment');
      await enter(tester, 'Amount paid now *', '200');
      await tester.pumpAndSettle();
      await pickOption(tester, 'Cash', 'MoMo');
      await seek(tester, 'Owed to supplier');
      expect(find.text('GHC 320.00'), findsOneWidget, reason: '520 total, 200 paid');

      await save();
      final body = api.lastBody(receiptsBase);
      expect(body['supplierId'], 9);
      expect(body['supplierName'], isNull);
      expect(body['purchaseDate'], '2026-10-12');
      expect(body['additionalCosts'], 20);
      expect(body['amountPaid'], 200);
      expect(body['paymentMethod'], 'MoMo');
      expect(body['cashAccountId'], 2);
      expect((body['clientRequestId'] as String).length, 36);
      expect(body['lines'], [
        {'poultryRawMaterialItemId': 5, 'quantity': 10, 'unitCost': 50, 'productionUnit': 'kg', 'productionUnitsPerPurchaseUnit': 50, 'notes': null},
      ]);
      expect(find.textContaining('Received as PR-0004'), findsOneWidget);
      // As on the web, the saved receipt opens straight away.
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the receipt dialog opens after saving');
      expect(find.text('PR-0003'), findsWidgets);
      expect(find.text('Expensed as paid'), findsOneWidget);
      expect(find.text('Reverse receipt'), findsOneWidget);
    });

    testWidgets("Supply Purchases' Receive Invoice link opens the native form", (tester) async {
      final api = api0();
      final screen = moneyScreenForHref('/poultry-purchase-receipts?receive=1', await sessionFor(api), adminCompany);
      expect(screen, isA<PurchaseReceiptsScreen>());
      await open(tester, screen!, size: phone);
      expect(find.byType(ReceivePurchaseScreen), findsOneWidget, reason: 'the receive form is open');
    });
  });
}
