// Generic → Admin → Business Features (`app/generic-business-features/page.tsx`
// with `lib/generic/recommended-modules.ts`): which features the company has
// on, grouped, with the recommended ones marked, dependent features switched
// off together, and "Restore Recommended". Turning a feature off hides it; no
// data is deleted.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'generic_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

// ------------------------------------------------- recommended-modules.ts

const _subscriptionDefaults = {
  'enableProducts': false, 'enableInventory': false, 'enableStockAdjustments': false, 'enableInternalUse': false,
  'enablePurchases': false, 'enableSubscriptions': true, 'enableInvoices': true, 'enableCustomerBalances': true,
  'enableStaffPayments': true, 'enableCashAccounts': true, 'enableRecurringExpenses': true, 'enableSupplierBalances': true,
};
const _retailDefaults = {
  'enableProducts': true, 'enableInventory': true, 'enableStockAdjustments': true, 'enableInternalUse': true,
  'enablePurchases': true, 'enableSubscriptions': false, 'enableInvoices': false, 'enableCustomerBalances': false,
  'enableStaffPayments': true, 'enableCashAccounts': true, 'enableRecurringExpenses': true, 'enableSupplierBalances': true,
};

/// getRecommendedModules: null for an unknown or missing template.
Map<String, bool>? recommendedGenericModules(String? template) => switch (template) {
      'SubscriptionServiceBusiness' => _subscriptionDefaults,
      'RetailBusiness' || 'GeneralBusiness' => _retailDefaults,
      _ => null,
    };

typedef GenericFeature = ({String key, String label, String description, String group});

const List<GenericFeature> genericFeatureCatalog = [
  (key: 'enableSubscriptions', label: 'Subscriptions', description: 'Plans, subscriptions and billing runs', group: 'Sales & Billing'),
  (key: 'enableInvoices', label: 'Invoices', description: 'Raise bills and track what is owed', group: 'Sales & Billing'),
  (key: 'enableCustomerBalances', label: 'Customer balances', description: 'See who owes money, with aged balances and statements', group: 'Sales & Billing'),
  (key: 'enableProducts', label: 'Products', description: 'A catalogue of things you sell', group: 'Inventory & Products'),
  (key: 'enableInventory', label: 'Inventory', description: 'Stock levels, movements and valuation', group: 'Inventory & Products'),
  (key: 'enableStockAdjustments', label: 'Stock adjustments', description: 'Corrections to stock on hand', group: 'Inventory & Products'),
  (key: 'enableInternalUse', label: 'Internal use', description: 'Stock consumed by the business itself', group: 'Inventory & Products'),
  (key: 'enablePurchases', label: 'Purchases', description: 'What you buy from suppliers', group: 'Inventory & Products'),
  (key: 'enableRecurringExpenses', label: 'Recurring expenses', description: 'Templates that raise a bill when it falls due', group: 'Expenses & Finance'),
  (key: 'enableSupplierBalances', label: 'Supplier balances', description: 'What you owe vendors — from expenses as well as purchases', group: 'Expenses & Finance'),
  (key: 'enableCashAccounts', label: 'Cash accounts', description: 'Tills, bank accounts and mobile money', group: 'Expenses & Finance'),
  (key: 'enableStaffPayments', label: 'Staff payments', description: 'Pay staff, contractors and commission-based workers', group: 'Employees & Payroll'),
];

/// groupedFeatures: the catalogue by group, in order.
List<(String, List<GenericFeature>)> groupedGenericFeatures() {
  final out = <(String, List<GenericFeature>)>[];
  for (final f in genericFeatureCatalog) {
    final i = out.indexWhere((g) => g.$1 == f.group);
    if (i < 0) {
      out.add((f.group, [f]));
    } else {
      out[i].$2.add(f);
    }
  }
  return out;
}

/// The page's DEPENDENCIES: (feature, requires).
const genericFeatureDependencies = [
  ('enableInventory', 'enableProducts'),
  ('enableStockAdjustments', 'enableInventory'),
  ('enableInternalUse', 'enableInventory'),
  ('enableInvoices', 'enableSubscriptions'),
  ('enableCustomerBalances', 'enableInvoices'),
];

/// getDependents: every switched-on feature that (through others) needs [key].
List<String> genericFeatureDependents(String key, Map<String, dynamic> modules) {
  final result = <String>[];
  final queue = [key];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final (feature, requires) in genericFeatureDependencies) {
      if (requires == current && modules[feature] == true && !result.contains(feature)) {
        result.add(feature);
        queue.add(feature);
      }
    }
  }
  return result;
}

/// The page's toggle: flip [key]; switching off also switches off its dependents.
Map<String, dynamic> toggleGenericFeature(Map<String, dynamic> modules, String key) {
  final on = modules[key] != true;
  final updated = {...modules, key: on};
  if (!on) {
    for (final d in genericFeatureDependents(key, modules)) {
      updated[d] = false;
    }
  }
  return updated;
}

/// restoreChanges: what Restore Recommended would switch on and off.
({List<String> toEnable, List<String> toDisable}) genericRestoreChanges(Map<String, dynamic>? modules, Map<String, bool>? rec) {
  if (modules == null || rec == null) return (toEnable: <String>[], toDisable: <String>[]);
  final on = <String>[], off = <String>[];
  for (final e in rec.entries) {
    if (e.value && modules[e.key] != true) on.add(e.key);
    if (!e.value && modules[e.key] == true) off.add(e.key);
  }
  return (toEnable: on, toDisable: off);
}

String _featureLabel(String key) => genericFeatureCatalog.where((f) => f.key == key).firstOrNull?.label ?? key;

// ------------------------------------------------------------------ page

class GenericBusinessFeaturesScreen extends StatefulWidget {
  const GenericBusinessFeaturesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericBusinessFeaturesScreen> createState() => _State();
}

class _State extends State<GenericBusinessFeaturesScreen> {
  bool _loading = true, _saving = false, _dirty = false;
  Map<String, dynamic>? _modules;
  Map<String, bool>? _recommended;
  String? _industryLabel;

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Object? m, t;
    String? error;
    try {
      m = await _api.get('$_base/module-settings');
    } on ApiException catch (e) {
      error = e.message;
    }
    try {
      t = await _api.get('$_base/business-template');
    } on ApiException catch (_) {}
    if (!mounted) return;
    if (error != null) trackerToast(context, 'Could not load feature settings', description: error, error: true);
    setState(() {
      if (m is Map) _modules = Map<String, dynamic>.from(m);
      if (t is Map) {
        _recommended = recommendedGenericModules(tStr(t['genericBusinessTemplate']).isEmpty ? null : tStr(t['genericBusinessTemplate']));
        final industry = tStr(t['genericIndustryTemplate']);
        _industryLabel = businessTypeForIndustry(industry)?.label ?? (industry.isEmpty ? null : industry);
      }
      _loading = false;
    });
  }

  Future<bool> _put(Map<String, dynamic> modules) async {
    final rest = {...modules}..remove('farmId');
    final saved = await _api.put('$_base/module-settings', body: rest);
    if (saved is Map) _modules = Map<String, dynamic>.from(saved);
    invalidateGenericModules(widget.company.farmId);
    return true;
  }

  Future<void> _save() async {
    if (_modules == null) return;
    setState(() => _saving = true);
    try {
      await _put(_modules!);
      _dirty = false;
      if (mounted) trackerToast(context, 'Business features saved');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _restore() async {
    final c = genericRestoreChanges(_modules, _recommended);
    final ok = await showDialog<bool>(context: context, builder: (_) => _RestoreDialog(industry: _industryLabel ?? '', changes: c, apply: () async {
          try {
            await _put({..._modules!, ..._recommended!});
            _dirty = false;
            return null;
          } on ApiException catch (e) {
            return e.message;
          }
        }));
    if (!mounted) return;
    if (ok == true) {
      setState(() {});
      trackerToast(context, 'Recommended features restored', description: 'Your menus now match the recommended configuration.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-business-features');
    final c = genericRestoreChanges(_modules, _recommended);
    final canRestore = c.toEnable.isNotEmpty || c.toDisable.isNotEmpty;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Business Features')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        const Row(children: [
          Icon(Icons.tune, size: 24, color: Tone.fg(0xFF4F46E5)),
          SizedBox(width: 8),
          Expanded(child: Text('Business Features', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Your business is already set up with the recommended features. You can customise which features appear in your workspace anytime.',
          style: TextStyle(fontSize: 14, color: TColors.slate500),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_recommended != null)
            OutlinedButton.icon(
              key: const ValueKey('features-restore'),
              onPressed: _loading || !canRestore ? null : _restore,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restore Recommended'),
            ),
          FilledButton.icon(
            key: const ValueKey('features-save'),
            onPressed: _saving || _loading || _modules == null || !_dirty ? null : _save,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Changes'),
          ),
        ]),
        const SizedBox(height: 14),
        if (_loading)
          const Text('Loading…', style: TextStyle(color: TColors.slate500))
        else ...[
          if (_industryLabel != null)
            TCard(
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Tone.bg(0xFFE0E7FF), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_user_outlined, size: 20, color: Tone.fg(0xFF4F46E5)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Business Type: $_industryLabel', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                    Text('Recommended Configuration: ${_recommended != null ? 'Applied' : 'Not available'}',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          if (_modules == null)
            const TCard(child: Padding(padding: EdgeInsets.all(12), child: Text('Feature settings could not be loaded.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500))))
          else ...[
            for (final (group, features) in groupedGenericFeatures())
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(group, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
                    for (final (i, f) in features.indexed) ...[
                      if (i > 0) const Divider(height: 1, color: TColors.slate200),
                      _row(f),
                    ],
                  ]),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 20, color: Tone.fg(0xFF94A3B8)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Disabling a feature hides it from menus', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate600)),
                    SizedBox(height: 4),
                    Text(
                      'All your data is preserved. If you re-enable a feature later, everything — transactions, reports, history — will still be there.',
                      style: TextStyle(fontSize: 14, color: TColors.slate600),
                    ),
                  ]),
                ),
              ]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _row(GenericFeature f) {
    final on = _modules![f.key] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(f.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
              if (_recommended?[f.key] == true) const TBadge('Recommended', bg: Tone.bg(0xFFEEF2FF), fg: Tone.fg(0xFF4338CA), border: Tone.line(0xFFC7D2FE)),
            ]),
            const SizedBox(height: 2),
            Text(f.description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(on ? 'Enabled' : 'Disabled', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: on ? TColors.emerald600 : const Tone.fg(0xFF94A3B8))),
        Switch(
          key: ValueKey('feature-${f.key}'),
          value: on,
          onChanged: (_) => setState(() {
            _modules = toggleGenericFeature(_modules!, f.key);
            _dirty = true;
          }),
        ),
      ]),
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.industry, required this.changes, required this.apply});
  final String industry;
  final ({List<String> toEnable, List<String> toDisable}) changes;

  /// Saves; returns an error message, or null when it worked.
  final Future<String?> Function() apply;
  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final err = await widget.apply();
    if (!mounted) return;
    if (err == null) return Navigator.pop(context, true);
    trackerToast(context, 'Could not restore', description: err, error: true);
    setState(() => _busy = false);
  }

  Widget _list(String title, Color color, List<String> keys, Widget mark) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
          const SizedBox(height: 4),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [mark, const SizedBox(width: 8), Text(_featureLabel(k), style: const TextStyle(fontSize: 14, color: TColors.slate600))]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Restore Recommended Features'),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'This will reset your features to the recommended configuration for '),
                TextSpan(text: widget.industry, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '. Your data is never deleted.'),
              ]),
              style: const TextStyle(fontSize: 14, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            if (widget.changes.toEnable.isNotEmpty)
              _list('Features to enable:', TColors.emerald700, widget.changes.toEnable, const Icon(Icons.check, size: 14, color: Tone.fg(0xFF10B981))),
            if (widget.changes.toDisable.isNotEmpty)
              _list('Features to disable:', TColors.amber700, widget.changes.toDisable, const Text('—', style: TextStyle(color: Tone.fg(0xFFF59E0B)))),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'All existing data, transactions, reports and history will be preserved. No records are deleted when features are enabled or disabled.',
                style: TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.icon(
            key: const ValueKey('features-restore-go'),
            onPressed: _busy ? null : _go,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(_busy ? 'Restoring…' : 'Restore Recommended Features'),
          ),
        ],
      );
}
