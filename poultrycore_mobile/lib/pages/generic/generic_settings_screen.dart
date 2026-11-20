// Generic → Admin → Settings, as `app/generic-settings/page.tsx`: which
// modules the company has (twelve switches the menu is built from) and how
// they behave (subscription defaults, dashboard cards), saved together.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'generic_kit.dart';
import 'generic_setup_screen.dart';

/// BILLING_FREQUENCIES with FREQUENCY_LABELS (lib/generic/billing-schedule.ts).
const genericBillingFrequencies = [
  ('Weekly', 'Every week'),
  ('Monthly', 'Every month'),
  ('Quarterly', 'Every 3 months'),
  ('Termly', 'Every term (4 months)'),
  ('SemiAnnual', 'Every 6 months'),
  ('Annual', 'Every year'),
  ('OneTime', 'One time only'),
];

class GenericSettingsScreen extends StatefulWidget {
  const GenericSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericSettingsScreen> createState() => _GenericSettingsScreenState();
}

class _GenericSettingsScreenState extends State<GenericSettingsScreen> {
  bool _loading = true, _saving = false;
  Map<String, dynamic>? _modules, _settings;
  GenericModules _gm = const GenericModules();
  final _dueDays = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dueDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    loadGenericModules(widget.session, widget.company).then((v) {
      if (mounted) setState(() => _gm = v);
    });
    // allSettled: one half failing must not blank the other.
    Map<String, dynamic>? m, s;
    try {
      final r = await _api.get('$_base/module-settings');
      if (r is Map) m = Map<String, dynamic>.from(r);
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load modules', description: e is ApiException ? e.message : '$e', error: true);
    }
    try {
      final r = await _api.get('$_base/business-settings');
      if (r is Map) s = Map<String, dynamic>.from(r);
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load settings', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (!mounted) return;
    setState(() {
      _modules = m;
      _settings = s;
      if (s != null) _dueDays.text = '${tNum(s['defaultPaymentDueDays']).toInt()}';
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_modules == null || _settings == null) return;
    setState(() => _saving = true);
    try {
      final modules = {..._modules!}..remove('farmId');
      final r = await Future.wait([
        _api.put('$_base/module-settings', body: modules),
        _api.put('$_base/business-settings', body: _settings),
      ]);
      if (r[0] is Map) _modules = Map<String, dynamic>.from(r[0] as Map);
      if (r[1] is Map) _settings = Map<String, dynamic>.from(r[1] as Map);
      // The menus read the cached copy; drop it so they pick the change up.
      invalidateGenericModules(widget.company.farmId);
      if (mounted) trackerToast(context, 'Settings saved');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  bool _b(Map<String, dynamic>? m, String k) => m?[k] == true;

  Widget _mod(String key, String label, String hint) => GenericToggle(
        label: label,
        hint: hint,
        value: _b(_modules, key),
        onChanged: (v) => setState(() => _modules![key] = v),
      );

  Widget _set(String key, String label, {String? hint}) => GenericToggle(
        label: label,
        hint: hint,
        value: _b(_settings, key),
        onChanged: (v) => setState(() => _settings![key] = v),
      );

  static const _missing = Text('Settings could not be loaded.', style: TextStyle(fontSize: 13, color: TColors.slate500));

  @override
  Widget build(BuildContext context) {
    final l = _gm.labels;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-settings');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GenericSetupScreen(session: widget.session, company: widget.company),
              )),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Company setup', style: TextStyle(fontSize: 13)),
            ),
          ),
          const GenericTitle(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Which modules this company has, and how they behave.',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: _saving || _loading || _modules == null || _settings == null ? null : _save,
            icon: busyIcon(_saving, Icons.save_outlined),
            label: const Text('Save changes'),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else ...[
            GenericCard(
              title: 'Modules',
              description: 'Turning a module off hides its menu items. It never deletes anything — '
                  'a gym that starts selling towels turns Products back on and its old stock is still there.',
              children: _modules == null
                  ? const [Text('Modules could not be loaded.', style: TextStyle(fontSize: 13, color: TColors.slate500))]
                  : [
                      genericEyebrow('Selling'),
                      _mod('enableSubscriptions', l.subscriptionPlural, 'Plans, subscriptions and billing runs'),
                      _mod('enableInvoices', l.invoicePlural, 'The invoices a billing run raises'),
                      _mod('enableCustomerBalances', l.customerBalance, 'Who owes you, aged, with statements'),
                      genericEyebrow('Buying & paying'),
                      _mod('enablePurchases', 'Purchases', 'Buying stock from suppliers'),
                      _mod('enableSupplierBalances', 'Supplier balances', 'What you owe vendors — from expenses as well as purchases'),
                      _mod('enableRecurringExpenses', 'Recurring expenses', 'Templates that raise a bill when it falls due'),
                      _mod('enableStaffPayments', 'Staff payments', 'Paying a contractor without a full payroll run'),
                      genericEyebrow('Stock'),
                      _mod('enableProducts', 'Products', 'A catalogue of things you sell'),
                      _mod('enableInventory', 'Inventory', 'Stock levels and valuation'),
                      _mod('enableStockAdjustments', 'Stock adjustments', 'Correcting a count'),
                      _mod('enableInternalUse', 'Internal use', 'Stock consumed by the business itself'),
                      genericEyebrow('Money'),
                      _mod('enableCashAccounts', 'Cash accounts', 'Tills, bank accounts and mobile money'),
                    ],
            ),
            const SizedBox(height: 14),
            GenericCard(
              title: '${l.subscription} defaults',
              description: 'What a new ${l.subscription.toLowerCase()} is prefilled with, and what a billing run does with '
                  'what it raises.',
              children: _settings == null
                  ? const [_missing]
                  : [
                      FilterLabel(
                        'Billing frequency',
                        AppSelect<String>(
                          value: tStr(_settings!['defaultBillingFrequency']),
                          items: [for (final (v, label) in genericBillingFrequencies) AppSelectItem(value: v, label: label)],
                          onChanged: (v) => setState(() => _settings!['defaultBillingFrequency'] = v),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilterLabel(
                        'Payment due after (days)',
                        AppNumberInput(
                          controller: _dueDays,
                          onChanged: (v) => _settings!['defaultPaymentDueDays'] = (int.tryParse(v) ?? 0).clamp(0, 1 << 30),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Text(
                          '0 means due on the day it is raised. An ${l.invoice.toLowerCase()} is overdue the day after its due date.',
                          style: const TextStyle(fontSize: 12, color: TColors.slate500),
                        ),
                      ),
                      _set('autoGenerateInvoices', 'Bill new ${l.subscriptionPlural.toLowerCase()} automatically',
                          hint: 'Sets the auto-generate flag on a new subscription. It can still be changed per subscription.'),
                      _set('autoPostInvoices', 'Approve ${l.invoicePlural.toLowerCase()} as they are raised',
                          hint: _b(_settings, 'autoPostInvoices')
                              ? "A billing run posts straight to the ${l.customer.toLowerCase()}'s account — no one reviews it first."
                              : 'A billing run leaves drafts for someone to approve. Nothing is owed until they do.'),
                    ],
            ),
            const SizedBox(height: 14),
            GenericCard(
              title: 'Dashboard cards',
              description: 'Which numbers the dashboard leads with.'
                  '${_gm.isSubscriptionBusiness ? '' : ' This company is not on a subscription template, so it sees the standard dashboard and these have no effect yet.'}',
              children: _settings == null
                  ? const [_missing]
                  : [
                      _set('showMrr', 'Monthly recurring revenue'),
                      _set('showBurnRate', 'Burn rate', hint: 'Shown under the monthly spend'),
                      _set('showBreakEvenCustomers', 'Break-even ${l.customerPlural.toLowerCase()}'),
                      _set('showCustomerBalances', l.customerBalance),
                      _set('showSupplierBalances', 'Supplier balances'),
                      _set('showCalculatedCashAtHand', 'Cash at hand'),
                      _set('showInventoryCards', 'Stock value', hint: 'Only meaningful with Products on'),
                    ],
            ),
          ],
        ],
      ),
    );
  }
}
