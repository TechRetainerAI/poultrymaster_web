import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderDecoratedBox;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

/// A colour that follows the phone's light / dark setting.
///
/// The app's screens were written for a light page, so most of them name their
/// colours directly (`Color(0xFFF1F5F9)`, `Colors.white`, ...). Rewriting each
/// of those thousands of call sites as `Theme.of(context)...` would break every
/// `const` widget, so instead each one is a [Tone]: still a compile-time
/// constant, written with its light value, and it works out a matching dark
/// value by itself when [Tone.dark] is on.
///
/// The dark value depends on what the colour is *for*, because the same white
/// is a card in one place and text on a blue button in another:
///
///  * [Tone.bg]   a surface: card, panel, chip or button fill.
///  * [Tone.fg]   text or an icon.
///  * [Tone.line] a border or divider.
///  * [Tone.new]  not known: decided from the colour alone.
///
/// The dark palette is slate-based (the hue of the app's header), so cards,
/// panels and borders all sit in the same family:
///
///   page #0B1120 · card #131C2E · raised #1A2438 · border #2A3650
///   text #E2E8F0 · muted text #94A3B8
///
/// Pastel tints (blue-50, amber-100, ...) become a low-alpha wash of the same
/// hue over the card, coloured text is lifted until it reads on that card, and
/// solid brand colours (button fills, badges) stay as they are.
class Tone extends Color {
  const Tone(super.value) : _role = _Role.auto;
  const Tone.bg(super.value) : _role = _Role.bg;
  const Tone.fg(super.value) : _role = _Role.fg;
  const Tone.line(super.value) : _role = _Role.line;

  final _Role _role;

  /// Set by the app root from the phone's brightness. Off in tests unless a
  /// test turns it on, so light mode is exactly what it always was.
  static bool dark = false;

  /// True for the single frame in which the app re-applies every colour after
  /// the phone switches mode. During it a Tone never equals anything, which
  /// makes Flutter's "did the colour change?" checks repaint it.
  static bool refreshing = false;

  static final Map<int, Color> _cache = <int, Color>{};

  Color get _d {
    final light = Color.from(alpha: super.a, red: super.r, green: super.g, blue: super.b);
    final key = (_role.index << 32) | light.toARGB32();
    return _cache[key] ??= darkOf(light, _role);
  }

  @override
  double get a => dark ? _d.a : super.a;
  @override
  double get r => dark ? _d.r : super.r;
  @override
  double get g => dark ? _d.g : super.g;
  @override
  double get b => dark ? _d.b : super.b;

  /// The colour as written, whatever the mode.
  Color get light => Color.from(alpha: super.a, red: super.r, green: super.g, blue: super.b);

  /// A button's fill. Its label is written in white for the light page, so a
  /// brand fill must stay solid in the dark (not lifted like coloured text),
  /// and a near-black fill becomes a raised slate so it still reads as a
  /// button on a dark card. Pale fills (outline-style buttons) follow [Tone].
  static Color? button(Color? c) {
    if (c == null) return null;
    if (!dark) return c;
    final base = c is Tone ? c.light : c;
    if (base.a == 0) return c;
    final hsl = HSLColor.fromColor(base);
    final grey = isGrey(base);
    if (grey && hsl.lightness < 0.35) return const Color(0xFF334155);
    if (hsl.lightness >= 0.78) return darkOf(base, _Role.bg); // pale, outline-style button
    return base;
  }

  @override
  bool operator ==(Object other) => !refreshing && super == other;
  // Equal Tones share the same channel values, so the inherited hash is right.
  @override
  // ignore: unnecessary_overrides
  int get hashCode => super.hashCode;

  // ---------------------------------------------------------------- palette

  static const page = Color(0xFF0B1120);
  static const card = Color(0xFF131C2E);
  static const raised = Color(0xFF1A2438);
  static const border = Color(0xFF2A3650);
  static const ink = Color(0xFFE2E8F0);
  static const inkMuted = Color(0xFF94A3B8);

  /// Grey, judged the way the eye does. HSL saturation is no use here: the
  /// Tailwind slates (#0F172A) score as saturated, so slate text would be
  /// lifted like a blue. Chroma (brightest minus darkest channel) is the test,
  /// except for pale colours, where blue-50 and slate-50 differ only in
  /// saturation.
  static bool isGrey(Color c) {
    final hi = math.max(c.r, math.max(c.g, c.b)), lo = math.min(c.r, math.min(c.g, c.b));
    final l = (hi + lo) / 2;
    if (l > 0.9) return HSLColor.fromColor(c).saturation < 0.6;
    return hi - lo < 0.17;
  }

  /// The dark partner of [c] for [role]. Public so tests can pin the mapping.
  @visibleForTesting
  static Color darkOf(Color c, [Object? role]) {
    final r = role is _Role ? role : _Role.auto;
    final hsl = HSLColor.fromColor(c.withValues(alpha: 1));
    final alpha = c.a;
    final l = hsl.lightness;
    final grey = isGrey(c);

    Color out;
    switch (r) {
      case _Role.fg:
        if (l >= 0.82) {
          out = c; // white / pale text sits on a solid colour: keep it.
        } else if (grey) {
          out = _greyInk(hsl);
        } else {
          out = _liftInk(hsl, 0.70);
        }
        return out.withValues(alpha: alpha);
      case _Role.bg:
        if (l < 0.30) return c; // already dark chrome (headers, sheets).
        if (grey) return _greySurface(l).withValues(alpha: alpha);
        if (l >= 0.78) return _wash(hsl, l, alpha);
        if (l >= 0.56) return _dim(hsl).withValues(alpha: alpha);
        return c; // solid brand fill: keep.
      case _Role.line:
        if (grey) {
          if (l >= 0.6) return _greySurface(l, line: true).withValues(alpha: alpha);
          return border.withValues(alpha: alpha);
        }
        if (l >= 0.7) return _wash(hsl, l, alpha, strength: 1.9);
        return c;
      case _Role.auto:
        if (grey) {
          if (l >= 0.76) return _greySurface(l).withValues(alpha: alpha);
          return _greyInk(hsl).withValues(alpha: alpha);
        }
        if (l >= 0.78) return _wash(hsl, l, alpha);
        // Only the deep shades (700-900), which are nearly always text, are
        // lifted; mid shades are as often a fill behind white text.
        if (c.computeLuminance() < 0.15) return _liftInk(hsl, 0.6).withValues(alpha: alpha);
        return c;
    }
  }

  /// White -> card, slate-50 -> a touch lighter, slate-200 -> border, ...
  /// so the light ladder of greys keeps its order in the dark.
  static Color _greySurface(double l, {bool line = false}) {
    final dl = (0.125 + (1 - l) * (line ? 1.25 : 1.05)).clamp(0.125, 0.36);
    return HSLColor.fromAHSL(1, 221, 0.36 - (dl - 0.125) * 0.5, dl).toColor();
  }

  /// Near-black text -> near-white, slate-500 -> slate-400, ...
  static Color _greyInk(HSLColor hsl) {
    // Dark greys flip to light. Light greys (slate-300/400, written for dark
    // chrome: headers, the All pages sheet) never get darker than 0.68.
    final l = hsl.lightness;
    final dl = math.max(0.93 - l * 0.58, math.min(l, 0.68)).clamp(0.5, 0.93);
    return HSLColor.fromAHSL(1, 216, math.min(hsl.saturation, 0.28), dl).toColor();
  }

  /// Coloured text: same hue, light enough to read on the dark card.
  static Color _liftInk(HSLColor hsl, double floor) {
    if (hsl.lightness >= floor) return hsl.toColor();
    final dl = floor + hsl.lightness * 0.12;
    // Lifting alone greys a deep colour out (blue-900 -> periwinkle); give it
    // back some colour so a heading still reads as blue, not grey.
    final s = hsl.saturation > 0.35 ? hsl.saturation.clamp(0.72, 0.9) : hsl.saturation;
    return hsl.withLightness(dl.clamp(0, 0.86)).withSaturation(s).toColor();
  }

  /// A pastel tint becomes a soft wash of its hue over the card.
  static Color _wash(HSLColor hsl, double l, double alpha, {double strength = 1}) {
    final hue = hsl.withSaturation(math.min(hsl.saturation, 0.75)).withLightness(0.55).toColor();
    final t = ((0.08 + (0.99 - l) * 1.1) * strength).clamp(0.08, 0.6);
    return Color.lerp(card, hue, t)!.withValues(alpha: alpha < 1 ? math.min(1, alpha * 2.2) : 1);
  }

  /// A mid-bright fill (amber-400, sky-300) is toned down so its text reads.
  static Color _dim(HSLColor hsl) =>
      hsl.withLightness(0.22 + (hsl.lightness - 0.56) * 0.45).withSaturation(math.min(hsl.saturation, 0.7)).toColor();
}

enum _Role { auto, bg, fg, line }

/// Follows the phone's light / dark setting, live, and builds the app with it.
///
/// The Material theme switches by itself; the colours the screens name
/// directly are [Tone]s, which switch with [Tone.dark]. When the phone changes
/// mode while the app is open, [refreshTones] re-applies them in place, so the
/// user stays on the same screen with what they typed.
class FollowPhoneBrightness extends StatefulWidget {
  const FollowPhoneBrightness({super.key, required this.builder});

  final Widget Function(BuildContext context, bool dark) builder;

  @override
  State<FollowPhoneBrightness> createState() => _FollowPhoneBrightnessState();
}

class _FollowPhoneBrightnessState extends State<FollowPhoneBrightness> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Tone.dark = _platformDark;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _platformDark => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  @override
  void didChangePlatformBrightness() {
    final dark = _platformDark;
    if (dark == Tone.dark) return;
    setState(() => Tone.dark = dark);
    refreshTones(context);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, Tone.dark);
}

/// Re-applies every [Tone] after the phone switches between light and dark.
///
/// Flutter keeps what it already painted (text layouts, box painters) until a
/// widget's colour compares as changed. This marks the whole tree for rebuild
/// with [Tone.refreshing] on for one frame, so each colour is applied afresh
/// and nothing — including the screen the user is on and what they typed —
/// is thrown away.
///
/// The flag is on only while the tree rebuilds and lays out, never while it
/// paints: during it a Tone is not even equal to itself, and painting then
/// breaks every rounded box with a one-colour border (Flutter checks that all
/// four sides match and throws "A borderRadius can only be given on borders
/// with uniform colors"). That is what made Farm Setup, which is full of such
/// boxes, fall apart when the phone switched mode on it. So the rebuild and
/// layout run straight away, and the next frame paints with the flag off.
void refreshTones(BuildContext context) {
  final binding = WidgetsBinding.instance;
  if (binding.schedulerPhase != SchedulerPhase.idle) {
    // Mid-frame: do it once this frame is finished.
    binding.addPostFrameCallback((_) {
      if (context.mounted) refreshTones(context);
    });
    binding.scheduleFrame();
    return;
  }
  final root = context as Element;
  Tone.refreshing = true;
  try {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
    binding.buildOwner?.buildScope(binding.rootElement ?? root);
    // Layout runs LayoutBuilders, whose children build only then.
    binding.rootPipelineOwner.flushLayout();

    // A `const BoxDecoration` is identical to itself, and BoxDecoration ==
    // returns true for identical objects before it ever compares a colour, so
    // the box keeps its cached (light) background. Hand each box a stand-in
    // and then its own decoration back: that drops the cached painter.
    void reset(Element e) {
      if (e is RenderObjectElement) {
        final ro = e.renderObject;
        if (ro is RenderDecoratedBox) {
          final d = ro.decoration;
          ro.decoration = const _Stand();
          ro.decoration = d;
        }
      }
      e.visitChildren(reset);
    }

    root.visitChildren(reset);
  } finally {
    Tone.refreshing = false;
  }
  binding.scheduleFrame();
}

/// A decoration that paints nothing, used by [refreshTones] for one moment.
class _Stand extends Decoration {
  const _Stand();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _StandPainter();
}

class _StandPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {}
}
