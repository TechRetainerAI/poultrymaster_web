import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../design/ui/form_dialog.dart';
import '../design/ui/inputs.dart';
import '../models/company.dart';
import '../pages/poultry/flock_lifecycle_logic.dart' show dueLabel, lifecycleStatusTone, sortTasks, taskSentence;
import '../pages/poultry/flock_lifecycle_screen.dart';
import '../pages/shared/billing_screen.dart';
import '../pages/shared/companies_screen.dart' show CompaniesScreen, businessTypes;
import '../pages/poultry/trackers/tracker_widgets.dart' show FilterLabel;
import '../pages/shared/help_screen.dart';
import '../pages/web_page_screen.dart';
import '../state/session.dart';
import 'business_office/administration_screen.dart';

/// The company-neutral landing, as `app/business-office/page.tsx` inside
/// `components/dashboard/business-office-shell.tsx`.
///
/// Everyone lands here after signing in -- no company is selected yet (Doc 3
/// §4/§9) -- and picks one. The orange top bar, the dark sidebar (a drawer on
/// a phone), the company selector, VisibilityCore Announcements, the type
/// counts, the company cards with today's numbers, My Tasks and Quick actions
/// are the web's, with its wording and its endpoints.
class BusinessOfficeScreen extends StatefulWidget {
  const BusinessOfficeScreen({
    super.key,
    required this.session,
    required this.onPicked,
    required this.onSignedOut,
  });

  final Session session;
  final VoidCallback onPicked;
  final VoidCallback onSignedOut;

  @override
  State<BusinessOfficeScreen> createState() => _BusinessOfficeScreenState();
}

// ---------------------------------------------------------------- palette

const _slate50 = Color(0xFFF8FAFC);
const _slate100 = Color(0xFFF1F5F9);
const _slate200 = Color(0xFFE2E8F0);
const _slate300 = Color(0xFFCBD5E1);
const _slate400 = Color(0xFF94A3B8);
const _slate500 = Color(0xFF64748B);
const _slate600 = Color(0xFF475569);
const _slate700 = Color(0xFF334155);
const _slate800 = Color(0xFF1E293B);
const _slate900 = Color(0xFF0F172A);
const _orange300 = Color(0xFFFDBA74);
const _orange400 = Color(0xFFFB923C);
const _orange500 = Color(0xFFF97316);
const _orange600 = Color(0xFFEA580C);
const _amber500 = Color(0xFFF59E0B);
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);
const _indigo600 = Color(0xFF4F46E5);

/// SHOW_CURRENCY_KEY: the page's own remembered "Show currency" choice.
const _showCurrencyKey = 'vc.businessOffice.showCurrency';

/// typeIcon on the web: Water a drop, Poultry a bird, Generic a bag, else a building.
IconData _typeIcon(CompanyType t) => switch (t) {
      CompanyType.water => Icons.water_drop_outlined,
      CompanyType.poultry => Icons.flutter_dash,
      CompanyType.generic => Icons.shopping_bag_outlined,
      _ => Icons.apartment_outlined,
    };

/// typeStrip (the card's top edge) and typeTone (icon tile + badge).
({Color strip, Color bg, Color fg}) _typeTone(CompanyType t) => switch (t) {
      CompanyType.water => (strip: const Color(0xFF38BDF8), bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0369A1)),
      CompanyType.poultry => (strip: _orange400, bg: const Color(0xFFFFEDD5), fg: const Color(0xFFC2410C)),
      CompanyType.generic => (strip: const Color(0xFFA78BFA), bg: const Color(0xFFEDE9FE), fg: const Color(0xFF6D28D9)),
      CompanyType.hotel => (strip: const Color(0xFFC084FC), bg: const Color(0xFFF3E8FF), fg: const Color(0xFF7E22CE)),
      _ => (strip: _slate300, bg: _slate100, fg: _slate700),
    };

/// annStyle: (background, border, text, icon) per announcement type.
({Color bg, Color border, Color fg, IconData icon}) _annStyle(String type) => switch (type) {
      'Critical' || 'Security' =>
        (bg: const Color(0xFFFFF1F2), border: const Color(0xFFFECDD3), fg: const Color(0xFFBE123C), icon: Icons.gpp_maybe_outlined),
      'Warning' => (bg: const Color(0xFFFFFBEB), border: const Color(0xFFFDE68A), fg: const Color(0xFFB45309), icon: Icons.warning_amber_rounded),
      'Payment' => (bg: const Color(0xFFFFF7ED), border: const Color(0xFFFED7AA), fg: const Color(0xFFC2410C), icon: Icons.credit_card),
      'Maintenance' => (bg: _slate50, border: _slate200, fg: _slate700, icon: Icons.build_outlined),
      'FeatureUpdate' => (bg: const Color(0xFFF5F3FF), border: const Color(0xFFDDD6FE), fg: const Color(0xFF6D28D9), icon: Icons.auto_awesome),
      'Success' => (bg: const Color(0xFFECFDF5), border: const Color(0xFFA7F3D0), fg: _emerald700, icon: Icons.check),
      _ => (bg: const Color(0xFFEFF6FF), border: const Color(0xFFBFDBFE), fg: const Color(0xFF1D4ED8), icon: Icons.info_outline),
    };

const _annTypes = ['Info', 'Success', 'Warning', 'Critical', 'Maintenance', 'FeatureUpdate', 'Payment', 'Security'];

/// COMPANY_CARD_METRICS (lib/api/business-office.ts): label, slot, format,
/// admin-only. Every other type takes the Generic set, as on the web.
const _cardMetrics = {
  'Water': [
    ('Production today', 1, 'count', false),
    ('Bags in stock', 2, 'count', false),
    ('Driver returns', 3, 'count', false),
    ("Today's sales", 4, 'money', true),
  ],
  'Poultry': [
    ('Eggs today', 1, 'count', false),
    ('Feed stock', 2, 'kg', false),
    ('Mortality', 3, 'count', false),
    ("Today's sales", 4, 'money', true),
  ],
  'Generic': [
    ('Sales today', 1, 'money', true),
    ('Expenses today', 2, 'money', true),
    ('Low stock', 3, 'count', false),
    ('Customer debt', 4, 'money', true),
  ],
};

List<(String, int, String, bool)> cardMetricsForType(CompanyType t) => _cardMetrics[t.wire] ?? _cardMetrics['Generic']!;

/// orgCurrencySymbol: GHS → GH₵, USD → $, anything else shows as typed.
String orgCurrencySymbol(String code) {
  final c = code.trim().toUpperCase();
  if (c.isEmpty || c == 'GHS') return 'GH₵';
  if (c == 'USD') return r'$';
  return c;
}

/// The company sidebar palette (lib/utils/company-color.ts): handed out in
/// creation order, so the first eight companies never share a colour.
const _palette = [
  Color(0xFF10B981), Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFFF59E0B),
  Color(0xFFF43F5E), Color(0xFF14B8A6), Color(0xFF6366F1), Color(0xFFD946EF),
];

Map<String, Color> companyColorMap(List<Company> companies) {
  final ordered = [...companies]..sort((a, b) {
      final ta = DateTime.tryParse(a.createdAt ?? '')?.millisecondsSinceEpoch ?? 0;
      final tb = DateTime.tryParse(b.createdAt ?? '')?.millisecondsSinceEpoch ?? 0;
      if (ta != tb) return ta.compareTo(tb);
      return a.farmId.compareTo(b.farmId);
    });
  return {for (final (i, c) in ordered.indexed) c.farmId: _palette[i % _palette.length]};
}

String companyInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

/// The caller's local day, YYYY-MM-DD.
String _localToday() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _BusinessOfficeScreenState extends State<BusinessOfficeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _noticesKey = GlobalKey();
  final _tasksKey = GlobalKey();

  String _query = '';
  String _typeFilter = 'all';
  String? _openingId;

  /// Today's tile numbers by farmId; a missing company is loading or failed
  /// and shows a dash.
  final Map<String, Map> _snapshots = {};
  bool _showCurrency = false;
  String _orgCurrency = '';
  List<Map> _announcements = [];

  Session get _s => widget.session;
  List<Company> get _companies => _s.myCompanies;

  /// usePermissions().isAdmin: not plain staff. The Business Office has no
  /// active company, so any company where the user is not staff counts.
  bool get _isAdmin => _companies.any((c) => (c.role ?? '').toLowerCase() != 'staff');

  /// useCanCreateCompany: not staff, or the owner of a company.
  bool get _canCreateCompany {
    final me = _s.tokens.userId;
    return _isAdmin || (me != null && _companies.any((c) => c.ownerUserId == me));
  }

  String? get _orgOwnerUserId => _companies.where((c) => (c.ownerUserId ?? '').isNotEmpty).firstOrNull?.ownerUserId;

  String get _officeName => _s.organisationName ?? 'Business Office';
  String get _userName => _s.username ?? '';
  String get _orgCode => (_s.tokens.rememberedOrgCode ?? '').toUpperCase();

  /// The Business Office pages (Help, Billing, Companies) take a company; here
  /// there is none, so they get a neutral stand-in. It also keeps the module
  /// sidebar off them, as the web shows them in the Business Office chrome.
  Company get _neutral => Company(farmId: '', name: _officeName, type: CompanyType.unknown, role: _isAdmin ? 'Admin' : 'Staff');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted && p.getString(_showCurrencyKey) == '1') setState(() => _showCurrency = true);
    }).catchError((Object _) {});
    _s.loginClient.get('/api/Admin/organization/profile').then((res) {
      if (mounted && res is Map) setState(() => _orgCurrency = '${res['businessOfficeCurrency'] ?? ''}');
    }).catchError((Object _) {});
    _loadSnapshots();
    _loadAnnouncements();
  }

  Future<void> _reload() async {
    await _s.loadCompanies();
    _snapshots.clear();
    _loadSnapshots();
    await _loadAnnouncements();
    if (mounted) setState(() {});
  }

  /// One snapshot request per card, each landing on its own; a failure leaves
  /// that card at dashes rather than a toast.
  void _loadSnapshots() {
    for (final c in _companies) {
      _s.farmClient.get('/api/BusinessOffice/company-snapshot',
          query: {'farmId': c.farmId, 'type': c.type.wire, 'today': _localToday()}).then((res) {
        if (mounted && res is Map) setState(() => _snapshots[c.farmId] = res);
      }).catchError((Object _) {});
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      final res = await _s.farmClient.get('/api/Announcements', query: {
        'userId': _s.tokens.userId ?? '',
        if ((_orgOwnerUserId ?? '').isNotEmpty) 'orgOwnerUserId': _orgOwnerUserId,
        if (_isAdmin) 'isAdmin': 'true',
      });
      if (mounted) setState(() => _announcements = res is List ? [for (final a in res) if (a is Map) a] : []);
    } catch (_) {}
  }

  void _toast(String title, {String? description, bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
      content: Text(description == null ? title : '$title. $description'),
    ));
  }

  void _toggleCurrency() {
    setState(() => _showCurrency = !_showCurrency);
    SharedPreferences.getInstance().then((p) => p.setString(_showCurrencyKey, _showCurrency ? '1' : '0')).catchError((Object _) => false);
  }

  /// formatMetric: a dash for "no number yet"; money as a whole number, with
  /// the organisation's symbol only once "Show currency" is on.
  String _formatMetric(Object? raw, String format) {
    if (raw == null || '$raw'.isEmpty) return '—';
    final v = num.tryParse('$raw');
    if (v == null || !v.isFinite) return '—';
    final n = NumberFormat('#,##0').format(v.round());
    if (format == 'money') return _showCurrency ? '${orgCurrencySymbol(_orgCurrency)} $n' : n;
    if (format == 'kg') return '$n kg';
    return n;
  }

  /// Switch into the company, then the shell opens its dashboard -- or
  /// [then], the page asked for (My Tasks → Flock Lifecycle).
  Future<void> _openCompany(Company c, {Widget Function(Session, Company)? then}) async {
    if (_openingId != null) return;
    setState(() => _openingId = c.farmId);
    _s.pendingScreen = then;
    final ok = await _s.setActive(c);
    if (!mounted) return;
    if (ok) {
      widget.onPicked();
    } else {
      _s.pendingScreen = null;
      setState(() => _openingId = null);
      _toast("Couldn't open company", description: _s.error, error: true);
    }
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _administration([String tab = 'org']) => _push(AdministrationScreen(session: _s, initialTab: tab, onCompaniesChanged: _reload));

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: .05);
  }

  Future<void> _signOut() async {
    await _s.signOut();
    widget.onSignedOut();
  }

  // ------------------------------------------------------------ announcements

  Future<void> _annAction(Map a, String action) async {
    final id = a['announcementId'];
    try {
      await _s.farmClient.post('/api/Announcements/$id/receipt',
          query: {'userId': _s.tokens.userId ?? '', 'action': action});
      setState(() {
        if (action == 'Dismiss') {
          _announcements = [for (final x in _announcements) if (x['announcementId'] != id) x];
        } else {
          _announcements = [
            for (final x in _announcements)
              x['announcementId'] == id ? {...x, 'acknowledgedAt': DateTime.now().toIso8601String()} : x,
          ];
        }
      });
    } on ApiException catch (e) {
      _toast('Action failed', description: e.message, error: true);
    }
  }

  Future<void> _annDelete(Map a) async {
    final owner = _orgOwnerUserId;
    if (owner == null) return;
    try {
      await _s.farmClient.delete('/api/Announcements/${a['announcementId']}?orgOwnerUserId=${Uri.encodeQueryComponent(owner)}');
      setState(() => _announcements = [for (final x in _announcements) if (x['announcementId'] != a['announcementId']) x]);
    } on ApiException catch (e) {
      _toast('Delete failed', description: e.message, error: true);
    }
  }

  /// The announcement's link: a page of this app's web is opened in-app; an
  /// outside address is copied, since the app opens no outside browser.
  Future<void> _annOpen(Map a) async {
    final url = '${a['actionUrl'] ?? ''}'.trim();
    if (url.isEmpty) return;
    if (url.startsWith('/')) {
      _push(WebPageScreen(label: '${a['actionLabel'] ?? a['title'] ?? 'Open'}', href: url, company: _neutral, session: _s));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _toast('Link copied', description: 'Open it in your browser: $url');
  }

  Future<void> _postAnnouncement() async {
    final posted = await showDialog<bool>(
      context: context,
      builder: (_) => _PostAnnouncementDialog(session: _s, orgOwnerUserId: _orgOwnerUserId),
    );
    if (posted == true) {
      _toast('Announcement posted');
      await _loadAnnouncements();
    }
  }

  // ------------------------------------------------------------ create company

  Future<void> _createCompany() async {
    final created = await showDialog<({String name, String farmId, String companyType, String? industry})>(
      context: context,
      builder: (_) => _CreateCompanyDialog(session: _s, officeName: _officeName),
    );
    if (created == null || !mounted) return;
    _toast('Created ${created.name}');
    await _s.loadCompanies();
    _loadSnapshots();
    if (mounted) setState(() {});
    // A business type that carries a template is set up before it is useful:
    // switch into it and hand over to the setup wizard, as the web does.
    if (created.industry != null && created.farmId.isNotEmpty) {
      final c = Company(farmId: created.farmId, name: created.name, type: companyTypeFrom(created.companyType));
      await _openCompany(c,
          then: (s, company) => WebPageScreen(
                label: 'Set up ${created.name}',
                href: '/generic-setup/wizard?industry=${Uri.encodeQueryComponent(created.industry!)}',
                company: company,
                session: s,
              ));
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final all = _companies;
    int by(CompanyType t) => all.where((c) => c.type == t).length;
    final loading = _s.busy && all.isEmpty;
    final q = _query.trim().toLowerCase();
    final visible = [
      for (final c in all)
        if ((_typeFilter == 'all' || c.type.wire == _typeFilter) &&
            (q.isEmpty || '${c.name} ${c.type.wire} ${c.role ?? ''}'.toLowerCase().contains(q)))
          c,
    ];

    return Scaffold(
      key: _scaffold,
      backgroundColor: _slate50,
      drawer: _Sidebar(
        companies: all,
        loading: loading,
        openingId: _openingId,
        isAdmin: _isAdmin,
        onHome: () => Navigator.pop(context),
        onTasks: () {
          Navigator.pop(context);
          _scrollTo(_tasksKey);
        },
        onOpen: (c) {
          Navigator.pop(context);
          _openCompany(c);
        },
        onNewCompany: () {
          Navigator.pop(context);
          _createCompany();
        },
        onAdministration: () {
          Navigator.pop(context);
          _administration();
        },
        onBilling: () {
          Navigator.pop(context);
          _push(BillingScreen(session: _s, company: _neutral));
        },
        onLogout: () {
          Navigator.pop(context);
          _signOut();
        },
      ),
      body: Column(children: [
        _TopBar(
          userName: _userName,
          officeName: _officeName,
          roleLabel: _isAdmin ? 'Organization Admin' : 'Staff',
          orgCode: _isAdmin ? _orgCode : '',
          onMenu: () => _scaffold.currentState?.openDrawer(),
          onBell: () => _scrollTo(_noticesKey),
          onHelp: () => _push(HelpCenterScreen(session: _s, company: _neutral)),
        ),
        // Phones: the company selector sits under the bar, full width.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _CompanySelector(companies: all, openingId: _openingId, onOpen: _openCompany),
        ),
        const Divider(height: 1, color: _slate200),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                _announcementsSection(),
                const SizedBox(height: 22),
                _summaryTiles(loading, all.length, by),
                const SizedBox(height: 26),
                ..._companiesSection(loading, all, visible),
                _MyTasks(
                  key: _tasksKey,
                  session: _s,
                  companies: all,
                  onOpen: (c, flockId) => _openCompany(c,
                      then: (s, company) => FlockLifecycleScreen(session: s, company: company, initialFlockId: '$flockId')),
                ),
                const SizedBox(height: 24),
                _quickActions(),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sectionLabel(IconData? icon, String text) => Row(children: [
        if (icon != null) ...[Icon(icon, size: 16, color: _slate500), const SizedBox(width: 6)],
        Flexible(
          child: Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: .6, color: _slate500)),
        ),
      ]);

  Widget _announcementsSection() {
    return Column(key: _noticesKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _sectionLabel(Icons.campaign_outlined, 'VisibilityCore Announcements')),
        if (_isAdmin) _OutlineButton(icon: Icons.add, label: 'Post', onTap: _postAnnouncement),
      ]),
      const SizedBox(height: 10),
      if (_announcements.isEmpty)
        _DashedBox(child: const Text('No new notifications.', style: TextStyle(fontSize: 14, color: _slate400)))
      else
        for (final a in _announcements) ...[_announcementCard(a), const SizedBox(height: 8)],
    ]);
  }

  Widget _announcementCard(Map a) {
    final type = '${a['type'] ?? 'Info'}';
    final st = _annStyle(type);
    final acked = '${a['acknowledgedAt'] ?? ''}'.isNotEmpty;
    final requiresAck = a['requiresAck'] == true;
    final message = '${a['message'] ?? ''}';
    final hasAction = '${a['actionUrl'] ?? ''}'.isNotEmpty;
    final canDelete = _isAdmin && '${a['orgOwnerUserId'] ?? ''}'.isNotEmpty;
    Widget pill(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        );
    TextButton link(String label, Color color, VoidCallback onTap, {IconData? icon, bool bold = true}) => TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            visualDensity: VisualDensity.compact,
            textStyle: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w600 : FontWeight.w500),
          ),
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15),
          label: Text(label),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
      decoration: BoxDecoration(color: st.bg, border: Border.all(color: st.border), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(10)),
          child: Icon(st.icon, size: 20, color: st.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${a['title'] ?? ''}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _slate900)),
              pill(type, const Color(0xB3FFFFFF), _slate700),
              if (requiresAck)
                acked
                    ? pill('Acknowledged', const Color(0xFFD1FAE5), _emerald700)
                    : pill('Action needed', _slate200, _slate700),
            ]),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(message, style: const TextStyle(fontSize: 13.5, color: _slate700, height: 1.35)),
            ],
            if (hasAction || (requiresAck && !acked) || canDelete) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 8, children: [
                if (hasAction) link('${a['actionLabel'] ?? ''}'.isEmpty ? 'Open' : '${a['actionLabel']}', st.fg, () => _annOpen(a)),
                if (requiresAck && !acked) link('Acknowledge', _emerald700, () => _annAction(a, 'Ack')),
                if (canDelete) link('Delete', _slate500, () => _annDelete(a), icon: Icons.delete_outline, bold: false),
              ]),
            ],
          ]),
        ),
        if (a['isDismissible'] == true)
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: _slate400),
            onPressed: () => _annAction(a, 'Dismiss'),
          ),
      ]),
    );
  }

  Widget _summaryTiles(bool loading, int total, int Function(CompanyType) by) {
    final tiles = [
      ('Companies', total, Icons.apartment_outlined, _slate600, _slate100),
      ('Water', by(CompanyType.water), Icons.water_drop_outlined, const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
      ('Poultry', by(CompanyType.poultry), Icons.flutter_dash, _orange600, const Color(0xFFFFEDD5)),
      ('Generic', by(CompanyType.generic), Icons.shopping_bag_outlined, const Color(0xFF7C3AED), const Color(0xFFEDE9FE)),
      ('Hotel', by(CompanyType.hotel), Icons.apartment_outlined, const Color(0xFF9333EA), const Color(0xFFF3E8FF)),
    ];
    // Two to a row; the odd one out takes the full width.
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final pair = tiles.skip(i).take(2).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 12 : 0),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (j, t) in pair.indexed) ...[
              if (j > 0) const SizedBox(width: 12),
              Expanded(child: _SummaryTile(label: t.$1, value: loading ? '…' : '${t.$2}', icon: t.$3, fg: t.$4, bg: t.$5)),
            ],
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }

  List<Widget> _companiesSection(bool loading, List<Company> all, List<Company> visible) {
    final empty = !loading && all.isEmpty;
    return [
      const Text('Your companies', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _slate900)),
      const SizedBox(height: 12),
      // Off by default: the cards show plain numbers until asked; remembered.
      Row(children: [
        _OutlineButton(
          icon: Icons.toll_outlined,
          label: _showCurrency ? 'Hide currency' : 'Show currency',
          selected: _showCurrency,
          tooltip: _showCurrency
              ? 'Hide the currency symbol on the cards'
              : 'Show amounts in ${orgCurrencySymbol(_orgCurrency)} (Organization Profile default)',
          onTap: _toggleCurrency,
          height: 46,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppSelect<String>(
            value: _typeFilter,
            items: const [
              AppSelectItem(value: 'all', label: 'All types'),
              AppSelectItem(value: 'Water', label: 'Water'),
              AppSelectItem(value: 'Poultry', label: 'Poultry'),
              AppSelectItem(value: 'Generic', label: 'Generic'),
              AppSelectItem(value: 'Hotel', label: 'Hotel'),
            ],
            onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      AppSearchField(hintText: 'Search companies…', onChanged: (v) => setState(() => _query = v)),
      const SizedBox(height: 14),
      if (loading)
        const Padding(
          padding: EdgeInsets.all(28),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading your companies…', style: TextStyle(color: _slate500)),
          ]),
        )
      else if (empty)
        _EmptyCard(
          icon: Icons.apartment_outlined,
          text: _canCreateCompany
              ? 'Create your first company to get started.'
              : "You don't currently have access to any company. Contact your Business Office administrator.",
          action: _canCreateCompany
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _slate900),
                  onPressed: _createCompany,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create company'),
                )
              : null,
        )
      else if (visible.isEmpty)
        const _EmptyCard(text: 'No companies match your search.')
      else
        for (final c in visible) ...[
          _CompanyCard(
            company: c,
            metrics: [
              for (final m in cardMetricsForType(c.type).where((m) => _isAdmin || !m.$4).take(4))
                (m.$1, _formatMetric(_snapshots[c.farmId]?['metric${m.$2}'], m.$3)),
            ],
            opening: _openingId == c.farmId,
            disabled: _openingId != null,
            isAdmin: _isAdmin,
            onOpen: () => _openCompany(c),
            onAccess: () => _administration('users'),
          ),
          const SizedBox(height: 14),
        ],
      const SizedBox(height: 10),
    ];
  }

  Widget _quickActions() {
    final actions = [
      if (_canCreateCompany) (Icons.add, 'Create company', _createCompany),
      if (_isAdmin) (Icons.group_outlined, 'Manage users', () => _administration('users')),
      (Icons.apartment_outlined, 'All companies', () => _push(CompaniesScreen(session: _s, company: _neutral))),
      (Icons.help_outline, 'Help center', () => _push(HelpCenterScreen(session: _s, company: _neutral))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionLabel(null, 'Quick actions'),
      const SizedBox(height: 10),
      // A Material, not a coloured box: the rows' tap ripple paints on it.
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(side: const BorderSide(color: _slate200), borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, (icon, label, onTap)) in actions.indexed) ...[
            if (i > 0) const Divider(height: 1, color: _slate100),
            ListTile(
              onTap: onTap,
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: _slate100, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 18, color: _slate600),
              ),
              title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: _slate700)),
              trailing: const Icon(Icons.chevron_right, color: _slate300),
            ),
          ],
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- top bar

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.userName,
    required this.officeName,
    required this.roleLabel,
    required this.orgCode,
    required this.onMenu,
    required this.onBell,
    required this.onHelp,
  });
  final String userName, officeName, roleLabel, orgCode;
  final VoidCallback onMenu, onBell, onHelp;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_orange600, _amber500]),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0x40FFFFFF)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onMenu,
                child: const SizedBox(width: 38, height: 38, child: Icon(Icons.menu, color: Colors.white, size: 21)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  'Welcome${userName.isEmpty ? '' : ', $userName'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$officeName · $roleLabel'),
                    if (orgCode.isNotEmpty)
                      TextSpan(text: '  $orgCode', style: const TextStyle(fontFamily: 'monospace', color: Color(0xB3FFFFFF))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 11.5),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: onBell,
              icon: const Icon(Icons.notifications_none, color: Colors.white),
            ),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x4DFFFFFF)),
              ),
              child: Text(
                (userName.isEmpty ? 'U' : userName.characters.first).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            IconButton(
              tooltip: 'Help',
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The global company selector (bo-company-selector.tsx): "Select a company…",
/// listing every company the user can open; picking one opens it.
class _CompanySelector extends StatelessWidget {
  const _CompanySelector({required this.companies, required this.openingId, required this.onOpen});
  final List<Company> companies;
  final String? openingId;
  final Future<void> Function(Company c) onOpen;

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<Company>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Select a company', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _slate900)),
            ),
            if (companies.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No companies yet.', textAlign: TextAlign.center, style: TextStyle(color: _slate500)),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [
                for (final c in companies)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: _typeTone(c.type).bg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(_typeIcon(c.type), size: 20, color: _typeTone(c.type).fg),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${c.type.wire}${c.role != null ? ' · ${c.role}' : ''}'),
                    trailing: const Icon(Icons.arrow_forward, size: 18, color: _slate400),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (picked != null) await onOpen(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: openingId != null ? null : () => _pick(context),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _slate200)),
          child: Row(children: [
            const Icon(Icons.apartment_outlined, size: 18, color: _slate500),
            const SizedBox(width: 10),
            const Expanded(child: Text('Select a company…', style: TextStyle(fontSize: 14, color: _slate500))),
            if (openingId != null)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.keyboard_arrow_down, color: _slate500),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sidebar

/// The Business Office sidebar, as a drawer: Business Office and My Tasks,
/// every company (its own colour, initial, kind and icon) with "New company"
/// last, Administration and Billing at the bottom, then Logout.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.companies,
    required this.loading,
    required this.openingId,
    required this.isAdmin,
    required this.onHome,
    required this.onTasks,
    required this.onOpen,
    required this.onNewCompany,
    required this.onAdministration,
    required this.onBilling,
    required this.onLogout,
  });
  final List<Company> companies;
  final bool loading, isAdmin;
  final String? openingId;
  final VoidCallback onHome, onTasks, onNewCompany, onAdministration, onBilling, onLogout;
  final ValueChanged<Company> onOpen;

  Widget _row(IconData icon, String label, VoidCallback onTap, {bool active = false, Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: active ? _slate800 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: active
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: _orange400, width: 2)),
                    )
                  : null,
              child: Row(children: [
                Icon(icon, size: 19, color: color ?? (active ? _orange300 : _slate400)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color ?? (active ? Colors.white : _slate300))),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colours = companyColorMap(companies);
    return Drawer(
      backgroundColor: _slate900,
      width: 288,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(children: [
          InkWell(
            onTap: onHome,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate800))),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: _orange500, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.work_outline, size: 19, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('VisibilityCore',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('Business Office', overflow: TextOverflow.ellipsis, style: TextStyle(color: _slate400, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(8, 12, 8, 12), children: [
              _row(Icons.work_outline, 'Business Office', onHome, active: true),
              _row(Icons.checklist, 'My Tasks', onTasks),
              const SizedBox(height: 18),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _slate400)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(color: _slate500, fontSize: 13)),
                  ]),
                )
              else if (companies.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('No companies yet.', style: TextStyle(color: _slate500, fontSize: 12)),
                )
              else
                for (final c in companies) _companyRow(c, colours[c.farmId] ?? _palette.first),
              if (isAdmin) _row(Icons.add, 'New company', onNewCompany, color: _orange300),
              if (isAdmin) ...[
                const SizedBox(height: 22),
                _row(Icons.settings_outlined, 'Administration', onAdministration),
                _row(Icons.credit_card, 'Billing', onBilling),
              ],
            ]),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _slate800))),
            padding: const EdgeInsets.all(8),
            child: _row(Icons.logout, 'Logout', onLogout),
          ),
        ]),
      ),
    );
  }

  Widget _companyRow(Company c, Color colour) {
    final opening = openingId == c.farmId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: colour.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: openingId != null ? null : () => onOpen(c),
          child: Opacity(
            opacity: openingId != null && !opening ? .6 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(6)),
                  child: Text(companyInitial(c.name),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _slate900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(c.type.wire, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _slate400, fontSize: 11.5)),
                  ]),
                ),
                if (opening)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _slate300))
                else
                  Icon(_typeIcon(c.type), size: 15, color: _slate400),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.tooltip,
    this.height = 36,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final String? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      toggled: selected,
      child: Material(
        color: selected ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? _orange300 : _slate200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: selected ? _orange600 : _slate700),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: selected ? _orange600 : _slate700)),
            ]),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

/// The web's `border-dashed` box.
class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _slate300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.fg, required this.bg});
  final String label, value;
  final IconData icon;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 21, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _slate500)),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15, color: _slate900)),
            ]),
          ),
        ]),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text, this.icon, this.action});
  final String text;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          if (icon != null) ...[Icon(icon, size: 40, color: _slate300), const SizedBox(height: 12)],
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _slate600, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.company,
    required this.metrics,
    required this.opening,
    required this.disabled,
    required this.isAdmin,
    required this.onOpen,
    required this.onAccess,
  });
  final Company company;
  final List<(String, String)> metrics;
  final bool opening, disabled, isAdmin;
  final VoidCallback onOpen, onAccess;

  @override
  Widget build(BuildContext context) {
    final tone = _typeTone(company.type);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _slate200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 4, color: tone.strip),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(_typeIcon(company.type), size: 21, color: tone.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(company.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: _slate900)),
                  const SizedBox(height: 2),
                  Text('Role: ${company.role ?? '—'}', style: const TextStyle(fontSize: 12, color: _slate500)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
                child: Text(company.type.wire, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg)),
              ),
            ]),
            const SizedBox(height: 14),
            // Today's numbers, two to a row.
            for (var i = 0; i < metrics.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(children: [
                for (final (j, m) in metrics.skip(i).take(2).indexed) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: _slate50, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _slate500)),
                        const SizedBox(height: 1),
                        Text(m.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate700)),
                      ]),
                    ),
                  ),
                ],
                if (metrics.skip(i).length == 1) ...[const SizedBox(width: 8), const Expanded(child: SizedBox.shrink())],
              ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _slate900,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: disabled ? null : onOpen,
                  child: opening
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 8),
                          Text('Opening…'),
                        ])
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Open'),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward, size: 17),
                        ]),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _slate700,
                    side: const BorderSide(color: _slate200),
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: onAccess,
                  child: const Text('Access'),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- My Tasks

/// My Tasks (migration 347): the flock lifecycle reminders of every Poultry
/// company, one request per company. A company that refuses (401/403) is left
/// out; one that fails otherwise is named. Hidden when there is no Poultry
/// company, or none lets this user see its tasks.
class _MyTasks extends StatefulWidget {
  const _MyTasks({super.key, required this.session, required this.companies, required this.onOpen});
  final Session session;
  final List<Company> companies;
  final void Function(Company company, Object? flockId) onOpen;

  @override
  State<_MyTasks> createState() => _MyTasksState();
}

class _MyTasksState extends State<_MyTasks> {
  static const _show = 8;
  final List<Map> _tasks = [];
  final Map<String, String> _state = {};
  bool _showAll = false;
  String _loadedFor = '';

  List<Company> get _poultry => [for (final c in widget.companies) if (c.type == CompanyType.poultry) c];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MyTasks old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final key = _poultry.map((c) => c.farmId).join(',');
    if (key == _loadedFor) return;
    _loadedFor = key;
    _tasks.clear();
    _state
      ..clear()
      ..addAll({for (final c in _poultry) c.farmId: 'loading'});
    for (final c in _poultry) {
      widget.session.farmClient.get('/api/Poultry/lifecycle/tasks', query: {'farmId': c.farmId, 'view': 'Open'}).then((res) {
        if (!mounted || _loadedFor != key) return;
        setState(() {
          _tasks.addAll([
            for (final r in (res is List ? res : const []))
              if (r is Map) {...r, 'companyFarmId': c.farmId, 'companyName': c.name},
          ]);
          _state[c.farmId] = 'ok';
        });
      }).catchError((Object e) {
        if (!mounted || _loadedFor != key) return;
        final denied = e is ApiException && (e.statusCode == 401 || e.statusCode == 403);
        setState(() => _state[c.farmId] = denied ? 'denied' : 'failed');
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final poultry = _poultry;
    if (poultry.isEmpty) return const SizedBox.shrink();
    final loading = _state.values.contains('loading');
    final allowed = [for (final c in poultry) if (_state[c.farmId] != 'denied') c];
    if (!loading && allowed.isEmpty) return const SizedBox.shrink();
    final failed = [for (final c in poultry) if (_state[c.farmId] == 'failed') c.name];
    final sorted = sortTasks(_tasks);
    final shown = _showAll ? sorted : sorted.take(_show).toList();
    final overdue = _tasks.where((t) => t['status'] == 'Overdue').length;
    final due = _tasks.where((t) => t['status'] == 'Due').length;

    Widget badge(String text, (Color, Color, Color) tone) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: tone.$1, border: Border.all(color: tone.$3), borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.$2)),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.checklist, size: 21, color: _indigo600),
            const SizedBox(width: 8),
            const Text('My Tasks', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _slate900)),
            if (loading) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _slate400)),
            ],
          ]),
          if (_tasks.isNotEmpty)
            Wrap(spacing: 6, children: [
              if (overdue > 0) badge('$overdue overdue', lifecycleStatusTone('Overdue')),
              if (due > 0) badge('$due due', lifecycleStatusTone('Due')),
              badge('${_tasks.length} open', (Colors.white, _slate700, _slate200)),
            ]),
        ]),
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!loading && _tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle_outline, size: 17, color: _emerald600),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text('No flock lifecycle reminders need attention.', style: TextStyle(color: _slate500)),
                  ),
                ]),
              ),
            if (loading && _tasks.isEmpty) const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator())),
            for (final (i, t) in shown.indexed) ...[
              if (i > 0) const Divider(height: 1, color: _slate100),
              _taskRow(t, badge),
            ],
            if (sorted.length > _show) ...[
              const Divider(height: 1, color: _slate100),
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? 'Show fewer' : 'Show all ${sorted.length}'),
              ),
            ],
          ]),
        ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text("Couldn't load tasks for ${failed.join(', ')}.", style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ],
      ]),
    );
  }

  Widget _taskRow(Map t, Widget Function(String, (Color, Color, Color)) badge) {
    final company = widget.companies.firstWhere((c) => c.farmId == t['companyFarmId']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              badge('${t['status'] ?? ''}', lifecycleStatusTone(t['status'])),
              Text('${t['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
              if (t['isEstimated'] == true) badge('Estimated', (const Color(0xFFFFFBEB), const Color(0xFF92400E), const Color(0xFFFCD34D))),
            ]),
            const SizedBox(height: 3),
            Text('${taskSentence(t)} · ${dueLabel(t)}', style: const TextStyle(fontSize: 13, color: _slate600)),
            Text('${t['companyName'] ?? ''}', style: const TextStyle(fontSize: 12, color: _slate500)),
          ]),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _slate700,
            side: const BorderSide(color: _slate200),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => widget.onOpen(company, t['flockId']),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Open'), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 15)]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- dialogs

/// "Create new company": the business types the web offers (one of them may
/// carry a template, which then goes to the setup wizard). Pops what was made.
class _CreateCompanyDialog extends StatefulWidget {
  const _CreateCompanyDialog({required this.session, required this.officeName});
  final Session session;
  final String officeName;

  @override
  State<_CreateCompanyDialog> createState() => _CreateCompanyDialogState();
}

class _CreateCompanyDialogState extends State<_CreateCompanyDialog> {
  String _typeId = 'water';
  final _name = TextEditingController(), _email = TextEditingController(), _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Company name is required')));
      return;
    }
    final type = businessTypes.firstWhere((t) => t.id == _typeId);
    setState(() => _saving = true);
    try {
      final res = await widget.session.loginClient.post('/api/Companies', body: {
        'Name': name,
        'Type': type.companyType,
        'Email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'PhoneNumber': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      });
      // The web emails the company's address, or the account's. The app keeps
      // no account email, so it sends only when one was typed here.
      final to = _email.text.trim();
      if (to.isNotEmpty) {
        try {
          await widget.session.farmClient.post('/api/Email/send-welcome',
              body: {'Email': to, 'CompanyName': name, 'CompanyType': type.companyType});
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(context, (
        name: name,
        farmId: res is Map ? '${res['farmId'] ?? res['id'] ?? ''}' : '',
        companyType: type.companyType,
        industry: type.industryTemplate,
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Create failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = businessTypes.firstWhere((t) => t.id == _typeId);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.apartment_outlined, color: FormColor.amber, text: 'Create new company'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel(
              'Business type *',
              AppSelect<String>(
                value: _typeId,
                items: [for (final t in businessTypes) AppSelectItem(value: t.id, label: t.label)],
                onChanged: (v) => setState(() => _typeId = v ?? _typeId),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              type.industryTemplate != null
                  ? "We'll set up the right menus and starter categories for this, and you can change any of it later."
                  : type.description,
              style: const TextStyle(fontSize: 12, color: _slate500),
            ),
            const SizedBox(height: 12),
            FilterLabel('Company name *', AppInput(controller: _name, hintText: 'e.g. Great Favour Water Co.')),
            const SizedBox(height: 12),
            FilterLabel('Contact email', AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
            const SizedBox(height: 12),
            FilterLabel('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Created under '),
                TextSpan(text: widget.officeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(text: '; appears here and in your switcher.'),
              ]),
              style: const TextStyle(fontSize: 12, color: _slate500),
            ),
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _saving, children: [
            FilledButton(
              style: formPrimary(FormColor.amber),
              onPressed: _saving ? null : _create,
              child: Text(_saving ? 'Creating…' : 'Create'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// "Post an announcement" (organisation admins). Pops true once posted.
class _PostAnnouncementDialog extends StatefulWidget {
  const _PostAnnouncementDialog({required this.session, required this.orgOwnerUserId});
  final Session session;
  final String? orgOwnerUserId;

  @override
  State<_PostAnnouncementDialog> createState() => _PostAnnouncementDialogState();
}

class _PostAnnouncementDialogState extends State<_PostAnnouncementDialog> {
  final _title = TextEditingController(), _message = TextEditingController();
  final _actionLabel = TextEditingController(), _actionUrl = TextEditingController();
  String _type = 'Info', _audience = 'All';
  bool _dismissible = true, _requiresAck = false, _posting = false;

  @override
  void dispose() {
    for (final c in [_title, _message, _actionLabel, _actionUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _post() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_title.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }
    setState(() => _posting = true);
    try {
      await widget.session.farmClient.post('/api/Announcements', body: {
        'orgOwnerUserId': widget.orgOwnerUserId,
        'title': _title.text,
        'message': _message.text,
        'type': _type,
        'audienceRole': _audience,
        'isDismissible': _dismissible,
        'requiresAck': _requiresAck,
        'actionLabel': _actionLabel.text.isEmpty ? null : _actionLabel.text,
        'actionUrl': _actionUrl.text.isEmpty ? null : _actionUrl.text,
        'createdBy': widget.session.tokens.userId,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _posting = false);
      messenger.showSnackBar(SnackBar(content: Text('Post failed. ${e.message}')));
    }
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
        onTap: () => onChanged(!value),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 30, height: 30, child: Checkbox(value: value, onChanged: (v) => onChanged(v == true))),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13.5))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_posting,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.campaign_outlined, color: FormColor.blue, text: 'Post an announcement'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel('Title *', AppInput(controller: _title, hintText: 'e.g. Subscription renewal due')),
            const SizedBox(height: 12),
            FilterLabel('Message', AppInput(controller: _message, minLines: 3, maxLines: 6)),
            const SizedBox(height: 12),
            FormPair(
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  items: [for (final t in _annTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              FilterLabel(
                'Audience',
                AppSelect<String>(
                  value: _audience,
                  items: const [
                    AppSelectItem(value: 'All', label: 'Everyone'),
                    AppSelectItem(value: 'Admin', label: 'Admins only'),
                    AppSelectItem(value: 'Staff', label: 'Staff only'),
                  ],
                  onChanged: (v) => setState(() => _audience = v ?? _audience),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FormPair(
              FilterLabel('Action label (optional)', AppInput(controller: _actionLabel, hintText: 'e.g. Renew now')),
              FilterLabel('Action URL (optional)', AppInput(controller: _actionUrl, hintText: 'https://…')),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _check('Dismissible', _dismissible, (v) => setState(() => _dismissible = v)),
              _check('Requires acknowledgement', _requiresAck, (v) => setState(() => _requiresAck = v)),
            ]),
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _posting, children: [
            FilledButton(
              style: formPrimary(FormColor.blue),
              onPressed: _posting ? null : _post,
              child: Text(_posting ? 'Posting…' : 'Post announcement'),
            ),
          ]),
        ],
      ),
    );
  }
}
