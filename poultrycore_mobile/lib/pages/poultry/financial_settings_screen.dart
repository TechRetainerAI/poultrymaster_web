import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';

/// Poultry → Setup → Company → Financial Settings ("Cost Recognition"), as
/// `app/poultry-financial-settings/page.tsx`: when feed costs and when
/// medication costs reach Profit & Loss, chosen independently, with an
/// optional future start date. GET / PUT
/// `/Poultry/financial-settings/cost-recognition`.
///
/// As on the web: Save stays disabled until something differs, the warnings
/// appear only in front of a real change, and the deferral caveat only when
/// a choice moves TOWARDS deferral.
class FinancialSettingsScreen extends StatefulWidget {
  const FinancialSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FinancialSettingsScreen> createState() => _FinancialSettingsScreenState();
}

// lib/poultry/cost-recognition.ts
const purchased = 'EXPENSE_WHEN_PURCHASED';
const consumed = 'EXPENSE_WHEN_CONSUMED';
const _methods = [purchased, consumed];
const _label = {purchased: 'Expense when purchased', consumed: 'Expense when consumed'};
const _help = {
  purchased: 'The purchase cost is recognised in Profit & Loss straight away. Inventory quantity is '
      'still tracked, and using the item later does not create another expense.',
  consumed: 'The purchase is held as inventory value first. The cost reaches Profit & Loss later, '
      'as the item is used.',
};
const _feedHint = {
  purchased: 'Simpler. Suits farms that buy feed often and use it quickly.',
  consumed: 'More precise. Feed and raw-material costs affect Profit & Loss as stock is used.',
};
const _medHint = {
  purchased: 'Simpler. Recognise the cost when you buy, while still tracking what is left.',
  consumed: 'More precise. Recognise the cost as recorded usage reduces stock.',
};
const _changeWarning = 'This applies to new purchases from now on. Purchases already recorded keep '
    'the treatment they were created with, so past reports do not change.';
const _deferredNote = 'A deferred purchase holds its cost as inventory value and reaches Profit & Loss '
    'as you record usage of the stock. Feed production carries the cost into the feed it makes, so '
    'nothing is expensed twice.';

class _FinancialSettingsScreenState extends State<FinancialSettingsScreen> {
  Map? _saved;
  String _feed = purchased;
  String _medication = purchased;
  DateTime? _from;
  bool _loading = true;
  bool _saving = false;

  String get _path =>
      '/api/Poultry/financial-settings/cost-recognition?farmId=${Uri.encodeComponent(widget.company.farmId)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _day(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _savedDay(Map? s) => '${s?['effectiveFromDate'] ?? ''}'.split('T').first;

  void _apply(Map s) {
    _saved = s;
    _feed = '${s['feedCostRecognitionMethod'] ?? purchased}';
    _medication = '${s['medicationCostRecognitionMethod'] ?? purchased}';
    _from = DateTime.tryParse(_savedDay(s));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await widget.session.farmClient.get(_path);
      if (s is Map) _apply(s);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load financial settings. ${e.message}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _dirty {
    final s = _saved;
    if (s == null) return false;
    return _feed != '${s['feedCostRecognitionMethod']}' ||
        _medication != '${s['medicationCostRecognitionMethod']}' ||
        _day(_from) != _savedDay(s);
  }

  bool get _turningOnDeferral =>
      (_feed == consumed && '${_saved?['feedCostRecognitionMethod']}' != consumed) ||
      (_medication == consumed && '${_saved?['medicationCostRecognitionMethod']}' != consumed);

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await widget.session.farmClient.put(_path, body: {
        'feedCostRecognitionMethod': _feed,
        'medicationCostRecognitionMethod': _medication,
        'effectiveFromDate': _from == null ? null : _day(_from),
        'farmId': widget.company.farmId,
        'updatedBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      setState(() {
        if (s is Map) _apply(s);
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Cost recognition saved. New purchases from now on use these settings. '
              'Existing purchases are unchanged.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save. ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-financial-settings');
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cost Recognition')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                Text(
                  'Choose when inventory costs affect Profit & Loss. Physical stock is tracked either way — '
                  'this only decides when a cost counts as a cost.',
                  style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                ),
                const SizedBox(height: 12),
                // Never present a default as though somebody chose it.
                if (_saved?['isConfigured'] != true) ...[
                  const _Note(
                    color: Color(0xFFE0F2FE), // sky-50
                    border: Color(0xFFBAE6FD), // sky-200
                    fg: Color(0xFF0C4A6E), // sky-900
                    icon: Icons.info_outline,
                    text: 'Nobody has set this up yet, so both are on the standard treatment: costs reach '
                        'Profit & Loss as you pay for them. Nothing changes until you save something '
                        'different here.',
                  ),
                  const SizedBox(height: 12),
                ],
                _MethodSection(
                  icon: const Icon(Icons.grass, color: Color(0xFFD97706)),
                  title: 'Feed & Feed Raw Materials',
                  blurb: 'Feed ingredients, finished feed and grain.',
                  value: _feed,
                  hints: _feedHint,
                  onChanged: (m) => setState(() => _feed = m),
                ),
                const SizedBox(height: 12),
                _MethodSection(
                  icon: const Icon(Icons.medication_outlined, color: Color(0xFFE11D48)),
                  title: 'Medication',
                  blurb: 'Drugs and vaccines. Independent of the feed setting above — one can defer while '
                      'the other does not.',
                  value: _medication,
                  hints: _medHint,
                  onChanged: (m) => setState(() => _medication = m),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Start from (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: AppDateField(
                              value: _from,
                              hintText: 'Apply immediately',
                              // A past date is refused, as on the web.
                              firstDate: DateTime(now.year, now.month, now.day),
                              onChanged: (d) => setState(() => _from = d),
                            ),
                          ),
                          if (_from != null)
                            IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _from = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Leave blank to apply immediately. A future date holds the change until then. A past '
                        'date is refused — purchases already recorded keep the treatment they were created '
                        'with, so backdating could not change them anyway.',
                        style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                      ),
                      if (_saved?['isConfigured'] == true) ...[
                        const Divider(height: 20),
                        Text(
                          'Last changed'
                          '${_saved?['updatedAt'] != null ? ' on ${'${_saved!['updatedAt']}'.replaceFirst('T', ' ').split('.').first}' : ''}'
                          '${_saved?['updatedBy'] != null ? ' by ${_saved!['updatedBy']}' : ''}.',
                          style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_dirty) ...[
                  const SizedBox(height: 12),
                  const _Note(
                    color: Color(0xFFFFFBEB), // amber-50
                    border: Color(0xFFFDE68A), // amber-200
                    fg: Color(0xFF78350F), // amber-900
                    icon: Icons.warning_amber_rounded,
                    text: _changeWarning,
                  ),
                  if (_turningOnDeferral) ...[
                    const SizedBox(height: 8),
                    const _Note(
                      color: Color(0xFFFFFBEB),
                      border: Color(0xFFFDE68A),
                      fg: Color(0xFF78350F),
                      icon: Icons.warning_amber_rounded,
                      text: _deferredNote,
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: _saving ? 'Saving…' : 'Save changes',
                        icon: Icons.save_outlined,
                        size: AppButtonSize.lg,
                        fullWidth: true,
                        busy: _saving,
                        onPressed: !_dirty || _saving ? null : _save,
                      ),
                    ),
                    if (_dirty) ...[
                      const SizedBox(width: 12),
                      AppButton(
                        label: 'Discard',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.lg,
                        onPressed: _saving ? null : _load,
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// One choice: two radio cards, the selected one ringed in emerald.
class _MethodSection extends StatelessWidget {
  const _MethodSection({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.value,
    required this.hints,
    required this.onChanged,
  });
  final Widget icon;
  final String title;
  final String blurb;
  final String value;
  final Map<String, String> hints;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            icon,
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text(blurb, style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
          const SizedBox(height: 10),
          for (final m in _methods) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(m),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: value == m ? const Color(0xFFECFDF5) : null, // emerald-50
                  border: Border.all(color: value == m ? const Color(0xFF10B981) : tokens.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(value == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18, color: value == m ? const Color(0xFF059669) : tokens.mutedForeground),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(_label[m]!, style: const TextStyle(fontWeight: FontWeight.w500)),
                            if (m == purchased) const AppBadge(label: 'Current standard'),
                          ]),
                          const SizedBox(height: 2),
                          Text(hints[m]!, style: TextStyle(fontSize: 12, color: tokens.cardForeground)),
                          const SizedBox(height: 4),
                          Text(_help[m]!, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.border, required this.fg, required this.icon, required this.text});
  final Color color;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
          ],
        ),
      );
}
