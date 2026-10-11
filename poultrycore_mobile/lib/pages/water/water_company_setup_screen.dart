import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/company_setup_screen.dart' show SetUpBadge;
import '../shared/company_timezone_field.dart';
import '../shared/currencies.dart';
import '../shared/search_picker.dart';

/// Water → Setup → Company → Company Setup, as
/// `app/water-company-setup/page.tsx`: the business details, saved with
/// POST `/Water/company/setup` the first time (which also seeds default
/// expense categories and cash accounts) and PUT `/Water/company` after.
///
/// Saving also moves the farm's display currency when the code changed, as
/// the web does — that row is what every money figure reads.
class WaterCompanySetupScreen extends StatefulWidget {
  const WaterCompanySetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterCompanySetupScreen> createState() => _WaterCompanySetupScreenState();
}

const _businessTypes = ['Sachet', 'Bottled', 'Both'];
const _sources = <(String, String)>[
  ('Borehole', 'Borehole'),
  ('GhanaWater', 'Ghana Water'),
  ('Tanker', 'Tanker'),
  ('Mixed', 'Mixed'),
];

/// The allowed value matching [raw] case-insensitively, else [fallback] —
/// the web normalises what it shows and what it sends the same way.
String _normalise(String? raw, List<String> allowed, String fallback) =>
    allowed.where((o) => o.toLowerCase() == (raw ?? '').toLowerCase()).firstOrNull ?? fallback;

class _WaterCompanySetupScreenState extends State<WaterCompanySetupScreen> {
  final _brand = TextEditingController();
  final _site = TextEditingController();
  final _location = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _sachets = TextEditingController(text: '30');
  final _notes = TextEditingController();
  String _business = 'Sachet';
  String _source = 'Borehole';
  String _currency = 'GHC';
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;

  ApiClient get _client => widget.session.farmClient;
  String get _farm => Uri.encodeComponent(widget.company.farmId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_brand, _site, _location, _owner, _phone, _sachets, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _fill(Map p) {
    _profile = Map<String, dynamic>.from(p);
    _brand.text = '${p['brandName'] ?? ''}';
    _business = '${p['businessType'] ?? ''}';
    _site.text = '${p['productionSiteAddress'] ?? ''}';
    _location.text = '${p['mainLocation'] ?? ''}';
    _source = '${p['waterSourceType'] ?? ''}';
    _currency = '${p['defaultCurrency'] ?? 'GHC'}';
    _sachets.text = '${p['defaultBagSachetCount'] ?? 30}';
    _owner.text = '${p['ownerName'] ?? ''}';
    _phone.text = '${p['phoneNumber'] ?? ''}';
    _notes.text = '${p['notes'] ?? ''}';
  }

  Future<void> _load() async {
    try {
      final p = await _client.get('/api/Water/company?farmId=$_farm');
      if (p is Map) _fill(p);
    } on ApiException catch (e) {
      // 404 means "not set up yet": leave the empty form.
      if (e.statusCode != 404 && mounted) _snack('Could not load water profile. ${e.message}');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'brandName': _brand.text,
      'businessType': _normalise(_business, _businessTypes, 'Sachet'),
      'productionSiteAddress': _site.text,
      'mainLocation': _location.text,
      'waterSourceType': _normalise(_source, [for (final s in _sources) s.$1], 'Borehole'),
      // Required by the SP; a blank falls back to its own default.
      'defaultCurrency': _currency.trim().isEmpty ? 'GHC' : _currency.trim(),
      'defaultBagSachetCount': int.tryParse(_sachets.text.trim()) ?? 30,
      'ownerName': _owner.text,
      'phoneNumber': _phone.text,
      'notes': _notes.text,
    };
    // The farm's display currency follows the profile, but only when the
    // code actually changes — re-saving must not undo a preferred symbol.
    try {
      final current = await _client.get('/api/Water/farm-settings?farmId=$_farm');
      final picked = '${payload['defaultCurrency']}'.toUpperCase();
      final now = current is Map ? '${current['currencyCode'] ?? ''}'.toUpperCase() : '';
      if (picked.isNotEmpty && picked != now) {
        await _client.put('/api/Water/farm-settings/currency?farmId=$_farm', body: {
          'currencyCode': picked,
          'currencySymbol': currencySymbolFor(picked),
          'showCurrencySymbol': current is Map ? current['showCurrencySymbol'] != false : true,
        });
      }
    } catch (_) {
      if (mounted) {
        _snack('Currency not applied app-wide. The profile saved, but the display currency '
            'could not be updated. Set it in Water setup > Company.');
      }
    }
    try {
      final wasNew = _profile == null;
      final res = wasNew
          ? await _client.post('/api/Water/company/setup', body: {...payload, 'farmId': widget.company.farmId})
          : await _client.put('/api/Water/company?farmId=$_farm', body: payload);
      if (!mounted) return;
      setState(() {
        if (res is Map) {
          _fill(res);
        } else {
          _profile ??= payload;
        }
      });
      _snack(wasNew
          ? 'Water Company set up. Default expense categories and cash accounts seeded.'
          : 'Profile updated');
    } on ApiException catch (e) {
      if (mounted) {
        _snack('Save failed. ${e.message.isNotEmpty ? e.message : "Save returned a 500 with no detail. Check the Farm API logs or the active company's Farms.Type column — most often this is the 'Farm is not a Water company (Type=Poultry).' guard in spWaterCompany_Setup."}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final setUp = _profile != null;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-company-setup');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Row(
          children: [
            const Flexible(child: Text('Water Company Setup', overflow: TextOverflow.ellipsis)),
            if (setUp) ...[
              const SizedBox(width: 8),
              const SetUpBadge(),
            ],
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                FormSection(title: 'Business details', color: SectionColor.sky, children: [
                  AppField(label: 'Brand name', full: true,
                      child: AppInput(controller: _brand, hintText: 'e.g. ProfOwusu Pure Water')),
                  AppField(
                    label: 'Business type',
                    required: true,
                    child: AppSelect<String>(
                      value: _normalise(_business, _businessTypes, 'Sachet'),
                      hintText: 'Pick business type',
                      items: [for (final b in _businessTypes) AppSelectItem(value: b, label: b)],
                      onChanged: (v) => setState(() => _business = v ?? _business),
                    ),
                  ),
                  AppField(
                    label: 'Water source',
                    required: true,
                    child: AppSelect<String>(
                      value: _normalise(_source, [for (final s in _sources) s.$1], 'Borehole'),
                      hintText: 'Pick water source',
                      items: [for (final (v, l) in _sources) AppSelectItem(value: v, label: l)],
                      onChanged: (v) => setState(() => _source = v ?? _source),
                    ),
                  ),
                  AppField(label: 'Production site address', full: true, child: AppInput(controller: _site)),
                  AppField(label: 'Main location / town', child: AppInput(controller: _location)),
                  AppField(label: 'Owner name', child: AppInput(controller: _owner)),
                  AppField(label: 'Phone',
                      child: AppInput(controller: _phone, hintText: '+233...', keyboardType: TextInputType.phone)),
                  AppField(
                    label: 'Default currency',
                    child: CurrencyPickerField(
                      code: _currency,
                      onChanged: (o) => setState(() => _currency = o.code),
                    ),
                  ),
                  AppField(
                    label: 'Business timezone',
                    child: CompanyTimeZoneField(session: widget.session, company: widget.company),
                  ),
                  AppField(label: 'Sachets per bag', child: AppNumberInput(controller: _sachets)),
                  AppField(label: 'Notes', full: true, child: AppTextarea(controller: _notes)),
                ]),
                const SizedBox(height: 18),
                AppButton(
                  label: _saving ? 'Saving…' : setUp ? 'Save changes' : 'Set up Water Company',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (!setUp) ...[
                  const SizedBox(height: 8),
                  Text('First-time setup seeds default expense categories and cash accounts automatically.',
                      style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                ],
              ],
            ),
    );
  }
}
