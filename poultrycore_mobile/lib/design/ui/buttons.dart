import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web `Button` variants.
enum AppButtonVariant { primary, secondary, outline, ghost, destructive, link }

/// The web `Button` sizes: sm h-8 px-3, default h-9 px-4, lg h-10 px-6.
enum AppButtonSize { sm, md, lg }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.busy = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool busy;
  final bool fullWidth;

  /// Visual height, matching the web (sm h-8, default h-9, lg h-10).
  double get _height => switch (size) {
        AppButtonSize.sm => 32,
        AppButtonSize.md => 36,
        AppButtonSize.lg => 40,
      };

  /// Tap height. Material and Android accessibility both require 48dp minimum,
  /// and the web's own sizes are all below it. The button keeps its web look
  /// while the touch area is padded out to 48 — the standard way to satisfy
  /// both, rather than drawing a bigger button than the web has.
  static const double _minTapHeight = 48;

  double get _padding => switch (size) {
        AppButtonSize.sm => 12,
        AppButtonSize.md => 16,
        AppButtonSize.lg => 24,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final disabled = onPressed == null || busy;

    late final Color bg;
    late final Color fg;
    BorderSide side = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = scheme.primary;
        fg = scheme.onPrimary;
      case AppButtonVariant.secondary:
        bg = scheme.secondary;
        fg = scheme.onSecondary;
      case AppButtonVariant.outline:
        final light = scheme.brightness == Brightness.light;
        bg = light ? const Color(0xFFF8FAFC) : scheme.surface;
        fg = scheme.onSurface;
        side = BorderSide(color: light ? const Color(0xFFCBD5E1) : const Color(0xFF404040));
      case AppButtonVariant.ghost:
      case AppButtonVariant.link:
        bg = Colors.transparent;
        fg = scheme.onSurface;
      case AppButtonVariant.destructive:
        bg = tokens.destructive;
        fg = tokens.destructiveForeground;
    }

    // shadcn disables via opacity-50 rather than a separate colour.
    final content = busy
        ? SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 8), // gap-2
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: variant == AppButtonVariant.link
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ],
          );

    final button = Opacity(
      opacity: disabled ? .5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dim.radiusMd),
          onTap: disabled ? null : onPressed,
          child: Container(
            height: _height,
            padding: EdgeInsets.symmetric(horizontal: _padding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Dim.radiusMd),
              border: side == BorderSide.none ? null : Border.fromBorderSide(side),
            ),
            child: Center(
              widthFactor: fullWidth ? null : 1,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: fg),
                child: IconTheme(data: IconThemeData(color: fg), child: content),
              ),
            ),
          ),
        ),
      ),
    );

    // Pad the hit area to 48dp without changing the drawn height.
    // widthFactor 1 keeps the button its own width: without it Center grows
    // to the full row, so buttons laid out in a Wrap each took a whole line.
    final tappable = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapHeight),
      child: Center(heightFactor: 1, widthFactor: fullWidth ? null : 1, child: button),
    );

    return fullWidth
        ? SizedBox(width: double.infinity, child: tappable)
        : tappable;
  }
}

/// The web `Card`: 1px border, rounded-xl, no shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final String? description;
  final Widget? trailing;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(title!,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              ?trailing,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!,
                style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground)),
          ],
          const SizedBox(height: 12),
        ],
        child,
      ],
    );

    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(Dim.radiusXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusXl),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusXl),
            border: Border.all(color: tokens.border),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// The web `Badge` variants — exactly the four it defines in
/// `components/ui/badge.tsx`: default (primary), secondary, destructive and
/// outline. Deliberately no success/warning/info: the web has none, and adding
/// them here would put colours on screen that exist nowhere in the product.
enum BadgeVariant { primary, secondary, destructive, outline }

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, this.variant = BadgeVariant.secondary});

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color fg;
    Color? border;

    switch (variant) {
      case BadgeVariant.primary:
        bg = scheme.primary;
        fg = scheme.onPrimary;
      case BadgeVariant.secondary:
        bg = scheme.secondary;
        fg = scheme.onSecondary;
      case BadgeVariant.destructive:
        bg = tokens.destructive;
        fg = Colors.white; // the web uses text-white here, not the token
      case BadgeVariant.outline:
        bg = Colors.transparent;
        fg = scheme.onSurface;
        border = tokens.border;
    }

    // rounded-md, px-2 py-0.5, text-xs font-medium.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}
