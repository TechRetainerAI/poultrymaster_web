// The report Email dialog in its three web forms: the single report
// (poultry-report-view), the dashboards (poultry-dashboard-view) and the
// report shell (Cash Account Report, Closing Report), which checks "at least
// one" and "which are invalid" separately.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_widgets.dart';

import 'support/harness.dart';

Future<FakeApi> _open(WidgetTester tester, ReportEmailVariant variant) async {
  final a = FakeApi();
  final s = await sessionFor(a);
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showReportEmailDialog(
        context,
        client: s.farmClient,
        document: () => const ReportDocument(title: 'Cash Account Report', filename: 'cash-accounts', farmName: 'Test Farm', sections: []),
        defaultRecipient: '',
        variant: variant,
      ),
      child: const Text('email'),
    ))),
    size: phone,
  );
  await tester.tap(find.text('email'));
  await tester.pumpAndSettle();
  return a;
}

void main() {
  testWidgets('single report and dashboard wording', (tester) async {
    await _open(tester, ReportEmailVariant.report);
    expect(find.text('Separate multiple addresses with commas. A PDF of this report is generated and sent.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('dashboard wording', (tester) async {
    await _open(tester, ReportEmailVariant.dashboard);
    expect(find.text('Separate multiple addresses with commas. A PDF of every table on this view is generated and sent.'), findsOneWidget);
  });

  testWidgets('report shell: wording and its two checks', (tester) async {
    final a = await _open(tester, ReportEmailVariant.shell);
    expect(
        find.text('Separate multiple addresses with commas. A PDF of this report (current date range and filters) will be generated and sent to each recipient.'),
        findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least one email'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'owner@farm.com, bad, worse@');
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email address — bad, worse@'), findsOneWidget);
    expect(a.writes, isEmpty);
  });
}
