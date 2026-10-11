import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'asset_logic.dart';

/// The pieces shared by the register and the investment page:
/// `components/capital-assets/asset-details-panel.tsx`,
/// `cost-detail-dialog.tsx`, `correct-original-cost-dialog.tsx`, and the
/// PromptDialog the reversals use.

Widget assetStatusBadge(Object? status) {
  final (bg, fg, border) = assetStatusTone(status);
  return TBadge(assetStatusLabel(status), bg: bg, fg: fg, border: border);
}

String signedMoney(FarmMoney fmt, num n) => n < 0 ? '-${fmt(n.abs())}' : fmt(n);

Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
    );

/// The panel's Line: label left, value right.
Widget assetLine(String label, String value, {Color? color, bool bold = false, String? hint}) {
  final row = Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate600))),
      const SizedBox(width: 16),
      Expanded(
        child: Text(value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: color ?? TColors.slate900, fontWeight: bold ? FontWeight.w600 : null)),
      ),
    ]),
  );
  return hint == null ? row : Tooltip(message: hint, triggerMode: TooltipTriggerMode.longPress, child: row);
}

/// The panel's Figure tile.
Widget assetFigure(String label, String value, {Color? tone, bool strong = false, String? hint}) {
  final fg = tone == TColors.amber800 ? TColors.amber800 : tone == TColors.emerald800 ? TColors.emerald800 : TColors.slate900;
  final border = tone == TColors.amber800
      ? const Color(0xFFFDE68A)
      : tone == TColors.emerald800
          ? const Color(0xFFA7F3D0)
          : TColors.slate200;
  final box = Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: strong ? TColors.slate300 : border, width: strong ? 1.5 : 1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
    ]),
  );
  return hint == null ? box : Tooltip(message: hint, triggerMode: TooltipTriggerMode.tap, showDuration: const Duration(seconds: 6), child: box);
}

Widget _grid(List<Widget> tiles) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });

/// AssetDetailsPanel: Overview / Cost history / Depreciation history for one
/// investment, read from the full record (`GET /Poultry/assets/{id}`).
class AssetDetailsPanel extends StatefulWidget {
  const AssetDetailsPanel({
    super.key,
    required this.view,
    required this.loading,
    required this.error,
    required this.fmt,
    required this.offset,
    this.onRetry,
    this.onEdit,
    this.onAddCost,
    this.onCorrectOriginalCost,
    this.onOpenFullPage,
    this.onOpenExpenses,
    this.onViewCost,
    this.onReverseCost,
    this.onReverseDepreciation,
  });
  final Map? view;
  final bool loading;
  final String? error;
  final FarmMoney fmt;
  final Duration offset;
  final VoidCallback? onRetry, onEdit, onAddCost, onCorrectOriginalCost, onOpenFullPage, onOpenExpenses;
  final void Function(Map cost)? onViewCost, onReverseCost, onReverseDepreciation;

  @override
  State<AssetDetailsPanel> createState() => _AssetDetailsPanelState();
}

class _AssetDetailsPanelState extends State<AssetDetailsPanel> {
  String _tab = 'overview';

  FarmMoney get _fmt => widget.fmt;
  String _dt(Object? d, [Map? r]) => fmtDateTime(d, r, widget.offset);

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    if (widget.loading && v == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading the full history…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
      );
    }
    if (widget.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB91C1C)),
          Text(widget.error!, style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
          if (widget.onRetry != null) OutlinedButton(onPressed: widget.onRetry, child: const Text('Try again')),
        ]),
      );
    }
    if (v == null) return const SizedBox.shrink();
    final costs = [for (final c in v['costs'] as List? ?? const []) c as Map];
    final posted = [for (final c in costs) if (tStr(c['status']) == 'Posted') c];
    final reversed = [for (final c in costs) if (tStr(c['status']) != 'Posted') c];
    final deps = [for (final d in v['depreciation'] as List? ?? const []) d as Map];
    Widget tab(String key, String label, [int? count]) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            selected: _tab == key,
            onSelected: (_) => setState(() => _tab = key),
            label: Text(count == null ? label : '$label  $count'),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            tab('overview', 'Overview'),
            tab('costs', 'Cost history', posted.length),
            tab('depreciation', 'Depreciation history', deps.length),
          ]),
        ),
        const SizedBox(height: 10),
        switch (_tab) {
          'costs' => _costs(v, posted, reversed),
          'depreciation' => _depreciation(v, deps),
          _ => _overview(v),
        },
      ]),
    );
  }

  Widget _overview(Map v) {
    final locked = tNum(v['depreciationEntries']) > 0;
    final closed = tStr(v['status']) == 'Disposed' || tStr(v['status']) == 'Reversed';
    final total = tNum(v['totalCapitalizedCost']), acc = tNum(v['accumulatedDepreciation']);
    final bv = tNum(v['currentBookValue']), res = tNum(v['residualValue']);
    final life = tIntOrNull(v['usefulLifeMonths']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sectionLabel('What it cost'),
      _grid([
        assetFigure('Original acquisition cost', _fmt(tNum(v['acquisitionCost'])), hint: acquisitionCostTooltip),
        assetFigure('Additional capitalised costs', _fmt(tNum(v['additionalCost'])), hint: additionalCostTooltip),
        assetFigure('Total capitalised cost', _fmt(total), strong: true, hint: totalCapitalizedCostTooltip),
      ]),
      const SizedBox(height: 14),
      sectionLabel('What it is worth now'),
      _grid([
        assetFigure('Accumulated depreciation', _fmt(acc), tone: TColors.amber800, hint: depreciationNoncashNote),
        assetFigure('Current book value', _fmt(bv), tone: TColors.emerald800, strong: true, hint: bookValueTooltip),
        assetFigure('Residual value', _fmt(res),
            hint: 'What the investment is expected to still be worth at the end of its life. Book value never falls below it.'),
      ]),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${_fmt(total)} total capitalised cost − ${_fmt(acc)} depreciation charged = '),
          TextSpan(text: _fmt(bv), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate700)),
          const TextSpan(text: ' book value'),
          if (bv <= res && res > 0) const TextSpan(text: ' — held at the residual value, which book value never falls below'),
        ]),
        style: const TextStyle(fontSize: 11, color: TColors.slate500),
      ),
      const SizedBox(height: 14),
      sectionLabel('How it depreciates'),
      assetLine('Method', life != null && life > 0 ? 'Straight line' : '—'),
      assetLine('Useful life', life != null && life > 0 ? '$life months' : 'Not set'),
      assetLine('Monthly charge', tNum(v['monthlyDepreciation']) != 0 ? _fmt(tNum(v['monthlyDepreciation'])) : '—'),
      assetLine('Depreciable amount', _fmt(tNum(v['depreciableAmount']))),
      assetLine('Still to be charged', _fmt(tNum(v['remainingDepreciable']))),
      assetLine('In service', tStr(v['inServiceDate']).isNotEmpty ? _dt(v['inServiceDate']) : 'Not in service'),
      const SizedBox(height: 14),
      sectionLabel('What it is'),
      assetLine('Category', tStr(v['categoryName']).isEmpty ? '—' : tStr(v['categoryName'])),
      assetLine('Acquired', _dt(v['acquisitionDate'], v).isEmpty ? '—' : _dt(v['acquisitionDate'], v)),
      assetLine('Status', assetStatusLabel(v['status'])),
      assetLine('Location', tStr(v['location']).isEmpty ? '—' : tStr(v['location'])),
      assetLine('Serial number', tStr(v['serialNumber']).isEmpty ? '—' : tStr(v['serialNumber'])),
      assetLine('Supplier', tStr(v['supplierName']).isEmpty ? '—' : tStr(v['supplierName'])),
      assetLine('Recorded by', tStr(v['createdBy']).isEmpty ? '—' : tStr(v['createdBy'])),
      assetLine('Recorded', tStr(v['createdAt']).isEmpty ? '—' : fmtInstant(v['createdAt'], widget.offset)),
      if (tStr(v['description']).isNotEmpty) assetLine('Description', tStr(v['description'])),
      if (tStr(v['notes']).isNotEmpty) assetLine('Notes', tStr(v['notes'])),
      if (!closed) ...[
        const Divider(height: 24),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (widget.onEdit != null)
            OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Edit investment')),
          if (widget.onAddCost != null)
            Tooltip(
              message: locked ? costLockedByDepreciationNote : 'Add capitalised cost',
              child: OutlinedButton.icon(
                  onPressed: locked ? null : widget.onAddCost, icon: const Icon(Icons.payments_outlined, size: 15), label: const Text('Add cost')),
            ),
          if (widget.onCorrectOriginalCost != null)
            Tooltip(
              message: tNum(v['acquisitionCost']) <= 0
                  ? 'This investment has no original acquisition to correct — its cost was built up with Add cost.'
                  : 'Fix a mistake in what the original acquisition was recorded as costing',
              child: OutlinedButton.icon(
                onPressed: tNum(v['acquisitionCost']) <= 0 ? null : widget.onCorrectOriginalCost,
                icon: const Icon(Icons.tune, size: 15),
                label: const Text('Correct original cost'),
              ),
            ),
          if (widget.onOpenFullPage != null) TextButton(onPressed: widget.onOpenFullPage, child: const Text('Open full page')),
        ]),
      ],
      if (locked) ...[
        const SizedBox(height: 10),
        _amberNote(costLockedByDepreciationNote),
      ],
    ]);
  }

  Widget _paymentText(Map c) {
    if (tStr(c['sourceType']) == 'OriginalCostCorrection') {
      return const Text('Adjusts the acquisition', style: TextStyle(fontSize: 12, color: TColors.slate500));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${tStr(c['paymentStatus']).isEmpty ? '—' : tStr(c['paymentStatus'])}${tStr(c['paymentMethod']).isNotEmpty ? ' · ${tStr(c['paymentMethod'])}' : ''}',
          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      if (tNum(c['balance']) > 0) Text('${_fmt(tNum(c['balance']))} owed', style: const TextStyle(fontSize: 11, color: TColors.amber700)),
    ]);
  }

  Widget _costBadge(Map c) {
    final src = tStr(c['sourceType']);
    final (bg, fg, border) = src == 'OriginalCostCorrection'
        ? (const Color(0xFFFFF1F2), TColors.rose700, const Color(0xFFFDA4AF))
        : src == 'Acquisition'
            ? (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), TColors.blue300)
            : (const Color(0xFFF5F3FF), const Color(0xFF6D28D9), const Color(0xFFC4B5FD));
    return TBadge(costTypeLabel(c), bg: bg, fg: fg, border: border);
  }

  Widget _costs(Map v, List<Map> posted, List<Map> reversed) {
    final locked = tNum(v['depreciationEntries']) > 0;
    final total = posted.fold<num>(0, (s, c) => s + tNum(c['amount']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (posted.isEmpty)
        _box(Text(
          'Nothing has been capitalised into this investment yet, so its cost is ${_fmt(0)}. Use “Add cost” to build it up — that is how a investment that is constructed rather than bought is recorded.',
          style: const TextStyle(fontSize: 13, color: TColors.slate600),
        ))
      else ...[
        for (final c in posted) ...[
          _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _costBadge(c),
                  const SizedBox(height: 4),
                  Text(tStr(c['description']).isEmpty ? '—' : tStr(c['description']),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColors.slate900)),
                  Text('${_dt(c['costDate'], c)}${tStr(c['supplierName']).isNotEmpty ? ' · ${tStr(c['supplierName'])}' : ''}',
                      style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
              ),
              Text(signedMoney(_fmt, tNum(c['amount'])),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tNum(c['amount']) < 0 ? TColors.red600 : null)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _paymentText(c)),
              if (widget.onViewCost != null)
                IconButton(
                  tooltip: 'View everything recorded about this cost',
                  onPressed: () => widget.onViewCost!(c),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                ),
              if (widget.onReverseCost != null && costReversible(c))
                IconButton(
                  tooltip: locked ? costLockedByDepreciationNote : 'Reverse this cost',
                  onPressed: locked ? null : () => widget.onReverseCost!(c),
                  icon: Icon(Icons.undo, size: 18, color: locked ? null : const Color(0xFFEF4444)),
                ),
            ]),
          ])),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            const Expanded(child: Text('Total capitalised cost', style: TextStyle(fontSize: 13, color: TColors.slate700))),
            Text(_fmt(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ],
      if (reversed.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            sectionLabel('Reversed — kept on the record, excluded from the total'),
            for (final c in reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${_dt(c['costDate'], c)} · ${tStr(c['description']).isEmpty ? '—' : tStr(c['description'])}',
                          style: const TextStyle(fontSize: 13, color: TColors.slate500, decoration: TextDecoration.lineThrough)),
                    ),
                    Text(signedMoney(_fmt, tNum(c['amount'])),
                        style: const TextStyle(fontSize: 13, color: TColors.slate500, decoration: TextDecoration.lineThrough)),
                  ]),
                  if (tStr(c['reversalReason']).isNotEmpty)
                    Text(
                      'Reversed${tStr(c['reversedBy']).isNotEmpty ? ' by ${tStr(c['reversedBy'])}' : ''}'
                      '${tStr(c['reversedAt']).isNotEmpty ? ' on ${fmtInstant(c['reversedAt'], widget.offset)}' : ''}: ${tStr(c['reversalReason'])}',
                      style: const TextStyle(fontSize: 11, color: TColors.slate500),
                    ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _depreciation(Map v, List<Map> rows) {
    final life = tIntOrNull(v['usefulLifeMonths']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _grid([
        assetFigure('Depreciable basis', _fmt(tNum(v['depreciableAmount'])),
            hint: 'Total capitalised cost less the residual value. This is what is charged to profit over the life.'),
        assetFigure('Monthly charge', tNum(v['monthlyDepreciation']) != 0 ? _fmt(tNum(v['monthlyDepreciation'])) : '—',
            hint: life != null && life > 0 ? 'Straight line over $life months.' : 'No useful life set yet.'),
        assetFigure('Charged so far', _fmt(tNum(v['accumulatedDepreciation'])), tone: TColors.amber800),
        assetFigure('Still to charge', _fmt(tNum(v['remainingDepreciable'])), tone: TColors.emerald800),
      ]),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('No depreciation has been posted for this investment yet.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
          if (tStr(v['status']) == 'Draft')
            const Text('It is not in service, so it does not depreciate. Set an in-service date and a useful life to start.',
                style: TextStyle(fontSize: 11, color: TColors.slate500))
          else if (tNum(v['remainingDepreciable']) > 0)
            const Text('Depreciation may be due. Use the Depreciation button above the list to review and post it.',
                style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ]))
      else
        for (final d in rows) ...[
          Opacity(
            opacity: tStr(d['status']) == 'Reversed' ? .6 : 1,
            child: _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtMonthYear(d['periodStart']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      '${tStr(d['sourceType'])}${tStr(d['depreciationDate']).isNotEmpty ? ' · posted ${_dt(d['depreciationDate'], d)}' : ''}',
                      style: const TextStyle(fontSize: 11, color: TColors.slate500),
                    ),
                  ]),
                ),
                Text(signedMoney(_fmt, tNum(d['amount'])),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tNum(d['amount']) < 0 ? TColors.red600 : null)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text('Accumulated ${d['accumulatedAfter'] != null ? _fmt(tNum(d['accumulatedAfter'])) : '—'}',
                        style: const TextStyle(fontSize: 11, color: TColors.slate500))),
                Expanded(
                    child: Text('Book value after ${d['bookValueAfter'] != null ? _fmt(tNum(d['bookValueAfter'])) : '—'}',
                        style: const TextStyle(fontSize: 11, color: TColors.slate500))),
              ]),
              Wrap(alignment: WrapAlignment.spaceBetween, children: [
                if (d['expenseId'] != null)
                  TextButton.icon(
                    onPressed: widget.onOpenExpenses,
                    icon: const Icon(Icons.receipt_long, size: 14),
                    label: Text('Expense #${tStr(d['expenseId'])}', style: const TextStyle(fontSize: 11)),
                  ),
                if (widget.onReverseDepreciation != null && tStr(d['status']) == 'Posted' && tNum(d['amount']) > 0)
                  TextButton.icon(
                    onPressed: () => widget.onReverseDepreciation!(d),
                    icon: const Icon(Icons.undo, size: 14, color: Color(0xFFEF4444)),
                    label: const Text('Reverse'),
                  ),
              ]),
            ])),
          ),
          const SizedBox(height: 8),
        ],
      Text('$depreciationNoncashNote $depreciationConventionNote', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
    ]);
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: child,
      );
}

Widget _amberNote(String text) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(6)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, size: 15, color: TColors.amber900),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, color: TColors.amber900))),
      ]),
    );

Widget amberNote(String text) => _amberNote(text);

/// CostDetailDialog: everything recorded about one cost row.
class CostDetailDialog extends StatelessWidget {
  const CostDetailDialog({
    super.key,
    required this.cost,
    required this.assetName,
    required this.fmt,
    required this.offset,
    this.onReverse,
    this.reverseDisabledReason,
    this.onOpenExpenses,
  });
  final Map cost;
  final String? assetName;
  final FarmMoney fmt;
  final Duration offset;
  final VoidCallback? onReverse, onOpenExpenses;
  final String? reverseDisabledReason;

  @override
  Widget build(BuildContext context) {
    final c = cost;
    final correction = tStr(c['sourceType']) == 'OriginalCostCorrection';
    final label = costTypeLabel(c);
    String dt(Object? d, [Map? r]) => fmtDateTime(d, r, offset);
    Widget row(String l, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Flexible(child: Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate600))),
            const SizedBox(width: 16),
            Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
          ]),
        );
    Text t(String s, {Color? color}) => Text(s, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: color ?? TColors.slate900));
    final amount = tNum(c['amount']);
    return AlertDialog(
      scrollable: true,
      title: Text(label),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            correction
                ? "A correction to what this investment was recorded as costing. It amended the original acquisition's own document — no second payment and no second expense were created."
                : "One amount capitalised into ${assetName ?? 'this investment'}. It increased what the investment is worth and was not charged against this period's profit.",
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          sectionLabel('The cost'),
          row('Amount', Text(amount < 0 ? '−${fmt(amount.abs())}' : fmt(amount),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: amount < 0 ? TColors.red600 : null))),
          row('Date', t(dt(c['costDate'], c).isEmpty ? '—' : dt(c['costDate'], c))),
          row('Cost type', TBadge(label, bg: Colors.white, fg: TColors.slate700, border: TColors.slate300)),
          row(correction ? 'Reason' : 'What it was for', t(tStr(c['description']).isEmpty ? '—' : tStr(c['description']))),
          row(
            'Status',
            tStr(c['status']) == 'Posted'
                ? TBadge(tStr(c['status']), bg: const Color(0xFFECFDF5), fg: TColors.emerald700, border: TColors.emerald300)
                : TBadge(tStr(c['status']), bg: const Color(0xFFFEF2F2), fg: const Color(0xFFB91C1C), border: const Color(0xFFFCA5A5)),
          ),
          if (!correction) ...[
            const SizedBox(height: 12),
            sectionLabel('Who was paid, and how'),
            row('Supplier / payee', t(tStr(c['supplierName']).isEmpty ? '—' : tStr(c['supplierName']))),
            row('Payment status', t(tStr(c['paymentStatus']).isEmpty ? '—' : tStr(c['paymentStatus']))),
            row('Payment method', t(tStr(c['paymentMethod']).isEmpty ? '—' : tStr(c['paymentMethod']))),
            if (c['amountPaid'] != null) row('Amount paid', t(fmt(tNum(c['amountPaid'])))),
            if (tNum(c['balance']) > 0) row('Balance owed', t(fmt(tNum(c['balance'])), color: TColors.amber700)),
            if (tStr(c['dueDate']).isNotEmpty) row('Balance due', t(dt(c['dueDate']))),
            if (tStr(c['cashAccountName']).isNotEmpty) row('Paid from', t(tStr(c['cashAccountName']))),
          ],
          const SizedBox(height: 12),
          sectionLabel('The record behind it'),
          c['expenseId'] != null
              ? row(
                  'Expense',
                  InkWell(
                    onTap: onOpenExpenses,
                    child: Text('Expense #${tStr(c['expenseId'])}',
                        style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
                  ),
                )
              : row('Expense', t('None — nothing was paid or owed for this entry.', color: TColors.slate500)),
          if (tStr(c['expenseCategory']).isNotEmpty) row('Filed under', t(tStr(c['expenseCategory']))),
          if (c['expenseAmount'] != null) row(correction ? 'Document now reads' : 'Document total', t(fmt(tNum(c['expenseAmount'])))),
          row('Recorded by', t(tStr(c['createdBy']).isEmpty ? '—' : tStr(c['createdBy']))),
          row('Recorded', t(tStr(c['createdAt']).isEmpty ? '—' : dt(c['createdAt']))),
          if (tStr(c['status']) != 'Posted') ...[
            row('Reversed by', t(tStr(c['reversedBy']).isEmpty ? '—' : tStr(c['reversedBy']))),
            row('Reversed', t(tStr(c['reversedAt']).isEmpty ? '—' : dt(c['reversedAt']))),
            row('Reversal reason', t(tStr(c['reversalReason']).isEmpty ? '—' : tStr(c['reversalReason']))),
          ],
        ]),
      ),
      actions: [
        if (onReverse != null && costReversible(c))
          Tooltip(
            message: reverseDisabledReason ?? 'Reverse this cost',
            child: OutlinedButton.icon(
              onPressed: reverseDisabledReason != null ? null : onReverse,
              style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reverse this cost'),
            ),
          ),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

/// CorrectOriginalCostDialog. [onSubmit] throws to keep the dialog open with the error.
class CorrectOriginalCostDialog extends StatefulWidget {
  const CorrectOriginalCostDialog({super.key, required this.asset, required this.fmt, required this.onSubmit});
  final Map asset;
  final FarmMoney fmt;
  final Future<void> Function(num newAmount, String? effectiveDate, String reason) onSubmit;

  @override
  State<CorrectOriginalCostDialog> createState() => _CorrectOriginalCostDialogState();
}

class _CorrectOriginalCostDialogState extends State<CorrectOriginalCostDialog> {
  late final _amount = TextEditingController(text: _plain(tNum(widget.asset['acquisitionCost'])));
  final _reason = TextEditingController();
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;
  String? _error;

  static String _plain(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(CorrectionPreview p) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(p.next, _date.isEmpty ? null : _date, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final fmt = widget.fmt;
    final acq = tNum(a['acquisitionCost']), add = tNum(a['additionalCost']), total = tNum(a['totalCapitalizedCost']);
    final res = tNum(a['residualValue']), acc = tNum(a['accumulatedDepreciation']);
    final life = tIntOrNull(a['usefulLifeMonths']);
    final deps = tIntOrNull(a['depreciationEntries']) ?? 0;
    final p = previewCorrection(
      acquisitionCost: acq,
      additionalCost: add,
      residualValue: res,
      usefulLifeMonths: life,
      accumulatedDepreciation: acc,
      newAcquisitionCost: num.tryParse(_amount.text),
    );
    final canSave = p != null && !p.residualTooHigh && _reason.text.trim().isNotEmpty && !_saving;
    final curDep = round2(total - res) > 0 ? round2(total - res) : 0;
    final curRem = round2(curDep - acc) > 0 ? round2(curDep - acc) : 0;
    Widget ro(String label, String value, {Color? color}) => FilterLabel(
          label,
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Text(value, style: TextStyle(color: color ?? TColors.slate500)),
          ),
        );
    Widget change(String label, String from, String to) {
      final same = from == to || to == 'unchanged';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)))),
          Flexible(
            child: same
                ? Text('${to == 'unchanged' ? from : to} (unchanged)', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)))
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(text: from, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0x990C4A6E))),
                      const TextSpan(text: ' → '),
                      TextSpan(text: to, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
                  ),
          ),
        ]),
      );
    }

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.tune, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text('Correct the original cost of ${tStr(a['assetName'])}')),
        ]),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(correctOriginalCostNote, style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            ro('Current original acquisition cost', fmt(acq)),
            if (add > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Plus ${fmt(add)} of additional costs, which this does not touch.',
                    style: const TextStyle(fontSize: 11, color: TColors.slate500)),
              ),
            const SizedBox(height: 10),
            FilterLabel(
              'Corrected original acquisition cost',
              AppInput(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Effective date',
              AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d))),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('The date the correction is recorded against. It does not move the acquisition date.',
                  style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ),
            const SizedBox(height: 10),
            ro('Difference', p == null ? '—' : '${p.difference < 0 ? '−' : '+'}${fmt(p.difference.abs())}',
                color: p != null && p.difference < 0 ? TColors.red600 : null),
            const SizedBox(height: 10),
            FilterLabel('Reason *',
                AppInput(controller: _reason, minLines: 2, maxLines: 4, hintText: 'Original invoice amount was entered incorrectly', onChanged: (_) => setState(() {}))),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text("Required. It is kept on the investment's cost history with your name and the date.",
                  style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ),
            if (p != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('What this will change — a projection, not yet saved',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
                  const SizedBox(height: 6),
                  change('Total capitalised cost', fmt(total), fmt(p.newTotal)),
                  change('Depreciable basis', fmt(curDep), fmt(p.newDepreciable)),
                  change('Current book value', fmt(tNum(a['currentBookValue'])), fmt(p.newBookValue)),
                  change('Monthly depreciation', life != null && life > 0 ? fmt(round2(curDep / life)) : '—',
                      p.newMonthly != null ? fmt(p.newMonthly!) : '—'),
                  change('Still to be charged to profit', fmt(curRem), fmt(p.newRemaining)),
                  change('Depreciation already posted', fmt(acc), 'unchanged'),
                  const SizedBox(height: 4),
                  Text(
                    p.difference < 0
                        ? 'Cash already recorded as paid is reduced to the corrected amount and the difference is returned to the account it came from. No second payment and no second expense are created.'
                        : 'The amount recorded as owed rises by ${fmt(p.difference.abs())}. No payment is created — correcting what something cost does not spend money.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
                  ),
                ]),
              ),
            ],
            if (deps > 0) ...[
              const SizedBox(height: 10),
              _amberNote('$deps month(s) of depreciation have already been posted for this investment. $correctionDepreciationNote'),
            ],
            if (p != null && p.residualTooHigh) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFCA5A5)), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'The residual value of ${fmt(res)} would be more than the corrected cost of ${fmt(p.newTotal)}. Lower the residual value first — book value can never fall below it.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
                ),
              ),
            ],
            if (p != null && !p.residualTooHigh && (p.overDepreciated || p.nothingLeft)) ...[
              const SizedBox(height: 10),
              _amberNote(
                  'After this correction there is nothing further to depreciate. The months already charged stand as charged and nothing more will be due — the investment will read as fully depreciated.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: canSave ? () => _save(p) : null, child: Text(_saving ? 'Saving…' : 'Record correction')),
        ],
      ),
    );
  }
}

/// PromptDialog (free text): a required reason, the error shown inline, the
/// dialog kept open when [onSubmit] throws. Pops true when done.
class ReasonTextPrompt extends StatefulWidget {
  const ReasonTextPrompt({
    super.key,
    required this.title,
    required this.description,
    required this.placeholder,
    required this.confirmLabel,
    required this.onSubmit,
    this.label = 'Reason',
  });
  final String title, description, placeholder, confirmLabel, label;
  final Future<void> Function(String reason) onSubmit;

  @override
  State<ReasonTextPrompt> createState() => _ReasonTextPromptState();
}

class _ReasonTextPromptState extends State<ReasonTextPrompt> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final t = _text.text.trim();
    if (t.isEmpty) return setState(() => _error = '${widget.label} is required.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(t);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              FilterLabel(widget.label, AppInput(controller: _text, autofocus: true, minLines: 4, maxLines: 6, hintText: widget.placeholder)),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFBE123C))),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: _busy ? null : _go,
              style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      );
}
