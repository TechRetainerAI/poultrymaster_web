// Restaurant → Delivery & Online → QR / Customer Order, as
// `app/restaurant-order-online/page.tsx`: the page a guest lands on after
// scanning the restaurant's QR code. The rose hero, Takeaway / Delivery,
// search and categories, the menu cards with their steppers, the cart and
// "Your details" sheet, the order tracking card with its rating, and "My
// orders" kept on this device.
//
// The web reads ?qr=, ?farmId= / ?r= and ?track=. Opened from the app's menu
// there is no scanned code, so the screen is given the active company as
// farmId — the `?r=<farmId>` link the web page already supports. Guest
// details and past orders are kept under the web's own storage keys.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../shared/business_dates.dart' show fmtInstant;
import 'restaurant_widgets.dart' show restaurantImage;

const _rose600 = Color(0xFFE11D48);
const _rose700 = Color(0xFFBE123C);
const _rose50 = Color(0xFFFFF1F2);
const _rose200 = Color(0xFFFECDD3);
const _stone50 = Color(0xFFFAFAF9);
const _stone100 = Color(0xFFF5F5F4);
const _stone200 = Color(0xFFE7E5E4);
const _stone300 = Color(0xFFD6D3D1);
const _stone400 = Color(0xFFA8A29E);
const _stone500 = Color(0xFF78716C);
const _stone600 = Color(0xFF57534E);
const _stone700 = Color(0xFF44403C);
const _stone900 = Color(0xFF1C1917);
const _page = Color(0xFFFAF7F6);
const _amber50 = Color(0xFFFFFBEB);
const _amber200 = Color(0xFFFDE68A);
const _amber400 = Color(0xFFFBBF24);
const _amber600 = Color(0xFFD97706);
const _amber700 = Color(0xFFB45309);
const _amber900 = Color(0xFF78350F);
const _emerald50 = Color(0xFFECFDF5);
const _emerald600 = Color(0xFF059669);
const _emerald900 = Color(0xFF064E3B);

const _done = ['Completed', 'Cancelled', 'Refunded', 'Served'];

/* ── Formatting ─────────────────────────────────────────────────────────── */

/// makeMoney: a currency amount when the profile has a valid ISO code,
/// otherwise the plain number with two decimals.
String Function(num) makeMoney(String? currency) {
  final code = (currency ?? '').trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return (n) => n.toStringAsFixed(2);
  try {
    final f = NumberFormat.currency(name: code, symbol: NumberFormat.simpleCurrency(name: code).currencySymbol, decimalDigits: 2);
    return (n) => f.format(n);
  } catch (_) {
    return (n) => n.toStringAsFixed(2);
  }
}

/// openState: a hint only, from plain "HH:mm" hours; null when unparseable.
({bool open, String label})? openState(String? opening, String? closing, [DateTime? now]) {
  int? parse(String? s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch((s ?? '').trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  final from = parse(opening), to = parse(closing);
  if (from == null || to == null) return null;
  final t = now ?? DateTime.now();
  final mins = t.hour * 60 + t.minute;
  final open = from <= to ? mins >= from && mins < to : mins >= from || mins < to;
  return (open: open, label: '$opening–$closing');
}

String _localTime(Object? v, {bool seconds = true}) {
  final d = DateTime.tryParse(tStr(v));
  if (d == null) return '';
  return (seconds ? DateFormat.jms() : DateFormat.jm()).format(d.toLocal());
}

/* ── This device's guest details (lib/utils/guest-profile.ts) ─────────── */

class GuestStore {
  static const profileKey = 'pm.restaurant.guest.profile.v1';
  static const ordersKey = 'pm.restaurant.guest.orders.v1';
  static const maxOrdersPerFarm = 8;
  static const maxAgeDays = 30;

  static Future<Map<String, dynamic>> _json(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      final v = raw == null ? null : jsonDecode(raw);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(String key, Object value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(value));
    } catch (_) {}
  }

  static Future<Map<String, String>> loadProfile() async {
    final p = await _json(profileKey);
    return {for (final k in const ['name', 'phone', 'email', 'savedAt']) if (p[k] is String) k: p[k] as String};
  }

  static bool hasProfile(Map<String, String> p) =>
      (p['name'] ?? '').trim().isNotEmpty || (p['phone'] ?? '').trim().isNotEmpty || (p['email'] ?? '').trim().isNotEmpty;

  static Future<void> saveProfile(Map<String, String?> next) async {
    final merged = <String, String>{
      ...await loadProfile(),
      for (final e in next.entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _write(profileKey, merged);
  }

  static bool _fresh(Map o) {
    final t = DateTime.tryParse(tStr(o['placedAt']));
    return t != null && DateTime.now().difference(t) < const Duration(days: maxAgeDays);
  }

  static Future<List<Map>> loadOrders(String farmId) async {
    if (farmId.isEmpty) return [];
    final list = (await _json(ordersKey))[farmId];
    return [
      for (final o in (list is List ? list : const []))
        if (o is Map && o['trackingToken'] is String && o['orderNumber'] is String && _fresh(o)) o,
    ].take(maxOrdersPerFarm).toList();
  }

  static Future<void> rememberOrder(String farmId, Map order) async {
    if (farmId.isEmpty || tStr(order['trackingToken']).isEmpty) return;
    final all = await _json(ordersKey);
    final existing = all[farmId] is List ? all[farmId] as List : const [];
    all[farmId] = [
      order,
      for (final o in existing)
        if (o is Map && o['trackingToken'] != order['trackingToken']) o,
    ].where(_fresh).take(maxOrdersPerFarm).toList();
    await _write(ordersKey, all);
  }

  /// forgetGuest: the details and every restaurant's past orders.
  static Future<void> forget() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(profileKey);
      await p.remove(ordersKey);
    } catch (_) {}
  }
}

/* ── The page ───────────────────────────────────────────────────────────── */

class _CartLine {
  _CartLine(this.menuItemId, this.name, this.price);
  final int menuItemId;
  final String name;
  final num price;
  int quantity = 1;
  String notes = '';
}

class RestaurantOrderOnlineScreen extends StatefulWidget {
  const RestaurantOrderOnlineScreen({super.key, required this.session, this.company, this.qrToken, this.farmId, this.trackToken});
  final Session session;
  final Company? company;
  final String? qrToken;
  final String? farmId;
  final String? trackToken;

  @override
  State<RestaurantOrderOnlineScreen> createState() => _RestaurantOrderOnlineScreenState();
}

class _RestaurantOrderOnlineScreenState extends State<RestaurantOrderOnlineScreen> {
  bool _loading = true;
  String _farmId = '';
  int? _tableId;
  String _tableNumber = '';
  Map? _settings;
  Map? _profile;
  List<Map> _categories = [];
  List<Map> _items = [];
  int? _selectedCat;
  String _search = '';
  final List<_CartLine> _cart = [];
  String _orderType = '';
  bool _scrolled = false;
  final _scroll = ScrollController();
  final _searchBox = TextEditingController();
  final _searchFocus = FocusNode();

  bool _recalled = false;
  List<Map> _pastOrders = [];
  final Map<String, String> _pastStatuses = {};

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _promo = TextEditingController();
  final _payAmount = TextEditingController();
  Map? _promoResult;
  String _payIntent = 'Cash';

  String _step = 'cart';
  bool _placing = false;
  String? _orderError;

  Map? _tracking;
  String _trackingToken = '';

  Map? _fb;
  int _fbRating = 0, _fbFood = 0, _fbService = 0, _fbAmbience = 0;
  final _fbComment = TextEditingController();
  bool _fbSending = false;
  String? _fbError;
  bool _fbThanks = false;

  Timer? _trackTimer;
  Timer? _pastTimer;

  /// Repaints the open cart / history sheet when the page's state changes.
  final _sheetTick = ValueNotifier<int>(0);

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.hasClients && _scroll.offset > 72;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
    GuestStore.loadProfile().then((p) {
      if (!mounted || !GuestStore.hasProfile(p)) return;
      setState(() {
        _name.text = p['name'] ?? '';
        _phone.text = p['phone'] ?? '';
        _email.text = p['email'] ?? '';
        _recalled = true;
      });
    });
    _init();
  }

  @override
  void dispose() {
    _trackTimer?.cancel();
    _pastTimer?.cancel();
    for (final c in [_searchBox, _name, _phone, _email, _address, _promo, _payAmount, _fbComment]) {
      c.dispose();
    }
    _scroll.dispose();
    _searchFocus.dispose();
    _sheetTick.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _sheetTick.value++;
  }

  Map? _asMap(Object? v) => v is Map ? v : null;
  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];

  Future<void> _init() async {
    try {
      final track = widget.trackToken ?? '';
      if (track.isNotEmpty) {
        final t = _asMap(await _api.get('/api/Restaurant/public/track/$track'));
        _trackingToken = track;
        _tracking = t;
        _afterTrackingChange();
        _set(() => _loading = false);
        return;
      }
      var fId = widget.farmId ?? widget.company?.farmId ?? '';
      final qr = widget.qrToken ?? '';
      if (qr.isNotEmpty) {
        final q = _asMap(await _api.get('/api/Restaurant/public/qr/$qr')) ?? {};
        fId = tStr(q['farmId']);
        final venue = tStr(q['codeType']) == 'Restaurant' || q['tableId'] == null;
        _tableId = venue ? null : tNum(q['tableId']).toInt();
        _tableNumber = venue ? '' : tStr(q['tableNumber']);
        _orderType = venue ? 'Takeaway' : 'DineIn';
      }
      if (fId.isEmpty) {
        _set(() => _loading = false);
        return;
      }
      _farmId = fId;
      final r = await Future.wait<Object?>([
        _api.get('/api/Restaurant/public/$fId/settings'),
        _api.get('/api/Restaurant/public/$fId/categories'),
        _api.get('/api/Restaurant/public/$fId/menu'),
        // Newer than the rest of the public API; never a reason to deny lunch.
        _api.get('/api/Restaurant/public/$fId/profile').catchError((Object _) => null),
      ]);
      _settings = _asMap(r[0]);
      _categories = _rows(r[1]);
      _items = _rows(r[2]);
      _profile = _asMap(r[3]);
      if (qr.isEmpty && _settings != null) {
        if (_settings!['allowTakeaway'] == true) {
          _orderType = 'Takeaway';
        } else if (_settings!['allowDelivery'] == true) {
          _orderType = 'Delivery';
        }
      }
      _pastOrders = await GuestStore.loadOrders(_farmId);
      _refreshPastStatuses();
      _pastTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshPastStatuses());
    } catch (_) {
      // Falls through to "Restaurant not found", as the web does.
    }
    _set(() => _loading = false);
  }

  /// Only orders that can still change are asked about again.
  Future<void> _refreshPastStatuses() async {
    final open = [for (final o in _pastOrders) if (!_done.contains(_pastStatuses[tStr(o['trackingToken'])] ?? '')) o];
    if (open.isEmpty) return;
    final found = await Future.wait(open.map((o) async {
      try {
        final t = _asMap(await _api.get('/api/Restaurant/public/track/${tStr(o['trackingToken'])}'));
        return t == null ? null : MapEntry(tStr(o['trackingToken']), tStr(t['status']));
      } catch (_) {
        return null;
      }
    }));
    final hits = found.whereType<MapEntry<String, String>>();
    if (hits.isNotEmpty) _set(() => _pastStatuses.addEntries(hits));
  }

  /* ── Cart ── */

  int _qtyOf(int id) => _cart.where((c) => c.menuItemId == id).fold(0, (n, c) => n + c.quantity);

  void _add(Map item) => _set(() {
        final id = tNum(item['menuItemId']).toInt();
        final line = _cart.where((c) => c.menuItemId == id).firstOrNull;
        if (line != null) {
          line.quantity++;
        } else {
          _cart.add(_CartLine(id, tStr(item['name']), tNum(item['price'])));
        }
      });

  void _dec(int id) => _set(() {
        final line = _cart.where((c) => c.menuItemId == id).firstOrNull;
        if (line == null) return;
        if (line.quantity > 1) {
          line.quantity--;
        } else {
          _cart.remove(line);
        }
      });

  int get _cartCount => _cart.fold(0, (n, c) => n + c.quantity);
  num get _subtotal => _cart.fold<num>(0, (s, c) => s + c.price * c.quantity);
  num get _deliveryFee => _orderType == 'Delivery' ? tNum(_settings?['deliveryFeeAmount']) : 0;
  bool get _freeDelivery => tNum(_settings?['freeDeliveryAbove']) > 0 && _subtotal >= tNum(_settings?['freeDeliveryAbove']);
  num get _actualDeliveryFee => _freeDelivery ? 0 : _deliveryFee;
  num get _promoDiscount => _promoResult?['valid'] == true ? tNum(_promoResult?['calculatedDiscount']) : 0;
  num get _total => _subtotal + _actualDeliveryFee - _promoDiscount;
  bool get _belowMinimum => tNum(_settings?['minOrderAmount']) > 0 && _subtotal < tNum(_settings?['minOrderAmount']);
  String Function(num) get _money => makeMoney(tStr(_profile?['defaultCurrency']));
  bool get _isVenueCode => (widget.qrToken ?? '').isNotEmpty && _tableId == null;

  bool get _emailLooksWrong => _email.text.trim().isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());
  bool get _canSubmit =>
      _cart.isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty &&
      !_emailLooksWrong &&
      (_orderType != 'Delivery' || _address.text.trim().isNotEmpty);

  Future<void> _applyPromo() async {
    if (_promo.text.trim().isEmpty) return;
    try {
      final r = await _api.post('/api/Restaurant/public/$_farmId/validate-promo',
          body: {'code': _promo.text, 'orderAmount': _subtotal, 'channel': _orderType == 'DineIn' ? 'QR' : 'Online'});
      _set(() => _promoResult = _asMap(r));
    } catch (e) {
      _set(() => _promoResult = {'valid': false, 'message': e is ApiException ? e.message : '$e'});
    }
  }

  Future<void> _placeOrder(BuildContext sheet) async {
    if (_cart.isEmpty) return;
    _set(() {
      _orderError = null;
      _placing = true;
    });
    try {
      final email = _email.text.trim();
      final qr = widget.qrToken ?? '';
      final total = _total;
      final r = _asMap(await _api.post('/api/Restaurant/public/$_farmId/place-order', body: {
            if (qr.isNotEmpty) 'qrToken': qr,
            'orderType': _orderType,
            'tableId': ?_tableId,
            if (_tableNumber.isNotEmpty) 'tableNumber': _tableNumber,
            'customerName': _name.text.trim(),
            'customerPhone': _phone.text.trim(),
            if (email.isNotEmpty) 'customerEmail': email,
            'covers': 1,
            if (_orderType == 'Delivery') 'notes': 'Delivery: ${_address.text}',
            'onlineSource': qr.isNotEmpty ? 'QR' : 'Web',
            if (_orderType == 'Delivery') 'deliveryAddress': _address.text,
            'deliveryFee': _actualDeliveryFee,
            if (_promoResult?['valid'] == true) 'promoCode': _promo.text,
            'guestPaymentIntent': _payIntent,
            'guestPaymentAmount': _payAmount.text.trim().isEmpty ? total : (num.tryParse(_payAmount.text.trim()) ?? 0),
            // Only ids, quantities and notes: prices are read server-side.
            'items': [
              for (final c in _cart) {'menuItemId': c.menuItemId, 'quantity': c.quantity, if (c.notes.isNotEmpty) 'notes': c.notes},
            ],
          })) ??
          {};
      await GuestStore.saveProfile({'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': email.isEmpty ? null : email});
      await GuestStore.rememberOrder(_farmId, {
        'orderNumber': tStr(r['orderNumber']),
        'trackingToken': tStr(r['trackingToken']),
        'total': total,
        'orderType': _orderType,
        'placedAt': DateTime.now().toUtc().toIso8601String(),
      });
      _pastOrders = await GuestStore.loadOrders(_farmId);
      _refreshPastStatuses();
      final t = _asMap(await _api.get('/api/Restaurant/public/track/${tStr(r['trackingToken'])}'));
      if (sheet.mounted) Navigator.of(sheet).pop();
      _showTracking(t, tStr(r['trackingToken']));
      _set(() => _cart.clear());
    } catch (e) {
      _set(() => _orderError = e is ApiException && e.message.isNotEmpty
          ? e.message
          : 'We could not send your order. Please try again or ask a member of staff.');
    }
    _set(() => _placing = false);
  }

  /* ── Tracking ── */

  void _showTracking(Map? t, String token) {
    _set(() {
      _trackingToken = token;
      _tracking = t;
      _fbThanks = false;
    });
    _afterTrackingChange();
  }

  void _dismissTracking() {
    _trackTimer?.cancel();
    _set(() {
      _tracking = null;
      _trackingToken = '';
      _fb = null;
    });
  }

  /// Polls every 10 s until the order can no longer change, and re-asks
  /// whether it can be rated whenever its status moves.
  void _afterTrackingChange() {
    _trackTimer?.cancel();
    _loadFeedbackStatus();
    if (_trackingToken.isEmpty || (_tracking != null && _done.contains(tStr(_tracking!['status'])))) return;
    _trackTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final t = _asMap(await _api.get('/api/Restaurant/public/track/$_trackingToken'));
        final moved = tStr(t?['status']) != tStr(_tracking?['status']);
        _set(() => _tracking = t);
        if (moved) _afterTrackingChange();
      } catch (_) {}
    });
  }

  Future<void> _loadFeedbackStatus() async {
    if (_trackingToken.isEmpty) {
      _set(() => _fb = null);
      return;
    }
    try {
      final st = _asMap(await _api.get('/api/Restaurant/public/feedback/${Uri.encodeComponent(_trackingToken)}'));
      _set(() => _fb = st);
    } catch (_) {
      _set(() => _fb = null);
    }
  }

  Future<void> _sendFeedback() async {
    if (_trackingToken.isEmpty || _fbRating < 1) return;
    _set(() {
      _fbSending = true;
      _fbError = null;
    });
    final path = '/api/Restaurant/public/feedback/${Uri.encodeComponent(_trackingToken)}';
    try {
      await _api.post(path, body: {
        'rating': _fbRating,
        if (_fbFood > 0) 'foodRating': _fbFood,
        if (_fbService > 0) 'serviceRating': _fbService,
        if (_fbAmbience > 0) 'ambienceRating': _fbAmbience,
        if (_fbComment.text.trim().isNotEmpty) 'comment': _fbComment.text.trim(),
      });
      _fbThanks = true;
      Map? st;
      try {
        st = _asMap(await _api.get(path));
      } catch (_) {
        st = {'found': true, 'canRate': false, 'alreadyRated': true, 'rating': _fbRating};
      }
      _set(() => _fb = st);
    } catch (e) {
      _set(() => _fbError = e is ApiException && e.message.isNotEmpty ? e.message : 'We could not send your rating. Please try again.');
    }
    _set(() => _fbSending = false);
  }

  Future<void> _forget({bool closeSheet = false, BuildContext? sheet}) async {
    await GuestStore.forget();
    _set(() {
      _name.clear();
      _phone.clear();
      _email.clear();
      _pastOrders = [];
      _pastStatuses.clear();
      _recalled = false;
    });
    if (closeSheet && sheet != null && sheet.mounted) Navigator.of(sheet).pop();
  }

  /* ── Build ── */

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final lead = c == null ? null : sidebarLeading(context, widget.session, c, href: '/restaurant-order-online');
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator(color: _rose600));
    } else if (_tracking != null) {
      body = _trackingView();
    } else if (_farmId.isEmpty || _settings == null) {
      body = _shell([
        _stateIcon(Icons.search, tone: 'stone'),
        const Text('Restaurant not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _stone900)),
        const SizedBox(height: 8),
        const Text("That code didn't match a restaurant. Please scan the QR code again, or ask a member of staff for help.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: _stone500)),
      ]);
    } else if (_settings!['isEnabled'] != true || _settings!['acceptingOrders'] != true) {
      body = _closedView();
    } else {
      body = _menuView();
    }
    return Scaffold(
      backgroundColor: _page,
      appBar: lead == null ? null : AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('QR / Customer Order')),
      body: body,
    );
  }

  Widget _shell(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _stone200),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -12)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );

  Widget _stateIcon(IconData icon, {String tone = 'rose'}) {
    final (bg, fg) = switch (tone) {
      'amber' => (_amber50, _amber600),
      'stone' => (_stone100, _stone500),
      _ => (_rose50, _rose600),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, size: 28, color: fg),
    );
  }

  Widget _closedView() {
    final name = tStr(_profile?['restaurantName']);
    final hours = openState(tStr(_profile?['openingTime']), tStr(_profile?['closingTime']));
    if (_settings!['isEnabled'] != true) {
      return _shell([
        _stateIcon(Icons.storefront_outlined, tone: 'stone'),
        Text(name.isNotEmpty ? "$name isn't taking phone orders yet" : "This restaurant isn't taking phone orders yet",
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _stone900)),
        const SizedBox(height: 8),
        const Text('Please order at the counter.', style: TextStyle(fontSize: 14, color: _stone500)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: _stone50, borderRadius: BorderRadius.circular(12)),
          child: const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Staff: switch on '),
              TextSpan(text: 'Online Settings → Enable online ordering', style: TextStyle(fontWeight: FontWeight.w500, color: _stone600)),
              TextSpan(text: ' and save.'),
            ]),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _stone400),
          ),
        ),
      ]);
    }
    final reason = tStr(_settings!['pausedReason']);
    return _shell([
      _stateIcon(Icons.schedule, tone: 'amber'),
      const Text('Orders are paused right now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _stone900)),
      const SizedBox(height: 8),
      Text(reason.isNotEmpty ? reason : 'The kitchen has stopped taking new orders for the moment. Please ask a member of staff.',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _stone500)),
      if (hours != null) ...[
        const SizedBox(height: 16),
        Text('Usual hours ${hours.label}', style: const TextStyle(fontSize: 12, color: _stone400)),
      ],
    ]);
  }

  /* ── Tracking card ── */

  Widget _trackingView() {
    final t = _tracking!;
    const steps = ['Placed', 'Confirmed', 'Preparing', 'Ready'];
    final status = tStr(t['status']);
    final step = status == 'Served' || status == 'Completed' ? steps.length - 1 : steps.indexOf(status);
    final waiting = status == 'Placed';
    final rejected = status == 'Cancelled';
    final canReturn = _farmId.isNotEmpty && _settings != null;
    final name = tStr(_profile?['restaurantName']);
    Widget dl(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(k, style: const TextStyle(fontSize: 14, color: _stone500)),
            const Spacer(),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: _stone900))),
          ]),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 32), children: [
      if (canReturn)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _stone600, shape: const StadiumBorder()),
            onPressed: _dismissTracking,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Back to menu', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      const SizedBox(height: 12),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _stone200), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: rejected ? const [Color(0xFF57534E), Color(0xFF44403C)] : const [_rose600, _rose700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
                  child: Icon(rejected ? Icons.error_outline : Icons.check_circle_outline, size: 28, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text((rejected ? 'Not accepted' : waiting ? 'Order sent' : 'Your order').toUpperCase(),
                    style: const TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w500, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(tStr(t['orderNumber']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                if (name.isNotEmpty) Text(name, style: const TextStyle(fontSize: 14, color: Colors.white70)),
              ]),
            ),
            if (canReturn)
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Close and return to the menu',
                  onPressed: _dismissTracking,
                  icon: const Icon(Icons.close, size: 18, color: Colors.white),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (rejected)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _stone50, border: Border.all(color: _stone200), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('This order was not accepted', style: TextStyle(fontWeight: FontWeight.w600, color: _stone900)),
                    const SizedBox(height: 4),
                    Text(tStr(t['cancelReason']).isNotEmpty ? tStr(t['cancelReason']) : 'The restaurant could not take this order.',
                        style: const TextStyle(fontSize: 14, color: _stone600)),
                    const SizedBox(height: 8),
                    Text(
                        'Please speak to a member of staff${tStr(t['tableNumber']).isNotEmpty ? ' - you are at table ${tStr(t['tableNumber'])}' : ''}.',
                        style: const TextStyle(fontSize: 14, color: _stone600)),
                  ]),
                )
              else ...[
                if (waiting) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(16)),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _amber600)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Sent to the restaurant.', style: TextStyle(fontWeight: FontWeight.w600)),
                            TextSpan(text: ' A member of staff is confirming your order - it will start being prepared once they accept it.'),
                          ]),
                          style: TextStyle(fontSize: 14, color: _amber900),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (i, label) in steps.indexed) ...[
                    Column(children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: i <= step ? _rose600 : _stone100, shape: BoxShape.circle),
                        child: i <= step
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stone400)),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 56,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: i <= step ? _rose700 : _stone400)),
                        ),
                      ),
                    ]),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(top: 17),
                          height: 2,
                          color: i < step ? _rose600 : _stone200,
                        ),
                      ),
                  ],
                ]),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _stone50, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  dl('Type', '${tStr(t['orderType'])}${tStr(t['tableNumber']).isNotEmpty ? ' · Table ${tStr(t['tableNumber'])}' : ''}'),
                  dl('Total', _money(tNum(t['totalAmount'])), bold: true),
                  dl('Placed', _localTime(t['createdAt'])),
                  if (tStr(t['estimatedReadyTime']).isNotEmpty) dl('Est. ready', _localTime(t['estimatedReadyTime'])),
                ]),
              ),
              ?_feedbackCard(),
              const SizedBox(height: 16),
              const Text('This page updates automatically.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: _stone400)),
              if (canReturn) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _stone100,
                    foregroundColor: _stone700,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _dismissTracking,
                  icon: const Icon(Icons.restaurant, size: 16),
                  label: Text(rejected ? 'Back to the menu' : 'Order something else', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _stars(int value, ValueChanged<int> onPick, {bool big = true, required String label}) => Semantics(
        label: label,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var n = 1; n <= 5; n++)
            InkResponse(
              onTap: () => onPick(n == value ? 0 : n),
              radius: big ? 26 : 20,
              child: Padding(
                padding: EdgeInsets.all(big ? 6 : 4),
                child: Icon(value >= n ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: big ? 34 : 22, color: value >= n ? _amber400 : _stone300, semanticLabel: '$n star${n == 1 ? '' : 's'}'),
              ),
            ),
        ]),
      );

  Widget? _feedbackCard() {
    final fb = _fb;
    if (fb == null || fb['found'] != true) return null;
    if (fb['alreadyRated'] == true) {
      final r = tNum(fb['rating']).toInt();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var n = 1; n <= 5; n++) Icon(r >= n ? Icons.star_rounded : Icons.star_outline_rounded, size: 22, color: r >= n ? _amber400 : _amber200),
            ]),
            const SizedBox(height: 8),
            Text(_fbThanks ? 'Thank you - that means a lot.' : 'You rated this visit',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _amber900)),
            if (tStr(fb['comment']).isNotEmpty)
              Text('“${tStr(fb['comment'])}”', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: _amber700)),
          ]),
        ),
      );
    }
    if (fb['canRate'] != true) return null;
    final name = tStr(_profile?['restaurantName']);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_amber50, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border.all(color: _amber200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('How was everything?', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _stone900)),
          const SizedBox(height: 2),
          Text(name.isNotEmpty ? 'Tell $name how they did' : 'Your rating helps the team',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _stone500)),
          const SizedBox(height: 10),
          Center(child: _stars(_fbRating, (n) => _set(() => _fbRating = n), label: 'Overall rating')),
          if (_fbRating > 0) ...[
            Text(const ['', 'Not good', 'Could be better', 'Fine', 'Really good', 'Excellent'][_fbRating],
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _amber700)),
            const Divider(height: 28, color: _amber200),
            const Text('ANYTHING MORE? (OPTIONAL)',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w500, color: _stone400)),
            const SizedBox(height: 8),
            for (final (label, value, setter) in [
              ('Food', _fbFood, (int n) => _set(() => _fbFood = n)),
              ('Service', _fbService, (int n) => _set(() => _fbService = n)),
              ('Ambience', _fbAmbience, (int n) => _set(() => _fbAmbience = n)),
            ])
              Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: _stone600))),
                _stars(value, setter, big: false, label: '$label rating'),
              ]),
            const SizedBox(height: 8),
            TextField(
              controller: _fbComment,
              maxLength: 1000,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Tell them what you loved, or what could be better...',
                filled: true,
                fillColor: Colors.white,
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _stone200)),
              ),
            ),
            if (_fbError != null) ...[const SizedBox(height: 8), _errorBox(_fbError!)],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _rose600, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _fbSending || _fbRating < 1 ? null : _sendFeedback,
              icon: _fbSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.star_rounded, size: 16),
              label: Text(_fbSending ? 'Sending...' : 'Send my rating'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _errorBox(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: _rose50, border: Border.all(color: _rose200), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 13, color: _rose700)),
      );

  /* ── Menu ── */

  List<Map> get _filtered => [
        for (final i in _items)
          if ((_selectedCat == null || tNum(i['categoryId']).toInt() == _selectedCat) &&
              (_search.isEmpty || tStr(i['name']).toLowerCase().contains(_search.toLowerCase())))
            i,
      ];

  Widget _menuView() {
    final items = _filtered;
    final qr = widget.qrToken ?? '';
    final s = _settings!;
    return Stack(children: [
      CustomScrollView(controller: _scroll, slivers: [
        SliverToBoxAdapter(child: _hero()),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: [
            if ((qr.isEmpty || _isVenueCode) && (s['allowTakeaway'] == true || s['allowDelivery'] == true))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, children: [
                  if (s['allowTakeaway'] == true) _typeChip('Takeaway', Icons.shopping_bag_outlined),
                  if (s['allowDelivery'] == true) _typeChip('Delivery', Icons.local_shipping_outlined),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchBox,
              focusNode: _searchFocus,
              onChanged: (v) => _set(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search the menu...',
                prefixIcon: const Icon(Icons.search, size: 18, color: _stone400),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchBox.clear();
                          _set(() => _search = '');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _stone200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _stone200)),
              ),
            ),
            const SizedBox(height: 10),
            ?_categoryRail(),
            const SizedBox(height: 6),
          ]),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(child: _emptyMenu())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 268),
              itemCount: items.length,
              itemBuilder: (_, i) => _menuCard(items[i]),
            ),
          ),
      ]),
      // The compact bar, once the hero scrolls away.
      AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        top: _scrolled ? 0 : -130,
        left: 0,
        right: 0,
        child: _compactBar(),
      ),
      if (_cartCount > 0) Positioned(left: 0, right: 0, bottom: 0, child: _cartBar()),
    ]);
  }

  Widget _typeChip(String type, IconData icon) {
    final on = _orderType == type;
    return Material(
      color: on ? _stone900 : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: on ? _stone900 : _stone200)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _set(() => _orderType = type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: on ? Colors.white : _stone600),
            const SizedBox(width: 6),
            Text(type, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Colors.white : _stone600)),
          ]),
        ),
      ),
    );
  }

  Widget? _categoryRail() {
    if (_categories.isEmpty) return null;
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: on ? _rose600 : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: on ? _rose600 : _stone200)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: on ? Colors.white : _stone600)),
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('All', _selectedCat == null, () => _set(() => _selectedCat = null)),
        for (final c in _categories)
          chip(tStr(c['name']), _selectedCat == tNum(c['menuCategoryId']).toInt(), () => _set(() => _selectedCat = tNum(c['menuCategoryId']).toInt())),
      ]),
    );
  }

  Widget _logo(double size, double icon) {
    final url = tStr(_profile?['logoUrl']);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(size / 4)),
      child: restaurantImage(url, fallback: Icon(Icons.restaurant, size: icon, color: Colors.white)),
    );
  }

  Widget _hero() {
    final p = _profile ?? const {};
    final name = tStr(p['restaurantName']);
    final hours = openState(tStr(p['openingTime']), tStr(p['closingTime']));
    final facts = [tStr(p['cuisineType']), tStr(p['city']), tStr(p['phone'])].where((v) => v.isNotEmpty).join('  ·  ');
    final welcome = tStr(_settings!['welcomeMessage']).isNotEmpty ? tStr(_settings!['welcomeMessage']) : tStr(p['description']);
    final liveOrder = _pastOrders.any((o) {
      final st = _pastStatuses[tStr(o['trackingToken'])];
      return st != null && !_done.contains(st);
    });
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_rose600, _rose600, _rose700], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _logo(44, 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(name.isEmpty ? 'Order online' : name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                if (_isVenueCode)
                  _heroBadge('SKIP THE QUEUE', Colors.white.withValues(alpha: .2), Colors.white)
                else if (_tableNumber.isNotEmpty)
                  _heroBadge('TABLE $_tableNumber', Colors.white, _rose700),
                if (hours != null)
                  _heroBadge('${hours.open ? 'Open' : 'Closed'} · ${hours.label}',
                      hours.open ? const Color(0x3334D399) : const Color(0x33000000), hours.open ? const Color(0xFFECFDF5) : Colors.white70),
              ]),
              if (facts.isNotEmpty) Text(facts, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ),
        ]),
        if (welcome.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(welcome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
        if (_pastOrders.isNotEmpty) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.white.withValues(alpha: .15),
            shape: const StadiumBorder(side: BorderSide(color: Color(0x40FFFFFF))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _openHistory,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('My orders (${_pastOrders.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  if (liveOrder) ...[
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF6EE7B7), shape: BoxShape.circle)),
                  ],
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _heroBadge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6, color: fg)),
      );

  Widget _compactBar() {
    final name = tStr(_profile?['restaurantName']);
    return Material(
      color: Colors.white.withValues(alpha: .95),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _rose600, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.restaurant, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name.isEmpty ? 'Order online' : name,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _stone900)),
            ),
            IconButton(
              tooltip: 'Search the menu',
              onPressed: () async {
                await _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                _searchFocus.requestFocus();
              },
              icon: const Icon(Icons.search, size: 18, color: _stone500),
            ),
            if (_cartCount > 0)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _rose600, visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                label: Text('$_cartCount'),
              ),
          ]),
          if (_categories.isNotEmpty) ...[const SizedBox(height: 8), _categoryRail()!],
        ]),
      ),
    );
  }

  Widget _emptyMenu() {
    final filtering = _search.isNotEmpty || _selectedCat != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 140),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .6), border: Border.all(color: _stone200), borderRadius: BorderRadius.circular(24)),
      child: Column(children: [
        const Icon(Icons.restaurant, size: 40, color: _stone300),
        const SizedBox(height: 12),
        Text(filtering ? 'Nothing matches that' : 'Nothing on the menu yet', style: const TextStyle(fontWeight: FontWeight.w600, color: _stone700)),
        const SizedBox(height: 4),
        Text(filtering ? 'Try a different search or category.' : 'Please ask a member of staff.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _stone500)),
        if (filtering) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            onPressed: () {
              _searchBox.clear();
              _set(() {
                _search = '';
                _selectedCat = null;
              });
            },
            child: const Text('Clear filters'),
          ),
        ],
      ]),
    );
  }

  Widget _menuCard(Map item) {
    final id = tNum(item['menuItemId']).toInt();
    final qty = _qtyOf(id);
    final url = tStr(item['imageUrl']);
    final spicy = tNum(item['spicyLevel']).toInt();
    final name = tStr(item['name']);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: qty > 0 ? const Color(0xFFFDA4AF) : _stone200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Add $name to your order',
            child: InkWell(
              onTap: () => _add(item),
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [_rose50, _stone100], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: restaurantImage(url, fallback: const Icon(Icons.restaurant, size: 32, color: _rose200)),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Wrap(spacing: 4, children: [
                    if (item['isVegan'] == true)
                      _heroBadge('VEGAN', _emerald600, Colors.white)
                    else if (item['isVegetarian'] == true)
                      _heroBadge('VEG', _emerald600, Colors.white),
                    if (spicy > 0) _heroBadge('🌶️' * (spicy > 3 ? 3 : spicy), const Color(0x8C000000), Colors.white),
                  ]),
                ),
                if (qty > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      height: 24,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: _rose600, borderRadius: BorderRadius.circular(12)),
                      child: Text('$qty', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _stone900)),
              if (tStr(item['description']).isNotEmpty)
                Text(tStr(item['description']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _stone500)),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_money(tNum(item['price'])), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _stone900)),
                    if (tNum(item['prepTime']) > 0)
                      Row(children: [
                        const Icon(Icons.schedule, size: 12, color: _stone400),
                        const SizedBox(width: 3),
                        Text('${tNum(item['prepTime']).toInt()} min', style: const TextStyle(fontSize: 11, color: _stone400)),
                      ]),
                  ]),
                ),
                if (qty == 0)
                  IconButton.filled(
                    tooltip: 'Add $name to your order',
                    style: IconButton.styleFrom(backgroundColor: _rose600, fixedSize: const Size(36, 36), minimumSize: const Size(36, 36)),
                    onPressed: () => _add(item),
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
              ]),
              if (qty > 0) ...[
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: _rose50, border: Border.all(color: _rose200), borderRadius: BorderRadius.circular(999)),
                  child: Row(children: [
                    IconButton(
                      tooltip: 'Remove one $name',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _dec(id),
                      icon: const Icon(Icons.remove, size: 16, color: _rose700),
                    ),
                    Expanded(child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: _rose700))),
                    IconButton.filled(
                      tooltip: 'Add another $name',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(backgroundColor: _rose600),
                      onPressed: () => _add(item),
                      icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    ),
                  ]),
                ),
              ],
            ]),
        ),
      ]),
    );
  }

  Widget _cartBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _stone200)),
          boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 32, offset: Offset(0, -8), spreadRadius: -16)],
        ),
        child: SafeArea(
          top: false,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _rose600,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _openCart,
            child: Row(children: [
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                height: 24,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(12)),
                child: Text('$_cartCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('View order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              Text(_money(_total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  /* ── Cart / details sheet ── */

  Future<void> _openCart() async {
    _set(() => _step = 'cart');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .92,
        child: ValueListenableBuilder<int>(valueListenable: _sheetTick, builder: (_, _, _) => _cartSheet(sheet)),
      ),
    );
    if (mounted) _set(() => _step = 'cart');
  }

  Widget _cartSheet(BuildContext sheet) {
    final details = _step == 'details';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _stone200))),
          child: Row(children: [
            if (details)
              IconButton(tooltip: 'Back to order', onPressed: () => _set(() => _step = 'cart'), icon: const Icon(Icons.chevron_left, size: 20)),
            Padding(
              padding: EdgeInsets.only(left: details ? 0 : 6),
              child: Text(details ? 'Your details' : 'Your order', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _stone900)),
            ),
            if (_cartCount > 0 && !details) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _rose50, borderRadius: BorderRadius.circular(999)),
                child: Text('$_cartCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _rose700)),
              ),
            ],
            const Spacer(),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheet).pop(), icon: const Icon(Icons.close, size: 18)),
          ]),
        ),
        Expanded(
          child: _cart.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: _emptyCart())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (!details) ...[
                    for (final (i, line) in _cart.indexed) _cartLine(i, line),
                    if (_belowMinimum) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                            'Minimum order is ${_money(tNum(_settings!['minOrderAmount']))}. Add ${_money(tNum(_settings!['minOrderAmount']) - _subtotal)} more.',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF92400E))),
                      ),
                    ],
                  ] else
                    _detailsForm(),
                  const SizedBox(height: 16),
                  _totals(),
                ]),
        ),
        if (_cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _stone200))),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_orderError != null) ...[_errorBox(_orderError!), const SizedBox(height: 8)],
                if (!details)
                  _bigButton('Continue · ${_money(_total)}', _belowMinimum ? null : () => _set(() => _step = 'details'))
                else ...[
                  _bigButton('Place order · ${_money(_total)}', _placing || !_canSubmit || _belowMinimum ? null : () => _placeOrder(sheet),
                      icon: _placing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 20)),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: _stone500),
                    onPressed: () => _set(() => _step = 'cart'),
                    icon: const Icon(Icons.chevron_left, size: 16),
                    label: const Text('Back to order'),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _bigButton(String label, VoidCallback? onTap, {Widget? icon}) => FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: _rose600, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[icon, const SizedBox(width: 8)],
          Flexible(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _emptyCart() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: _stone200), borderRadius: BorderRadius.circular(16)),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_bag_outlined, size: 32, color: _stone300),
          SizedBox(height: 8),
          Text('Your order is empty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _stone600)),
          Text('Tap a dish to add it.', style: TextStyle(fontSize: 12, color: _stone400)),
        ]),
      );

  Widget _cartLine(int i, _CartLine line) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _stone50, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _stone900)),
              Text('${_money(line.price)} each', style: const TextStyle(fontSize: 12, color: _stone500)),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _stone200), borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Decrease quantity',
                visualDensity: VisualDensity.compact,
                onPressed: () => _set(() => line.quantity = line.quantity > 1 ? line.quantity - 1 : 1),
                icon: const Icon(Icons.remove, size: 14),
              ),
              Text('${line.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              IconButton(
                tooltip: 'Increase quantity',
                visualDensity: VisualDensity.compact,
                onPressed: () => _set(() => line.quantity++),
                icon: const Icon(Icons.add, size: 14),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: Text(_money(line.price * line.quantity),
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _stone900)),
          ),
          IconButton(
            tooltip: 'Remove ${line.name}',
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(() => _cart.removeAt(i)),
            icon: const Icon(Icons.close, size: 14, color: _stone300),
          ),
        ]),
      );

  Widget _totals() => Column(children: [
        _totalRow('Subtotal', _money(_subtotal)),
        if (_orderType == 'Delivery')
          _totalRow('Delivery', _freeDelivery ? 'Free' : _money(_actualDeliveryFee), valueColor: _freeDelivery ? _emerald600 : null),
        if (_promoDiscount > 0) _totalRow('Promo · ${_promo.text}', '-${_money(_promoDiscount)}', color: _emerald600, valueColor: _emerald600),
        const Divider(height: 16, color: _stone200),
        Row(children: [
          const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _stone900)),
          const Spacer(),
          Text(_money(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _stone900)),
        ]),
      ]);

  Widget _totalRow(String k, String v, {Color? color, Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: TextStyle(fontSize: 14, color: color ?? _stone500)),
          const Spacer(),
          Text(v, style: TextStyle(fontSize: 14, color: valueColor ?? _stone700)),
        ]),
      );

  InputDecoration _boxDeco(String hint, {bool bad = false}) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: _stone50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _stone200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: bad ? const Color(0xFFFB7185) : _stone200)),
      );

  Widget _label(String text, {bool required = false, String? note}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: text),
            if (required) const TextSpan(text: ' *', style: TextStyle(color: _rose600)),
            if (note != null) TextSpan(text: ' $note', style: const TextStyle(fontWeight: FontWeight.w400, color: _stone400)),
          ]),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _stone600),
        ),
      );

  Widget _detailsForm() {
    const methods = [('MobileMoney', 'Mobile Money', Icons.smartphone), ('CreditCard', 'Card', Icons.credit_card), ('Cash', 'Cash', Icons.payments_outlined)];
    final r = _promoResult;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _promo,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) {
              final up = v.toUpperCase();
              if (up != v) _promo.value = _promo.value.copyWith(text: up);
            },
            decoration: _boxDeco('Promo code'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(tooltip: 'Apply promo', onPressed: _applyPromo, icon: const Icon(Icons.sell_outlined, size: 18)),
      ]),
      if (r != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: r['valid'] == true ? _emerald50 : _rose50,
            border: Border.all(color: r['valid'] == true ? const Color(0xFFA7F3D0) : _rose200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(tStr(r['message']), style: TextStyle(fontSize: 14, color: r['valid'] == true ? const Color(0xFF047857) : _rose700)),
        ),
      ],
      if (_recalled) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _emerald50, border: Border.all(color: const Color(0xFFA7F3D0)), borderRadius: BorderRadius.circular(16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.how_to_reg_outlined, size: 16, color: _emerald600),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Filled in from last time.', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: ' Change anything that is out of date. '),
                  ]),
                  style: TextStyle(fontSize: 12, color: _emerald900),
                ),
                GestureDetector(
                  onTap: () => _forget(),
                  child: const Text('Not you?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _emerald900, decoration: TextDecoration.underline)),
                ),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      _label('Your name', required: true),
      TextField(controller: _name, onChanged: (_) => _set(() {}), decoration: _boxDeco('So we know whose order this is')),
      const SizedBox(height: 12),
      _label('Phone number', required: true),
      TextField(
          controller: _phone, keyboardType: TextInputType.phone, onChanged: (_) => _set(() {}), decoration: _boxDeco('In case we need to check something')),
      const SizedBox(height: 12),
      _label('Email address', note: '(optional)'),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => _set(() {}),
        decoration: _boxDeco('For your receipt', bad: _emailLooksWrong),
      ),
      if (_emailLooksWrong)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('That email address does not look right. Leave it blank if you would rather not give one.',
              style: TextStyle(fontSize: 12, color: _rose600)),
        ),
      if (_orderType == 'Delivery') ...[
        const SizedBox(height: 12),
        _label('Delivery address', required: true),
        TextField(controller: _address, onChanged: (_) => _set(() {}), decoration: _boxDeco('Where should we bring it?')),
      ],
      const SizedBox(height: 14),
      _label('How will you pay?', required: true),
      Row(children: [
        for (final (i, (value, label, icon)) in methods.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: _payIntent == value ? _rose50 : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _payIntent == value ? const Color(0xFFF43F5E) : _stone200),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _set(() => _payIntent = value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Column(children: [
                    Icon(icon, size: 20, color: _payIntent == value ? _rose700 : _stone500),
                    const SizedBox(height: 6),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _payIntent == value ? _rose700 : _stone500)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      _label('Amount'),
      TextField(
        controller: _payAmount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _boxDeco(_total.toStringAsFixed(2)),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Nothing is charged now - you settle with the staff. Leave blank to use the order total.',
            style: TextStyle(fontSize: 12, color: _stone400)),
      ),
    ]);
  }

  /* ── My orders ── */

  static const _statusTone = <String, (Color, Color)>{
    'Placed': (Color(0xFFFEF3C7), Color(0xFF92400E)),
    'Confirmed': (Color(0xFFDBEAFE), Color(0xFF1E40AF)),
    'Preparing': (Color(0xFFE0E7FF), Color(0xFF3730A3)),
    'Ready': (Color(0xFFD1FAE5), Color(0xFF065F46)),
    'Served': (Color(0xFFD1FAE5), Color(0xFF065F46)),
    'Completed': (_stone100, _stone600),
    'Cancelled': (Color(0xFFFFE4E6), _rose700),
    'Refunded': (Color(0xFFFFE4E6), _rose700),
  };
  static const _statusWords = <String, String>{
    'Placed': 'Waiting for the restaurant',
    'Confirmed': 'Confirmed',
    'Preparing': 'Being prepared',
    'Ready': 'Ready for you',
    'Served': 'Served',
    'Completed': 'Completed',
    'Cancelled': 'Not accepted',
  };

  Future<void> _openHistory() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheet) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * .85),
          child: ValueListenableBuilder<int>(
            valueListenable: _sheetTick,
            builder: (_, _, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _stone200))),
                child: const Row(children: [
                  Icon(Icons.history, size: 16, color: _rose600),
                  SizedBox(width: 8),
                  Text('Your recent orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _stone900)),
                ]),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
                  for (final o in _pastOrders) _pastRow(sheet, o),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _stone200))),
                child: SafeArea(
                  top: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text("Saved on this device only, so you don't have to type your details again. They are not shared with anyone.",
                        style: TextStyle(fontSize: 11, color: _stone400)),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _stone500),
                      onPressed: () => _forget(closeSheet: true, sheet: sheet),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Forget my details on this device'),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _pastRow(BuildContext sheet, Map o) {
    final status = _pastStatuses[tStr(o['trackingToken'])];
    final tone = _statusTone[status] ?? (_stone100, _stone600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _stone200)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            Navigator.of(sheet).pop();
            try {
              final t = _asMap(await _api.get('/api/Restaurant/public/track/${tStr(o['trackingToken'])}'));
              _showTracking(t, tStr(o['trackingToken']));
            } catch (_) {
              _set(() => _trackingToken = '');
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tStr(o['orderNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700, color: _stone900)),
                  Text('${tStr(o['orderType'])} · ${fmtInstant(o['placedAt'], Duration.zero)} · ${_localTime(o['placedAt'], seconds: false)}',
                      style: const TextStyle(fontSize: 12, color: _stone500)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: status == null ? _stone100 : tone.$1, borderRadius: BorderRadius.circular(999)),
                    child: Text(status == null ? 'Checking...' : (_statusWords[status] ?? status),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status == null ? _stone400 : tone.$2)),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_money(tNum(o['total'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _stone900)),
                const Text('Track', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _rose600)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
