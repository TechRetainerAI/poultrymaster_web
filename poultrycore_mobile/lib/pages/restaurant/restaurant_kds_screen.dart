// Restaurant → Orders & Kitchen → Kitchen Display, as `app/restaurant-kds/page.tsx`:
// the dark kitchen board. Station tabs (All, each active station in its own
// colour, Expo), the counts, Sound, Full screen and Exit (back to the POS);
// one card per order, coloured by its oldest item (green < 5 m, yellow < 10,
// orange < 15, red after), each item with Bump and Recall, and Bump All /
// Complete Order when a card holds more than one item. Refreshed every 5 s.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart' show trackerToast;
import 'restaurant_pos_screen.dart';

/// getTimingColor: border and background.
(Color, Color) kdsTiming(num minutes) {
  if (minutes < 5) return (const Color(0xFF22C55E), const Color(0xFFF0FDF4));
  if (minutes < 10) return (const Color(0xFFEAB308), const Color(0xFFFEFCE8));
  if (minutes < 15) return (const Color(0xFFF97316), const Color(0xFFFFF7ED));
  return (const Color(0xFFEF4444), const Color(0xFFFEF2F2));
}

/// formatTime: "<1m", "12m", "1h5m".
String kdsTime(num minutes) {
  if (minutes < 1) return '<1m';
  if (minutes < 60) return '${minutes.floor()}m';
  return '${(minutes / 60).floor()}h${(minutes % 60).floor()}m';
}

/// groupByOrder, in the order the queue lists them.
List<List<Map>> kdsGroups(List<Map> queue) {
  final groups = <String, List<Map>>{};
  for (final i in queue) {
    groups.putIfAbsent('${i['orderId']}-${i['orderNumber']}', () => []).add(i);
  }
  return groups.values.toList();
}

Color _hex(String s, Color fallback) {
  final h = s.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

class RestaurantKdsScreen extends StatefulWidget {
  const RestaurantKdsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantKdsScreen> createState() => _RestaurantKdsScreenState();
}

class _RestaurantKdsScreenState extends State<RestaurantKdsScreen> {
  bool _loading = true;
  List<Map> _stations = [];
  List<Map> _queue = [];
  Map? _stats;
  int? _station;
  bool _expo = false;
  bool _soundOn = true;
  bool _fullscreen = false;
  int _prevCount = 0;
  Timer? _poll;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  Future<void> _loadInitial() async {
    try {
      final st = await _api.get('/api/Restaurant/kds/stations', query: _q);
      _stations = [for (final s in (st is List ? st : const [])) if (s is Map && s['isActive'] != false) s];
      await _refresh();
    } catch (e) {
      _toast('Failed to load', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    try {
      final r = await Future.wait<Object?>([
        _api.get('/api/Restaurant/kds/queue', query: {..._q, '_': 1, 'stationId': ?_station, if (_expo) 'isExpo': 'true'}),
        _api.get('/api/Restaurant/kds/stats', query: _q),
      ]);
      final q = [for (final x in (r[0] is List ? r[0] as List : const [])) if (x is Map) x];
      if (_soundOn && q.length > _prevCount && _prevCount > 0) SystemSound.play(SystemSoundType.alert);
      _prevCount = q.length;
      if (mounted) {
        setState(() {
          _queue = q;
          _stats = r[1] is Map ? r[1] as Map : null;
        });
      }
    } catch (_) {}
  }

  void _pick(int? station, bool expo) {
    setState(() {
      _station = station;
      _expo = expo;
    });
    _refresh();
  }

  Future<void> _act(String path, String ok, String fail, {bool newStatus = true}) async {
    try {
      final r = await _api.post(path, query: _q);
      _toast(newStatus ? '$ok ${r is Map ? tStr(r['newStatus']) : ''}'.trim() : ok);
      _refresh();
    } catch (e) {
      _toast(fail, description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    SystemChrome.setEnabledSystemUIMode(_fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  void _exit() => Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RestaurantPosScreen(session: widget.session, company: widget.company),
      ));

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF111827);
    if (_loading) {
      return const Scaffold(backgroundColor: bg, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    final groups = kdsGroups(_queue);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.soup_kitchen_outlined, size: 64, color: Color(0xFF6B7280)),
                      SizedBox(height: 12),
                      Text('No active orders', style: TextStyle(fontSize: 20, color: Color(0xFF6B7280))),
                      SizedBox(height: 4),
                      Text('Waiting for orders...', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                    ]),
                  )
                : ListView(padding: const EdgeInsets.all(14), children: [for (final g in groups) _orderCard(g)]),
          ),
        ]),
      ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onTap, {Color color = const Color(0xFFEA580C)}) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: on ? color : Colors.transparent,
            foregroundColor: on ? Colors.white : const Color(0xFFD1D5DB),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  Widget _topBar() {
    final s = _stats;
    final longest = tNum(s?['longestWaitMinutes']);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(color: Color(0xFF1F2937), border: Border(bottom: BorderSide(color: Color(0xFF374151)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.soup_kitchen_outlined, size: 24, color: Color(0xFFF97316)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Kitchen Display', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white))),
          IconButton(
            tooltip: _soundOn ? 'Sound on' : 'Sound off',
            onPressed: () => setState(() => _soundOn = !_soundOn),
            icon: Icon(_soundOn ? Icons.volume_up_outlined : Icons.volume_off_outlined, size: 18, color: const Color(0xFF9CA3AF)),
          ),
          IconButton(
            tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
            onPressed: _toggleFullscreen,
            icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 18, color: const Color(0xFF9CA3AF)),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent, foregroundColor: const Color(0xFFF3F4F6), side: const BorderSide(color: Color(0xFF4B5563))),
            onPressed: _exit,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Exit'),
          ),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _tab('All', _station == null && !_expo, () => _pick(null, false)),
            for (final st in _stations)
              _tab(tStr(st['name']), _station == tNum(st['kdsStationId']).toInt(), () => _pick(tNum(st['kdsStationId']).toInt(), st['isExpo'] == true),
                  color: _hex(tStr(st['displayColor']), const Color(0xFF374151))),
            _tab('Expo', _expo && _station == null, () => _pick(null, true), color: const Color(0xFF9333EA)),
          ]),
        ),
        if (s != null) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 2, children: [
            Text('Pending: ${tNum(s['pendingCount']).toInt()}', style: const TextStyle(fontSize: 12, color: Color(0xFF60A5FA))),
            Text('Preparing: ${tNum(s['preparingCount']).toInt()}', style: const TextStyle(fontSize: 12, color: Color(0xFFFACC15))),
            Text('Ready: ${tNum(s['readyCount']).toInt()}', style: const TextStyle(fontSize: 12, color: Color(0xFF4ADE80))),
            if (s['avgPrepMinutes'] != null)
              Text('Avg: ${tNum(s['avgPrepMinutes']).toStringAsFixed(1)}m', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            if (longest > 0)
              Text('Max: ${kdsTime(longest)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: longest > 15 ? const Color(0xFFF87171) : const Color(0xFF9CA3AF),
                      fontWeight: longest > 15 ? FontWeight.w700 : null)),
          ]),
        ],
      ]),
    );
  }

  Widget _orderCard(List<Map> items) {
    final first = items.first;
    final maxElapsed = items.map((i) => tNum(i['elapsedMinutes'])).fold<num>(0, (a, b) => a > b ? a : b);
    final allReady = items.every((i) => tStr(i['status']) == 'Ready');
    final (border, bg) = kdsTiming(maxElapsed);
    final timeColor = maxElapsed > 15
        ? const Color(0xFFF87171)
        : maxElapsed > 10
            ? const Color(0xFFFACC15)
            : const Color(0xFF4ADE80);
    Widget chip(String t) => Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4B5563)), borderRadius: BorderRadius.circular(999)),
          child: Text(t, style: const TextStyle(fontSize: 10, color: Color(0xFFD1D5DB))),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: const Color(0xE61F2937),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tStr(first['orderNumber']), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                Row(children: [
                  chip(tStr(first['orderType'])),
                  if (tStr(first['tableNumber']).isNotEmpty) chip('T${tStr(first['tableNumber'])}'),
                ]),
              ]),
            ),
            const Icon(Icons.schedule, size: 12, color: Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(kdsTime(maxElapsed),
                style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: timeColor, fontWeight: maxElapsed > 15 ? FontWeight.w700 : null)),
          ]),
        ),
        for (final (n, i) in items.indexed)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(border: n == 0 ? null : const Border(top: BorderSide(color: Color(0x4DD1D5DB)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tNum(i['quantity']).toInt()}x ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      TextSpan(text: tStr(i['itemName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                    ]),
                    style: const TextStyle(color: Color(0xFF111827)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tStr(i['modifiers']).isNotEmpty) Text(tStr(i['modifiers']), style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
                  if (tStr(i['notes']).isNotEmpty)
                    Text('* ${tStr(i['notes'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFB91C1C))),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: switch (tStr(i['status'])) {
                        'Pending' => const Color(0xFF3B82F6),
                        'Preparing' => const Color(0xFFCA8A04),
                        _ => const Color(0xFF16A34A),
                      },
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(tStr(i['status']), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D), visualDensity: VisualDensity.compact),
                  onPressed: () => _act('/api/Restaurant/kds/bump/${i['orderItemId']}', 'Item bumped to', 'Bump failed'),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Bump'),
                ),
                if (tStr(i['status']) != 'Pending')
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF4B5563), visualDensity: VisualDensity.compact),
                    onPressed: () => _act('/api/Restaurant/kds/recall/${i['orderItemId']}', 'Item recalled to', 'Recall failed'),
                    icon: const Icon(Icons.replay, size: 13),
                    label: const Text('Recall', style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ]),
          ),
        if (items.length > 1)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x4DD1D5DB)))),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: allReady ? const Color(0xFF15803D) : const Color(0xFF374151)),
              onPressed: () => _act('/api/Restaurant/kds/bump-order/${first['orderId']}', 'Order bumped', 'Bump failed', newStatus: false),
              icon: const Icon(Icons.notifications_none, size: 14),
              label: Text(allReady ? 'Complete Order' : 'Bump All'),
            ),
          ),
      ]),
    );
  }
}
