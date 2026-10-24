// Restaurant → Delivery & Online → Online Settings, as
// `app/restaurant-online-orders/page.tsx`: the Accepting Orders switch, and the
// Settings, QR Codes and Promo Codes tabs, with the promo dialog.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtDateTime, fmtInstant;
import '../shared/company_clock.dart';
import 'restaurant_money_kit.dart' show rField, rNumberInput, rDialog, rConfirm, rCancel;
import 'restaurant_qr.dart';
import 'restaurant_widgets.dart';

/// The page's starting settings, before the saved ones are read.
const onlineSettingsDefaults = <String, Object?>{
  'isEnabled': false,
  'allowDineInQr': true,
  'allowTakeaway': true,
  'allowDelivery': true,
  'minOrderAmount': 0,
  'maxOrdersPerSlot': 0,
  'slotDurationMins': 30,
  'estimatedPrepMinsDine': 15,
  'estimatedPrepMinsTake': 20,
  'estimatedPrepminsDeliv': 30,
  'deliveryFeeType': 'Fixed',
  'deliveryFeeAmount': 0,
  'maxDeliveryDistanceKm': 10,
  'acceptingOrders': true,
};

const _feeTypes = [('Fixed', 'Fixed'), ('DistanceBased', 'Distance Based'), ('Free', 'Free')];
const _promoTypes = [('Percentage', 'Percentage'), ('FixedAmount', 'Fixed Amount'), ('FreeDelivery', 'Free Delivery')];
const _channels = [('all', 'All Channels'), ('Online', 'Online Only'), ('QR', 'QR Only'), ('Delivery', 'Delivery Only')];

/// parseFloat(v) || fallback.
num _float(String v, num fallback) {
  final n = double.tryParse(v.trim());
  return n == null || n == 0 || n.isNaN ? fallback : (n == n.roundToDouble() ? n.toInt() : n);
}

/// parseInt(v) || fallback.
int _int(String v, int fallback) {
  final m = RegExp(r'^\s*(-?\d+)').firstMatch(v);
  final n = m == null ? null : int.tryParse(m.group(1)!);
  return n == null || n == 0 ? fallback : n;
}

String _numText(Object? v) {
  final n = tNum(v);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// The promo's value badge: "10%", "Free Delivery" or "5.00".
String promoValueLabel(Map p) => switch (tStr(p['discountType'])) {
      'Percentage' => '${_numText(p['discountValue'])}%',
      'FreeDelivery' => 'Free Delivery',
      _ => tNum(p['discountValue']).toStringAsFixed(2),
    };

class RestaurantOnlineSettingsScreen extends StatefulWidget {
  const RestaurantOnlineSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantOnlineSettingsScreen> createState() => _RestaurantOnlineSettingsScreenState();
}

class _RestaurantOnlineSettingsScreenState extends State<RestaurantOnlineSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String _tab = 'settings';
  final Map<String, Object?> _s = {...onlineSettingsDefaults};
  List<Map> _qr = [];
  List<Map> _promos = [];
  String? _profileName;
  Duration _offset = Duration.zero;

  final _minOrder = TextEditingController();
  final _maxSlot = TextEditingController();
  final _slotMins = TextEditingController();
  final _prepDine = TextEditingController();
  final _prepTake = TextEditingController();
  final _prepDeliv = TextEditingController();
  final _fee = TextEditingController();
  final _freeAbove = TextEditingController();
  final _welcome = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    for (final c in [_minOrder, _maxSlot, _slotMins, _prepDine, _prepTake, _prepDeliv, _fee, _freeAbove, _welcome]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];

  Future<void> _load() async {
    Future<Object?> safe(Future<Object?> f, Object? fallback) => f.catchError((Object _) => fallback);
    final r = await Future.wait([
      safe(_api.get('/api/Restaurant/online/settings', query: _q), null),
      safe(_api.get('/api/Restaurant/online/qr-codes', query: _q), const []),
      safe(_api.get('/api/Restaurant/online/promo-codes', query: _q), const []),
      // Only used to title the printed card, so never let it fail the page.
      safe(_api.get('/api/Restaurant/setup/profile', query: _q), null),
    ]);
    if (r[0] is Map) _s.addAll({for (final e in (r[0] as Map).entries) '${e.key}': e.value});
    _qr = _rows(r[1]);
    _promos = _rows(r[2]);
    final prof = r[3];
    _profileName = prof is Map && tStr(prof['restaurantName']).isNotEmpty ? tStr(prof['restaurantName']) : null;
    _fillBoxes();
    if (mounted) setState(() => _loading = false);
  }

  /// The boxes show `value || default`, as the web's inputs do.
  void _fillBoxes() {
    String or(Object? v, Object fallback) => tNum(v) == 0 ? _numText(fallback) : _numText(v);
    _minOrder.text = or(_s['minOrderAmount'], 0);
    _maxSlot.text = or(_s['maxOrdersPerSlot'], 0);
    _slotMins.text = or(_s['slotDurationMins'], 30);
    _prepDine.text = or(_s['estimatedPrepMinsDine'], 15);
    _prepTake.text = or(_s['estimatedPrepMinsTake'], 20);
    _prepDeliv.text = or(_s['estimatedPrepminsDeliv'], 30);
    _fee.text = or(_s['deliveryFeeAmount'], 0);
    _freeAbove.text = tNum(_s['freeDeliveryAbove']) == 0 ? '' : _numText(_s['freeDeliveryAbove']);
    _welcome.text = tStr(_s['welcomeMessage']);
  }

  void _readBoxes() {
    _s['minOrderAmount'] = _float(_minOrder.text, 0);
    _s['maxOrdersPerSlot'] = _int(_maxSlot.text, 0);
    _s['slotDurationMins'] = _int(_slotMins.text, 30);
    _s['estimatedPrepMinsDine'] = _int(_prepDine.text, 15);
    _s['estimatedPrepMinsTake'] = _int(_prepTake.text, 20);
    _s['estimatedPrepminsDeliv'] = _int(_prepDeliv.text, 30);
    _s['deliveryFeeAmount'] = _float(_fee.text, 0);
    final free = double.tryParse(_freeAbove.text.trim());
    _s['freeDeliveryAbove'] = free == null || free == 0 ? null : _float(_freeAbove.text, 0);
    _s['welcomeMessage'] = _welcome.text;
  }

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _saveSettings() async {
    _readBoxes();
    setState(() => _saving = true);
    try {
      await _api.post('/api/Restaurant/online/settings', body: {..._s, 'farmId': _farmId});
      _toast('Settings saved');
    } catch (e) {
      _toast('Save failed', description: _err(e), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggleAccepting() async {
    final next = _s['acceptingOrders'] != true;
    try {
      await _api.patch('/api/Restaurant/online/settings/toggle',
          query: _q, body: {'accepting': next, if (!next) 'reason': 'Paused by staff'});
      setState(() => _s['acceptingOrders'] = next);
      _toast(next ? 'Now accepting orders' : 'Orders paused');
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _reloadQr() async => _qr = _rows(await _api.get('/api/Restaurant/online/qr-codes', query: _q));
  Future<void> _reloadPromos() async => _promos = _rows(await _api.get('/api/Restaurant/online/promo-codes', query: _q));

  Future<void> _genRestaurantQr() async {
    try {
      await _api.post('/api/Restaurant/online/qr-codes', query: _q, body: {'codeType': 'Restaurant', 'tableId': null, 'tableNumber': null});
      _toast('Restaurant QR code ready', description: 'Print it and put it where the queue forms.');
      await _reloadQr();
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _delQr(Map q) async {
    try {
      await _api.delete('/api/Restaurant/online/qr-codes/${q['qrCodeId']}', query: _q);
      await _reloadQr();
      if (mounted) setState(() {});
      _toast('QR deleted');
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _copyLink(Map q) async {
    await Clipboard.setData(ClipboardData(text: buildQrOrderUrl(tStr(q['qrToken']), tStr(_s['publicBaseUrl']))));
    _toast('Ordering link copied');
  }

  Future<void> _png(Map q) async {
    try {
      await shareQrPng(q, tStr(_s['publicBaseUrl']));
      _toast('Saved table ${tStr(q['tableNumber'])} QR');
    } catch (e) {
      _toast('Download failed', description: '$e', error: true);
    }
  }

  Future<void> _print({int? only}) async {
    try {
      final n = await shareQrCards(_qr, only: only, restaurantName: _profileName, publicBaseUrl: tStr(_s['publicBaseUrl']));
      if (n == 0) _toast('No active QR codes yet. Generate them under Online Settings → QR Codes.');
    } catch (e) {
      _toast('Could not load the QR codes.', description: '$e', error: true);
    }
  }

  Future<void> _openPromo([Map? p]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _PromoDialog(api: _api, farmId: _farmId, editing: p));
    if (saved == true) {
      await _reloadPromos();
      if (mounted) setState(() {});
    }
  }

  Future<void> _delPromo(Map p) async {
    try {
      await _api.delete('/api/Restaurant/online/promo-codes/${p['promoCodeId']}', query: _q);
      await _reloadPromos();
      if (mounted) setState(() {});
      _toast('Deleted');
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-online-orders');
    final accepting = _s['acceptingOrders'] == true;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Online Ordering')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
              RPageHeader(
                icon: Icons.public,
                title: 'Online Ordering',
                subtitle: 'QR codes, promo codes and delivery settings',
                actions: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: accepting ? const Color(0xFF0F172A) : const Color(0xFFDC2626), minimumSize: const Size.fromHeight(44)),
                    onPressed: _toggleAccepting,
                    icon: Icon(accepting ? Icons.power_settings_new : Icons.power_off_outlined, size: 18),
                    label: Text(accepting ? 'Accepting Orders' : 'Orders Paused'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RTabs(
                value: _tab,
                onChanged: (v) => setState(() => _tab = v),
                tabs: [
                  ('settings', Icons.settings_outlined, 'Settings', null),
                  ('qr', Icons.qr_code_2, 'QR Codes (${_qr.length})', null),
                  ('promos', Icons.sell_outlined, 'Promo Codes (${_promos.length})', null),
                ],
              ),
              const SizedBox(height: 14),
              switch (_tab) {
                'qr' => _qrTab(),
                'promos' => _promoTab(),
                _ => _settingsTab(),
              },
            ]),
    );
  }

  Widget _settingsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Online Ordering Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final (key, label) in const [
            ('isEnabled', 'Enable Online Ordering'),
            ('allowDineInQr', 'Allow QR Table Ordering'),
            ('allowTakeaway', 'Allow Takeaway'),
            ('allowDelivery', 'Allow Delivery'),
          ])
            AppCheckbox(value: _s[key] == true, onChanged: (v) => setState(() => _s[key] = v), label: label),
          const SizedBox(height: 8),
          twoColumns([
            rField('Min Order Amount', rNumberInput(_minOrder)),
            rField('Max Orders/Slot (0=unlimited)', rNumberInput(_maxSlot)),
            rField('Slot Duration (mins)', rNumberInput(_slotMins)),
            rField('Est. Prep Dine-In (mins)', rNumberInput(_prepDine)),
            rField('Est. Prep Takeaway (mins)', rNumberInput(_prepTake)),
            rField('Est. Prep Delivery (mins)', rNumberInput(_prepDeliv)),
          ], gap: 12),
          const SizedBox(height: 12),
          rField(
            'Delivery Fee Type',
            AppSelect<String>(
              value: tStr(_s['deliveryFeeType']).isEmpty ? 'Fixed' : tStr(_s['deliveryFeeType']),
              items: [for (final (v, l) in _feeTypes) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _s['deliveryFeeType'] = v ?? 'Fixed'),
            ),
          ),
          const SizedBox(height: 12),
          twoColumns([
            rField('Delivery Fee', rNumberInput(_fee)),
            rField('Free Delivery Above', rNumberInput(_freeAbove)),
          ], gap: 12),
          const SizedBox(height: 12),
          rField('Welcome Message', AppInput(controller: _welcome, maxLines: 3, minLines: 2)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A), minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const SizedBox.shrink(),
            label: const Text('Save Settings'),
          ),
        ]),
      );

  Widget _qrTab() {
    final hasVenue = _qr.any((q) => tStr(q['codeType']) == 'Restaurant');
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.qr_code_2, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Restaurant QR Code', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          if (_qr.isNotEmpty)
            OutlinedButton.icon(onPressed: () => _print(), icon: const Icon(Icons.print_outlined, size: 16), label: const Text('Print')),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x80FFF1F2),
            border: Border.all(color: const Color(0xFFFECDD3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Restaurant QR code', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            const SizedBox(height: 2),
            const Text(
              'One code for the whole restaurant. Put it where the queue forms — a guest scans it, sees your full menu, '
              'orders on their phone and skips the line. This is the one most restaurants want.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            hasVenue
                ? rBadge('Created')
                : FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                    onPressed: _genRestaurantQr,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create it'),
                  ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_qr.isEmpty)
          const Text('No QR codes generated yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
        else
          for (final q in _qr) ...[_qrTile(q), const SizedBox(height: 12)],
      ]),
    );
  }

  Widget _qrTile(Map q) {
    final active = q['isActive'] != false;
    final scans = tNum(q['scanCount']).toInt();
    final last = tStr(q['lastScannedAt']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        QrTableCardView(
          token: tStr(q['qrToken']),
          tableNumber: tStr(q['tableNumber']),
          codeType: tStr(q['codeType']).isEmpty ? 'Table' : tStr(q['codeType']),
          restaurantName: _profileName,
          publicBaseUrl: tStr(_s['publicBaseUrl']),
          faded: !active,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (tStr(q['codeType']) == 'Restaurant') rBadge('Whole restaurant', bg: const Color(0xFFE11D48), fg: Colors.white),
          active ? rBadge('Active', bg: const Color(0xFF0F172A), fg: Colors.white) : rBadge('Inactive'),
          Text('$scans scan${scans == 1 ? '' : 's'}${last.isEmpty ? '' : ' · last ${fmtInstant(last, _offset)}'}',
              style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          OutlinedButton.icon(onPressed: () => _copyLink(q), icon: const Icon(Icons.copy, size: 15), label: const Text('Copy link')),
          OutlinedButton.icon(onPressed: () => _png(q), icon: const Icon(Icons.download, size: 15), label: const Text('PNG')),
          OutlinedButton.icon(
              onPressed: () => _print(only: tNum(q['qrCodeId']).toInt()), icon: const Icon(Icons.print_outlined, size: 15), label: const Text('Print')),
          IconButton(tooltip: 'Delete QR', onPressed: () => _delQr(q), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
        ]),
      ]),
    );
  }

  Widget _promoTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.sell_outlined, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Promo Codes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () => _openPromo(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Promo'),
            ),
          ]),
          const SizedBox(height: 12),
          if (_promos.isEmpty)
            const Text('No promo codes. Create codes for discounts and promotions.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final p in _promos) ...[_promoRow(p), const SizedBox(height: 8)],
        ]),
      );

  Widget _promoRow(Map p) {
    final maxUses = tNum(p['maxUses']).toInt();
    final meta = [
      '${tStr(p['description'])} | Uses: ${tNum(p['currentUses']).toInt()}/${maxUses == 0 ? '∞' : maxUses}',
      if (tStr(p['channelRestriction']).isNotEmpty) ' | ${tStr(p['channelRestriction'])} only',
      if (tStr(p['validUntil']).isNotEmpty) ' | Expires: ${fmtDateTime(p['validUntil'], null, _offset)}',
    ].join();
    final active = p['isActive'] != false;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tStr(p['code']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              rBadge(promoValueLabel(p), bg: Colors.white, border: TColors.slate200),
            ]),
            const SizedBox(height: 2),
            Text(meta, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
        active ? rBadge('Active', bg: const Color(0xFF0F172A), fg: Colors.white) : rBadge('Inactive'),
        IconButton(tooltip: 'Edit promo', onPressed: () => _openPromo(p), icon: const Icon(Icons.edit_outlined, size: 18)),
        IconButton(tooltip: 'Delete promo', onPressed: () => _delPromo(p), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
      ]),
    );
  }
}

/// "YYYY-MM-DDTHH:mm" or empty: the web's datetime-local box.
class RDateTimeBox extends StatelessWidget {
  const RDateTimeBox({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.length >= 16 ? value.substring(0, 16) : value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final now = DateTime.now();
        final cur = DateTime.tryParse(v);
        final d = await showDatePicker(context: context, initialDate: cur ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
        if (d == null || !context.mounted) return;
        final t = await showTimePicker(context: context, initialTime: cur == null ? const TimeOfDay(hour: 0, minute: 0) : TimeOfDay.fromDateTime(cur));
        if (t == null) return;
        String two(int n) => n.toString().padLeft(2, '0');
        onChanged('${d.year}-${two(d.month)}-${two(d.day)}T${two(t.hour)}:${two(t.minute)}');
      },
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: v.isEmpty
              ? const Icon(Icons.event, size: 18)
              : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close, size: 16), onPressed: () => onChanged(null)),
        ),
        child: Text(v.isEmpty ? 'dd/mm/yyyy, --:--' : v.replaceFirst('T', ' '),
            style: TextStyle(fontSize: 14, color: v.isEmpty ? TColors.slate400 : TColors.slate900)),
      ),
    );
  }
}

/// New / Edit Promo Code.
class _PromoDialog extends StatefulWidget {
  const _PromoDialog({required this.api, required this.farmId, this.editing});
  final ApiClient api;
  final String farmId;
  final Map? editing;

  @override
  State<_PromoDialog> createState() => _PromoDialogState();
}

class _PromoDialogState extends State<_PromoDialog> {
  late final Map<String, Object?> _f;
  late final TextEditingController _code;
  late final TextEditingController _desc;
  late final TextEditingController _value;
  late final TextEditingController _min;
  late final TextEditingController _uses;

  @override
  void initState() {
    super.initState();
    final p = widget.editing;
    if (p != null) {
      _f = {
        for (final k in const ['code', 'description', 'discountType', 'discountValue', 'minOrderAmount', 'maxDiscountAmount', 'maxUses',
          'validFrom', 'validUntil', 'isActive', 'channelRestriction'])
          k: p[k],
      };
    } else {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final r = Random();
      _f = {'code': 'PROMO-${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}', 'discountValue': 10, 'discountType': 'Percentage', 'isActive': true};
    }
    _code = TextEditingController(text: tStr(_f['code']));
    _desc = TextEditingController(text: tStr(_f['description']));
    _value = TextEditingController(text: _numText(_f['discountValue']));
    _min = TextEditingController(text: _numText(_f['minOrderAmount']));
    _uses = TextEditingController(text: _numText(_f['maxUses']));
  }

  @override
  void dispose() {
    for (final c in [_code, _desc, _value, _min, _uses]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.toUpperCase();
    if (code.trim().isEmpty) {
      trackerToast(context, 'Code required', error: true);
      return;
    }
    final body = {
      ..._f,
      'code': code,
      'description': _desc.text,
      'discountValue': _float(_value.text, 0),
      'minOrderAmount': _float(_min.text, 0),
      'maxUses': _int(_uses.text, 0),
      'farmId': widget.farmId,
    };
    final editing = widget.editing;
    try {
      if (editing != null) {
        await widget.api.put('/api/Restaurant/online/promo-codes/${editing['promoCodeId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/online/promo-codes', body: body);
      }
      if (!mounted) return;
      trackerToast(context, editing != null ? 'Promo updated' : 'Promo created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return rDialog(
      title: editing ? 'Edit Promo Code' : 'New Promo Code',
      children: [
        rField('Code', AppInput(controller: _code, hintText: 'e.g. SAVE20', onChanged: (v) {
          final up = v.toUpperCase();
          if (up != v) _code.value = _code.value.copyWith(text: up);
        }), required: true),
        rField(
          'Type',
          AppSelect<String>(
            value: tStr(_f['discountType']).isEmpty ? 'Percentage' : tStr(_f['discountType']),
            items: [for (final (v, l) in _promoTypes) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _f['discountType'] = v),
          ),
        ),
        rField('Description', AppInput(controller: _desc)),
        twoColumns([
          rField('Value', rNumberInput(_value)),
          rField('Min Order', rNumberInput(_min)),
          rField('Max Uses (0=∞)', rNumberInput(_uses)),
        ], gap: 10),
        rField('Valid From', RDateTimeBox(value: tStr(_f['validFrom']), onChanged: (v) => setState(() => _f['validFrom'] = v))),
        rField('Valid Until', RDateTimeBox(value: tStr(_f['validUntil']), onChanged: (v) => setState(() => _f['validUntil'] = v))),
        rField(
          'Channel Restriction',
          AppSelect<String>(
            value: tStr(_f['channelRestriction']).isEmpty ? 'all' : tStr(_f['channelRestriction']),
            items: [for (final (v, l) in _channels) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _f['channelRestriction'] = v == 'all' ? null : v),
          ),
        ),
      ],
      actions: [rCancel(context, 'Cancel'), rConfirm(editing ? 'Update' : 'Create', _save)],
    );
  }
}
