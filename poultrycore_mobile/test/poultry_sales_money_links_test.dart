// Links inside the Sales, Expenses & Money pages open native screens: the
// Products link (Internal Use, Inventory) opens the same list the sidebar
// does, and /poultry-payroll/{id} opens the run's page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/list_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/payroll_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_routes.dart';
import 'package:poultrycore_mobile/pages/web_page_screen.dart';

import 'support/harness.dart';

void main() {
  test('a payroll run link opens the run page', () async {
    final s = await sessionFor(FakeApi());
    expect(moneyScreenForHref('/poultry-payroll/3', s, company), isA<PayrollRunDetailScreen>());
  });

  testWidgets('the Products link opens the native list, not the web page', (tester) async {
    final s = await sessionFor(FakeApi());
    await open(
      tester,
      Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => openAppHref(context, s, company, '/poultry-products', label: 'Products'),
        child: const Text('go'),
      ))),
      size: phone,
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ListScreen), findsOneWidget);
    expect(find.byType(WebPageScreen), findsNothing);
  });
}
