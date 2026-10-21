// Restaurant → Growth → Notifications, as `app/restaurant-notifications/page.tsx`
// ("Notifications & Alerts"): Mark All Read, then All (the unread filter, a row
// per notification that marks itself read when tapped) and Settings (alert
// types and delivery channels, loaded when the tab is opened).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtInstant;
import '../shared/company_clock.dart';
import 'restaurant_widgets.dart';

/// The alert toggles, then the delivery channels: key, label, description.
const notificationAlertTypes = <(String, String, String)>[
  ('newOrderAlerts', 'New Order Alerts', 'Get notified when a new order is placed'),
  ('lowStockAlerts', 'Low Stock Alerts', 'Alert when ingredients fall below reorder point'),
  ('reservationAlerts', 'Reservation Reminders', 'Upcoming reservation notifications'),
  ('kpiAlerts', 'KPI Threshold Alerts', 'Alert when food cost or other KPIs exceed thresholds'),
  ('shiftReminders', 'Shift Reminders', 'Notify staff before their shift starts'),
];
const notificationChannels = <(String, String, String)>[
  ('emailEnabled', 'Email', 'Receive notifications via email'),
  ('smsEnabled', 'SMS', 'Receive notifications via text message'),
  ('pushEnabled', 'Push', 'Receive browser push notifications'),
];

/// The page's defaults until saved settings load.
const notificationDefaults = <String, bool>{
  'newOrderAlerts': true, 'lowStockAlerts': true, 'reservationAlerts': true, 'kpiAlerts': true,
  'shiftReminders': false, 'emailEnabled': true, 'smsEnabled': false, 'pushEnabled': false,
};

/// timeAgo: "Just now", "5m ago", "3h ago", "2d ago", then the date.
String notificationTimeAgo(Object? createdAt, Duration offset, {DateTime? now}) {
  final then = DateTime.tryParse(tStr(createdAt));
  if (then == null) return '';
  final diff = (now ?? DateTime.now()).difference(then);
  final mins = diff.isNegative ? 0 : diff.inMinutes;
  if (mins < 1) return 'Just now';
  if (mins < 60) return '${mins}m ago';
  final hrs = mins ~/ 60;
  if (hrs < 24) return '${hrs}h ago';
  final days = hrs ~/ 24;
  if (days < 7) return '${days}d ago';
  return fmtInstant(createdAt, offset);
}

(IconData, Color) _severity(Object? s) => switch (tStr(s).toLowerCase()) {
      'warning' => (Icons.warning_amber_outlined, const Color(0xFFF59E0B)),
      'error' => (Icons.cancel_outlined, const Color(0xFFEF4444)),
      'success' => (Icons.check_circle_outline, const Color(0xFF22C55E)),
      _ => (Icons.info_outline, const Color(0xFF3B82F6)),
    };

class RestaurantNotificationsScreen extends StatefulWidget {
  const RestaurantNotificationsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantNotificationsScreen> createState() => _RestaurantNotificationsScreenState();
}

class _RestaurantNotificationsScreenState extends State<RestaurantNotificationsScreen> {
  bool _loading = true, _saving = false, _unreadOnly = false;
  String _tab = 'all';
  List<Map<String, dynamic>> _items = [];
  final Map<String, bool> _settings = {...notificationDefaults};
  Duration _offset = Duration.zero;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/Restaurant/notifications', query: _q);
      _items = [for (final x in (r is List ? r : const [])) if (x is Map) Map<String, dynamic>.from(x)];
    } catch (_) {
      if (mounted) trackerToast(context, 'Error', description: 'Failed to load notifications', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  // Settings may not exist yet; the defaults stay.
  Future<void> _loadSettings() async {
    try {
      final s = await _api.get('/api/Restaurant/notifications/settings', query: _q);
      if (s is Map && mounted) {
        setState(() {
          for (final k in notificationDefaults.keys) {
            if (s[k] is bool) _settings[k] = s[k] as bool;
          }
        });
      }
    } catch (_) {}
  }

  int get _unread => _items.where((n) => n['isRead'] != true).length;

  Future<void> _markAll() async {
    try {
      await _api.post('/api/Restaurant/notifications/read-all', query: _q);
      setState(() {
        for (final n in _items) {
          n['isRead'] = true;
        }
      });
      if (mounted) trackerToast(context, 'Done', description: 'All notifications marked as read');
    } catch (_) {
      if (mounted) trackerToast(context, 'Error', description: 'Failed to mark all as read', error: true);
    }
  }

  // Silent on failure, as the web.
  Future<void> _markRead(Map<String, dynamic> n) async {
    try {
      await _api.post('/api/Restaurant/notifications/${tIntOrNull(n['notificationId'])}/read', query: _q);
      if (mounted) setState(() => n['isRead'] = true);
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await _api.post('/api/Restaurant/notifications/settings', body: {..._settings, 'farmId': widget.company.farmId});
      if (mounted) trackerToast(context, 'Saved', description: 'Notification preferences updated');
    } catch (_) {
      if (mounted) trackerToast(context, 'Error', description: 'Failed to save settings', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-notifications');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Notifications & Alerts')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.notifications_none,
                  title: 'Notifications & Alerts',
                  subtitle: 'Stay on top of orders, stock, and operations',
                  actions: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: _unread == 0 ? null : _markAll,
                      child: const Text('Mark All Read'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                RTabs(
                  value: _tab,
                  onChanged: (v) {
                    setState(() => _tab = v);
                    if (v == 'settings') _loadSettings();
                  },
                  tabs: [
                    ('all', Icons.notifications_none, 'All', _unread > 0 ? rBadge('$_unread', bg: const Color(0xFFE11D48), fg: Colors.white) : null),
                    ('settings', Icons.settings_outlined, 'Settings', null),
                  ],
                ),
                const SizedBox(height: 12),
                if (_tab == 'all') _allTab() else _settingsTab(),
              ]),
            ),
    );
  }

  Widget _allTab() {
    final shown = _unreadOnly ? [for (final n in _items) if (n['isRead'] != true) n] : _items;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: _unreadOnly
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48), visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _unreadOnly = false),
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: const Text('Showing Unread'),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _unreadOnly = true),
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: const Text('Show Unread Only'),
                ),
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          REmptyState(
            icon: Icons.notifications_none,
            title: 'No notifications',
            description: _unreadOnly
                ? "You're all caught up! No unread notifications."
                : "You're all caught up! Alerts will appear here for orders, low stock, and more.",
          )
        else
          for (final n in shown) ...[_row(n), const SizedBox(height: 8)],
      ]),
    );
  }

  Widget _row(Map<String, dynamic> n) {
    final unread = n['isRead'] != true;
    final (icon, color) = _severity(n['severity']);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: unread ? () => _markRead(n) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: unread ? const Color(0x99EFF6FF) : Colors.white,
          border: Border.all(color: unread ? const Color(0xFFDBEAFE) : TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          if (unread)
            Positioned(
              left: -10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle)),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tStr(n['title']),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          color: unread ? const Color(0xFF111827) : const Color(0xFF374151))),
                  rBadge(tStr(n['type']), bg: Colors.white, border: TColors.slate200),
                ]),
                const SizedBox(height: 2),
                Text(tStr(n['message']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(notificationTimeAgo(n['createdAt'], _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ]),
      ),
    );
  }

  Widget _toggle((String, String, String) item) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text(item.$3, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Switch(
            value: _settings[item.$1] ?? false,
            activeTrackColor: const Color(0xFFE11D48),
            onChanged: (v) => setState(() => _settings[item.$1] = v),
          ),
        ]),
      );

  Widget _settingsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Notification Preferences', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const Text('Choose which alerts you receive and how', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          for (final item in notificationAlertTypes) _toggle(item),
          const Divider(height: 24),
          const Text('Delivery Channels', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          for (final item in notificationChannels) _toggle(item),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48), minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : _saveSettings,
            child: Text(_saving ? 'Saving...' : 'Save Preferences'),
          ),
        ]),
      );
}
