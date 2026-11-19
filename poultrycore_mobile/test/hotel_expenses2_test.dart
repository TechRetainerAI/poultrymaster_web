// Hotel → Sales, Expenses & Money → Expenses: Recurring Expenses, Internal Use
// and Payroll, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_payroll_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_internal_use_screen.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

FakeApi payrollApi() => FakeApi()
  ..gets['/api/Hotel/payroll-runs'] = [
    {'hotelpayrollrunid': 1, 'periodstart': '2026-10-01T00:00:00', 'periodend': '2026-10-31T00:00:00', 'status': 'Draft',
      'totalgrosspay': 1500, 'totaldeductions': 100, 'totalnetpay': 1400, 'cashaccountname': 'Payroll'},
    {'hotelpayrollrunid': 2, 'periodstart': '2026-09-01', 'periodend': '2026-09-30', 'status': 'Approved',
      'totalgrosspay': 1000, 'totaldeductions': 0, 'totalnetpay': 1000, 'cashaccountname': 'Payroll'},
    {'hotelpayrollrunid': 3, 'periodstart': '2026-08-01', 'periodend': '2026-08-31', 'status': 'Paid', 'totalnetpay': 900},
  ]
  ..gets['/api/Hotel/payroll-runs/1'] = {
    'run': {'hotelpayrollrunid': 1, 'periodstart': '2026-10-01', 'periodend': '2026-10-31', 'status': 'Draft', 'totalgrosspay': 1500,
      'totaldeductions': 100, 'totalnetpay': 1400, 'createdby': 'admin', 'createdat': '2026-10-01T09:00:00Z'},
    'items': [
      {'hotelpayrollitemid': 11, 'hotelstaffid': 1, 'staffname': 'Esi Boateng', 'staffrole': 'Housekeeping', 'basicpay': 1500, 'dailywage': 0,
        'commission': 0, 'bonus': 0, 'deductions': 100, 'otherdeductions': 0, 'netpay': 1400, 'paymentmethod': 'Cash'},
    ],
    'deductions': [
      {'hotelPayrollDeductionId': 5, 'hotelPayrollItemId': 11, 'loanNumber': 'LN-1', 'amount': 100, 'status': 'Draft'},
    ],
  }
  ..gets['/api/Hotel/staff'] = [
    {'hotelStaffId': 1, 'firstName': 'Esi', 'lastName': 'Boateng', 'department': 'Housekeeping', 'salaryAmount': 1500},
    {'hotelStaffId': 2, 'firstName': 'Kwame', 'lastName': 'Asante', 'department': 'Front Desk', 'role': 'Receptionist', 'salaryAmount': 1200},
    {'hotelStaffId': 3, 'firstName': 'Ama', 'lastName': 'Owusu', 'department': 'Kitchen', 'salaryAmount': 800},
  ]
  ..gets['/api/Hotel/employee-loans/eligible'] = [
    {'hotelEmployeeLoanId': 9, 'loanNumber': 'LN-9', 'loanType': 'SalaryAdvance', 'outstandingBalance': 600, 'available': 400,
      'suggestedDeduction': 200, 'currentDeduction': 0},
  ]
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Payroll', 'accounttype': 'Bank', 'isactive': true},
  ];

void main() {
  test('the three rows open native screens', () {
    for (final h in ['/hotel-recurring-expenses', '/hotel-internal-use', '/hotel-payroll']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(hotelPayrollLoanTotal({
      'run': {'status': 'Approved'},
      'deductions': [
        {'amount': 100, 'status': 'Posted'},
        {'amount': 50, 'status': 'Reversed'},
      ],
    }), 100);
    expect(hotelPayrollLoanTotal({
      'run': {'status': 'Cancelled'},
      'deductions': [
        {'amount': 50, 'status': 'Reversed'},
      ],
    }), 50, reason: 'on a cancelled run, what was reversed');
  });

  testWidgets('Recurring Expenses reads the Hotel lookups and says posting needs approval', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/finance/expense-categories'] = [
        {'hotelexpensecategoryid': 10, 'name': 'Utilities', 'isactive': true},
      ]
      ..gets['/api/Hotel/suppliers'] = [
        {'hotelSupplierId': 4, 'supplierName': 'CleanCo', 'isActive': true},
      ]
      ..gets['/api/Hotel/finance/cash-accounts'] = [
        {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'isactive': true},
      ];
    await open(tester, RecurringExpensesScreen(session: await sessionFor(api), company: hotel), size: tall);
    for (final p in ['/api/Hotel/finance/expense-categories', '/api/Hotel/suppliers', '/api/Hotel/finance/cash-accounts']) {
      expect(api.requests.any((r) => r.url.path == p), isTrue, reason: p);
    }
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry') || r.url.path == '/api/Supplier'), isFalse);
    expect(find.textContaining('Posted expenses then follow the normal approval on', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Internal Use: Hotel reasons, supplies, itemId on the line, violet', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/internal-usage'] = [
        {'internalUsageId': 1, 'usageDate': '2026-10-10', 'category': 'RoomAmenities', 'status': 'Draft', 'totalCostValue': 20,
          'items': [{'itemType': 'Supply', 'itemId': 4, 'itemName': 'Soap', 'entryQuantity': 8, 'entryUnit': 'pcs', 'entryUnitCost': 2.5}]},
      ]
      ..gets['/api/Hotel/internal-usage/items'] = [
        {'itemType': 'Supply', 'itemId': 4, 'name': 'Soap', 'unit': 'pcs', 'onHand': 50, 'suggestedUnitCost': 2.5},
      ];
    await open(tester, RestaurantInternalUseScreen(session: await sessionFor(api), company: hotel, flavor: hotelInternalUseFlavor), size: tall);
    expect(find.textContaining('Supplies used by the hotel itself'), findsOneWidget);
    expect(find.text('Rooms restocked (amenities)'), findsOneWidget);
    expect(find.text('8 pcs'), findsOneWidget);

    // Edit the draft: the stock line is found by its itemId.
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Soap'), findsWidgets);
    await tester.tap(filled('Save draft'));
    await tester.pumpAndSettle();
    final put = api.writes.lastWhere((w) => w.method == 'PUT');
    expect(put.url.path, '/api/Hotel/internal-usage/1');
    final line = ((jsonDecode(put.body) as Map)['items'] as List).first as Map;
    expect((line['itemType'], line['itemId'], line['ingredientId']), ('Supply', 4, 4));

    await tester.tap(find.byTooltip('Post').first);
    await tester.pumpAndSettle();
    await tester.tap(filled('Post'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Hotel/internal-usage/1/post'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Payroll list: cards, per-status actions, approve, mark paid, cancel', (tester) async {
    final api = payrollApi();
    await open(tester, HotelPayrollScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Total Runs'), findsOneWidget);
    expect(find.text('GH₵ 900.00'), findsNWidgets(2), reason: 'Total Net Paid, and the paid run\'s Net');
    expect(find.text('2026-10-01 — 2026-10-31'), findsOneWidget);
    expect(find.byTooltip('Approve'), findsOneWidget);
    expect(find.byTooltip('Mark Paid'), findsOneWidget);
    expect(find.byTooltip('Reopen to correct'), findsOneWidget);

    await tester.tap(find.byTooltip('Approve'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Hotel/payroll-runs/1/approve'), isTrue);
    await tester.tap(find.byTooltip('Mark Paid'));
    await tester.pumpAndSettle();
    expect(jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Hotel/payroll-runs/2/mark-paid').body), {'farmId': 'h1'});

    await tester.tap(find.byTooltip('Cancel').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Any staff loan repayments it recorded are reversed.'), findsOneWidget);
    await reasonPick(tester, 'Duplicate entry');
    await tester.tap(filled('Cancel Run'));
    await tester.pumpAndSettle();
    expect(jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Hotel/payroll-runs/1/cancel').body),
        {'farmId': 'h1', 'cancelReason': 'Duplicate entry'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('New payroll run posts the period and account', (tester) async {
    final api = payrollApi();
    await open(tester, HotelPayrollScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'New payroll run');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Period start and end are required'), findsOneWidget);
    expect(api.writes.where((w) => w.url.path == '/api/Hotel/payroll-runs'), isEmpty);
  });

  testWidgets('A run: lines with loan deductions, the line form with loans, Add by Department', (tester) async {
    final api = payrollApi();
    await open(tester, HotelPayrollRunScreen(session: await sessionFor(api), company: hotel, runId: 1), size: tall);
    expect(find.text('Status: Draft'), findsOneWidget);
    expect(find.text('Staff loan repayments'), findsOneWidget);
    expect(find.text('recorded when the run is approved'), findsOneWidget);
    expect(find.text('Esi Boateng'), findsOneWidget);
    expect(find.text('LN-1 GH₵ 100.00'), findsOneWidget);
    expect(find.textContaining('staff member(s) not yet added to this run', findRichText: true), findsOneWidget);
    expect(find.text('Front Desk (1)'), findsOneWidget);

    // Pick Kwame: his salary fills Basic Pay and his open loan is listed.
    await pick(tester, '-- Select --', 'Kwame Asante — Receptionist');
    expect(find.textContaining('owes GH₵ 600.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('already on another draft run', findRichText: true), findsOneWidget);
    expect(find.text('Net pay for this line: GH₵ 1000.00'), findsOneWidget, reason: '1200 less the suggested 200');
    await tapText(tester, 'Save Line');
    final body = jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Hotel/payroll-runs/1/items').body) as Map;
    expect((body['hotelStaffId'], body['basicPay'], body['staffName'], body['staffRole']), (2, 1200, 'Kwame Asante', 'Receptionist'));
    expect(body['loanDeductions'], [
      {'loanId': 9, 'amount': 200},
    ]);

    // Add by Department: Kitchen, with the loan capped by the salary.
    await tapText(tester, 'Kitchen (1)');
    final k = jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Hotel/payroll-runs/1/items').body) as Map;
    expect((k['hotelStaffId'], k['basicPay']), (3, 800));
    expect(k['loanDeductions'], [
      {'loanId': 9, 'amount': 200},
    ]);
    expect(tester.takeException(), isNull);
  });
}
