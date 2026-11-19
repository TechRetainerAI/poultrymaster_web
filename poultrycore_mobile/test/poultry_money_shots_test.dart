// Screenshots of Poultry's money charts, light and dark, for eyeballing the
// layout. Runs only with --dart-define=SHOTS=<dir>.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/app_theme.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_money_charts.dart';
import 'package:poultrycore_mobile/pages/shared/chart_period.dart';

import 'poultry_money_charts_test.dart' show pl;
import 'support/harness.dart';

const _shots = String.fromEnvironment('SHOTS');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    if (_shots.isEmpty) return;
    const fonts = 'C:/flutter_windows/flutter/bin/cache/artifacts/material_fonts';
    await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-medium.ttf', '$fonts/roboto-bold.ttf']);
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  });

  for (final dark in [false, true]) {
    testWidgets('money charts ${dark ? 'dark' : 'light'}', (tester) async {
      if (_shots.isEmpty) return;
      ChartFolds.reset();
      Tone.dark = dark;
      addTearDown(() => Tone.dark = false);
      final api = FakeApi()
        ..gets['/api/Poultry/profit-loss'] = pl(revenue: 4200, direct: 2100, operating: 900, other: 250)
        ..gets['/api/Poultry/cash-flow'] = {
          'summary': {'openingCash': 1500},
          'rows': [
            for (var m = 0; m < 12; m++) ...[
              {'transactionDate': '${m < 1 ? 2025 : 2026}-${(m < 1 ? 12 : m).toString().padLeft(2, '0')}-05', 'amount': 800 + m * 90},
              {'transactionDate': '${m < 1 ? 2025 : 2026}-${(m < 1 ? 12 : m).toString().padLeft(2, '0')}-18', 'amount': -(600 + (m % 4) * 350)},
            ],
          ],
        }
        ..gets['/api/Poultry/customer-balances/summary'] = {'totalBalance': 1250, 'partyCount': 4}
        ..gets['/api/Poultry/supplier-balances/summary'] = {'totalBalance': 700, 'partyCount': 2};
      final session = await sessionFor(api);
      tester.view.physicalSize = const Size(400, 2900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
              ChartCardScope(
                name: 'poultry',
                child: PoultryMoneyCharts(
                  session: session,
                  company: company,
                  window: const ChartWindow.preset(ChartPeriod.months),
                  now: () => DateTime(2026, 11, 4, 10),
                ),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_shots/poultry_money_${dark ? 'dark' : 'light'}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
