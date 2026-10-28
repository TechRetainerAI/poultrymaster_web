// Hotel → Sales, Expenses & Money → Money: Cash Flow, Financial Activity and
// Profit & Loss, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_cash_flow_screen.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_profit_loss_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/financial_activity_screen.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4200);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

final _pnl = {
  'totalRevenue': 1000, 'totalExpenses': 500, 'totalOtherCosts': 100, 'netProfit': 400, 'roomRevenue': 800, 'restaurantRevenue': 200,
  'depositsNet': 150, 'netMarginPercent': 40,
  'lines': [
    {'section': 'Revenue', 'lineKey': 'RoomRevenue', 'lineLabel': 'Room revenue', 'amount': 800, 'entryCount': 4},
    {'section': 'Revenue', 'lineKey': 'RestaurantSales', 'lineLabel': 'Restaurant sales', 'amount': 200, 'entryCount': 2},
    {'section': 'OperatingExpense', 'lineKey': 'SuppliesUsed', 'lineLabel': 'Supplies used', 'amount': 120, 'entryCount': 3},
    {'section': 'OperatingExpense', 'lineKey': 'StaffWages', 'lineLabel': 'Staff wages', 'amount': 380, 'entryCount': 1},
    {'section': 'OtherCost', 'lineKey': 'Depreciation', 'lineLabel': 'Depreciation', 'amount': 100, 'entryCount': 1},
    {'section': 'OtherCost', 'lineKey': 'Zero', 'lineLabel': 'Nothing', 'amount': 0, 'entryCount': 0},
  ],
};

void main() {
  test('the three rows open native screens; the P&L bands and totals; the Hotel source links', () {
    for (final h in ['/hotel-cash-flow', '/hotel-financial-activity', '/hotel-profit-loss']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final b = hotelPnlBands(_pnl);
    expect((b.revenue.length, b.direct.length, b.operating.length, b.other.length), (2, 1, 1, 1), reason: 'a zero line is left out');
    final t = hotelPnlTotals(_pnl, b);
    expect((t.revenue, t.direct, t.operating, t.other, t.gross, t.operatingProfit, t.net, t.total), (1000, 120, 380, 100, 880, 500, 400, 600));
    expect(hotelActivitySourceLink({'sourceType': 'SupplyPurchase', 'sourceId': 7}), ('/hotel-inventory?purchaseId=7', 'View purchase'));
    expect(hotelActivitySourceLink({'sourceType': 'LoanRepaid'}), ('/hotel-employee-loans', 'View staff loan'));
    expect(hotelActivitySourceLink({'sourceType': 'Unknown'}), isNull);
  });

  testWidgets('Cash Flow: the Hotel tiles and filters, no row editing, Add Adjustment as owner money', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/cash-flow'] = {
        'summary': {'moneyIn': 500, 'moneyOut': 200, 'netCashFlow': 300, 'openingCash': 100, 'closingCash': 400, 'operatingIn': 500,
          'operatingOut': 150, 'financingIn': 0, 'financingOut': 50, 'movementCount': 2},
        'rows': [
          {'id': 1, 'rowSource': 'Payment', 'transactionDate': '2026-10-10', 'category': 'RoomRevenue', 'flowGroup': 'OperatingIn',
            'sourceType': 'GuestPayment', 'amount': 500, 'description': 'Room 4'},
          {'id': 2, 'rowSource': 'Expense', 'transactionDate': '2026-10-11', 'category': 'Utilities', 'flowGroup': 'OperatingOut',
            'sourceType': 'Expense', 'amount': -200, 'description': 'Power'},
        ],
      }
      ..gets['/api/Hotel/finance/cash-accounts'] = [
        {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'isactive': true},
      ];
    await open(tester, HotelCashFlowScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('What the hotel earned and spent'), findsOneWidget);
    for (final t in ['LOANS & OWNER MONEY', 'CLOSING CASH', 'NET CASH FLOW (STRICTLY BUSINESS)', 'CASH AT HAND']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('CUSTOMER BALANCES'), findsNothing, reason: 'the Hotel page has no balance tiles');
    expect(find.byTooltip('Edit this adjustment'), findsNothing);
    expect(find.textContaining('Room 4'), findsWidgets);
    expect(api.requests.where((r) => r.url.path == '/api/Hotel/cash-flow').length, 3, reason: 'the period, the one before, and all time');

    await pick(tester, 'All categories', 'Staff advances out');
    expect(find.textContaining('No cash movement in this period.'), findsOneWidget);
    await pick(tester, 'Staff advances out', 'All categories');

    await tapText(tester, 'Add Adjustment');
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/finance/cash-accounts'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Financial Activity reads /api/Hotel, links to Hotel pages, in violet', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/financial-activity'] = {
        'summary': {'moneyIn': 50, 'moneyOut': 0, 'netCashFlow': 50, 'openingCash': 0, 'closingCash': 50, 'revenue': 50, 'expense': 0,
          'netProfit': 50, 'cashEvents': 1, 'nonCashEvents': 0},
        'rows': [
          {'eventKey': 'g-1', 'occurredAt': '2026-10-19', 'type': 'Guest payment', 'category': 'Rooms', 'activityType': 'Operating',
            'sourceType': 'GuestPayment', 'moneyIn': 50, 'revenue': 50, 'runningCash': 50, 'isCashActivity': true,
            'positionChanges': [
              {'positionType': 'Cash', 'positionName': 'Front desk', 'increaseAmount': 50, 'decreaseAmount': 0},
            ]},
        ],
      };
    await open(tester, FinancialActivityScreen(session: await sessionFor(api), company: hotel, hotel: true), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/financial-activity'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Restaurant') || r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.text('View payment →'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profit & Loss: the Hotel statement, its figures, and a line\'s entries', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/profit-loss'] = _pnl
      ..gets['/api/Hotel/profit-loss/expenses'] = [
        {'hotelExpenseId': 3, 'expenseDate': '2026-10-05T00:00:00', 'category': 'Payroll', 'description': 'October wages', 'amount': 380, 'vendor': 'Staff'},
      ];
    await open(tester, HotelProfitLossScreen(session: await sessionFor(api), company: hotel), size: tall);
    final q = api.requests.firstWhere((r) => r.url.path == '/api/Hotel/profit-loss').url.queryParameters;
    expect(q.containsKey('startDate') && q.containsKey('endDate'), isTrue);
    expect(find.text('Did the hotel make money from its operations this period?'), findsOneWidget);
    expect(find.textContaining('The hotel made a profit of'), findsOneWidget);
    expect(find.text('Supplies used'), findsOneWidget, reason: 'a supply line is a direct cost');
    expect(find.text('Nothing'), findsNothing);
    expect(find.text('Deposits held (not revenue)'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('88% of revenue'), findsOneWidget);

    await tapText(tester, 'Staff wages');
    final d = api.requests.lastWhere((r) => r.url.path == '/api/Hotel/profit-loss/expenses').url.queryParameters;
    expect(d.containsKey('lineKey'), isFalse, reason: 'staff wages drill into every expense');
    expect(find.text('October wages'), findsOneWidget);
    expect(find.textContaining('(1 entry)', findRichText: true), findsOneWidget);
    expect(jsonEncode(d['farmId']), '"h1"');
    expect(tester.takeException(), isNull);
  });
}
