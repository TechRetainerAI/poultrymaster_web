// Dark mode: the colour rules in design/tone.dart, and the live switch when the
// phone changes mode while the app is open.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/app_theme.dart';
import 'package:poultrycore_mobile/design/tone.dart';

double _lum(Color c) => c.computeLuminance();

/// Contrast ratio, WCAG style.
double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  tearDown(() => Tone.dark = false);

  group('colour rules', () {
    test('light mode is exactly the colour as written', () {
      Tone.dark = false;
      expect(const Tone.bg(0xFFFFFFFF).toARGB32(), 0xFFFFFFFF);
      expect(const Tone.fg(0xFF0F172A).toARGB32(), 0xFF0F172A);
      expect(const Tone(0xFFEFF6FF).toARGB32(), 0xFFEFF6FF);
    });

    test('white card -> dark card; near-black text -> near-white, readable on it', () {
      Tone.dark = true;
      const card = Tone.bg(0xFFFFFFFF), text = Tone.fg(0xFF0F172A), muted = Tone.fg(0xFF64748B);
      expect(_lum(card), lessThan(0.03));
      expect(_contrast(text, card), greaterThan(10));
      expect(_contrast(muted, card), greaterThan(4.5), reason: 'muted text still passes AA');
    });

    test('the grey ladder keeps its order: white < slate-50 < slate-100 < slate-200 border', () {
      Tone.dark = true;
      final steps = [0xFFFFFFFF, 0xFFF8FAFC, 0xFFF1F5F9].map((v) => _lum(Tone.bg(v))).toList();
      expect(steps[0], lessThan(steps[1]));
      expect(steps[1], lessThan(steps[2]));
      expect(_lum(const Tone.line(0xFFE2E8F0)), greaterThan(steps[2]));
    });

    test('a pastel tint becomes a dark wash of the same hue; its coloured text reads on it', () {
      Tone.dark = true;
      const wash = Tone.bg(0xFFDBEAFE), ink = Tone.fg(0xFF1D4ED8); // blue-100 badge, blue-700 text
      expect(_lum(wash), lessThan(0.06));
      expect(wash.b, greaterThan(wash.r), reason: 'still blue');
      expect(_contrast(ink, wash), greaterThan(4.5));
    });

    test('white text and solid brand fills stay as they are', () {
      Tone.dark = true;
      expect(const Tone.fg(0xFFFFFFFF).toARGB32(), 0xFFFFFFFF);
      expect(const Tone.bg(0xFF2563EB).toARGB32(), 0xFF2563EB);
    });

    test('button fills: brand colours stay solid, a near-black button becomes raised slate', () {
      Tone.dark = true;
      expect(Tone.button(const Tone(0xFF059669))!.toARGB32(), 0xFF059669, reason: 'not lifted like text');
      expect(Tone.button(const Tone(0xFF0F172A))!.toARGB32(), 0xFF334155);
      expect(Tone.button(null), isNull);
      Tone.dark = false;
      expect(Tone.button(const Tone(0xFF0F172A))!.toARGB32(), 0xFF0F172A);
    });

    test('dark chrome (headers, sheets) stays dark as a fill', () {
      Tone.dark = true;
      expect(const Tone.bg(0xFF111827).toARGB32(), 0xFF111827);
    });
  });

  testWidgets('the phone switching to dark repaints in place and keeps what was typed', (tester) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final key = GlobalKey();

    await tester.pumpWidget(FollowPhoneBrightness(
      builder: (context, dark) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        themeAnimationDuration: Duration.zero,
        home: RepaintBoundary(
          key: key,
          child: const Scaffold(
            body: ColoredBox(
              color: Tone.bg(0xFFFFFFFF),
              child: Padding(padding: EdgeInsets.only(top: 120), child: TextField()),
            ),
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'half-typed sale');

    Future<Color> pixel() async {
      late Color c;
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        const o = (10 * 200 + 10) * 4;
        c = Color.fromARGB(data.getUint8(o + 3), data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
      });
      return c;
    }

    expect((await pixel()).toARGB32(), 0xFFFFFFFF);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Tone.dark, isTrue);
    expect(Tone.refreshing, isFalse, reason: 'the refresh lasts one frame');
    expect(_lum(await pixel()), lessThan(0.03), reason: 'the same const box repainted dark');
    expect(find.text('half-typed sale'), findsOneWidget, reason: 'no state lost');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect((await pixel()).toARGB32(), 0xFFFFFFFF);
  });
}
