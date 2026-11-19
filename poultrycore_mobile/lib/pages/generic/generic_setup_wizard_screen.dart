// Generic setup wizard, as `app/generic-setup/wizard/page.tsx` (9 Nov pull):
// step 0 welcomes, step 1 picks the business type from a searchable list
// grouped by kind, step 2 is the handover. The wizard no longer asks which
// features to switch on: the type's recommended set is applied, and changed
// later in Admin → Business Features. A company that already has a type, or
// arrives with one picked at creation, goes straight to the dashboard.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/companies_screen.dart' show BusinessType;
import '../web_nav.dart' show NavLink;
import 'generic_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// CATEGORY_META: the wizard's kinds of business, in order.
const genericWizardCategories = [
  ('retail', 'Shops & retail', Icons.shopping_bag_outlined),
  ('service', 'Services', Icons.content_cut),
  ('subscription', 'Subscription & billing', Icons.event_repeat_outlined),
  ('other', 'Other', Icons.grid_view),
];

/// The web's filter: a category, then the search over label and description.
List<BusinessType> filterGenericWizardTypes({String category = 'all', String search = ''}) {
  final q = search.trim().toLowerCase();
  return [
    for (final c in genericBusinessTypes)
      if ((category == 'all' || c.category == category) &&
          (q.isEmpty || c.label.toLowerCase().contains(q) || c.description.toLowerCase().contains(q)))
        c,
  ];
}

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
  int _step = 0;
  BusinessType? _choice;
  bool _loading = true, _applying = false;
  String _category = 'all';
  final _search = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);
  GenericLabels get _l => genericLabels(_choice?.industryTemplate);
  bool get _isSub => _choice?.businessTemplate == 'SubscriptionServiceBusiness';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toDashboard() => Navigator.of(context).popUntil((r) => r.isFirst);

  /// A brand-new company has no profile yet: create one with its defaults,
  /// then stamp the template.
  Future<void> _applyType(BusinessType c) async {
    Object? profile;
    try {
      profile = await _api.get(_base);
    } catch (_) {}
    if (profile is! Map || profile.isEmpty) {
      await _api.post('/api/generic-company/setup', body: {'farmId': widget.company.farmId});
    }
    await _api.post('$_base/business-template', body: {'businessTemplate': c.businessTemplate, 'industryTemplate': c.industryTemplate});
    invalidateGenericModules(widget.company.farmId);
  }

  Future<void> _load() async {
    Object? template;
    try {
      template = await _api.get('$_base/business-template');
    } catch (_) {}
    if (!mounted) return;
    // Already templated: nothing to ask.
    if (template is Map && tStr(template['genericIndustryTemplate']).isNotEmpty) return _toDashboard();
    // Picked at creation: apply it and go to the dashboard.
    final match = widget.industry == null ? null : genericBusinessTypes.where((c) => c.industryTemplate == widget.industry).firstOrNull;
    if (match?.businessTemplate != null && match?.industryTemplate != null) {
      try {
        await _applyType(match!);
      } catch (_) {}
      if (mounted) _toDashboard();
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _apply() async {
    final c = _choice;
    if (c?.businessTemplate == null || c?.industryTemplate == null) return;
    setState(() => _applying = true);
    try {
      await _applyType(c!);
      if (mounted) {
        trackerToast(context, 'Set up as ${c.label}', description: 'Your workspace is ready with the recommended features enabled.');
        setState(() => _step = 2);
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not set up this business type', description: e.message, error: true);
    }
    if (mounted) setState(() => _applying = false);
  }

  void _go(String label, String href, String? specKey) =>
      openNavLink(Navigator.of(context), NavLink(label, href, specKey), widget.session, widget.company);

  Widget _numbered(int n, List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(999)),
            child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate900)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: TColors.slate600), children: spans))),
        ]),
      );

  Widget _note(List<InlineSpan> spans) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFEEF2FF),
          border: Border.all(color: const Tone.line(0xFFC7D2FE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: Tone.fg(0xFF4338CA)), children: spans)),
      );

  Widget _welcome() => GenericCard(
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Tone.bg(0xFFE0E7FF), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_outlined, size: 32, color: genericIndigo),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Welcome to VisibilityCore',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
          const SizedBox(height: 8),
          const Text(
            "Tell us what kind of business you run and we'll configure everything — menus, categories, cash accounts and "
            'reports — so it feels like it was built just for you.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: TColors.slate500),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Here's what happens next:", style: TextStyle(fontSize: 14, color: TColors.slate600)),
              const SizedBox(height: 8),
              _numbered(1, [t('Choose your business type')]),
              _numbered(2, [t('We automatically set up the recommended features')]),
              _numbered(3, [t('Start using your system')]),
            ]),
          ),
          const SizedBox(height: 12),
          _note([
            t('VisibilityCore will automatically include the recommended features for your business type. You can customise them anytime in '),
            b('Setup → Business Features'),
            t('.'),
          ]),
          const SizedBox(height: 14),
          Center(
            child: FilledButton(
              key: const ValueKey('wizard-start'),
              onPressed: () => setState(() => _step = 1),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Get started'), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 16)]),
            ),
          ),
        ],
      );

  Widget _chip(String id, String label, IconData? icon) {
    final on = _category == id;
    final fg = on ? const Tone.fg(0xFF4338CA) : TColors.slate600;
    return InkWell(
      key: ValueKey('wizard-cat-$id'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _category = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: on ? const Tone.bg(0xFFE0E7FF) : TColors.slate100, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg))),
        ]),
      ),
    );
  }

  Widget _typeCard(BusinessType c) {
    final picked = _choice?.id == c.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('wizard-type-${c.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _choice = c),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: picked ? const Tone.bg(0xFFEEF2FF) : Tone.bg(0xFFFFFFFF),
            border: Border.all(color: picked ? const Tone.line(0xFF6366F1) : TColors.slate200, width: picked ? 1.5 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900))),
              if (picked) const Icon(Icons.check, size: 16, color: genericIndigo),
            ]),
            const SizedBox(height: 2),
            Text(c.description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      ),
    );
  }

  Widget _pick() {
    final shown = filterGenericWizardTypes(category: _category, search: _search.text);
    return GenericCard(
      title: 'What kind of business is this?',
      description: "Pick the option closest to your business. We'll automatically set up the right menus, categories and features for you.",
      children: [
        AppInput(
          key: const ValueKey('wizard-search'),
          controller: _search,
          hintText: 'Search business types…',
          prefixIcon: const Icon(Icons.search, size: 18),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip('all', 'All', null),
          for (final (id, label, icon) in genericWizardCategories) _chip(id, label, icon),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('No business types match “${_search.text}”. Try a different search or pick “Other business”.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
          )
        else
          for (final c in shown) _typeCard(c),
        if (_choice != null) ...[
          const SizedBox(height: 4),
          _note([
            t('Your business is ready to be set up. VisibilityCore will automatically include the recommended features for '),
            b(_choice!.label),
            t('. You can customise them anytime.'),
          ]),
        ],
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(onPressed: () => setState(() => _step = 0), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back')),
          Flexible(
            child: FilledButton(
              key: const ValueKey('wizard-create'),
              onPressed: _choice == null || _applying ? null : _apply,
              child: _applying
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 6),
                      Text('Setting up…'),
                    ])
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text('Create My Business', overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ]),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _done() {
    final l = _l;
    return GenericCard(
      titleWidget: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: TColors.emerald100, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 20, color: TColors.emerald600),
        ),
        const SizedBox(width: 8),
        const Text("You're all set", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
      ]),
      descriptionWidget: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: TColors.slate500), children: [
        t('Your '),
        b(_choice?.label ?? ''),
        t(' workspace is ready with the recommended features already enabled.'),
      ])),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("What we've set up for you:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
            const SizedBox(height: 6),
            for (final line in [
              'Income and expense categories for your business',
              'Cash accounts (cash box, mobile money, bank)',
              if (_isSub) 'Starter ${l.planPlural.toLowerCase()} (you set the prices)',
              'Recommended features enabled in your menus',
            ])
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $line', style: const TextStyle(fontSize: 14, color: TColors.slate600))),
            const SizedBox(height: 6),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: TColors.slate500), children: [
              t('You can customise which features are active anytime in '),
              b('Setup → Business Features'),
              t('.'),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Here is the order things usually happen in:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
        const SizedBox(height: 8),
        if (_isSub) ...[
          _numbered(1, [t('Check your '), b(l.planPlural), t(' — starter ones are already there. Set the price and frequency.')]),
          _numbered(2, [t('Add your '), b(l.customerPlural), t('.')]),
          _numbered(3, [t('Put each one on a plan — that is a '), b(l.subscription.toLowerCase()), t('.')]),
          _numbered(4, [t('When the period comes round, open '), b('Billing runs'), t(' and raise the ${l.invoicePlural.toLowerCase()}.')]),
          _numbered(5, [t('Take payment on '), b(l.customerBalance), t('.')]),
        ] else ...[
          _numbered(1, [t('Add your '), b('products or services'), t(' with prices.')]),
          _numbered(2, [t('Record your first '), b('sale'), t('.')]),
          _numbered(3, [t('Add your '), b('suppliers'), t(' and record a purchase.')]),
          _numbered(4, [t('At the end of the day, do a '), b('daily closing'), t('.')]),
          _numbered(5, [t('Check your '), b('reports'), t(' to see how you are doing.')]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_isSub) ...[
            FilledButton(onPressed: () => _go(l.planPlural, '/generic-service-plans', 'generic-service-plans'), child: Text('Go to ${l.planPlural}')),
            OutlinedButton(onPressed: () => _go(l.customerPlural, '/generic-customers', 'generic-customers'), child: Text('Add ${l.customerPlural.toLowerCase()}')),
          ] else ...[
            FilledButton(onPressed: () => _go('Products', '/generic-products', 'generic-products'), child: const Text('Add products')),
            OutlinedButton(onPressed: () => _go('Sales', '/generic-sales', 'generic-sales'), child: const Text('Record a sale')),
          ],
          TextButton(onPressed: _toDashboard, child: const Text('Go to dashboard')),
        ]),
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
          GenericTitle(icon: Icons.auto_awesome_outlined, iconColor: genericIndigo, title: 'Set up your business', subtitle: _step == 1 ? 'Step 1 of 2' : null),
          const SizedBox(height: 14),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else if (_step == 0)
            _welcome()
          else if (_step == 1)
            _pick()
          else
            _done(),
        ],
      ),
    );
  }
}
