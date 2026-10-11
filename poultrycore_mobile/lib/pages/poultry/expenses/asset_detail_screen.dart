import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'asset_logic.dart';
import 'asset_widgets.dart';
import 'assets_screen.dart';

/// One capital investment, as `app/poultry-assets/[id]/page.tsx`: General,
/// Financial and Source & audit, the cost history and the depreciation
/// history with its reversal.
class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({super.key, required this.session, required this.company, required this.assetId});
  final Session session;
  final Company company;
  final int assetId;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  Map? _asset;
  bool _loading = true;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;
  late final AssetApi _api = AssetApi(widget.session, widget.company);

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final a = await _api.get(widget.assetId);
      if (mounted) setState(() => _asset = a);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load the investment', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _dt(Object? d, [Map? r]) => fmtDateTime(d, r, _offset);

  /// The web's router.push("/poultry-assets"): back when the register is underneath.
  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => AssetsScreen(session: widget.session, company: widget.company)));
    }
  }

  Future<void> _reverse(Map d) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _ReverseChargeDialog(api: _api, entryId: tIntOrNull(d['poultryAssetDepreciationId']) ?? 0));
    if (done == true && mounted) {
      trackerToast(context, 'Depreciation reversed', description: 'The original entry is kept and an opposite entry added. No cash moved.');
      await _load();
    }
  }

  Widget _card(String title, List<Widget> lines) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sectionLabel(title), ...lines]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-assets');
    final a = _asset;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(a == null ? 'Capital investment' : tStr(a['assetName']))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : a == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Capital investment not found. ', style: TextStyle(color: TColors.slate600)),
                    InkWell(
                      onTap: _back,
                      child: const Text('Back to Capital Investments/Assets', style: TextStyle(decoration: TextDecoration.underline)),
                    ),
                  ]),
                )
              : RefreshIndicator(onRefresh: _load, child: _body(a)),
    );
  }

  Widget _body(Map a) {
    final gh = _gh;
    final costs = [for (final c in a['costs'] as List? ?? const []) c as Map];
    final posted = [for (final c in costs) if (tStr(c['status']) == 'Posted') c];
    final reversed = costs.length - posted.length;
    final deps = [for (final d in a['depreciation'] as List? ?? const []) d as Map];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _back,
            style: TextButton.styleFrom(foregroundColor: TColors.slate600, padding: EdgeInsets.zero),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to Capital Investments'),
          ),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: TColors.emerald100, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.business, color: TColors.emerald700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(a['assetName']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                assetStatusBadge(a['status']),
                Text(tStr(a['assetNumber']), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.slate500)),
                if (tStr(a['categoryName']).isNotEmpty) Text('· ${tStr(a['categoryName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                Text('· Acquired ${_dt(a['acquisitionDate'], a)}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                if (tStr(a['location']).isNotEmpty) Text('· ${tStr(a['location'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ]),
          ),
        ]),
        if (tStr(a['status']) == 'Reversed' && tStr(a['reversalReason']).isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
            child: Text('This acquisition was reversed: ${tStr(a['reversalReason'])}', style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
          ),
        ],
        const SizedBox(height: 12),
        _card('General', [
          assetLine('Category', tStr(a['categoryName']).isEmpty ? '—' : tStr(a['categoryName'])),
          assetLine('Description', tStr(a['description']).isEmpty ? '—' : tStr(a['description'])),
          assetLine('Acquired', _dt(a['acquisitionDate'], a).isEmpty ? '—' : _dt(a['acquisitionDate'], a)),
          assetLine('In service', tStr(a['inServiceDate']).isNotEmpty ? _dt(a['inServiceDate']) : 'Not in service'),
          assetLine('Location', tStr(a['location']).isEmpty ? '—' : tStr(a['location'])),
          assetLine('Serial number', tStr(a['serialNumber']).isEmpty ? '—' : tStr(a['serialNumber'])),
        ]),
        const SizedBox(height: 12),
        _card('Financial', [
          assetLine(acquisitionCostLabel, gh(tNum(a['acquisitionCost'])), hint: acquisitionCostTooltip),
          assetLine(additionalCostLabel, gh(tNum(a['additionalCost'])), hint: additionalCostTooltip),
          assetLine(totalCapitalizedCostLabel, gh(tNum(a['totalCapitalizedCost'])), hint: totalCapitalizedCostTooltip, bold: true),
          assetLine('Residual value', gh(tNum(a['residualValue']))),
          assetLine('Depreciable amount', gh(tNum(a['depreciableAmount']))),
          assetLine('Useful life', tNum(a['usefulLifeMonths']) > 0 ? '${tStr(a['usefulLifeMonths'])} months' : 'Not set'),
          assetLine('Monthly depreciation', tNum(a['monthlyDepreciation']) != 0 ? gh(tNum(a['monthlyDepreciation'])) : '—'),
          assetLine('Depreciation so far', gh(tNum(a['accumulatedDepreciation'])), color: TColors.amber800),
          assetLine('Book value', gh(tNum(a['currentBookValue'])), hint: bookValueTooltip, bold: true, color: TColors.emerald800),
        ]),
        const SizedBox(height: 12),
        _card('Source & audit', [
          assetLine('Supplier', tStr(a['supplierName']).isEmpty ? '—' : tStr(a['supplierName'])),
          assetLine('Cost entries', tStr(a['costEntries']).isEmpty ? '0' : tStr(a['costEntries'])),
          assetLine('Depreciation entries', tStr(a['depreciationEntries']).isEmpty ? '0' : tStr(a['depreciationEntries'])),
          assetLine('Recorded by', tStr(a['createdBy']).isEmpty ? '—' : tStr(a['createdBy'])),
          assetLine('Recorded', tStr(a['createdAt']).isEmpty ? '—' : fmtInstant(a['createdAt'], _offset)),
          if (tStr(a['disposalDate']).isNotEmpty) ...[
            assetLine('Disposed', _dt(a['disposalDate']).isEmpty ? '—' : _dt(a['disposalDate'])),
            assetLine('Proceeds', a['disposalProceeds'] != null ? gh(tNum(a['disposalProceeds'])) : '—'),
          ],
        ]),
        const SizedBox(height: 12),
        _card('Cost history', [
          TrackerTable(
            emptyText: 'Nothing capitalised yet. Use "Add cost" on the register to build this investment up.',
            columns: const [
              TCol('Date', width: 140),
              TCol('What for', width: 150),
              TCol('Type', width: 140),
              TCol('Supplier', width: 120),
              TCol('Payment', width: 120),
              TCol('Amount', right: true, width: 120),
            ],
            rows: [
              for (final c in posted)
                [
                  cellText(_dt(c['costDate'], c)),
                  cellText(tStr(c['description']).isEmpty ? '—' : tStr(c['description'])),
                  Text(
                    tStr(c['sourceType']) == 'Acquisition'
                        ? 'Original acquisition'
                        : (tStr(c['costCategory']).isNotEmpty ? tStr(c['costCategory']) : (tStr(c['sourceType']).isEmpty ? '—' : tStr(c['sourceType']))),
                    style: const TextStyle(color: TColors.slate500),
                  ),
                  cellText(tStr(c['supplierName']).isEmpty ? '—' : tStr(c['supplierName'])),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tStr(c['paymentStatus']).isEmpty ? '—' : tStr(c['paymentStatus'])),
                    if (tNum(c['balance']) > 0) Text('${gh(tNum(c['balance']))} owed', style: const TextStyle(fontSize: 11, color: TColors.amber700)),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(tNum(c['amount']) < 0 ? '−${gh(tNum(c['amount']).abs())}' : gh(tNum(c['amount'])),
                        style: TextStyle(color: tNum(c['amount']) < 0 ? TColors.red600 : null)),
                  ),
                ],
            ],
          ),
          if (reversed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$reversed reversed cost entr${reversed == 1 ? 'y is' : 'ies are'} kept on the record and excluded from the total.',
                style: const TextStyle(fontSize: 11, color: TColors.slate500),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _card('Depreciation history', [
          const Text(depreciationNoncashNote, style: TextStyle(fontSize: 11, color: TColors.slate500)),
          const SizedBox(height: 8),
          TrackerTable(
            emptyText: 'Nothing charged yet.${tStr(a['status']) == 'Draft' ? ' This investment is not in service, so it does not depreciate.' : ''}',
            columns: const [
              TCol('Period', width: 130),
              TCol('Type', width: 140),
              TCol('Charge', right: true, width: 110),
              TCol('Accumulated', right: true, width: 120),
              TCol('Book value', right: true, width: 120),
              TCol('Actions', right: true, width: 80),
            ],
            rows: [
              for (final d in deps)
                [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: fmtMonthYear(d['periodStart'])),
                    if (tStr(d['status']) == 'Reversed') const TextSpan(text: '  reversed', style: TextStyle(fontSize: 11, color: TColors.red600)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tStr(d['sourceType']), style: const TextStyle(color: TColors.slate500)),
                    if (tStr(d['reversalReason']).isNotEmpty) Text(tStr(d['reversalReason']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(gh(tNum(d['amount'])), style: TextStyle(color: tNum(d['amount']) < 0 ? TColors.red600 : null)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(d['accumulatedAfter'] != null ? gh(tNum(d['accumulatedAfter'])) : '—', style: const TextStyle(color: TColors.slate500)),
                  ),
                  Align(alignment: Alignment.centerRight, child: Text(d['bookValueAfter'] != null ? gh(tNum(d['bookValueAfter'])) : '—')),
                  Align(
                    alignment: Alignment.centerRight,
                    child: tStr(d['status']) == 'Posted' && tNum(d['amount']) > 0
                        ? IconButton(
                            tooltip: 'Reverse this charge',
                            onPressed: () => _reverse(d),
                            icon: const Icon(Icons.undo, size: 18, color: Color(0xFFEF4444)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 6),
          const Text(depreciationConventionNote, style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      ],
    );
  }
}

/// The page's own reversal dialog: a typed reason, a toast when it is missing.
class _ReverseChargeDialog extends StatefulWidget {
  const _ReverseChargeDialog({required this.api, required this.entryId});
  final AssetApi api;
  final int entryId;

  @override
  State<_ReverseChargeDialog> createState() => _ReverseChargeDialogState();
}

class _ReverseChargeDialogState extends State<_ReverseChargeDialog> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_reason.text.trim().isEmpty) return trackerToast(context, 'A reason is required', error: true);
    setState(() => _saving = true);
    try {
      await widget.api.reverseDepreciation(widget.entryId, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not reverse', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: const Text('Reverse this depreciation charge'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'The original entry is kept and an opposite one is written beside it, so the history still shows what was charged and when. No cash is affected. The month is NOT reopened to the automatic run — post a corrected amount as an adjustment if one is needed.',
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              _ReasonBox(controller: _reason),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving ? null : _go,
              style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
              child: Text(_saving ? 'Saving…' : 'Reverse'),
            ),
          ],
        ),
      );
}

class _ReasonBox extends StatelessWidget {
  const _ReasonBox({required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Wrong in-service month', border: OutlineInputBorder()),
      );
}
