// Generic → Admin → Setup, as `app/generic-setup/page.tsx`: the company
// profile. "What kind of business is this?" both stores the legacy business
// category and stamps the business template (labels, menus, starter seeds);
// the rest is the profile itself, plus the company time zone.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/company_timezone_field.dart';
import 'generic_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';
class GenericSetupScreen extends StatefulWidget {
  const GenericSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericSetupScreen> createState() => _GenericSetupScreenState();
}

class _GenericSetupScreenState extends State<GenericSetupScreen> {
  bool _loading = true, _saving = false;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _categories = [];
  String? _typeId, _categoryId;
  DateTime? _startDate;

  final _currency = TextEditingController(text: 'GHC');
  final _opening = TextEditingController(text: '0');
  final _location = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _currency.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_currency, _opening, _location, _owner, _phone, _description, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _msg(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _load() async {
    // Categories are platform-wide, so a profile failure must not take them down.
    try {
      final r = await _api.get('/api/business-categories');
      if (r is List) _categories = [for (final c in r) if (c is Map) Map<String, dynamic>.from(c)];
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load business categories', description: _msg(e), error: true);
    }
    Map<String, dynamic>? profile;
    try {
      final r = await _api.get(_base);
      if (r is Map && r.isNotEmpty) profile = Map<String, dynamic>.from(r);
    } on ApiException catch (e) {
      // 404 is "not set up yet". Anything else is worth saying, 409 in its own words.
      if (e.statusCode != 404) {
        if (mounted) {
          trackerToast(context, e.statusCode == 409 ? 'Wrong company type' : "Could not load this company's setup",
              description: e.message, error: true);
          setState(() => _loading = false);
        }
        return;
      }
    }
    // Preselect whatever this company is already on.
    try {
      final t = await _api.get('$_base/business-template');
      if (t is Map) _typeId = businessTypeForIndustry(tStr(t['genericIndustryTemplate']))?.id;
    } catch (_) {}
    if (profile != null) {
      _profile = profile;
      _categoryId = profile['businessCategoryId'] == null ? null : '${profile['businessCategoryId']}';
      _description.text = tStr(profile['businessDescription']);
      _currency.text = tStr(profile['defaultCurrency']).isEmpty ? 'GHC' : tStr(profile['defaultCurrency']);
      final o = tNum(profile['openingCashBalance']);
      _opening.text = o == o.roundToDouble() ? '${o.toInt()}' : '$o';
      final d = tStr(profile['businessStartDate']);
      _startDate = d.length >= 10 ? DateTime.tryParse(d.substring(0, 10)) : null;
      _location.text = tStr(profile['mainLocation']);
      _owner.text = tStr(profile['ownerName']);
      _phone.text = tStr(profile['phoneNumber']);
      _notes.text = tStr(profile['notes']);
    }
    if (mounted) setState(() => _loading = false);
  }

  String? _orNull(TextEditingController c) => c.text.isEmpty ? null : c.text;

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() => _saving = true);
    final chosen = genericBusinessTypes.where((t) => t.id == _typeId).firstOrNull;
    final wasSetUp = _profile != null;
    try {
      final updated = await _api.post('/api/generic-company/setup', body: {
        // Derived from the business type rather than asked for separately.
        'businessCategoryId': legacyCategoryIdFor(chosen?.industryTemplate, _categories) ??
            (_categoryId == null ? null : int.tryParse(_categoryId!)),
        'businessDescription': _orNull(_description),
        'defaultCurrency': _currency.text.isEmpty ? 'GHC' : _currency.text,
        'openingCashBalance': double.tryParse(_opening.text) ?? 0,
        'businessStartDate': _startDate == null ? null : _ymd(_startDate!),
        'mainLocation': _orNull(_location),
        'ownerName': _orNull(_owner),
        'phoneNumber': _orNull(_phone),
        'notes': _orNull(_notes),
        'farmId': widget.company.farmId,
      });
      if (updated != null) {
        if (updated is Map) setState(() => _profile = Map<String, dynamic>.from(updated));
        // The profile must exist before a template can be stamped on it.
        final business = businessTemplateFor(chosen?.industryTemplate);
        if (chosen?.industryTemplate != null && business != null) {
          await _api.post('$_base/business-template', body: {
            'businessTemplate': business,
            'industryTemplate': chosen!.industryTemplate,
          });
          invalidateGenericModules(widget.company.farmId);
        }
        if (mounted) {
          trackerToast(
            context,
            wasSetUp ? 'Setup updated' : 'Set up as ${chosen?.label ?? 'a Generic company'}',
            description: chosen != null
                ? 'Menus, labels and starter categories now match this business.'
                : 'Default categories, cash accounts and lookups have been seeded.',
          );
          // A first setup goes on to the dashboard, as the web does.
          if (!wasSetUp) Navigator.of(context).popUntil((r) => r.isFirst);
        }
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _text(TextEditingController c, int max, {TextInputType? keyboard}) => AppInput(
        controller: c,
        keyboardType: keyboard,
        inputFormatters: [LengthLimitingTextInputFormatter(max)],
      );

  Widget _area(TextEditingController c, int max) => AppInput(
        controller: c,
        keyboardType: TextInputType.multiline,
        minLines: 2,
        maxLines: 6,
        inputFormatters: [LengthLimitingTextInputFormatter(max)],
      );

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  @override
  Widget build(BuildContext context) {
    final set = _profile != null;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-setup');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          GenericTitle(
            icon: Icons.settings_outlined,
            iconColor: genericEmerald,
            title: set ? 'Business profile' : 'Set up your business',
            subtitle: set
                ? 'Update your profile. Default lookups stay as they are; this form does not re-seed.'
                : "Pick a business category and basic details — we'll seed default expense categories, cash accounts, "
                    'customer/supplier types, and payment methods.',
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else
            GenericCard(
              title: 'Profile',
              descriptionWidget: set
                  ? const Row(children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Tone.fg(0xFF047857)),
                      SizedBox(width: 4),
                      Text('Already set up', style: TextStyle(fontSize: 13, color: Tone.fg(0xFF047857))),
                    ])
                  : null,
              children: [
                FilterLabel(
                  'What kind of business is this?',
                  AppSelect<String>(
                    value: _typeId,
                    hintText: 'Choose…',
                    items: [
                      for (final t in genericBusinessTypes) AppSelectItem(value: t.id, label: '${t.label} — ${t.description}'),
                    ],
                    onChanged: (v) => setState(() => _typeId = v),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Sets what things are called, which menus appear, and the categories, accounts and starter plans '
                    'you begin with. You can change all of it afterwards.',
                    style: TextStyle(fontSize: 12, color: TColors.slate500),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: Text('Restaurant, hotel, shop, salon, pharmacy, etc.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ),
                _gap(FilterLabel('Default currency', _text(_currency, 10))),
                _gap(CompanyTimeZoneField(session: widget.session, company: widget.company)),
                _gap(FilterLabel(
                  'Business start date',
                  AppDateField(value: _startDate, onChanged: (d) => setState(() => _startDate = d)),
                )),
                _gap(FilterLabel('Owner name', _text(_owner, 150))),
                _gap(FilterLabel('Phone number', _text(_phone, 50, keyboard: TextInputType.phone))),
                _gap(FilterLabel('Main location', _text(_location, 255))),
                FilterLabel(
                  'Opening cash (${_currency.text})',
                  AppNumberInput(controller: _opening, allowDecimal: true),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: Text('Seeds the "Main Cash Box" account.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ),
                _gap(FilterLabel('Business description', _area(_description, 500))),
                _gap(FilterLabel('Notes', _area(_notes, 1000))),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_saving) ...[busyIcon(true, Icons.check), const SizedBox(width: 6)],
                          Flexible(child: Text(set ? 'Save changes' : 'Set up & continue', overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
