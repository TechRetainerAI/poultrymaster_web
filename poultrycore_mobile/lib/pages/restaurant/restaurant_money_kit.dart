// Pieces the Restaurant money pages share (Owner Money, Loans, Cash Account):
// lib/api/restaurant-finance.ts's helpers, components/restaurant/money-stat,
// and the dialog shell and reason dialog every one of them uses.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart' show TColors, rowsOf, trackerToast;
import '../shared/business_dates.dart';
import '../shared/reason_select.dart';
import 'restaurant_roles.dart' show restaurantRose;

/// `/Restaurant/finance`, every call carrying farmId in the query.
String rFin(String path, String farmId, [Map<String, Object?> query = const {}]) {
  final q = {'farmId': farmId};
  query.forEach((k, v) {
    if (v != null && '$v' != '') q[k] = '$v';
  });
  return Uri(path: '/api/Restaurant/finance$path', queryParameters: q).toString();
}

/// todayIso: today in the phone's calendar, YYYY-MM-DD.
String rTodayIso() => isoDay(DateTime.now());

/// dateOnly: the date part, or "—".
String rDateOnly(Object? s) => tStr(s).isEmpty ? '—' : tStr(s).split('T').first;

/// The web's `num()`: blank is 0, a number is itself, anything else is null (NaN).
num? rMoney(String s) => s.trim().isEmpty ? 0 : num.tryParse(s.trim());

num rRound2(num n) => (n * 100).round() / 100;

/// listCashAccounts (which also creates the three defaults on first use).
Future<List<Map>> loadRestaurantAccounts(ApiClient api, String farmId) async => rowsOf(await api.get(rFin('/accounts', farmId)));

/// The account dropdown's items: "name — balance".
List<AppSelectItem<String>> rAccountItems(List<Map> accounts, String Function(num) fmt) => [
      for (final a in accounts)
        AppSelectItem(value: '${tIntOrNull(a['cashAccountId'])}', label: '${tStr(a['name'])} — ${fmt(tNum(a['currentBalance']))}'),
    ];

/// MoneyStat: small uppercase label, bold figure, one hint.
class MoneyStat extends StatelessWidget {
  const MoneyStat({super.key, required this.label, required this.value, this.hint, this.accent = 'slate'});
  final String label;
  final String value;
  final String? hint;
  final String accent;

  static const _colours = {
    'slate': TColors.slate900,
    'emerald': TColors.emerald700,
    'orange': Color(0xFFC2410C),
    'rose': Color(0xFFE11D48),
    'indigo': Color(0xFF4338CA),
    'amber': TColors.amber700,
    'violet': Color(0xFF6D28D9),
  };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _colours[accent] ?? TColors.slate900)),
          if (hint != null)
            Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      );
}

/// A label over its field, with the rose star when required.
Widget rField(String label, Widget child, {bool required = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: label),
        if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFF43F5E))),
      ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
      const SizedBox(height: 6),
      child,
    ]);

/// A money / number box.
Widget rNumberInput(TextEditingController c, {String? hint, VoidCallback? onChanged, bool signed = false}) => AppInput(
      controller: c,
      hintText: hint,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
      onChanged: (_) => onChanged?.call(),
    );

/// A date box over a YYYY-MM-DD string; empty means no date.
Widget rDateInput(String value, ValueChanged<String> onChanged, {String? min, String? max}) => AppDateField(
      value: businessDateAsDateTime(value),
      firstDate: min == null || min.isEmpty ? null : businessDateAsDateTime(min),
      lastDate: max == null || max.isEmpty ? null : businessDateAsDateTime(max),
      onChanged: (d) => onChanged(d == null ? '' : isoDay(d)),
    );

/// The dialog shell: a set width (a bare AlertDialog shrinks on a phone),
/// title, description, the fields, and the footer buttons wrapping.
Widget rDialog({required String title, String? description, required List<Widget> children, required List<Widget> actions}) =>
    AlertDialog(
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (description != null) ...[
            Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
        ]),
      ),
      actions: [Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions)],
    );

Widget rCancel(BuildContext context, String label, {bool busy = false}) =>
    OutlinedButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(label));

Widget rConfirm(String label, VoidCallback? onPressed, {Color color = restaurantRose}) =>
    FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onPressed, child: Text(label));

/// A grey box with a label on the left and a figure on the right.
Widget rFigureBox(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate900)),
      ]),
    );

/// The reverse / cancel dialogs: a reason from [options] ("Other" to type one),
/// then [submit]. Pops true once done; on failure it toasts and stays open.
class RReasonDialog extends StatefulWidget {
  const RReasonDialog({
    super.key,
    required this.title,
    required this.description,
    required this.options,
    required this.keepLabel,
    required this.confirmLabel,
    required this.busyLabel,
    required this.errorTitle,
    required this.submit,
    this.destructive = true,
    this.missingReason,
  });
  final String title;
  final String description;
  final List<String> options;
  final String keepLabel, confirmLabel, busyLabel, errorTitle;
  final Future<void> Function(String reason) submit;
  final bool destructive;

  /// A toast for an empty reason (the count reversal); otherwise the button
  /// stays disabled until there is one.
  final (String, String)? missingReason;

  @override
  State<RReasonDialog> createState() => _RReasonDialogState();
}

class _RReasonDialogState extends State<RReasonDialog> {
  String _reason = '';
  bool _busy = false;

  Future<void> _go() async {
    if (_reason.trim().isEmpty) {
      final m = widget.missingReason;
      if (m != null) trackerToast(context, m.$1, description: m.$2, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.submit(_reason.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, widget.errorTitle, description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: rDialog(
          title: widget.title,
          description: widget.description,
          children: [
            rField('Reason', ReasonSelect(options: widget.options, value: _reason, onChanged: (v) => setState(() => _reason = v)), required: true),
          ],
          actions: [
            rCancel(context, widget.keepLabel, busy: _busy),
            rConfirm(_busy ? widget.busyLabel : widget.confirmLabel,
                _busy || (widget.missingReason == null && _reason.trim().isEmpty) ? null : _go,
                color: widget.destructive ? TColors.red600 : restaurantRose),
          ],
        ),
      );
}

/// A small status / type badge.
Widget rStatusBadge(String text, {Color bg = Colors.white, Color fg = TColors.slate700, Color border = TColors.slate200}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );

/// ConfirmDeleteDialog: a red confirm that runs [onConfirm]; pops true when it
/// succeeds, and toasts [errorTitle] and stays open when it fails.
class RConfirmDialog extends StatefulWidget {
  const RConfirmDialog({
    super.key,
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.errorTitle,
    required this.onConfirm,
    this.busyLabel = 'Deleting…',
  });
  final String title, description, confirmLabel, errorTitle, busyLabel;
  final Future<void> Function() onConfirm;

  @override
  State<RConfirmDialog> createState() => _RConfirmDialogState();
}

class _RConfirmDialogState extends State<RConfirmDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, widget.errorTitle, description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: rDialog(
          title: widget.title,
          description: widget.description,
          children: const [],
          actions: [
            rCancel(context, 'Cancel', busy: _busy),
            rConfirm(_busy ? widget.busyLabel : widget.confirmLabel, _busy ? null : _go, color: TColors.red600),
          ],
        ),
      );
}
