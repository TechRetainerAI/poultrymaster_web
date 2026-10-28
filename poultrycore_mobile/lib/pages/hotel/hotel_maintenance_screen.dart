// Hotel → Setup → Facilities → Maintenance, as `app/hotel-maintenance/page.tsx`:
// the "N open" badge, New Request, the status filter buttons with their counts,
// a card per request (room, asset, issue, priority, status, estimated cost,
// reported date) with its Change status picker, and the New Maintenance
// Request dialog (room, asset / area as a HotelOtherSelect, issue, priority,
// estimated cost).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';
import 'hotel_other_select.dart';

const hotelMaintenanceStatuses = ['Open', 'Assigned', 'InProgress', 'Completed', 'Cancelled'];
const _priorities = ['Low', 'Normal', 'High', 'Critical'];

(Color, Color) _priorityColors(String p) => switch (p) {
  'Low' => (TColors.slate100, TColors.slate700),
  'Normal' => (TColors.blue100, const Color(0xFF1D4ED8)),
  'High' => (TColors.amber100, TColors.amber700),
  'Critical' => (TColors.red100, TColors.red700),
  _ => (Colors.white, TColors.slate600),
};

(Color, Color) _statusColors(String s) => switch (s) {
  'Open' => (TColors.blue100, const Color(0xFF1D4ED8)),
  'Assigned' => (TColors.amber100, TColors.amber700),
  'InProgress' => (TColors.violet100, TColors.violet700),
  'Completed' => (TColors.emerald100, TColors.emerald700),
  'Cancelled' => (TColors.slate100, TColors.slate700),
  _ => (Colors.white, TColors.slate600),
};

class HotelMaintenanceScreen extends StatefulWidget {
  const HotelMaintenanceScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelMaintenanceScreen> createState() => _HotelMaintenanceScreenState();
}

class _HotelMaintenanceScreenState extends State<HotelMaintenanceScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [], _rooms = [], _assets = [];
  String _status = 'all';

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/maintenance', query: _q),
        _api.get('/api/Hotel/rooms', query: _q),
        _api.get('/api/Hotel/setup/maintenance-assets', query: _q).catchError((_) => const []),
      ]);
      _items = hotelAlias(hotelRows(r[0]), [
        'hotelMaintenanceRequestId',
        'roomNumber',
        'assetDescription',
        'issueDescription',
        'estimatedCost',
        'reportedAt',
        'createdAt',
      ]);
      _rooms = hotelRows(r[1]);
      _assets = hotelRows(r[2]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _changeStatus(Map<String, dynamic> m, String status) async {
    try {
      await _api.patch('/api/Hotel/maintenance/${m['hotelMaintenanceRequestId']}/status', query: _q, body: {'status': status});
      if (mounted) trackerToast(context, 'Status → $status');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _openNew() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RequestDialog(
        session: widget.session,
        company: widget.company,
        rooms: _rooms,
        assets: [for (final a in _assets) tStr(a['description'])],
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-maintenance');
    final open = _items.where((m) => const {'Open', 'Assigned', 'InProgress'}.contains(tStr(m['status']))).length;
    final rows = [
      for (final m in _items)
        if (_status == 'all' || tStr(m['status']) == _status) m,
    ];
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Maintenance')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.build_outlined, size: 24, color: hotelViolet),
                const Text(
                  'Maintenance',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900),
                ),
                if (open > 0) hotelBadge('$open open', TColors.red100, TColors.red700),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46))),
              onPressed: _openNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Request'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in ['all', ...hotelMaintenanceStatuses])
                  _chip(
                    s == 'all' ? 'All (${_items.length})' : '$s (${_items.where((m) => tStr(m['status']) == s).length})',
                    _status == s,
                    () => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else ...[
              if (rows.isEmpty) hotelEmpty('No maintenance requests.', icon: Icons.build_outlined),
              for (final m in rows) ...[_row(m), const SizedBox(height: 8)],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => on
      ? FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: hotelViolet,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        )
      : OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        );

  Widget _row(Map<String, dynamic> m) {
    final status = tStr(m['status']), priority = tStr(m['priority']);
    final (pbg, pfg) = _priorityColors(priority);
    final (sbg, sfg) = _statusColors(status);
    final reported = tStr(m['reportedAt']).isNotEmpty ? tStr(m['reportedAt']) : tStr(m['createdAt']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  tStr(m['roomNumber']).isEmpty ? 'General' : tStr(m['roomNumber']),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tStr(m['assetDescription']),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900),
                ),
              ),
              Text(
                tNum(m['estimatedCost']).toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tStr(m['issueDescription']), style: const TextStyle(fontSize: 13.5, color: TColors.slate700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              hotelBadge(priority, pbg, pfg),
              hotelBadge(status, sbg, sfg),
              if (reported.isNotEmpty)
                Text(
                  reported.length >= 10 ? reported.substring(0, 10) : reported,
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // The status picker: every status but the current one.
          AppSelect<String>(
            value: null,
            hintText: 'Change...',
            items: [
              for (final s in hotelMaintenanceStatuses)
                if (s != status) AppSelectItem(value: s, label: s),
            ],
            onChanged: (v) {
              if (v != null && tIntOrNull(m['hotelMaintenanceRequestId']) != null) _changeStatus(m, v);
            },
          ),
        ],
      ),
    );
  }
}

/// "New Maintenance Request". Pops true once created.
class _RequestDialog extends StatefulWidget {
  const _RequestDialog({required this.session, required this.company, required this.rooms, required this.assets});
  final Session session;
  final Company company;
  final List<Map<String, dynamic>> rooms;
  final List<String> assets;
  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _assetOther = GlobalKey<HotelOtherSelectState>();
  int _room = 0; // 0 = General / Common Area
  String _asset = '', _priority = 'Normal';
  final _issue = TextEditingController();
  final _cost = TextEditingController(text: '0');
  bool _saving = false;

  Future<void> _save() async {
    if (_issue.text.trim().isEmpty) return trackerToast(context, 'Issue description required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Hotel/maintenance',
        body: {
          if (_room != 0) 'hotelRoomId': _room,
          'assetDescription': _asset,
          'issueDescription': _issue.text,
          'priority': _priority,
          'estimatedCost': double.tryParse(_cost.text) ?? 0,
          'farmId': widget.company.farmId,
        },
      );
      // Before closing: closing drops the field that holds what was typed.
      await _assetOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Request created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.build_outlined,
    title: 'New Maintenance Request',
    saveLabel: 'Submit Request',
    saving: _saving,
    onSave: _save,
    children: [
      FilterLabel(
        'Room (optional)',
        AppSelect<int>(
          value: _room,
          items: [
            const AppSelectItem(value: 0, label: 'General / Common Area'),
            for (final r in widget.rooms)
              AppSelectItem(
                value: tIntOrNull(r['hotelRoomId']) ?? 0,
                label: 'Room ${tStr(r['roomNumber'])} — ${tStr(r['floorName'])} (${tStr(r['roomTypeName'])})',
              ),
          ],
          onChanged: (v) => setState(() => _room = v ?? 0),
        ),
      ),
      FilterLabel(
        'Asset / Area *',
        HotelOtherSelect(
          key: _assetOther,
          session: widget.session,
          company: widget.company,
          listKey: 'MaintenanceAsset',
          baseOptions: widget.assets,
          value: _asset,
          onChanged: (v) => setState(() => _asset = v ?? ''),
          placeholder: 'Select asset/area',
          includeNone: true,
          noneLabel: 'Select asset/area',
          otherLabel: 'Other (type asset/area)',
        ),
      ),
      FilterLabel('Issue Description *', AppInput(controller: _issue, hintText: 'Describe the problem in detail')),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FilterLabel(
              'Priority',
              AppSelect<String>(
                value: _priority,
                items: [for (final p in _priorities) AppSelectItem(value: p, label: p)],
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterLabel(
              'Estimated Cost',
              AppInput(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
