// Restaurant → Growth → Customers & CRM, as `app/restaurant-crm/page.tsx`
// ("Customer Relationships"): the customer stats, and three tabs — Customers
// (search, segment filter, edit / delete), Feedback (rating averages, add
// feedback, respond) and Campaigns (create from a template, delete).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtInstant;
import '../shared/company_clock.dart';
import 'restaurant_widgets.dart';

/// SEGMENTS: value, emoji, badge colours.
const crmSegments = <(String, String, Color, Color)>[
  ('New', '🆕', Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  ('Regular', '🔄', Color(0xFFDCFCE7), Color(0xFF15803D)),
  ('VIP', '👑', Color(0xFFF3E8FF), Color(0xFF7E22CE)),
  ('Lapsed', '😴', Color(0xFFF3F4F6), Color(0xFF374151)),
];

const crmCampaignTypes = ['Birthday', 'WinBack', 'Promotion', 'Announcement'];

/// The campaign message templates, word for word.
const crmTemplates = <(String, String, String)>[
  ('birthday', 'Birthday Greeting',
      "Dear {first_name},\n\nHappy Birthday! 🎂 We'd love to celebrate with you. Enjoy a special treat on your next visit — it's on us!\n\nWarmest wishes,\n{restaurant_name}"),
  ('winback', 'Win-Back / We Miss You',
      "Dear {first_name},\n\nWe miss you! It's been a while since your last visit. Come back and enjoy 10% off your next meal.\n\nWe'd love to see you again!\n{restaurant_name}"),
  ('promotion', 'Promotion / Offer',
      'Dear {first_name},\n\nGreat news! We have a special offer just for you. Visit us this week and enjoy our latest dishes at amazing prices.\n\nSee you soon!\n{restaurant_name}'),
  ('announcement', 'Announcement / New Menu',
      "Dear {first_name},\n\nWe have exciting news to share! We've updated our menu with new dishes we think you'll love.\n\nCome check them out!\n{restaurant_name}"),
  ('thankyou', 'Thank You / Appreciation',
      'Dear {first_name},\n\nThank you for being a valued guest! Your loyalty means the world to us. We look forward to serving you again soon.\n\nWith gratitude,\n{restaurant_name}'),
  ('loyalty', 'Loyalty Points Reminder',
      "Dear {first_name},\n\nYou've been earning points with every visit! Check your loyalty balance and redeem your rewards on your next visit.\n\nThank you for choosing us!\n{restaurant_name}"),
  ('holiday', 'Holiday / Seasonal',
      'Dear {first_name},\n\nHappy Holidays! 🎉 Join us for a special holiday menu and festive atmosphere. Make a reservation today!\n\nBest wishes,\n{restaurant_name}'),
];

class RestaurantCrmScreen extends StatefulWidget {
  const RestaurantCrmScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantCrmScreen> createState() => _RestaurantCrmScreenState();
}

class _RestaurantCrmScreenState extends State<RestaurantCrmScreen> {
  bool _loading = true;
  String _tab = 'customers';
  List<Map> _customers = [], _feedback = [], _campaigns = [];
  Map? _custStats, _fbStats;
  String _search = '';
  String _segment = 'all';
  Duration _offset = Duration.zero;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _loadAll();
  }

  Future<List<Map>> _list(String path) async {
    try {
      final r = await _api.get(path, query: _q);
      return [for (final x in (r is List ? r : const [])) if (x is Map) x];
    } catch (_) {
      return [];
    }
  }

  Future<Map?> _map(String path) async {
    try {
      final r = await _api.get(path, query: _q);
      return r is Map && r.isNotEmpty ? r : null;
    } catch (_) {
      return null;
    }
  }

  // Every part is fetched on its own and may fail without blanking the page.
  Future<void> _loadAll() async {
    setState(() => _loading = _customers.isEmpty && _feedback.isEmpty && _campaigns.isEmpty);
    final r = await Future.wait<Object?>([
      _list('/api/Restaurant/crm/customers'),
      _map('/api/Restaurant/crm/customers/stats'),
      _list('/api/Restaurant/crm/feedback'),
      _map('/api/Restaurant/crm/feedback/stats'),
      _list('/api/Restaurant/crm/campaigns'),
    ]);
    if (!mounted) return;
    setState(() {
      _customers = r[0] as List<Map>;
      _custStats = r[1] as Map?;
      _feedback = r[2] as List<Map>;
      _fbStats = r[3] as Map?;
      _campaigns = r[4] as List<Map>;
      _loading = false;
    });
  }

  void _fail(ApiException e) => trackerToast(context, 'Failed', description: e.message, error: true);

  List<Map> get _filtered => [
        for (final c in _customers)
          if ((_segment == 'all' || tStr(c['segment']) == _segment) &&
              (_search.isEmpty || tStr(c['name']).toLowerCase().contains(_search.toLowerCase()) || tStr(c['phone']).contains(_search)))
            c,
      ];

  Future<void> _openCustomer([Map? c]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CustomerForm(api: _api, farmId: widget.company.farmId, existing: c),
    ));
    if (saved == true) _loadAll();
  }

  Future<void> _deleteCustomer(Map c) async {
    try {
      await _api.delete('/api/Restaurant/crm/customers/${c['customerId']}', query: _q);
      _loadAll();
    } on ApiException catch (e) {
      _fail(e);
    }
  }

  Future<void> _addFeedback() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _FeedbackDialog(api: _api, farmId: widget.company.farmId));
    if (saved == true) _loadAll();
  }

  Future<void> _respond(Map f) async {
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Respond to Feedback'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (tStr(f['comment']).isNotEmpty) ...[
              Text(tStr(f['comment']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
            ],
            rLabel('Your Response'),
            AppTextarea(controller: text, hintText: 'Thank you for your feedback...', rows: 4),
            const SizedBox(height: 16),
            rDialogActions(ctx, 'Send Response', () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    try {
      await _api.post('/api/Restaurant/crm/feedback/${f['feedbackId']}/respond', query: _q, body: {'response': text.text});
      if (mounted) trackerToast(context, 'Response sent');
      _loadAll();
    } on ApiException catch (e) {
      _fail(e);
    }
  }

  Future<void> _createCampaign() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CampaignForm(api: _api, farmId: widget.company.farmId),
    ));
    if (saved == true) _loadAll();
  }

  Future<void> _deleteCampaign(Map c) async {
    try {
      await _api.delete('/api/Restaurant/crm/campaigns/${c['campaignId']}', query: _q);
      _loadAll();
    } on ApiException catch (e) {
      _fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-crm');
    final fbNew = tNum(_fbStats?['newCount']).toInt();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Customer Relationships')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.favorite_border,
                  title: 'Customer Relationships',
                  subtitle: 'Profiles, feedback, and campaigns',
                  actions: [roseButton('Add Customer', () => _openCustomer())],
                ),
                if (_custStats != null) ...[
                  const SizedBox(height: 14),
                  twoColumns([
                    for (final (label, value, icon, color) in [
                      ('Total', '${tNum(_custStats!['totalCustomers']).toInt()}', Icons.groups_outlined, const Color(0xFF111827)),
                      ('New', '${tNum(_custStats!['newCount']).toInt()}', Icons.person_add_alt, const Color(0xFF1D4ED8)),
                      ('Regular', '${tNum(_custStats!['regularCount']).toInt()}', Icons.groups_outlined, const Color(0xFF15803D)),
                      ('VIP', '${tNum(_custStats!['vipCount']).toInt()}', Icons.workspace_premium_outlined, const Color(0xFF7E22CE)),
                      ('Lifetime Value', tNum(_custStats!['totalLifetimeValue']).toStringAsFixed(0), Icons.attach_money, const Color(0xFFBE123C)),
                    ])
                      TCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
                              Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                ],
                const SizedBox(height: 14),
                RTabs(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  tabs: [
                    ('customers', Icons.groups_outlined, 'Customers', rBadge('${_customers.length}')),
                    ('feedback', Icons.star_border, 'Feedback', fbNew > 0 ? rBadge('$fbNew', bg: const Color(0xFFF59E0B), fg: Colors.white) : null),
                    ('campaigns', Icons.campaign_outlined, 'Campaigns', null),
                  ],
                ),
                const SizedBox(height: 12),
                if (_tab == 'customers') _customersTab(),
                if (_tab == 'feedback') ..._feedbackTab(),
                if (_tab == 'campaigns') _campaignsTab(),
              ]),
            ),
    );
  }

  Widget _customersTab() {
    final rows = _filtered;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppInput(hintText: 'Search customers...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (v) => setState(() => _search = v)),
        const SizedBox(height: 8),
        AppSelect<String>(
          value: _segment,
          items: [
            const AppSelectItem(value: 'all', label: 'All Segments'),
            for (final (v, e, _, _) in crmSegments) AppSelectItem(value: v, label: '$e $v'),
          ],
          onChanged: (v) => setState(() => _segment = v ?? 'all'),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          REmptyState(
            icon: Icons.groups_outlined,
            title: 'No customers yet',
            description: 'Add your regular guests to track their visits and preferences',
            actionLabel: 'Add Customer',
            onAction: () => _openCustomer(),
          )
        else
          for (final c in rows) ...[_customerRow(c), const SizedBox(height: 8)],
      ]),
    );
  }

  Widget _customerRow(Map c) {
    final seg = crmSegments.where((s) => s.$1 == tStr(c['segment'])).firstOrNull;
    String dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
    final dietary = '${dash(c['dietaryPreferences'])}${tStr(c['allergies']).isNotEmpty ? ' ⚠️ ${tStr(c['allergies'])}' : ''}';
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              rBadge(tStr(c['segment']), bg: seg?.$3 ?? const Color(0xFFF3F4F6), fg: seg?.$4 ?? const Color(0xFF374151)),
            ]),
          ),
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openCustomer(c)),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteCustomer(c)),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(children: [
            line('Phone', dash(c['phone'])),
            line('Email', dash(c['email'])),
            line('Visits', '${tNum(c['totalVisits']).toInt()}'),
            line('Dietary', dietary),
            line('Lifetime Spent', tNum(c['totalSpent']).toStringAsFixed(2), bold: true),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _feedbackTab() {
    final s = _fbStats;
    return [
      if (s != null) ...[
        twoColumns([
          for (final (l, v, e) in [
            ('Overall', s['avgRating'], '⭐'),
            ('Food', s['avgFood'], '🍕'),
            ('Service', s['avgService'], '🙋'),
            ('Ambience', s['avgAmbience'], '🎵'),
            ('Total', s['totalFeedback'], '📝'),
          ])
            TCard(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Text(e, style: const TextStyle(fontSize: 20)),
                Text(v == null ? '—' : tNum(v).toStringAsFixed(1), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(l, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
      ],
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.star_border, const Color(0xFFFEF3C7), const Color(0xFFD97706), 'Customer Feedback', 'Reviews and ratings'),
          const SizedBox(height: 10),
          roseButton('Add Feedback', _addFeedback),
          const SizedBox(height: 12),
          if (_feedback.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No feedback yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
            )
          else
            for (final f in _feedback.take(20)) ...[_feedbackRow(f), const SizedBox(height: 8)],
        ]),
      ),
    ];
  }

  Widget _cardHead(IconData icon, Color bg, Color fg, String title, String description) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: fg),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ]),
        ),
      ]);

  Widget _feedbackRow(Map f) {
    final status = tStr(f['status']);
    final (sbg, sfg) = switch (status) {
      'New' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      'Responded' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      _ => (const Color(0xFFF3F4F6), const Color(0xFF374151)),
    };
    final rating = tNum(f['rating']).toInt().clamp(0, 5);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('⭐' * rating, style: const TextStyle(fontSize: 15)),
          if (tStr(f['customerName']).isNotEmpty) Text(tStr(f['customerName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          rBadge(tStr(f['source']), bg: Colors.white, border: TColors.slate200),
          rBadge(status, bg: sbg, fg: sfg),
        ]),
        const SizedBox(height: 2),
        Text(fmtInstant(f['createdAt'], _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        if (tStr(f['comment']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(tStr(f['comment']), style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
        ],
        if (tStr(f['response']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Response:', style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF15803D))),
              TextSpan(text: ' ${tStr(f['response'])}'),
            ]), style: const TextStyle(fontSize: 13)),
          ),
        ],
        if (status == 'New')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48)),
              onPressed: () => _respond(f),
              icon: const Icon(Icons.chat_bubble_outline, size: 14),
              label: const Text('Respond', style: TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  Widget _campaignsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.campaign_outlined, const Color(0xFFE0E7FF), const Color(0xFF4F46E5), 'Marketing Campaigns',
              'Reach your customers with targeted messages'),
          const SizedBox(height: 10),
          roseButton('Create Campaign', _createCampaign),
          const SizedBox(height: 12),
          if (_campaigns.isEmpty)
            const REmptyState(
              icon: Icons.campaign_outlined,
              title: 'No campaigns yet',
              description: 'Create birthday offers, win-back campaigns, or promotions',
            )
          else
            for (final ca in _campaigns) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tStr(ca['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        rBadge(tStr(ca['campaignType']), bg: Colors.white, border: TColors.slate200),
                        rBadge(tStr(ca['channel']), bg: Colors.white, border: TColors.slate200),
                        tStr(ca['status']) == 'Sent'
                            ? rBadge('Sent', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D))
                            : rBadge(tStr(ca['status'])),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        'Target: ${tStr(ca['targetSegment']).isEmpty ? 'All' : tStr(ca['targetSegment'])} '
                        '${tNum(ca['recipientCount']) > 0 ? '| Sent to: ${tNum(ca['recipientCount']).toInt()}' : ''}',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500),
                      ),
                    ]),
                  ),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteCampaign(ca)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
        ]),
      );
}

// ---------------------------------------------------------------- forms

/// Add / Edit Customer.
class _CustomerForm extends StatefulWidget {
  const _CustomerForm({required this.api, required this.farmId, this.existing});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  late final Map? c = widget.existing;
  late final _name = TextEditingController(text: tStr(c?['name']));
  late final _phone = TextEditingController(text: tStr(c?['phone']));
  late final _email = TextEditingController(text: tStr(c?['email']));
  late String _segment = tStr(c?['segment']).isEmpty ? 'New' : tStr(c?['segment']);
  late String _dob = tStr(c?['dateOfBirth']).split('T').first;
  late String _anniversary = tStr(c?['anniversary']).split('T').first;
  late final _dietary = TextEditingController(text: tStr(c?['dietaryPreferences']));
  late final _allergies = TextEditingController(text: tStr(c?['allergies']));
  late final _notes = TextEditingController(text: tStr(c?['notes']));

  @override
  void dispose() {
    for (final x in [_name, _phone, _email, _dietary, _allergies, _notes]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    String? v(TextEditingController t) => c == null && t.text.isEmpty ? null : t.text;
    final body = {
      'name': _name.text,
      'phone': ?v(_phone),
      'email': ?v(_email),
      if (_dob.isNotEmpty || c != null) 'dateOfBirth': _dob,
      if (_anniversary.isNotEmpty || c != null) 'anniversary': _anniversary,
      'dietaryPreferences': ?v(_dietary),
      'allergies': ?v(_allergies),
      if (c != null) 'favouriteItems': c!['favouriteItems'],
      'segment': _segment,
      'notes': ?v(_notes),
      if (c != null) 'isActive': c!['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (c != null) {
        await widget.api.put('/api/Restaurant/crm/customers/${c!['customerId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/crm/customers', body: body);
      }
      if (!mounted) return;
      trackerToast(context, c != null ? 'Updated' : 'Customer added');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _dateField(String value, ValueChanged<String> onChanged) => AppDateField(
        value: DateTime.tryParse(value),
        hintText: 'dd/mm/yyyy',
        onChanged: (d) => onChanged(d == null
            ? ''
            : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(c != null ? 'Edit Customer' : 'Add Customer')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          const Text('Track guest preferences and visit history', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 16),
          rLabel('Name', required: true),
          AppInput(controller: _name),
          const SizedBox(height: 12),
          rLabel('Phone'),
          AppInput(controller: _phone, keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          rLabel('Email'),
          AppInput(controller: _email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          rLabel('Segment'),
          AppSelect<String>(
            value: _segment,
            items: [for (final (v, e, _, _) in crmSegments) AppSelectItem(value: v, label: '$e $v')],
            onChanged: (v) => setState(() => _segment = v ?? _segment),
          ),
          const SizedBox(height: 12),
          rLabel('Birthday'),
          _dateField(_dob, (v) => setState(() => _dob = v)),
          const SizedBox(height: 12),
          rLabel('Anniversary'),
          _dateField(_anniversary, (v) => setState(() => _anniversary = v)),
          const SizedBox(height: 12),
          rLabel('Dietary Preferences'),
          AppInput(controller: _dietary, hintText: 'e.g. Vegetarian, No spicy'),
          const SizedBox(height: 12),
          rLabel('Allergies'),
          AppInput(controller: _allergies, hintText: 'e.g. Nuts, Shellfish, Dairy'),
          const SizedBox(height: 12),
          rLabel('Notes'),
          AppInput(controller: _notes),
          const SizedBox(height: 20),
          rDialogActions(context, c != null ? 'Update' : 'Add Customer', _save),
        ]),
      );
}

/// Add Feedback.
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _name = TextEditingController();
  final _comment = TextEditingController();
  int _rating = 5;
  int? _food, _service, _ambience;

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.api.post('/api/Restaurant/crm/feedback', body: {
        'rating': _rating,
        if (_name.text.isNotEmpty) 'customerName': _name.text,
        'foodRating': ?_food,
        'serviceRating': ?_service,
        'ambienceRating': ?_ambience,
        if (_comment.text.isNotEmpty) 'comment': _comment.text,
        'farmId': widget.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Feedback recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _sub(String label, int? value, ValueChanged<int?> set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        AppSelect<int>(
          value: value,
          hintText: '—',
          items: [for (var r = 1; r <= 5; r++) AppSelectItem(value: r, label: '$r/5')],
          onChanged: set,
        ),
      ]);

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Add Feedback'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rLabel('Customer Name'),
            AppInput(controller: _name),
            const SizedBox(height: 12),
            rLabel('Overall Rating'),
            Wrap(spacing: 4, children: [
              for (var r = 1; r <= 5; r++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _rating = r),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _rating >= r ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                    child: const Text('⭐', style: TextStyle(fontSize: 18)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            _sub('Food', _food, (v) => setState(() => _food = v)),
            const SizedBox(height: 8),
            _sub('Service', _service, (v) => setState(() => _service = v)),
            const SizedBox(height: 8),
            _sub('Ambience', _ambience, (v) => setState(() => _ambience = v)),
            const SizedBox(height: 12),
            rLabel('Comment'),
            AppTextarea(controller: _comment, rows: 3),
            const SizedBox(height: 16),
            rDialogActions(context, 'Submit', _save),
          ]),
        ),
      );
}

/// Create Campaign.
class _CampaignForm extends StatefulWidget {
  const _CampaignForm({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_CampaignForm> createState() => _CampaignFormState();
}

class _CampaignFormState extends State<_CampaignForm> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  String _type = 'Promotion';
  String? _target;
  String? _channel;

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    try {
      await widget.api.post('/api/Restaurant/crm/campaigns', body: {
        'name': _name.text,
        'campaignType': _type,
        'targetSegment': ?_target,
        'channel': ?_channel,
        if (_message.text.isNotEmpty) 'message': _message.text,
        'farmId': widget.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Campaign created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create Campaign')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          const Text('Send targeted messages to your customers', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 16),
          rLabel('Campaign Name', required: true),
          AppInput(controller: _name),
          const SizedBox(height: 12),
          rLabel('Type'),
          AppSelect<String>(
            value: _type,
            items: [for (final t in crmCampaignTypes) AppSelectItem(value: t, label: t)],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          rLabel('Target'),
          AppSelect<String>(
            value: _target ?? 'All',
            items: [for (final s in const ['All', 'New', 'Regular', 'VIP', 'Lapsed']) AppSelectItem(value: s, label: s)],
            onChanged: (v) => setState(() => _target = v),
          ),
          const SizedBox(height: 12),
          rLabel('Channel'),
          AppSelect<String>(
            value: _channel ?? 'Email',
            items: [for (final c in const ['Email', 'Push']) AppSelectItem(value: c, label: c)],
            onChanged: (v) => setState(() => _channel = v),
          ),
          const SizedBox(height: 12),
          rLabel('Template'),
          AppSelect<String>(
            value: null,
            hintText: 'Pick a template (optional)',
            items: [
              const AppSelectItem(value: '__none__', label: 'Write custom message'),
              for (final (k, label, _) in crmTemplates) AppSelectItem(value: k, label: label),
            ],
            onChanged: (v) {
              if (v == null || v == '__none__') return;
              setState(() => _message.text = crmTemplates.firstWhere((t) => t.$1 == v).$3);
            },
          ),
          const SizedBox(height: 12),
          rLabel('Message'),
          AppTextarea(controller: _message, rows: 6),
          const SizedBox(height: 4),
          const Text('Tokens: {first_name} {restaurant_name} — replaced with real values when sent.',
              style: TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 20),
          rDialogActions(context, 'Create', _save),
        ]),
      );
}

