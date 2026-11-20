// Generic → Admin at phone width: the menu (sidebar.tsx genericAdminItems),
// Setup (app/generic-setup), the setup wizard, Settings (app/generic-settings),
// the Reports hub and its 13 reports, each against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/generic_reports_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_settings_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_setup_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_setup_wizard_screen.dart';
import 'package:poultrycore_mobile/pages/generic/reports/generic_report_screens.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Gym', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

/// Phone width, tall enough that a whole page is built at once.
const tall = Size(360, 2600);

Map<String, dynamic> _modules({bool products = true, bool subscriptions = true}) => {
      'farmId': 'g1',
      for (final k in genericModuleKeys) k: true,
      'enableProducts': products,
      'enableSubscriptions': subscriptions,
    };

final _business = {
  'farmId': 'g1', 'defaultBillingFrequency': 'Monthly', 'defaultPaymentDueDays': 7,
  'autoGenerateInvoices': true, 'autoPostInvoices': false,
  'showMrr': true, 'showBurnRate': true, 'showBreakEvenCustomers': true, 'showCustomerBalances': true,
  'showSupplierBalances': true, 'showCalculatedCashAtHand': true, 'showInventoryCards': false,
};

FakeApi _api({String? industry = 'Gym', bool products = true}) => FakeApi()
  ..gets['$base/module-settings'] = _modules(products: products)
  ..gets['$base/business-settings'] = _business
  ..gets['$base/business-template'] = {
    'farmId': 'g1',
    'genericIndustryTemplate': industry,
    'genericBusinessTemplate': industry == null ? null : businessTemplateFor(industry),
  }
  ..gets['/api/business-categories'] = [
    {'businessCategoryId': 3, 'name': 'Services Business', 'sortOrder': 1, 'isActive': true},
    {'businessCategoryId': 9, 'name': 'Other', 'sortOrder': 9, 'isActive': true},
  ]
  ..gets['/api/Company/timezone'] = {'timeZone': 'Africa/Accra'};

/// Builds [f] if the list has scrolled it away: back to the top, then down.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) return;
  final list = find.byType(Scrollable).first;
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 300, scrollable: list);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _reveal(tester, f);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, Finder field, String option) async {
  await _tap(tester, field);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    LookupLoader.clear();
    invalidateGenericModules();
  });

  test('Admin is Reports, Setup, Business Features, Settings; the old Setup rows left More pages', () {
    final groups = webNavGroups['generic']!;
    final admin = groups.firstWhere((g) => g.title == 'Admin');
    expect([for (final l in admin.subGroups.single.links) (l.label, l.href)], [
      ('Reports', '/generic-reports'),
      ('Setup', '/generic-setup'),
      ('Business Features', '/generic-business-features'),
      ('Settings', '/generic-settings'),
    ]);
    final more = groups.firstWhere((g) => g.title == 'More pages').subGroups.single.links.map((l) => l.href);
    expect(more, isNot(contains('/generic-setup')));
    expect(more, isNot(contains('/generic-setup/wizard')));
    for (final href in ['/generic-reports', '/generic-setup', '/generic-settings', '/generic-reports/mrr']) {
      expect(pageScreens[href], isNotNull, reason: href);
    }
  });

  test('labels follow template-labels.ts', () {
    final gym = genericLabels('Gym');
    expect((gym.customerPlural, gym.invoicePlural, gym.customerBalance), ('Members', 'Membership Bills', 'Member Balances'));
    final school = genericLabels('School');
    expect((school.customer, school.customerBalance, school.overdueCustomer), ('Student', 'Outstanding Fees', 'Overdue Student / Parent'));
    expect(genericLabels(null).subscription, 'Subscription / Contract');
    expect(genericLabels('Retail').planPlural, 'Service / Plans');
    expect(genericLabels('CleaningService').subscriptionPlural, 'Service Contracts');
    expect(genericBusinessTypes.length, 25);
    expect(genericLabels('CarDealership').invoicePlural, 'Vehicle Invoices');
    expect(genericLabels('Freelancer').customerPlural, 'Clients');
    expect(businessTemplateFor('Barbershop'), 'GeneralBusiness');
    expect(businessTemplateFor('Pharmacy'), 'RetailBusiness');
    expect(legacyCategoryIdFor('Grocery', [{'businessCategoryId': 4, 'name': 'Retail Shop'}]), 4);
    expect(legacyCategoryIdFor('Gym', [{'businessCategoryId': 3, 'name': 'Services Business'}]), 3);
    expect(legacyCategoryIdFor('School', [{'businessCategoryId': 9, 'name': 'Other'}]), 9);
  });

  testWidgets('Settings: the Gym words, a module switch and the frequency, saved together', (tester) async {
    final api = _api();
    final s = await sessionFor(api);
    await open(tester, GenericSettingsScreen(session: s, company: generic), size: tall);
    expect(find.text('Memberships'), findsOneWidget); // the Subscriptions switch, in the gym's words
    expect(find.text('Membership defaults'), findsOneWidget);
    expect(find.text('Approve membership bills as they are raised'), findsOneWidget);
    // The hint follows the switch.
    expect(find.text('A billing run leaves drafts for someone to approve. Nothing is owed until they do.'), findsOneWidget);
    await _pick(tester, find.text('Every month'), 'Every term (4 months)');
    final products = find.ancestor(of: find.text('A catalogue of things you sell'), matching: find.byType(GenericToggle));
    await tester.ensureVisible(products);
    await tester.tap(find.descendant(of: products, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Save changes'));
    final m = api.lastBody('$base/module-settings', 'PUT');
    expect((m['enableProducts'], m.containsKey('farmId')), (false, false));
    expect(api.lastBody('$base/business-settings', 'PUT')['defaultBillingFrequency'], 'Termly');
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets('Setup: preselects the type, saves the profile then stamps the template', (tester) async {
    final api = _api()
      ..gets[base] = {
        'genericCompanyProfileId': 1, 'farmId': 'g1', 'defaultCurrency': 'GHS', 'openingCashBalance': 250,
        'ownerName': 'Kofi Asante', 'businessStartDate': '2026-01-05T00:00:00', 'createdAt': '2026-01-05',
      }
      ..writeAnswers['/api/generic-company/setup'] = {'genericCompanyProfileId': 1, 'farmId': 'g1'};
    final s = await sessionFor(api);
    await open(tester, GenericSetupScreen(session: s, company: generic), size: tall);
    expect(find.text('Business profile'), findsOneWidget);
    expect(find.text('Already set up'), findsOneWidget);
    expect(find.text('Gym / fitness centre — Members on monthly or annual memberships'), findsOneWidget);
    expect(find.text('Opening cash (GHS)'), findsOneWidget);
    await _pick(tester, find.text('Gym / fitness centre — Members on monthly or annual memberships'),
        'School / training centre — Students, termly fees, fee notes');
    await _tap(tester, find.text('Save changes'));
    final body = api.lastBody('/api/generic-company/setup');
    // School maps to the legacy "School" category; it is not in the list, so "Other".
    expect((body['businessCategoryId'], body['ownerName'], body['openingCashBalance'], body['businessStartDate']),
        (9, 'Kofi Asante', 250.0, '2026-01-05'));
    expect(api.lastBody('$base/business-template'), {'businessTemplate': 'SubscriptionServiceBusiness', 'industryTemplate': 'School'});
    expect(find.textContaining('Setup updated', findRichText: true), findsOneWidget);
  });

  testWidgets('Setup: a company with no profile asks to set up', (tester) async {
    final api = _api(industry: null)..statuses[base] = 404;
    final s = await sessionFor(api);
    await open(tester, GenericSetupScreen(session: s, company: generic), size: tall);
    expect(find.text('Set up your business'), findsOneWidget);
    expect(find.text('Set up & continue'), findsOneWidget);
    expect(find.text('Choose…'), findsOneWidget);
  });

  testWidgets('Wizard: welcome, search and kinds, apply (creating the profile), the shop handover', (tester) async {
    final api = _api(industry: null)..statuses[base] = 404;
    final s = await sessionFor(api);
    await open(tester, GenericSetupWizardScreen(session: s, company: generic), size: tall);
    expect(find.text('Welcome to VisibilityCore'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('wizard-start')));
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-create')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('wizard-cat-service')));
    expect(find.text('Barbershop'), findsOneWidget);
    expect(find.text('Bakery'), findsNothing, reason: 'Bakery is a shop');
    await _tap(tester, find.byKey(const ValueKey('wizard-cat-all')));
    await tester.enterText(find.byKey(const ValueKey('wizard-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No business types match'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('wizard-search')), 'bread');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Bakery'));
    expect(find.textContaining('recommended features for'), findsWidgets);
    await _tap(tester, find.byKey(const ValueKey('wizard-create')));
    expect(api.lastBody('/api/generic-company/setup'), {'farmId': 'g1'});
    expect(api.lastBody('$base/business-template'), {'businessTemplate': 'RetailBusiness', 'industryTemplate': 'Bakery'});
    expect(api.writes.where((w) => w.url.path == '$base/module-settings'), isEmpty, reason: 'no feature step any more');
    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('Add products'), findsOneWidget);
    expect(find.text('Record a sale'), findsOneWidget);
    expect(find.text('Go to dashboard'), findsOneWidget);
  });

  testWidgets('Wizard: a type picked at creation is applied without asking; a templated company is left alone', (tester) async {
    final api = _api(industry: null);
    await open(tester, GenericSetupWizardScreen(session: await sessionFor(api), company: generic, industry: 'Agency'), size: tall);
    expect(api.lastBody('$base/business-template'), {'businessTemplate': 'SubscriptionServiceBusiness', 'industryTemplate': 'Agency'});
    expect(find.text('Welcome to VisibilityCore'), findsNothing);

    final done = _api();
    await open(tester, GenericSetupWizardScreen(session: await sessionFor(done), company: generic), size: tall);
    expect(done.writes, isEmpty);
    expect(find.text('Welcome to VisibilityCore'), findsNothing);
  });

  testWidgets('Reports hub: a gym sees its subscription reports in its words', (tester) async {
    final s = await sessionFor(_api());
    await open(tester, GenericReportsScreen(session: s, company: generic), size: phone);
    expect(find.text('MEMBERSHIP REPORTS'), findsOneWidget);
    expect(find.text('Membership revenue'), findsOneWidget);
    expect(find.text('Unpaid members'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Member Balances report'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Member Balances report'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Inventory value'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('PRODUCTS & STOCK'), findsOneWidget);
  });

  testWidgets('Reports hub: a shop with Products off sees Money only', (tester) async {
    final api = _api(industry: 'Retail', products: false)
      ..gets['$base/module-settings'] = _modules(products: false, subscriptions: false);
    final s = await sessionFor(api);
    await open(tester, GenericReportsScreen(session: s, company: generic), size: phone);
    expect(find.textContaining('REPORTS', findRichText: true), findsNothing);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('Customer Balances report'), findsOneWidget);
    expect(find.text('PRODUCTS & STOCK'), findsNothing);
  });

  testWidgets('Reports hub: a card opens its native report', (tester) async {
    final api = _api()..gets['$base/reports/mrr'] = [];
    final s = await sessionFor(api);
    await open(tester, GenericReportsScreen(session: s, company: generic), size: tall);
    await _tap(tester, find.text('Monthly recurring revenue'));
    expect(find.byType(GenericMrrScreen), findsOneWidget);
    expect(find.text('No months in this range.'), findsOneWidget);
  });

  group('reports render their web layout', () {
    final month = {'monthStart': '2026-09-01'};
    final cases = <(String, Widget Function(dynamic, Company), Map<String, Object?>, List<String>)>[
      ('P&L', (s, c) => GenericPeriodPnlScreen(session: s, company: c), {
        '$base/reports/period-pnl': {'totalIncome': 5000, 'totalExpenses': 2000, 'costOfGoodsSold': 0, 'grossProfit': 5000,
          'netProfit': 3000, 'profitMarginPct': 60, 'totalPurchasesPaid': 0, 'salesCount': 12},
        '$base/reports/income-split': {'subscriptionIncome': 4000, 'otherIncome': 1000, 'totalIncome': 5000},
      }, ['Period P&L', 'MEMBERSHIP INCOME', '80.0%', '60.0%']),
      ('Cash summary', (s, c) => GenericCashSummaryScreen(session: s, company: c), {
        '$base/reports/cash-summary': {'totalCashAtHand': 900, 'accounts': [
          {'genericCashAccountId': 1, 'accountName': 'Main Cash Box', 'accountType': 'Cash', 'periodCashIn': 500,
            'periodCashOut': 100, 'currentBalance': 900, 'isActive': true},
        ]},
      }, ['Cash summary', 'Main Cash Box', 'Active']),
      ('Expense report', (s, c) => GenericExpenseReportScreen(session: s, company: c), {
        '$base/reports/expense-report': {
          'byCategory': [{'categoryName': 'Rent', 'expenseCount': 1, 'totalAmount': 800}],
          'bySupplier': [{'supplierName': 'Landlord', 'genericSupplierId': 4, 'expenseCount': 1, 'totalAmount': 800, 'amountPaid': 600, 'outstanding': 200}],
          'trend': [{...month, 'expenseCount': 1, 'totalAmount': 800, 'recurringAmount': 800, 'staffAmount': 0}],
        },
      }, ['Rent', 'Landlord', '100.0% of spend', 'Sep 2026']),
      ('Staff cost', (s, c) => GenericStaffCostScreen(session: s, company: c), {
        '$base/reports/staff-cost': {
          'byPerson': [{'staffName': 'Abena Mensah', 'staffRole': 'Cashier', 'paymentCount': 2, 'staffPayments': 300,
            'payrollPay': 700, 'totalPaid': 1000, 'lastPaymentDate': '2026-09-28'}],
          'byMonth': [{...month, 'peoplePaid': 1, 'staffPayments': 300, 'payrollPay': 700, 'totalPaid': 1000}],
          'byRole': [{'staffRole': 'Cashier', 'peopleCount': 1, 'totalPaid': 1000, 'pctOfTotal': 100}],
        },
      }, ['Staff & contractor cost', 'Abena Mensah', '1 month(s) with pay']),
      ('Subscription revenue', (s, c) => GenericSubscriptionRevenueScreen(session: s, company: c), {
        '$base/reports/subscription-revenue': {
          'byMonth': [{...month, 'invoiceCount': 3, 'invoicedAmount': 600, 'collectedAmount': 400, 'outstanding': 200,
            'activeMrr': 600, 'newCount': 1, 'lostCount': 0}],
          'byPlan': [{'serviceName': 'Monthly membership', 'billingFrequency': 'Monthly', 'activeSubscriptions': 3, 'activeMrr': 600}],
          'byCustomer': [],
        },
      }, ['Membership revenue', 'Monthly membership', '3 membership bills', 'No members billed in this range.']),
      ('MRR', (s, c) => GenericMrrScreen(session: s, company: c), {
        '$base/reports/mrr': [
          {'monthStart': '2026-08-01', 'activeMrr': 400, 'activeCount': 2, 'newMrr': 0, 'lostMrr': 0, 'netMrrChange': 0},
          {...month, 'activeMrr': 600, 'activeCount': 3, 'newMrr': 200, 'newCount': 1, 'lostMrr': 0, 'netMrrChange': 200},
        ],
      }, ['MRR NOW', 'ACTIVE MEMBERSHIPS', '+50.0%', 'not tracked']),
      ('Customer payments', (s, c) => GenericCustomerPaymentsReportScreen(session: s, company: c), {
        '$base/balances/customer-payments': [
          {'paymentId': 7, 'paymentNumber': 'PAY-7', 'paymentDate': '2026-09-03', 'partyId': 2, 'partyName': 'Yaw Boateng',
            'paymentMethod': 'MoMo', 'allocationCount': 1, 'totalAmount': 200, 'status': 'Posted'},
          {'paymentId': 8, 'paymentDate': '2026-09-04', 'partyName': 'Esi', 'totalAmount': 50, 'status': 'Reversed'},
        ],
      }, ['Member payments', 'PAY-7', 'Yaw Boateng', 'MoMo', 'Excluded from the total']),
      ('Unpaid', (s, c) => GenericUnpaidCustomersScreen(session: s, company: c), {
        '$base/balances/customer-balances': [
          {'partyId': 2, 'partyName': 'Yaw Boateng', 'contactPhone': '0244000000', 'openDocumentCount': 2,
            'totalBalance': 300, 'overdueAmount': 100, 'paymentTermsDays': 7},
        ],
      }, ['Unpaid members', 'Yaw Boateng', '0244000000', '7d', 'Overdue only']),
      ('Hosting', (s, c) => GenericHostingCostScreen(session: s, company: c), {
        '$base/reports/hosting-cost': {
          'months': [{...month, 'hostingCost': 100, 'expenseCount': 1, 'totalRevenue': 1000, 'pctOfRevenue': 10, 'totalExpenses': 500, 'pctOfExpenses': 20}],
          'categories': [
            {'genericExpenseCategoryId': 5, 'categoryName': 'Cloud hosting', 'totalAmount': 1200, 'isSuggested': true},
            {'genericExpenseCategoryId': 6, 'categoryName': 'Rent', 'totalAmount': 9600, 'isSuggested': false},
          ],
        },
      }, ['Hosting & cloud cost', 'Cloud hosting', '10.0%', 'WHICH CATEGORIES COUNT']),
      ('Break-even', (s, c) => GenericBreakEvenScreen(session: s, company: c), {
        '$base/reports/break-even': {'breakEvenCustomers': 36, 'activeCustomers': 40, 'activeSubscriptions': 40,
          'customerSurplus': 4, 'monthlySurplus': 200, 'monthlyFixedCosts': 1800, 'monthlyRecurringRevenue': 2000,
          'avgRevenuePerCustomer': 50, 'monthsAveraged': 3, 'periodStart': '2026-07-01', 'periodEnd': '2026-09-30'},
      }, ['MEMBERS NEEDED', 'SURPLUS', '36 members', 'THE ARITHMETIC', 'The last 3 complete months']),
      ('Sales by product', (s, c) => GenericSalesByProductScreen(session: s, company: c), {
        '$base/reports/sales-by-product': [
          {'genericProductId': 1, 'productName': 'Towel', 'sku': 'TW-1', 'totalQuantity': 4, 'totalRevenue': 80, 'totalCost': 30, 'salesCount': 3},
        ],
      }, ['Sales by product', 'Towel', 'TW-1']),
      ('Sales by customer', (s, c) => GenericSalesByCustomerScreen(session: s, company: c), {
        '$base/reports/sales-by-customer': [],
      }, ['Sales by customer', 'No sales in this period.']),
      ('Inventory value', (s, c) => GenericInventoryValueScreen(session: s, company: c), {
        '$base/reports/inventory-value': {'totalCostValue': 300, 'totalRetailValue': 500, 'productCount': 4, 'byCategory': [
          {'genericProductCategoryId': 1, 'categoryName': 'Merch', 'productCount': 4, 'totalUnits': 20, 'totalCostValue': 300, 'totalRetailValue': 500},
        ]},
      }, ['Inventory value', 'Merch', 'TOTAL RETAIL VALUE']),
    ];

    for (final (name, build, gets, texts) in cases) {
      testWidgets(name, (tester) async {
        final api = _api();
        gets.forEach((k, v) => api.gets[k] = v);
        final s = await sessionFor(api);
        await open(tester, build(s, generic), size: tall);
        for (final t in texts) {
          final f = find.textContaining(t, findRichText: true);
          await _reveal(tester, f);
          expect(f, findsWidgets, reason: '$name: $t');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Hosting: unticking a category sends the owner\'s choice; none sends useSuggested=false', (tester) async {
    final api = _api()
      ..gets['$base/reports/hosting-cost'] = {
        'months': [],
        'categories': [
          {'genericExpenseCategoryId': 5, 'categoryName': 'Cloud hosting', 'totalAmount': 1200, 'isSuggested': true},
          {'genericExpenseCategoryId': 6, 'categoryName': 'CDN', 'totalAmount': 100, 'isSuggested': false},
        ],
      };
    final s = await sessionFor(api);
    await open(tester, GenericHostingCostScreen(session: s, company: generic), size: tall);
    Uri last() => api.requests.lastWhere((r) => r.url.path == '$base/reports/hosting-cost').url;
    expect(last().queryParametersAll.containsKey('categoryIds'), isFalse); // first load: the suggestion
    await _tap(tester, find.text('CDN'));
    await _tap(tester, find.text('Run'));
    expect(last().queryParametersAll['categoryIds'], ['5', '6']);
    await _tap(tester, find.text('CDN'));
    await _tap(tester, find.text('Cloud hosting'));
    await _tap(tester, find.text('Run'));
    expect(last().queryParameters['useSuggested'], 'false');
  });

  testWidgets('Unpaid: the Show filter and Break-even: the months go to the API', (tester) async {
    final api = _api()
      ..gets['$base/balances/customer-balances'] = []
      ..gets['$base/reports/break-even'] = {'breakEvenCustomers': 0, 'customerSurplus': 0};
    final s = await sessionFor(api);
    await open(tester, GenericUnpaidCustomersScreen(session: s, company: generic), size: tall);
    Uri last(String p) => api.requests.lastWhere((r) => r.url.path == p).url;
    expect(last('$base/balances/customer-balances').queryParameters['status'], 'Overdue');
    await _pick(tester, find.text('Overdue only'), 'Part paid');
    await _tap(tester, find.text('Run'));
    expect(last('$base/balances/customer-balances').queryParameters['status'], 'Partial');
    expect(find.text('Nothing outstanding. Every membership bill in this range is settled.'), findsOneWidget);

    await open(tester, GenericBreakEvenScreen(session: s, company: generic), size: tall);
    expect(last('$base/reports/break-even').queryParameters['months'], '3');
    await _pick(tester, find.text('The last 3 complete months'), 'The last 12 complete months');
    await _tap(tester, find.text('Run'));
    expect(last('$base/reports/break-even').queryParameters['months'], '12');
    expect(find.text('Not enough data yet'), findsOneWidget);
  });
}
