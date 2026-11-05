// Generic setup wizard, as `app/generic-setup/wizard/page.tsx`: the three
// steps a new Generic company runs once. Step 1 picks the business type and
// applies its template (creating the profile first if there is none), step 2
// confirms which modules are on, step 3 is the handover.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/companies_screen.dart' show BusinessType;
import '../web_nav.dart' show NavLink;
import 'generic_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';
/// MODULE_ROWS: the ten switches step 2 shows, in the web's order.
const genericWizardModules = [
  ('enableSubscriptions', 'Subscriptions', 'Bill the same customer every period'),
  ('enableInvoices', 'Invoices', 'Raise bills and track what is owed'),
  ('enableCustomerBalances', 'Customer balances', 'Who owes you, and take payment'),
  ('enableProducts', 'Products', 'Things you sell off a shelf'),
  ('enableInventory', 'Inventory', 'Stock levels and movements'),
  ('enableStockAdjustments', 'Stock adjustments', 'Corrections to stock on hand'),
  ('enableInternalUse', 'Internal use', 'Stock taken for the business itself'),
  ('enablePurchases', 'Purchases', 'What you buy from suppliers'),
  ('enableStaffPayments', 'Staff and payroll', 'Staff, attendance and pay runs'),
  ('enableCashAccounts', 'Cash accounts', 'Till, bank and mobile money'),
];

class GenericSetupWizardScreen extends StatefulWidget {
  const GenericSetupWizardScreen({super.key, required this.session, required this.company, this.industry});
  final Session session;
  final Company company;

  /// ?industry=: the business type picked when the company was created.
  final String? industry;

  @override
  State<GenericSetupWizardScreen> createState() => _GenericSetupWizardScreenState();
}

class _GenericSetupWizardScreenState extends State<GenericSetupWizardScreen> {
  int _step = 1;
  BusinessType? _choice;
  Map<String, dynamic>? _settings;
  bool _loading = true, _applying = false, _saving = false;

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);
  GenericLabels get _l => genericLabels(_choice?.industryTemplate);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Object?> _quiet(String path) => _api.get(path).then<Object?>((v) => v, onError: (_) => null);

  Future<void> _load() async {
    final r = await Future.wait([_quiet('$_base/business-template'), _quiet('$_base/module-settings')]);
    final template = r[0];
    // Already templated? Start from the truth; else the type picked at creation.
    final current = template is Map ? tStr(template['genericIndustryTemplate']) : '';
    final existing = current.isNotEmpty ? current : widget.industry;
    if (existing != null) _choice = businessTypeForIndustry(existing);
    if (r[1] is Map) _settings = Map<String, dynamic>.from(r[1] as Map);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _apply() async {
    final c = _choice;
    final business = businessTemplateFor(c?.industryTemplate);
    if (c?.industryTemplate == null || business == null) return;
    setState(() => _applying = true);
    try {
      // A brand-new company has no profile yet; create one with its defaults.
      Object? profile;
      try {
        profile = await _api.get(_base);
      } catch (_) {}
      if (profile is! Map || profile.isEmpty) {
        await _api.post('/api/generic-company/setup', body: {'farmId': widget.company.farmId});
      }
      final updated = await _api.post('$_base/business-template', body: {
        'businessTemplate': business,
        'industryTemplate': c!.industryTemplate,
      });
      // Step 2 opens on what the template chose.
      final s = updated is Map ? updated : await _api.get('$_base/module-settings');
      if (s is Map) _settings = Map<String, dynamic>.from(s);
      if (mounted) setState(() => _step = 2);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not set up this business type', description: e.message, error: true);
    }
    if (mounted) setState(() => _applying = false);
  }

  Future<void> _saveModules() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await _api.put('$_base/module-settings', body: {..._settings!}..remove('farmId'));
      invalidateGenericModules(widget.company.farmId);
      if (mounted) setState(() => _step = 3);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save what is switched on', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _go(String label, String href, String specKey) =>
      openNavLink(Navigator.of(context), NavLink(label, href, specKey), widget.session, widget.company);

  Widget _step1() => GenericCard(
        title: 'What kind of business is this?',
        description: 'This decides what things are called and what you start with — income categories, cash accounts '
            'and a few plans. You can change any of it later.',
        children: [
          for (final c in genericBusinessTypes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _choice = c),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _choice?.id == c.id ? const Tone.bg(0xFFEEF2FF) : Tone.bg(0xFFFFFFFF),
                    border: Border.all(
                      color: _choice?.id == c.id ? const Tone.line(0xFF6366F1) : TColors.slate200,
                      width: _choice?.id == c.id ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(c.label,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                        ),
                        if (_choice?.id == c.id) const Icon(Icons.check, size: 16, color: genericIndigo),
                      ]),
                      const SizedBox(height: 2),
                      Text(c.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    ],
                  ),
                ),
              ),
            ),
          if (_choice != null)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Text.rich(
                TextSpan(style: const TextStyle(fontSize: 13, color: TColors.slate700), children: [
                  t("You'll see "), b(_l.customerPlural), t(', '), b(_l.planPlural), t(', '),
                  b(_l.subscriptionPlural), t(' and '), b(_l.invoicePlural), t('.'),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _choice == null || _applying ? null : _apply,
              child: _applying
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 6),
                      Text('Setting up…'),
                    ])
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Continue'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ]),
            ),
          ),
        ],
      );

  Widget _step2() => GenericCard(
        title: 'What do you want to see?',
        description: 'These are the menus this company shows. Turning something off only hides it — nothing already '
            'recorded is deleted or lost.',
        children: [
          for (final (key, label, hint) in genericWizardModules) ...[
            GenericToggle(
              label: label,
              hint: hint,
              value: _settings?[key] == true,
              onChanged: (_) => setState(() => (_settings ??= {})[key] = !(_settings![key] == true)),
            ),
            const Divider(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _step = 1),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back'),
              ),
              FilledButton(
                onPressed: _saving ? null : _saveModules,
                child: _saving
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 6),
                        Text('Saving…'),
                      ])
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Continue'),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 16),
                      ]),
              ),
            ],
          ),
        ],
      );

  Widget _numbered(int n, List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(999)),
              child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: TColors.slate900), children: spans))),
          ],
        ),
      );

  Widget _step3() {
    final l = _l;
    return GenericCard(
      titleWidget: const Row(children: [
        Icon(Icons.check, size: 20, color: genericEmerald),
        SizedBox(width: 6),
        Text('Ready', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
      ]),
      description: '${_choice?.label ?? ''} set up. Here is the order things usually happen in.',
      children: [
        _numbered(1, [t('Check your '), b(l.planPlural), t(' — a few starter ones are already there. Set the price and how often they bill.')]),
        _numbered(2, [t('Add your '), b(l.customerPlural), t('.')]),
        _numbered(3, [t('Put each one on a plan — that is a '), b(l.subscription.toLowerCase()), t('.')]),
        _numbered(4, [
          t('When the period comes round, open '), b('Billing runs'),
          t(' and raise the ${l.invoicePlural.toLowerCase()}. Nothing bills on its own — you press the button.'),
        ]),
        _numbered(5, [
          t('Take payment on '), b(l.customerBalance),
          t('. One payment can settle several ${l.invoicePlural.toLowerCase()} at once.'),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => _go(l.planPlural, '/generic-service-plans', 'generic-service-plans'),
              child: Text('Go to ${l.planPlural}'),
            ),
            OutlinedButton(
              onPressed: () => _go(l.customerPlural, '/generic-customers', 'generic-customers'),
              child: Text('Add ${l.customerPlural.toLowerCase()}'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Skip to dashboard'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-setup/wizard');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Set up your business')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          GenericTitle(
            icon: Icons.auto_awesome_outlined,
            iconColor: genericIndigo,
            title: 'Set up your business',
            subtitle: 'Step $_step of 3',
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else if (_step == 1)
            _step1()
          else if (_step == 2)
            _step2()
          else
            _step3(),
        ],
      ),
    );
  }
}
