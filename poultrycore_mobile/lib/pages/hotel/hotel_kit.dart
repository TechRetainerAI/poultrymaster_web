// Shared pieces for the Hotel pages: the violet the web's Hotel pages use
// (bg-violet-600 buttons, violet-100 icon tiles), the page header, the card
// head, and the delete confirmation the web asks with `confirm()` or
// ConfirmDeleteDialog.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../poultry/trackers/tracker_widgets.dart';

const hotelViolet = TColors.violet600;

List<Map<String, dynamic>> hotelRows(Object? r) => [
  for (final x in (r is List ? r : const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

/// Some Hotel endpoints answer with all-lowercase keys (`stockonhand`); the web
/// reads `x.stockOnHand ?? x.stockonhand`. This fills each of [keys] from its
/// lowercase twin when only that one is present.
List<Map<String, dynamic>> hotelAlias(List<Map<String, dynamic>> rows, List<String> keys) {
  for (final r in rows) {
    for (final k in keys) {
      r[k] ??= r[k.toLowerCase()];
    }
  }
  return rows;
}

/// "2026-10-26" from a date, as an `<input type="date">` value.
String hotelYmd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The date in a "2026-10-26…" value, or null.
DateTime? hotelParseYmd(String v) => v.length < 10 ? null : DateTime.tryParse(v.substring(0, 10));

ButtonStyle get hotelPrimary => FilledButton.styleFrom(backgroundColor: hotelViolet, foregroundColor: Colors.white);

/// The page header: the violet icon tile, the title (with an optional badge
/// beside it) and the description.
class HotelPageHeader extends StatelessWidget {
  const HotelPageHeader({super.key, required this.icon, required this.title, required this.description, this.badge});
  final IconData icon;
  final String title, description;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: TColors.violet100, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: hotelViolet),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900),
                ),
                ?badge,
              ],
            ),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ],
        ),
      ),
    ],
  );
}

/// A white card with the web's CardHeader: icon, title, description and an
/// optional button on the right (underneath when it does not fit).
class HotelCard extends StatelessWidget {
  const HotelCard({super.key, required this.title, this.icon, this.description, this.action, required this.children});
  final String title;
  final IconData? icon;
  final String? description;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 20, color: const Color(0xFF8B5CF6)),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900),
                      ),
                      if (description != null) Text(description!, style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
                    ],
                  ),
                ),
              ],
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 14),
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), c],
      ],
    ),
  );
}

/// The web's small "+ Add" button in a card header.
Widget hotelAddButton(String label, VoidCallback? onPressed) => FilledButton.icon(
  style: hotelPrimary.copyWith(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
  ),
  onPressed: onPressed,
  icon: const Icon(Icons.add, size: 16),
  label: Text(label),
);

/// An outline badge (`Badge variant="outline"` with a tint).
Widget hotelBadge(String text, Color bg, Color fg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: fg.withValues(alpha: .25)),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
  ),
);

/// The filter row: a search box, then the selects, then "N of M".
class HotelFilters extends StatelessWidget {
  const HotelFilters({
    super.key,
    required this.hint,
    required this.onSearch,
    this.selects = const [],
    required this.shown,
    required this.total,
  });
  final String hint;
  final ValueChanged<String> onSearch;
  final List<Widget> selects;
  final int shown, total;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSearchField(hintText: hint, onChanged: onSearch),
      for (var i = 0; i < selects.length; i += 2) ...[
        const SizedBox(height: 8),
        if (i + 1 < selects.length)
          Row(
            children: [
              Expanded(child: selects[i]),
              const SizedBox(width: 8),
              Expanded(child: selects[i + 1]),
            ],
          )
        else
          selects[i],
      ],
      const SizedBox(height: 6),
      Text('$shown of $total', style: const TextStyle(fontSize: 13, color: TColors.slate400)),
    ],
  );
}

/// A row card in a list: [lead] on the left, [body] beside it, and the Edit /
/// Delete icon buttons always visible (the web shows them on every row).
class HotelRowCard extends StatelessWidget {
  const HotelRowCard({super.key, required this.body, this.lead, this.onEdit, this.onDelete, this.extra = const [], this.dim = false});
  final Widget body;
  final Widget? lead;
  final VoidCallback? onEdit, onDelete;
  final List<Widget> extra;
  final bool dim;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? .55 : 1,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (lead != null) ...[lead!, const SizedBox(width: 10)],
          Expanded(child: body),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ...extra,
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            ),
        ],
      ),
    ),
  );
}

/// The empty row of a web table.
Widget hotelEmpty(String text, {IconData? icon, String? sub}) => Container(
  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
  decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(12)),
  child: Column(
    children: [
      if (icon != null) ...[Icon(icon, size: 32, color: TColors.slate300), const SizedBox(height: 8)],
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, color: TColors.slate400),
      ),
      if (sub != null) ...[
        const SizedBox(height: 4),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: TColors.slate400),
        ),
      ],
    ],
  ),
);

/// The delete confirmation. Runs [onConfirm]; true once it succeeded.
Future<bool> hotelConfirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() onConfirm,
}) async {
  var busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: FormDialogTitle(icon: Icons.delete_outline, color: FormColor.red, text: title),
        content: SizedBox(
          width: 400,
          child: Text(message, style: const TextStyle(fontSize: 14, color: TColors.slate600)),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(ctx),
            cancelDisabled: busy,
            children: [
              FilledButton(
                style: formPrimary(FormColor.red),
                onPressed: busy
                    ? null
                    : () async {
                        setLocal(() => busy = true);
                        try {
                          await onConfirm();
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setLocal(() => busy = false);
                          if (ctx.mounted) {
                            trackerToast(ctx, 'Delete failed', description: e is ApiException ? e.message : '$e', error: true);
                          }
                        }
                      },
                child: Text(busy ? 'Deleting…' : 'Delete'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// The shared dialog frame: violet title tile, a set width (dialogs shrink on
/// phones without one), the red-outline Cancel and the violet main button.
class HotelDialog extends StatelessWidget {
  const HotelDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.saveLabel,
    required this.onSave,
    this.saving = false,
  });
  final IconData icon;
  final String title, saveLabel;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: FormDialogTitle(icon: icon, color: FormColor.purple, text: title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), c],
          ],
        ),
      ),
      actions: [
        FormDialogFooter(
          onCancel: () => Navigator.pop(context),
          cancelDisabled: saving,
          children: [
            FilledButton(
              style: hotelPrimary,
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(saveLabel),
            ),
          ],
        ),
      ],
    ),
  );
}
