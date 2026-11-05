// Screenshots of real screens in dark mode, for looking at by eye.
// Writes PNGs only when run with --dart-define=SHOTS=<folder>; otherwise it
// still renders each screen dark and fails on any overflow or exception.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/app_theme.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'package:poultrycore_mobile/pages/generic/generic_money_screens.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_view.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/deferred_costs_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_dashboard_view.dart';
import 'package:poultrycore_mobile/screens/business_office_screen.dart';

import 'business_office_test.dart' as bo;
import 'poultry_deferred_costs_test.dart' as dc;
import 'restaurant_dashboard_test.dart' as rd;
import 'generic_money_test.dart' as gm;
import 'hotel_dashboard_test.dart' as hd;
import 'support/harness.dart';

const _shots = String.fromEnvironment('SHOTS');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

final _key = GlobalKey();

Future<void> shoot(WidgetTester tester, String name, Widget screen, {Size size = const Size(400, 860)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Tone.dark = true;
  addTearDown(() => Tone.dark = false);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      navigatorKey: nav,
      home: const Scaffold(body: Text('host')),
    ),
  ));
  nav.currentState!.push(MaterialPageRoute(builder: (_) => screen));
  await tester.pumpAndSettle();
  await capture(tester, name);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (_shots.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_shots.isEmpty) return;
    const fonts = 'C:/flutter_windows/flutter/bin/cache/artifacts/material_fonts';
    await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-medium.ttf', '$fonts/roboto-bold.ttf']);
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  });

  testWidgets('Generic cash & accounts', (tester) async {
    await shoot(tester, 'cash', GenericCashScreen(session: await sessionFor(gm.api()), company: gm.generic));
  });

  testWidgets('Generic owner money + record dialog', (tester) async {
    await shoot(tester, 'owner', GenericOwnerMoneyScreen(session: await sessionFor(gm.api()), company: gm.generic));
    await tester.tap(find.textContaining('Record').first);
    await tester.pumpAndSettle();
    await capture(tester, 'owner_dialog');
  });

  testWidgets('Hotel dashboard', (tester) async {
    await shoot(
      tester,
      'hotel_dash',
      Scaffold(body: HotelDashboardView(session: await sessionFor(hd.base()), company: hd.hotel, now: () => hd.now, autoRefresh: false)),
      size: const Size(400, 2200),
    );
  });

  testWidgets('Business Office', (tester) async {
    final s = await sessionFor(bo.boApi());
    await s.loadCompanies();
    await shoot(tester, 'office', BusinessOfficeScreen(session: s, onPicked: () {}, onSignedOut: () {}), size: const Size(400, 1800));
  });

  testWidgets('Poultry deferred costs', (tester) async {
    await shoot(tester, 'deferred', DeferredCostsScreen(session: await sessionFor(dc.api()), company: company, itemId: 7), size: const Size(400, 1600));
  });

  testWidgets('Restaurant dashboard', (tester) async {
    await shoot(tester, 'rest_dash', RestaurantDashboardScreen(session: await sessionFor(rd.dashboardApi()), company: rd.rest), size: const Size(400, 2000));
  });
}
