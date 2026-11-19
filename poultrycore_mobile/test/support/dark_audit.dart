// A dark-mode audit that rides along with the ordinary screen tests.
//
//   flutter test --dart-define=DARK=true --dart-define=AUDIT=<file.jsonl>
//
// Whenever a test opens a screen, and whenever a dialog, sheet or menu finishes
// opening, it walks the rendered tree. For every visible piece of text it works
// out the colour actually behind it (the boxes, cards and materials it sits on,
// blended) and flags text that would be hard to read. It also flags large
// surfaces that are still bright. Findings go to <file.jsonl>, one JSON line
// each. Off unless AUDIT is set.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:poultrycore_mobile/design/tone.dart';

const _lightPage = Color(0xFFFFFFFF);

const auditFile = String.fromEnvironment('AUDIT');

/// Set by the harness so findings can name the test they came from.
String auditTest = '';

final Set<String> _seen = {};

double _lum(Color c) => c.computeLuminance();
double _ratio(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

Color _over(Color top, Color under) => Color.alphaBlend(top, under);

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The fill a render object paints behind its child, if any.
Color? _fillOf(RenderObject r) {
  if (r is RenderDecoratedBox && r.position == DecorationPosition.background) {
    final d = r.decoration;
    if (d is BoxDecoration) return d.color ?? d.gradient?.colors.first;
    if (d is ShapeDecoration) return d.color ?? d.gradient?.colors.first;
    return null;
  }
  if (r is RenderPhysicalModel) return r.color;
  if (r is RenderPhysicalShape) return r.color;
  if (r.runtimeType.toString() == '_RenderColoredBox') {
    try {
      return (r as dynamic).color as Color;
    } catch (_) {}
  }
  return null;
}

/// The colour behind [p]: its ancestors' fills blended, down to an opaque one.
Color _backgroundOf(RenderObject p, Color page) {
  final layers = <Color>[];
  RenderObject? r = p.parent;
  while (r != null) {
    final f = _fillOf(r);
    if (f != null && f.a > 0.02) {
      layers.add(f);
      if (f.a >= 0.95) break;
    }
    r = r.parent;
  }
  var c = page;
  for (final l in layers.reversed) {
    c = _over(l, c);
  }
  return c;
}

double _opacityAbove(RenderObject p) {
  var o = 1.0;
  RenderObject? r = p.parent;
  while (r != null) {
    if (r is RenderOpacity) o *= r.opacity;
    if (r is RenderAnimatedOpacity) o *= r.opacity.value;
    r = r.parent;
  }
  return o;
}

Color? _spanColor(InlineSpan span) {
  Color? found;
  span.visitChildren((s) {
    if (s is TextSpan && (s.text ?? '').trim().isNotEmpty && s.style?.color != null) {
      found = s.style!.color;
      return false;
    }
    return true;
  });
  return found ?? span.style?.color;
}

/// Audits what is on screen now. [phase] says when (open / dialog).
void darkAudit(String phase) {
  if (auditFile.isEmpty) return;
  final view = WidgetsBinding.instance.renderViews.firstOrNull;
  if (view == null) return;
  final screen = Offset.zero & view.size;
  final page = Theme.of(_anyContext() ?? (throw StateError('no context'))).scaffoldBackgroundColor;

  final issues = <Map<String, Object?>>[];
  final bright = <Map<String, Object?>>[];

  void check(RenderParagraph p) {
    final raw = p.text.toPlainText().trim();
    if (raw.isEmpty || !p.hasSize || p.size.width < 2) return;
    final rect = p.localToGlobal(Offset.zero) & p.size;
    if (!rect.overlaps(screen)) return;
    final c = _spanColor(p.text);
    if (c == null) return;
    final opacity = _opacityAbove(p);
    if (opacity < 0.05) return;
    final bg = _backgroundOf(p, page);
    final fg = _over(c.withValues(alpha: c.a * opacity), bg);
    final ratio = _ratio(_lum(fg), _lum(bg));
    if (ratio < 3.0) {
      // Was it just as faint in light mode (a brand header, a deliberate
      // grey)? Then it is the design, not something dark mode broke.
      Tone.dark = false;
      final lbg = _backgroundOf(p, _lightPage);
      final lfg = _over(c.withValues(alpha: c.a * opacity), lbg);
      final light = _ratio(_lum(lfg), _lum(lbg));
      Tone.dark = true;
      if (light < 3.0 && ratio >= light - 0.3) return;
      final isIcon = raw.runes.length == 1 && raw.runes.first >= 0xE000;
      issues.add({
        'text': isIcon ? 'icon U+${raw.runes.first.toRadixString(16)}' : (raw.length > 50 ? '${raw.substring(0, 50)}…' : raw),
        'fg': _hex(fg),
        'bg': _hex(bg),
        'ratio': double.parse(ratio.toStringAsFixed(2)),
      });
    }
  }

  void checkFill(RenderObject r) {
    final f = _fillOf(r);
    if (f == null || f.a < 0.9 || _lum(f) < 0.6 || r is! RenderBox || !r.hasSize) return;
    final rect = (r.localToGlobal(Offset.zero) & r.size).intersect(screen);
    if (rect.isEmpty || rect.width * rect.height < 3000) return;
    // Name it by the first text inside.
    String label = '';
    void find(RenderObject o) {
      if (label.isNotEmpty) return;
      if (o is RenderParagraph) label = o.text.toPlainText().trim();
      o.visitChildren(find);
    }

    r.visitChildren(find);
    bright.add({'fill': _hex(f), 'size': '${rect.width.round()}x${rect.height.round()}', 'first text': label.length > 40 ? label.substring(0, 40) : label});
  }

  void visit(RenderObject r) {
    if (r is RenderOffstage && r.offstage) return;
    if (r is RenderOpacity && r.opacity == 0) return;
    if (r is RenderParagraph) {
      check(r);
      return;
    }
    checkFill(r);
    r.visitChildren(visit);
  }

  view.visitChildren(visit);
  if (issues.isEmpty && bright.isEmpty) return;
  final key = '$auditTest|${issues.map((e) => '${e['text']}${e['fg']}').join()}|${bright.length}';
  if (!_seen.add(key)) return;
  File(auditFile).writeAsStringSync(
    '${jsonEncode({'test': auditTest, 'phase': phase, 'issues': issues, 'bright': bright})}\n',
    mode: FileMode.append,
    flush: true,
  );
}

BuildContext? _anyContext() {
  BuildContext? found;
  void walk(Element e) {
    if (found != null) return;
    if (e.widget is Scaffold || e.widget is Material) {
      found = e;
      return;
    }
    e.visitChildren(walk);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(walk);
  return found;
}

/// Audits each dialog, sheet and menu once it has finished opening.
class AuditObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (auditFile.isEmpty || route is! PopupRoute) return;
    final animation = route.animation;
    void run() => SchedulerBinding.instance.addPostFrameCallback((_) {
          try {
            darkAudit('dialog ${route.runtimeType}');
          } catch (_) {}
        });
    if (animation == null || animation.isCompleted) {
      run();
      return;
    }
    late AnimationStatusListener listener;
    listener = (s) {
      if (s == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        run();
      }
    };
    animation.addStatusListener(listener);
  }
}
