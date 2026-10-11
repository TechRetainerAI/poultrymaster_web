import 'package:flutter/material.dart';

import '../tokens.dart';

/// Header-band colours, matching Tailwind's `*-600` shades used by the web
/// `FormSection` component.
enum SectionColor { indigo, blue, green, sky, emerald, amber, rose, purple, slate }

const Map<SectionColor, Color> _sectionColors = {
  SectionColor.indigo: Color(0xFF4F46E5),
  SectionColor.blue: Color(0xFF2563EB),
  SectionColor.green: Color(0xFF16A34A),
  SectionColor.sky: Color(0xFF0284C7),
  SectionColor.emerald: Color(0xFF059669),
  SectionColor.amber: Color(0xFFD97706),
  SectionColor.rose: Color(0xFFE11D48),
  SectionColor.purple: Color(0xFF9333EA),
  SectionColor.slate: Color(0xFF475569),
};

/// Slate shades the web forms use directly (outside the shadcn token set).
class Slate {
  const Slate._();
  static const s400 = Color(0xFF94A3B8);
  static const s500 = Color(0xFF64748B);
  static const s600 = Color(0xFF475569);
  static const s700 = Color(0xFF334155);
}

/// A titled form section: coloured header band over a bordered body holding a
/// grid of fields.
///
/// The column behaviour is copied deliberately from the web, including the part
/// that looks wrong for mobile: multi-column sections stay multi-column on a
/// phone. The web comment explains why — with every input stretched full width
/// the form became about twice as tall as it needed to be. Pass
/// [stackOnMobile] for sections where one field per row really is right.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.color = SectionColor.indigo,
    this.columns = 2,
    this.stackOnMobile = false,
  });

  final String title;
  final SectionColor color;

  /// 1–4, as on the web.
  final int columns;
  final bool stackOnMobile;
  final List<Widget> children;

  int _columnsFor(double width) {
    if (columns == 1) return 1;
    if (stackOnMobile && width < 640) return 1;

    // The web steps 2 -> 3 -> 4 rather than jumping to four, because four
    // columns of input are narrower than the numbers inside them.
    if (columns == 4) {
      if (width >= 1280) return 4;
      if (width >= 768) return 3;
      return 2;
    }
    if (columns == 3) return width >= 768 ? 3 : 2;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final band = _sectionColors[color]!;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(Dim.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: band,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, c) => _Grid(
                columns: _columnsFor(c.maxWidth),
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays fields out in rows, honouring [FormField.full] which spans every column.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var buffer = <Widget>[];

    void flush() {
      if (buffer.isEmpty) return;
      final items = <Widget>[];
      for (var i = 0; i < buffer.length; i++) {
        items.add(Expanded(child: buffer[i]));
        if (i != buffer.length - 1) items.add(const SizedBox(width: _gap));
      }
      // Pad the last row so two items in a three-column grid keep their width.
      for (var i = buffer.length; i < columns; i++) {
        items
          ..add(const SizedBox(width: _gap))
          ..add(const Expanded(child: SizedBox.shrink()));
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: items));
      buffer = <Widget>[];
    }

    for (final child in children) {
      final isFull = child is AppField && child.full;
      if (isFull || columns == 1) {
        flush();
        rows.add(child);
        continue;
      }
      buffer.add(child);
      if (buffer.length == columns) flush();
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          rows[i],
        ],
      ],
    );
  }
}

/// Label + optional info tip + control + optional hint.
///
/// Mirrors the web's `FormField`: 4px gap, 12px label on phones stepping to
/// 14px at `sm`, slate-700.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.info,
    this.full = false,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? hint;

  /// Shown in a popover behind an info icon, as on the web.
  final String? info;

  /// Spans every column of whatever grid it lands in.
  final bool full;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? tokens.cardForeground : Slate.s700;
    final wide = MediaQuery.sizeOf(context).width >= 640;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: wide ? 14 : 13,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  height: 1.2,
                ),
              ),
            ),
            if (required)
              Text(' *',
                  style: TextStyle(fontSize: wide ? 14 : 12, color: tokens.destructive)),
            if (info != null) ...[
              const SizedBox(width: 4),
              _InfoTip(label: label, message: info!),
            ],
          ],
        ),
        const SizedBox(height: 4),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!,
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground, height: 1.3)),
        ],
      ],
    );
  }
}

class _InfoTip extends StatelessWidget {
  const _InfoTip({required this.label, required this.message});
  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'What "$label" means',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(label),
            content: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it')),
            ],
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(Icons.info_outline, size: 14, color: Slate.s400),
        ),
      ),
    );
  }
}
