// Restaurant → Growth → Loyalty & Rewards, as `app/restaurant-loyalty/page.tsx`:
// the four tier cards, then Program Settings (earn / redeem rules, tiers with
// their thresholds and multipliers) and Members (enroll, earn, redeem, and
// each member's point history).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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

/// TIER_META: emoji and badge colours (bg, fg, border).
const loyaltyTiers = <String, (String, Color, Color, Color)>{
  'Bronze': ('🥉', Color(0xFFFEF3C7), Color(0xFFB45309), Color(0xFFFDE68A)),
  'Silver': ('🥈', Color(0xFFF3F4F6), Color(0xFF374151), Color(0xFFE5E7EB)),
  'Gold': ('🥇', Color(0xFFFEF9C3), Color(0xFFA16207), Color(0xFFFEF08A)),
  'Platinum': ('💎', Color(0xFFF3E8FF), Color(0xFF7E22CE), Color(0xFFE9D5FF)),
};

/// DEFAULT_SETTINGS.
const loyaltyDefaults = <String, Object>{
  'isEnabled': false, 'pointsPerCurrencyUnit': 1, 'pointsRedemptionRate': 0.01,
  'minimumRedeemPoints': 100, 'pointsExpiryDays': 365, 'tiersEnabled': true,
  'bronzeThreshold': 0, 'silverThreshold': 500, 'goldThreshold': 1000, 'platinumThreshold': 2500,
  'bronzeMultiplier': 1, 'silverMultiplier': 1.5, 'goldMultiplier': 2, 'platinumMultiplier': 3,
  'referralBonus': 50,
};

String _pts(Object? n) => NumberFormat.decimalPattern('en_US').format(tNum(n));

Widget tierBadge(String tier) {
  final m = loyaltyTiers[tier] ?? loyaltyTiers['Bronze']!;
  return rBadge('${m.$1} $tier', bg: m.$2, fg: m.$3, border: m.$4);
}

class RestaurantLoyaltyScreen extends StatefulWidget {
  const RestaurantLoyaltyScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantLoyaltyScreen> createState() => _RestaurantLoyaltyScreenState();
}

class _RestaurantLoyaltyScreenState extends State<RestaurantLoyaltyScreen> {
  bool _loading = true, _saving = false;
  String _tab = 'settings';
  Map? _stats;
  List<Map> _members = [];
  final Map<String, Object> _settings = {...loyaltyDefaults};
  final Map<String, TextEditingController> _ctl = {};
  Duration _offset = Duration.zero;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  static const _numberKeys = [
    'pointsPerCurrencyUnit', 'pointsRedemptionRate', 'minimumRedeemPoints', 'pointsExpiryDays', 'referralBonus',
    'bronzeThreshold', 'silverThreshold', 'goldThreshold', 'platinumThreshold',
    'bronzeMultiplier', 'silverMultiplier', 'goldMultiplier', 'platinumMultiplier',
  ];

  TextEditingController _c(String k) => _ctl.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _syncControllers();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final k in _numberKeys) {
      final v = tNum(_settings[k]);
      _c(k).text = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    }
  }

  Future<Object?> _get(String path) async {
    try {
      return await _api.get(path, query: _q);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAll() async {
    final r = await Future.wait([
      _get('/api/Restaurant/loyalty/settings'),
      _get('/api/Restaurant/loyalty/accounts'),
      _get('/api/Restaurant/loyalty/stats'),
    ]);
    if (!mounted) return;
    setState(() {
      final s = r[0];
      if (s is Map && s.isNotEmpty) {
        for (final k in loyaltyDefaults.keys) {
          if (s[k] != null) _settings[k] = s[k] as Object;
        }
        _syncControllers();
      }
      _members = [for (final x in (r[1] is List ? r[1] as List : const [])) if (x is Map) x];
      _stats = r[2] is Map ? r[2] as Map : null;
      _loading = false;
    });
  }

  Future<void> _loadMembers() async {
    final r = await Future.wait([_get('/api/Restaurant/loyalty/accounts'), _get('/api/Restaurant/loyalty/stats')]);
    if (!mounted) return;
    setState(() {
      _members = [for (final x in (r[0] is List ? r[0] as List : const [])) if (x is Map) x];
      _stats = r[1] is Map ? r[1] as Map : _stats;
    });
  }

  num _tierThreshold(String tier) => tNum(_settings['${tier.toLowerCase()}Threshold']);

  int _tierCount(String tier) => tNum(_stats?['${tier.toLowerCase()}Count']).toInt();

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'isEnabled': _settings['isEnabled'],
      'tiersEnabled': _settings['tiersEnabled'],
      for (final k in _numberKeys) k: num.tryParse(_c(k).text) ?? 0,
      'farmId': widget.company.farmId,
    };
    try {
      await _api.post('/api/Restaurant/loyalty/settings', body: body);
      if (mounted) trackerToast(context, 'Settings saved');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  /// One small form dialog: (label, controller, hint, number?, required?) fields.
  Future<bool> _formDialog({
    required String title,
    required String description,
    required List<(String, TextEditingController, String, bool, bool)> fields,
    required String confirm,
    Color color = const Color(0xFFE11D48),
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 14),
              for (final (label, c, hint, number, _) in fields) ...[
                rLabel(label),
                AppInput(
                  controller: c,
                  hintText: hint,
                  keyboardType: number ? TextInputType.number : null,
                  inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              rDialogActions(ctx, confirm, () => Navigator.pop(ctx, true), color: color),
            ]),
          ),
        ),
      ) ==
      true;

  Future<void> _enroll() async {
    final name = TextEditingController(), phone = TextEditingController(), id = TextEditingController();
    if (!await _formDialog(
      title: 'Enroll New Member',
      description: 'Add a customer to the loyalty program',
      fields: [
        ('Customer Name *', name, 'Full name', false, true),
        ('Phone', phone, 'Phone number', false, false),
        ('Customer ID (optional)', id, 'Existing customer ID', true, false),
      ],
      confirm: 'Enroll',
    )) {
      return;
    }
    if (!mounted) return;
    if (name.text.trim().isEmpty) return trackerToast(context, 'Name is required', error: true);
    try {
      await _api.post('/api/Restaurant/loyalty/accounts', query: _q, body: {
        'customerName': name.text.trim(),
        'customerPhone': ?(phone.text.trim().isEmpty ? null : phone.text.trim()),
        'customerId': ?int.tryParse(id.text),
      });
      if (mounted) trackerToast(context, 'Member enrolled');
      _loadMembers();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _earn(Map m) async {
    final pts = TextEditingController(), desc = TextEditingController(), order = TextEditingController();
    if (!await _formDialog(
      title: 'Earn Points',
      description: 'Add points for ${tStr(m['customerName'])}',
      fields: [
        ('Points *', pts, 'Number of points', true, true),
        ('Description', desc, 'e.g. Purchase #1234', false, false),
        ('Order ID (optional)', order, 'Link to an order', true, false),
      ],
      confirm: 'Add Points',
      color: const Color(0xFF16A34A),
    )) {
      return;
    }
    final n = int.tryParse(pts.text) ?? 0;
    if (!mounted) return;
    if (n <= 0) return trackerToast(context, 'Enter valid points', error: true);
    try {
      await _api.post('/api/Restaurant/loyalty/accounts/${m['loyaltyAccountId']}/earn', query: _q, body: {
        'points': n,
        'description': desc.text.trim().isEmpty ? 'Manual earn' : desc.text.trim(),
        'orderId': ?int.tryParse(order.text),
      });
      if (mounted) trackerToast(context, '$n points added');
      _loadMembers();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _redeem(Map m) async {
    final pts = TextEditingController(), desc = TextEditingController();
    if (!await _formDialog(
      title: 'Redeem Points',
      description: 'Redeem points for ${tStr(m['customerName'])} (Available: ${_pts(m['totalPoints'])})',
      fields: [
        ('Points *', pts, 'Number of points', true, true),
        ('Description', desc, 'e.g. Discount on order', false, false),
      ],
      confirm: 'Redeem',
      color: const Color(0xFFDC2626),
    )) {
      return;
    }
    final n = int.tryParse(pts.text) ?? 0;
    if (!mounted) return;
    if (n <= 0) return trackerToast(context, 'Enter valid points', error: true);
    try {
      await _api.post('/api/Restaurant/loyalty/accounts/${m['loyaltyAccountId']}/redeem', query: _q, body: {
        'points': n,
        'description': desc.text.trim().isEmpty ? 'Manual redeem' : desc.text.trim(),
      });
      if (mounted) trackerToast(context, '$n points redeemed');
      _loadMembers();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _history(Map m) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Point History'),
          content: SizedBox(
            width: 460,
            child: FutureBuilder<Object?>(
              future: _get('/api/Restaurant/loyalty/accounts/${m['loyaltyAccountId']}/transactions'),
              builder: (_, snap) {
                final txns = [for (final x in (snap.data is List ? snap.data as List : const [])) if (x is Map) x];
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${tStr(m['customerName'])} -', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    tierBadge(tStr(m['currentTier']).isEmpty ? 'Bronze' : tStr(m['currentTier'])),
                  ]),
                  const SizedBox(height: 10),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E))))
                  else if (txns.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No transactions yet', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: ListView(shrinkWrap: true, children: [
                        for (final tx in txns)
                          Builder(builder: (_) {
                            final earn = tStr(tx['transactionType']) == 'Earn';
                            final created = DateTime.tryParse(tStr(tx['createdAt']));
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                              child: Row(children: [
                                Icon(earn ? Icons.arrow_circle_up_outlined : Icons.arrow_circle_down_outlined,
                                    size: 20, color: earn ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(tStr(tx['description']).isEmpty ? tStr(tx['transactionType']) : tStr(tx['description']),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                    Text(
                                      '${fmtInstant(tx['createdAt'], _offset)} '
                                      '${created == null ? '' : DateFormat('HH:mm').format(created.toLocal())}',
                                      style: const TextStyle(fontSize: 12, color: TColors.slate500),
                                    ),
                                  ]),
                                ),
                                Text('${earn ? '+' : '-'}${_pts(tx['points'])}',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: earn ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                              ]),
                            );
                          }),
                      ]),
                    ),
                ]);
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-loyalty');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Loyalty & Rewards')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                const RPageHeader(
                    icon: Icons.workspace_premium_outlined, title: 'Loyalty & Rewards', subtitle: 'Points, tiers, and customer rewards program'),
                const SizedBox(height: 14),
                twoColumns([
                  for (final tier in loyaltyTiers.keys)
                    TCard(
                      child: Column(children: [
                        Text(loyaltyTiers[tier]!.$1, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(tier, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${_pts(_tierThreshold(tier))}+ points', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        const SizedBox(height: 6),
                        rBadge('${_tierCount(tier)} member${_tierCount(tier) != 1 ? 's' : ''}',
                            bg: loyaltyTiers[tier]!.$2, fg: loyaltyTiers[tier]!.$3, border: loyaltyTiers[tier]!.$4),
                      ]),
                    ),
                ]),
                const SizedBox(height: 14),
                RTabs(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  tabs: const [
                    ('settings', Icons.settings_outlined, 'Program Settings', null),
                    ('members', Icons.groups_outlined, 'Members', null),
                  ],
                ),
                const SizedBox(height: 12),
                if (_tab == 'settings') _settingsTab() else _membersTab(),
              ]),
            ),
    );
  }

  Widget _numField(String label, String key, {String? hint, bool decimal = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          rLabel(label),
          AppInput(
            controller: _c(key),
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ],
        ]),
      );

  Widget _switch(String label, String key) => Row(children: [
        Switch(
          value: _settings[key] == true,
          activeTrackColor: const Color(0xFFE11D48),
          onChanged: (v) => setState(() => _settings[key] = v),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]);

  Widget _settingsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Loyalty Program Configuration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const Text('Set up how customers earn and redeem points', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          _switch('Program Enabled', 'isEnabled'),
          const SizedBox(height: 12),
          _numField('Points per currency unit', 'pointsPerCurrencyUnit', hint: r'e.g. 1 point per $1 spent'),
          _numField('Redemption rate', 'pointsRedemptionRate', hint: 'Value of 1 point in currency', decimal: true),
          _numField('Min. redeem points', 'minimumRedeemPoints'),
          _numField('Points expiry (days)', 'pointsExpiryDays'),
          _numField('Referral bonus', 'referralBonus', hint: 'Points for referring a friend'),
          const Divider(height: 24),
          _switch('Tiers Enabled', 'tiersEnabled'),
          if (_settings['tiersEnabled'] == true) ...[
            const SizedBox(height: 12),
            const Text('Tier Thresholds (lifetime points)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate500)),
            const SizedBox(height: 10),
            twoColumns([
              for (final tier in loyaltyTiers.keys) _numField('${loyaltyTiers[tier]!.$1} $tier', '${tier.toLowerCase()}Threshold'),
            ], gap: 10),
            const SizedBox(height: 4),
            const Text('Tier Multipliers (earn rate)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate500)),
            const SizedBox(height: 10),
            twoColumns([
              for (final tier in loyaltyTiers.keys)
                _numField('${loyaltyTiers[tier]!.$1} $tier', '${tier.toLowerCase()}Multiplier', hint: 'x earn multiplier', decimal: true),
            ], gap: 10),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48), minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const SizedBox.shrink(),
            label: const Text('Save Settings'),
          ),
        ]),
      );

  Widget _membersTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Loyalty Members', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const Text('Customers enrolled in the loyalty program', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 10),
          roseButton('Enroll Member', _enroll),
          const SizedBox(height: 12),
          if (_members.isEmpty)
            REmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No loyalty members yet',
              description: 'Enroll customers to start tracking points and rewards',
              actionLabel: 'Enroll Member',
              onAction: _enroll,
            )
          else
            Container(
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                for (final (i, m) in _members.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: TColors.slate200),
                  _memberRow(m),
                ],
              ]),
            ),
        ]),
      );

  Widget _memberRow(Map m) {
    final name = tStr(m['customerName']);
    Widget action(String label, IconData icon, Color color, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onTap,
            icon: Icon(icon, size: 16, color: color),
            label: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFFFE4E6),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF111827))),
              if (tStr(m['customerPhone']).isNotEmpty) Text(tStr(m['customerPhone']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 4),
              tierBadge(tStr(m['currentTier']).isEmpty ? 'Bronze' : tStr(m['currentTier'])),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${_pts(m['totalPoints'])} pts', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Lifetime: ${_pts(m['lifetimePoints'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ]),
        const Divider(height: 20),
        Row(children: [
          action('Earn', Icons.arrow_circle_up_outlined, const Color(0xFF16A34A), () => _earn(m)),
          const SizedBox(width: 6),
          action('Redeem', Icons.arrow_circle_down_outlined, const Color(0xFFEF4444), () => _redeem(m)),
          const SizedBox(width: 6),
          action('History', Icons.history, TColors.slate500, () => _history(m)),
        ]),
      ]),
    );
  }
}
