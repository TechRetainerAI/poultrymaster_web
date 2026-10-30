// Restaurant → Money (2026-10-20): Cash Flow, Financial Activity and Profit &
// Loss as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/financial_activity_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_cash_flow_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_profit_loss_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('the three Money rows open native screens; cash by account and the P&L totals', () {
    for (final h in ['/restaurant-cash-flow', '/restaurant-financial-activity', '/restaurant-profit-loss']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final acc = cashByAccount([
      {'accountName': 'Bank', 'amount': -40},
      {'accountName': 'Cash Box', 'amount': 100},
      {'accountName': null, 'amount': 5},
    ]);
    expect([for (final a in acc) (a.name, a.moneyIn, a.moneyOut)], [('Cash Box', 100, 0), ('Unassigned', 5, 0), ('Bank', 0, 40)]);
    final t = restaurantPnlTotals([
      {'section': 'Revenue', 'amount': 1000},
      {'section': 'CostOfSales', 'amount': -400},
      {'section': 'Expenses', 'amount': -250},
      {'section': 'Other', 'amount': -50},
    ], null);
    expect((t.direct, t.operating, t.other, t.total, t.gross, t.operatingProfit, t.net), (400, 250, 50, 700, 600, 350, 300));
    expect(restaurantActivitySourceLink({'sourceType': 'OrderPayment'}), ('/restaurant-payments', 'View payment'));
    expect(restaurantActivitySourceLink({'sourceType': 'Sale'}), isNull);
  });

  testWidgets('Cash Flow: tiles, cash by account, history, and Add Adjustment as owner money or a loan', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/cash-flow'] = {
        'summary': {'moneyIn': 100, 'moneyOut': 40, 'netCashFlow': 60, 'openingCash': 10, 'closingCash': 70,
          'operatingIn': 100, 'operatingOut': 40, 'financingIn': 0, 'financingOut': 0, 'movementCount': 2},
        'rows': [
          {'id': 1, 'rowSource': 'Ledger', 'sourceType': 'OrderPayment', 'flowGroup': 'OperatingIn', 'category': 'Sales',
            'transactionDate': '2026-10-19', 'amount': 100, 'accountName': 'Cash Box', 'description': 'Order #12'},
          {'id': 2, 'rowSource': 'Ledger', 'sourceType': 'Expense', 'flowGroup': 'OperatingOut', 'category': 'Utilities',
            'transactionDate': '2026-10-19', 'amount': -40, 'accountName': 'Bank', 'description': 'Power'},
        ],
      }
      ..gets['/api/Restaurant/finance/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'isActive': true},
      ];
    await open(tester, RestaurantCashFlowScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('What the restaurant received and spent'), findsOneWidget);
    expect(find.text('All accounts, today'), findsOneWidget);
    expect(find.text('LOANS & OWNER MONEY'), findsOneWidget);
    expect(find.text('Cash by account'), findsOneWidget);
    expect(find.text('Order #12'), findsOneWidget);
    expect(find.text('· 2 movements'), findsOneWidget);

    await pick(tester, 'All categories', 'Operating expense');
    expect(find.text('Order #12'), findsNothing);
    await pick(tester, 'Operating expense', 'All categories');

    await tester.tap(find.text('Add Adjustment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What kind of adjustment?'));
    await tester.pumpAndSettle();
    expect(find.text('Opening Balance'), findsNothing, reason: 'the Restaurant offers owner money and loans only');
    expect(find.text('Correction'), findsNothing);
    await tester.tap(find.text('Owner injection').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount *', '500');
    await pick(tester, 'Not linked to an account', 'Cash Box');
    await tester.tap(find.widgetWithText(FilledButton, 'Record injection'));
    await tester.pumpAndSettle();
    final o = api.lastBody('/api/Restaurant/finance/owner-money');
    expect((o['entryType'], o['cashAccountId'], o['amount'], o['ownerName']), ('Contribution', 3, 500, null));

    await tester.tap(find.text('Add Adjustment'));
    await tester.pumpAndSettle();
    await pick(tester, 'What kind of adjustment?', 'Loan received');
    await enter(tester, 'Amount *', '1000');
    await enter(tester, 'Lender *', 'GCB Bank');
    await tester.tap(find.widgetWithText(FilledButton, 'Record loan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose the cash account.'), findsOneWidget, reason: 'the web refuses a loan with no account');
    expect(api.requests.where((r) => r.url.path == '/api/Restaurant/finance/loans'), isEmpty);
    await pick(tester, 'Not linked to an account', 'Cash Box');
    await tester.tap(find.widgetWithText(FilledButton, 'Record loan'));
    await tester.pumpAndSettle();
    final l = api.lastBody('/api/Restaurant/finance/loans');
    expect((l['lenderName'], l['principal'], l['amountReceived'], l['receivedAccountId']), ('GCB Bank', 1000, 1000, 3));
  });

  testWidgets('Financial Activity (Restaurant): its own endpoint, rose links, filters and position detail', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/financial-activity'] = {
        'summary': {'moneyIn': 50, 'moneyOut': 0, 'netCashFlow': 50, 'openingCash': 0, 'closingCash': 50, 'revenue': 0,
          'expense': 0, 'netProfit': 0, 'cashEvents': 1, 'nonCashEvents': 0},
        'rows': [
          {'eventKey': 'p-1', 'occurredAt': '2026-10-19', 'type': 'Order payment', 'category': 'Sales', 'activityType': 'Operating',
            'sourceType': 'OrderPayment', 'moneyIn': 50, 'runningCash': 50, 'isCashActivity': true,
            'positionChanges': [
              {'positionType': 'Cash', 'positionName': 'Till 1', 'increaseAmount': 50, 'decreaseAmount': 0},
            ]},
        ],
      };
    await open(tester, FinancialActivityScreen(session: await sessionFor(api), company: rest, restaurant: true), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/financial-activity'), isTrue);
    expect(api.requests.any((r) => r.url.path == '/api/Poultry/financial-activity'), isFalse);
    expect(find.text('View payment →'), findsOneWidget);
    expect(find.text('1 cash · 0 non-cash events'), findsOneWidget);
    await pick(tester, 'Cash and non-cash', 'Non-cash activity');
    expect(find.text('No activity matches those filters.'), findsOneWidget);
    await tapText(tester, 'Reset filters');
    expect(find.text('View payment →'), findsOneWidget);
  });

  testWidgets('Profit & Loss: KPIs with their arithmetic, the four bands, the margins and the verdict', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/reports/pnl'] = {'revenue': 1000, 'netProfit': 300, 'grossMarginPct': 60, 'netMarginPct': 30,
        'foodCostPct': 40, 'orderCount': 12, 'tipsTotal': 50}
      ..gets['/api/Restaurant/finance/pnl-lines'] = [
        {'section': 'Revenue', 'lineKey': 'food', 'label': 'Food sales', 'amount': 1000},
        {'section': 'CostOfSales', 'lineKey': 'cogs', 'label': 'Food cost', 'amount': -400},
        {'section': 'Expenses', 'lineKey': 'rent', 'label': 'Rent', 'amount': -250},
        {'section': 'Expenses', 'lineKey': 'zero', 'label': 'Marketing', 'amount': 0},
        {'section': 'Other', 'lineKey': 'dep', 'label': 'Depreciation', 'amount': -50},
      ];
    await open(tester, RestaurantProfitLossScreen(session: await sessionFor(api), company: rest), size: tall);
    final q = api.requests.firstWhere((r) => r.url.path == '/api/Restaurant/finance/pnl-lines').url.queryParameters;
    expect(q.keys.toSet(), {'farmId', 'from', 'to'});
    expect(find.text('Did the restaurant make money from its operations this period?'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^The restaurant made a profit of \S+ 300\.00 this period\.$')), findsOneWidget);
    expect(find.text('60% of sales'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\S+ 700\.00$')), findsOneWidget, reason: 'Total expenses');
    expect(find.textContaining(RegExp(r'^\(\S+ 400\.00\)$')), findsNWidgets(2), reason: 'the line and its band total');
    expect(find.text('Marketing'), findsNothing, reason: 'zero lines are left out');
    expect(find.text('Total depreciation & financing'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Net profit'.toUpperCase()), findsOneWidget);
  });
}
