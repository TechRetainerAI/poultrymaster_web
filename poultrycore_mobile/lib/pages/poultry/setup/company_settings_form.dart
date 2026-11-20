import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/company_timezone_field.dart';
import '../../shared/currencies.dart';
import '../../shared/search_picker.dart';
import '../company_setup_screen.dart';
import '../poultry_profile_form.dart';
import 'setup_embed.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Production Setup → Company settings, as the web's
/// components/setup-views/poultry-company-settings.tsx: the poultry company
/// profile in one form, in four sections (Business profile, Farm details,
/// Currency & time zone, Notes). On a wide screen the web puts each section's
/// heading in a left-hand column; on a phone it sits above the fields.
///
/// Saves the whole profile row; the first save creates it (and seeds the
/// default cash accounts). Currency lives on the Farms row and is saved
/// alongside, on its own: the server keeps that route Water-only, so a refusal
/// there must never lose the profile save. The time zone saves itself.
class CompanySettingsForm extends StatefulWidget {
  const CompanySettingsForm({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CompanySettingsForm> createState() => _CompanySettingsFormState();
}

class _CompanySettingsFormState extends State<CompanySettingsForm> {
  final _form = PoultryProfileForm();
  final _symbol = TextEditingController(text: 'GHC');
  late final FocusNode _symbolFocus = FocusNode()
    ..addListener(() {
      if (!_symbolFocus.hasFocus && _symbol.text.trim().isEmpty) _symbol.text = currencySymbolFor(_code);
    });
  String _code = 'GHS';
  bool _show = true;
  bool _loading = true;
  bool _saving = false;

  /// What was loaded (or last saved): the form is dirty when it differs.
  String _savedForm = '';
  String _savedCur = '';
  final Object _dirtyKey = Object();

  String get _farm => Uri.encodeComponent(widget.company.farmId);

  List<TextEditingController> get _controllers =>
      [_form.brand, _form.site, _form.town, _form.owner, _form.phone, _form.email, _form.crate, _form.capacity, _form.hours, _form.notes, _symbol];

  String get _formShape => jsonEncode(_form.payload()..remove('defaultCurrency'));
  String get _curShape => jsonEncode([_code, _symbol.text, _show]);
  bool get _dirty => !_loading && (_formShape != _savedForm || _curShape != _savedCur);

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.dispose();
    _symbol.dispose();
    _symbolFocus.dispose();
    super.dispose();
  }

  void _snapshot() {
    _savedForm = _formShape;
    _savedCur = _curShape;
  }

  Future<void> _load() async {
    Map? settings;
    try {
      final s = await widget.session.farmClient.get('/api/Water/farm-settings?farmId=$_farm');
      if (s is Map) settings = s;
    } catch (_) {}
    try {
      await loadPoultryProfile(widget.session, widget.company, _form);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load company settings. ${e.message}')));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (settings != null) {
        _code = '${settings['currencyCode'] ?? 'GHS'}';
        _symbol.text = '${settings['currencySymbol'] ?? _code}';
        _show = settings['showCurrencySymbol'] != false;
      } else if (_form.isSetUp && _form.currency.isNotEmpty) {
        // A company set up before the Farms row carried a currency: seed the
        // picker from the profile, as the web does.
        _code = _form.currency.toUpperCase();
        _symbol.text = currencySymbolFor(_code);
      }
      _loading = false;
      _snapshot();
    });
  }

  /// Back to what was loaded or last saved.
  void _discard() {
    final saved = jsonDecode(_savedForm) as Map<String, dynamic>;
    final cur = jsonDecode(_savedCur) as List;
    setState(() {
      // fill() also marks the row as loaded; keep whether it really exists.
      final profile = _form.profile;
      _form.fill({...saved, 'defaultCurrency': _form.currency});
      _form.profile = profile;
      _code = '${cur[0]}';
      _symbol.text = '${cur[1]}';
      _show = cur[2] == true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final created = !_form.isSetUp;
    try {
      // The Currency control is the single place currency is chosen; the
      // profile mirrors it so the two rows always agree.
      await savePoultryProfile(widget.session, widget.company, _form, {..._form.payload(), 'defaultCurrency': _code});
      final symbol = _symbol.text.trim().isNotEmpty ? _symbol.text.trim() : currencySymbolFor(_code);
      _symbol.text = symbol;
      messenger.showSnackBar(SnackBar(
          content: Text(created ? 'Poultry Company set up. Default cash accounts seeded.' : 'Company settings saved')));
      try {
        await widget.session.farmClient.put('/api/Water/farm-settings/currency?farmId=$_farm', body: {
          'currencyCode': _code,
          'currencySymbol': symbol,
          'showCurrencySymbol': _show,
        });
      } on ApiException {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Currency not applied app-wide. The profile saved, but the display currency could not be updated.')));
      }
      if (mounted) setState(_snapshot);
    } on ApiException catch (e) {
      // Keep what was typed so it can be fixed and tried again.
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    reportSetupDirty(context, _dirtyKey, dirty);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading…', style: TextStyle(color: _slate500)),
        ]),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final embedded = isSetupEmbedded(context);
    final f = _form;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(
        wide,
        'Business profile',
        "Your farm's name, owner and how customers and receipts reach you.",
        [
          _field('Farm / brand name', AppInput(controller: f.brand, hintText: 'e.g. Gyimah Farm')),
          _field('Owner name', AppInput(controller: f.owner)),
          _field('Phone', AppInput(controller: f.phone, hintText: '+233...', keyboardType: TextInputType.phone)),
          _field('Email', AppInput(controller: f.email, keyboardType: TextInputType.emailAddress)),
          _field('Main location / town', AppInput(controller: f.town)),
          _field('Farm site address', AppInput(controller: f.site)),
        ],
        first: true,
      ),
      _section(
        wide,
        'Farm details',
        'Flock type, housing and the defaults your production records start from.',
        [
          _field(
            'Business type',
            AppSelect<String>(
              key: const ValueKey('company-business-type'),
              value: f.businessType,
              items: [for (final t in poultryBusinessTypes) AppSelectItem(value: t, label: t)],
              onChanged: (v) => setState(() => f.businessType = v ?? f.businessType),
            ),
          ),
          _field(
            'Housing system',
            AppSelect<String>(
              value: f.housingSystem,
              items: [for (final e in poultryHousing.entries) AppSelectItem(value: e.key, label: e.value)],
              onChanged: (v) => setState(() => f.housingSystem = v ?? f.housingSystem),
            ),
          ),
          _field('Total capacity (birds)', AppNumberInput(controller: f.capacity, hintText: '')),
          _field('Eggs per crate', AppNumberInput(controller: f.crate)),
          _field('Operating hours', AppInput(controller: f.hours, hintText: 'e.g. 6:00 AM – 6:00 PM')),
        ],
      ),
      _section(
        wide,
        'Currency & time zone',
        'How money is shown on amounts, and the time zone your days and reports follow.',
        [
          _field(
            'Currency',
            // Picking fills the standard symbol; the symbol stays editable,
            // since many Ghanaian businesses write "GHC", not "₵".
            CurrencyPickerField(
              code: _code,
              onChanged: (o) => setState(() {
                _code = o.code;
                _symbol.text = o.symbol;
              }),
            ),
          ),
          _field(
            'Symbol',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppInput(
                key: const ValueKey('currency-symbol'),
                controller: _symbol,
                focusNode: _symbolFocus,
                hintText: currencySymbolFor(_code),
                inputFormatters: [LengthLimitingTextInputFormatter(10)],
              ),
              const SizedBox(height: 4),
              const Text('To hide it, turn off "Show symbol on amounts".', style: TextStyle(fontSize: 12, color: _slate500)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Tone.bg(0x99F8FAFC),
              border: Border.all(color: _slate200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AppSwitchRow(label: 'Show symbol on amounts', value: _show, onChanged: (v) => setState(() => _show = v)),
          ),
          // Saves itself with its own button, so it is not part of this
          // form's unsaved changes.
          CompanyTimeZoneField(session: widget.session, company: widget.company),
        ],
      ),
      _section(
        wide,
        'Notes',
        'Anything else you want kept on file for this company.',
        [AppTextarea(controller: f.notes, rows: 5)],
        last: true,
      ),
      const SizedBox(height: 16),
      // In Farm Setup, Save and Discard are on the task bar.
      if (embedded)
        SetupTaskBar(tasks: [
          SetupTask(
            id: 'save',
            label: _saving ? 'Saving…' : 'Save company settings',
            icon: Icons.save_outlined,
            primary: true,
            onTap: _save,
            disabled: !dirty || _saving,
          ),
          SetupTask(id: 'discard', label: 'Discard', icon: Icons.undo, onTap: _discard, disabled: _saving, hidden: !dirty),
        ])
      else
        _saveBar(dirty),
    ]);
  }

  /// The SaveBar on the form's own page.
  Widget _saveBar(bool dirty) => Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _slate100))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (dirty) ...[
            const Text('You have unsaved changes.', style: TextStyle(fontSize: 12, color: Tone.fg(0xFFB45309))),
            const SizedBox(height: 8),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: _saving || !dirty ? null : _discard, child: const Text('Discard')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving || !dirty ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(_saving ? 'Saving…' : 'Save company settings'),
            ),
          ]),
        ]),
      );

  Widget _field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
        const SizedBox(height: 6),
        child,
      ]);

  /// One section: heading and one line, then its fields. Wide: the heading in
  /// a left-hand column (240 px), the fields beside it.
  Widget _section(bool wide, String title, String blurb, List<Widget> fields, {bool first = false, bool last = false}) {
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
      const SizedBox(height: 4),
      Text(blurb, style: const TextStyle(fontSize: 13.5, height: 1.45, color: _slate500)),
    ]);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, w) in fields.indexed) ...[if (i > 0) const SizedBox(height: 16), w],
    ]);
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 24, bottom: last ? 0 : 24),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _slate100))),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 240, child: head),
              const SizedBox(width: 40),
              Expanded(child: body),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 16), body]),
    );
  }
}

const _slate100 = Tone.line(0xFFF1F5F9);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate500 = Tone.fg(0xFF64748B);
const _slate900 = Tone.fg(0xFF0F172A);
