import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/company_timezone_field.dart';
import '../shared/currencies.dart';
import '../shared/search_picker.dart';
import 'poultry_profile_form.dart';

/// Poultry → Setup → Company → Company Setup, as
/// `app/poultry-company-setup/page.tsx`: the business details, saved with
/// POST `/Poultry/company/setup` the first time (which also seeds the
/// default cash accounts) and PUT `/Poultry/company` after.
///
/// Saving also moves the farm's display currency when the code changed, as
/// the web does — that row is what every money figure reads.
class PoultryCompanySetupScreen extends StatefulWidget {
  const PoultryCompanySetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<PoultryCompanySetupScreen> createState() => _PoultryCompanySetupScreenState();
}

/// Loads the profile into [form]; leaves it empty when not set up (404).
Future<void> loadPoultryProfile(Session session, Company company, PoultryProfileForm form) async {
  try {
    final p = await session.farmClient.get('/api/Poultry/company?farmId=${Uri.encodeComponent(company.farmId)}');
    if (p is Map) form.fill(p);
  } on ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
  }
}

/// First save sets the company up; later saves update it. Returns the
/// profile as stored.
Future<void> savePoultryProfile(
    Session session, Company company, PoultryProfileForm form, Map<String, dynamic> payload) async {
  final farm = Uri.encodeComponent(company.farmId);
  final res = form.isSetUp
      ? await session.farmClient.put('/api/Poultry/company?farmId=$farm', body: payload)
      : await session.farmClient.post('/api/Poultry/company/setup', body: {...payload, 'farmId': company.farmId});
  if (res is Map) {
    form.fill(res);
  } else {
    form.profile ??= payload;
  }
}

class _PoultryCompanySetupScreenState extends State<PoultryCompanySetupScreen> {
  final _form = PoultryProfileForm();
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
    _form.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      await loadPoultryProfile(widget.session, widget.company, _form);
    } on ApiException catch (e) {
      if (mounted) _snack('Could not load company profile. ${e.message}');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = _form.payload();
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
            'could not be updated. Set it in Setup > Company.');
      }
    }
    try {
      final wasNew = !_form.isSetUp;
      await savePoultryProfile(widget.session, widget.company, _form, payload);
      if (mounted) _snack(wasNew ? 'Poultry Company set up. Default cash accounts seeded.' : 'Profile updated');
    } on ApiException catch (e) {
      if (mounted) {
        _snack('Save failed. ${e.message.isNotEmpty ? e.message : "Check that the active company is a Poultry company."}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-company-setup');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Row(
          children: [
            const Flexible(child: Text('Poultry Company Setup', overflow: TextOverflow.ellipsis)),
            if (_form.isSetUp) ...[
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
                FormSection(
                  title: 'Business details',
                  color: SectionColor.amber,
                  children: _form.fields(setState, between: [
                    AppField(
                      label: 'Default currency',
                      child: CurrencyPickerField(
                        code: _form.currency,
                        onChanged: (o) => setState(() => _form.currency = o.code),
                      ),
                    ),
                    AppField(
                      label: 'Business timezone',
                      child: CompanyTimeZoneField(session: widget.session, company: widget.company),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                AppButton(
                  label: _saving ? 'Saving…' : _form.isSetUp ? 'Save changes' : 'Set up Poultry Company',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (!_form.isSetUp) ...[
                  const SizedBox(height: 8),
                  Text('First-time setup seeds the default cash accounts automatically.',
                      style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                ],
              ],
            ),
    );
  }
}

/// The green "✓ Set up" pill.
class SetUpBadge extends StatelessWidget {
  const SetUpBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7), // green-100
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('✓ Set up', style: TextStyle(fontSize: 11, color: Color(0xFF15803D))),
      );
}
