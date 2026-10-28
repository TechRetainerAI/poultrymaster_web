import 'package:flutter/material.dart';

/// The web's New sale dialog shell (`components/ui/form-dialog.tsx`), shared so
/// every form dialog looks like it:
///
///   AlertDialog(
///     title: FormDialogTitle(icon: Icons.savings_outlined, color: FormColor.blue, text: 'Add customer credit'),
///     content: Column(children: [TintedSection(title: 'Customer & Date', color: FormColor.blue, children: [...])]),
///     actions: [FormDialogFooter(onCancel: close, children: [FilledButton(style: formPrimary(FormColor.blue), ...)])],
///   )
///
/// Nothing here uses a LayoutBuilder: inside a dialog that draws as a blank
/// backdrop on real phones. Phone width is read from MediaQuery instead.
enum FormColor { blue, green, emerald, amber, orange, rose, red, purple, slate, sky }

/// The icon tile and the main button (`TILE` / `FORM_DIALOG_PRIMARY`).
const Map<FormColor, Color> formSolid = {
  FormColor.blue: Color(0xFF2563EB),
  FormColor.green: Color(0xFF16A34A),
  FormColor.emerald: Color(0xFF059669),
  FormColor.amber: Color(0xFFF59E0B),
  FormColor.orange: Color(0xFFF97316),
  FormColor.rose: Color(0xFFE11D48),
  FormColor.red: Color(0xFFDC2626),
  FormColor.purple: Color(0xFF9333EA),
  FormColor.slate: Color(0xFF334155),
  FormColor.sky: Color(0xFF0284C7),
};

/// A tinted FormSection's header band (form-section.tsx `COLORS`, -600 mostly).
const Map<FormColor, Color> _band = {
  FormColor.blue: Color(0xFF2563EB),
  FormColor.green: Color(0xFF16A34A),
  FormColor.emerald: Color(0xFF059669),
  FormColor.amber: Color(0xFFD97706),
  FormColor.orange: Color(0xFFF97316),
  FormColor.rose: Color(0xFFE11D48),
  FormColor.red: Color(0xFFDC2626),
  FormColor.purple: Color(0xFF9333EA),
  FormColor.slate: Color(0xFF475569),
  FormColor.sky: Color(0xFF0284C7),
};

/// `TINTS`: the border (-200) and the body (-50 at 40%; slate solid -50).
const Map<FormColor, (Color, Color)> _tint = {
  FormColor.blue: (Color(0xFFBFDBFE), Color(0x66EFF6FF)),
  FormColor.green: (Color(0xFFBBF7D0), Color(0x66F0FDF4)),
  FormColor.emerald: (Color(0xFFA7F3D0), Color(0x66ECFDF5)),
  FormColor.amber: (Color(0xFFFDE68A), Color(0x66FFFBEB)),
  FormColor.orange: (Color(0xFFFED7AA), Color(0x4DFFF7ED)),
  FormColor.rose: (Color(0xFFFECDD3), Color(0x66FFF1F2)),
  FormColor.red: (Color(0xFFFECACA), Color(0x66FEF2F2)),
  FormColor.purple: (Color(0xFFE9D5FF), Color(0x66FAF5FF)),
  FormColor.slate: (Color(0xFFE2E8F0), Color(0xFFF8FAFC)),
  FormColor.sky: (Color(0xFFBAE6FD), Color(0x66F0F9FF)),
};

bool _phone(BuildContext context) => MediaQuery.sizeOf(context).width < 640;

/// The main button's colours, matching the tile.
ButtonStyle formPrimary(FormColor color) => FilledButton.styleFrom(
      backgroundColor: formSolid[color],
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
    );

/// The red-outline Cancel / Close.
ButtonStyle get formCancel => OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFDC2626),
      side: const BorderSide(color: Color(0xFFFECACA)),
      backgroundColor: Colors.white,
    );

/// DialogTitle with the solid icon tile.
class FormDialogTitle extends StatelessWidget {
  const FormDialogTitle({super.key, required this.icon, required this.text, this.color = FormColor.blue, this.child});
  final IconData icon;
  final String text;
  final FormColor color;

  /// In place of [text], for a title that carries a badge (Sale · Posted).
  final Widget? child;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: formSolid[color], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(child: child ?? Text(text)),
      ]);
}

/// The footer: the red-outline Cancel, then the caller's main action(s). On a
/// phone every button is full width and Cancel sits underneath; from 640 px
/// they sit in a row on the right. Pass `cancelLabel: 'Close'` on a read-only
/// dialog with no main action.
class FormDialogFooter extends StatelessWidget {
  const FormDialogFooter({
    super.key,
    required this.onCancel,
    this.cancelLabel = 'Cancel',
    this.cancelDisabled = false,
    this.children = const [],
  });
  final VoidCallback onCancel;
  final String cancelLabel;
  final bool cancelDisabled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cancel = OutlinedButton(
      style: formCancel,
      onPressed: cancelDisabled ? null : onCancel,
      child: Text(cancelLabel),
    );
    final phone = _phone(context);
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
      child: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (final c in children.reversed) ...[c, const SizedBox(height: 8)],
              cancel,
            ])
          : Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [cancel, ...children]),
    );
  }
}

/// A tinted FormSection (form-section.tsx, `tinted`): a coloured header band,
/// with an optional count or button on its right, over a body in the band's
/// own colour. Inputs inside sit on white. The body is a plain column: the
/// caller lays out any side-by-side fields with a Row.
class TintedSection extends StatelessWidget {
  const TintedSection({
    super.key,
    required this.title,
    required this.children,
    this.color = FormColor.blue,
    this.titleWidget,
    this.action,
    this.gap = 12,
  });
  final String title;
  final Widget? titleWidget;
  final FormColor color;
  final Widget? action;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final (border, body) = _tint[color]!;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: _band[color],
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: action == null ? 8 : 5),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                child: titleWidget ?? Text(title),
              ),
              ?action,
            ],
          ),
        ),
        Container(
          color: body,
          padding: const EdgeInsets.all(14),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(filled: true, fillColor: Colors.white),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (final (i, c) in children.indexed) ...[if (i > 0) SizedBox(height: gap), c],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The white-on-colour count in a section header (`bg-white/25`).
class FormCountPill extends StatelessWidget {
  const FormCountPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}

/// Two fields side by side, or stacked on a phone when [stackOnMobile].
class FormPair extends StatelessWidget {
  const FormPair(this.a, this.b, {super.key, this.stackOnMobile = false});
  final Widget a, b;
  final bool stackOnMobile;

  @override
  Widget build(BuildContext context) {
    if (stackOnMobile && _phone(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        a,
        const SizedBox(height: 12),
        b,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ]);
  }
}
