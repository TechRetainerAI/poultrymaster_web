import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../shared/business_dates.dart';
import '../sales/balances_logic.dart' show entryTimestamp;
import '../trackers/tracker_widgets.dart';

/// ADJUSTMENT_TYPES, stored as text — keep stable.
const adjustmentTypes = [
  ('OpeningBalance', 'Opening Balance'),
  ('OwnerInjection', 'Owner injection'),
  ('LoanReceived', 'Loan received'),
  ('Withdrawal', 'Withdrawal'),
  ('Correction', 'Correction'),
];

/// adjustmentTypeFromLabel: the API hands back the label, an edit needs the value.
String adjustmentTypeFromLabel(Object? label) {
  final l = '${label ?? ''}'.trim().toLowerCase();
  for (final (v, lab) in adjustmentTypes) {
    if (lab.toLowerCase() == l) return v;
  }
  return '';
}

class CashAdjustmentSeed {
  const CashAdjustmentSeed({
    required this.adjustmentId,
    required this.adjustmentType,
    required this.adjustmentDate,
    required this.amount,
    required this.description,
  });
  final int adjustmentId;
  final String adjustmentType;
  final String adjustmentDate;

  /// SIGNED, as stored.
  final num amount;
  final String description;
}

typedef AdjustableAccount = ({int accountId, String accountName, bool isActive});

typedef AdjustmentInput = ({
  int? accountId,
  String adjustmentType,
  String adjustmentDate,
  num amount,
  String description,
  String? lenderName,
  String? ownerName,
});

/// `components/cash/cash-adjustment-dialog.tsx`: Add / Edit Adjustment with an
/// OPTIONAL cash account (required only for owner money). [onSubmit] does the
/// posting; this dialog says where it lands and toasts the outcome. Pops true
/// when saved.
class CashAdjustmentDialog extends StatefulWidget {
  const CashAdjustmentDialog({
    super.key,
    required this.accounts,
    required this.fmtMoney,
    required this.onSubmit,
    this.editing,
  });
  final List<AdjustableAccount> accounts;
  final String Function(num) fmtMoney;
  final CashAdjustmentSeed? editing;
  final Future<void> Function(AdjustmentInput input) onSubmit;

  @override
  State<CashAdjustmentDialog> createState() => _CashAdjustmentDialogState();
}

class _CashAdjustmentDialogState extends State<CashAdjustmentDialog> {
  String _account = 'none';
  String _type = '';
  late String _when;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _lender = TextEditingController();
  final _owner = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (e != null) {
      _type = e.adjustmentType;
      _when = (e.adjustmentDate.isEmpty ? today : e.adjustmentDate).split('T').first;
      final a = e.amount.abs();
      _amount.text = a == a.roundToDouble() ? a.toInt().toString() : '$a';
      _desc.text = e.description;
    } else {
      _when = today;
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _desc, _lender, _owner]) {
      c.dispose();
    }
    super.dispose();
  }

  List<AdjustableAccount> get _active => [for (final a in widget.accounts) if (a.isActive) a];
  num? get _value => num.tryParse(_amount.text);
  bool get _entered => _value != null && _value! > 0;
  num get _signed => _entered && _type.isNotEmpty ? (_type == 'Withdrawal' ? -_value!.abs() : _value!.abs()) : 0;
  bool get _linked => _account != 'none';
  bool get _asLoan => widget.editing == null && _type == 'LoanReceived';
  bool get _lenderMissing => _asLoan && _signed > 0 && _lender.text.trim().isEmpty;
  bool get _asOwnerMoney => widget.editing == null && (_type == 'OwnerInjection' || _type == 'Withdrawal');
  bool get _accountMissing => _asOwnerMoney && !_linked;
  bool get _canSubmit => _type.isNotEmpty && _entered && !_lenderMissing && !_accountMissing && !_saving;
  String get _accountName =>
      _active.where((a) => '${a.accountId}' == _account).firstOrNull?.accountName ?? 'the account';

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final signed = _signed;
    final fmt = widget.fmtMoney;
    final owner = _owner.text.trim();
    final editing = widget.editing != null;
    try {
      await widget.onSubmit((
        accountId: _linked ? int.parse(_account) : null,
        adjustmentType: _type,
        adjustmentDate: entryTimestamp(_when) ?? _when,
        amount: signed,
        description: _desc.text.trim(),
        lenderName: _asLoan && signed > 0 ? _lender.text.trim() : null,
        ownerName: _asOwnerMoney ? (owner.isEmpty ? null : owner) : null,
      ));
      if (!mounted) return;
      final title = _asLoan && signed > 0
          ? 'Loan recorded'
          : _asOwnerMoney
              ? (signed < 0 ? 'Withdrawal recorded' : 'Owner injection recorded')
              : editing && _linked
                  ? 'Adjustment linked'
                  : editing
                      ? 'Adjustment updated'
                      : 'Adjustment recorded';
      final desc = _asLoan && signed > 0
          ? '${fmt(signed)} borrowed from ${_lender.text.trim()}. It is on your Loans page, where you can record repayments against it.'
          : _asOwnerMoney
              ? '${fmt(signed.abs())} ${signed < 0 ? 'taken out of' : 'put into'} $_accountName by ${owner.isEmpty ? 'the owner' : owner}. It is on your Owner Money page.'
              : editing && _linked
                  ? '${fmt(signed.abs())} now sits in $_accountName.'
                  : _linked
                      ? '${fmt(signed.abs())} ${signed < 0 ? 'removed from' : 'added to'} $_accountName.'
                      : "${fmt(signed.abs())} recorded. It counts toward Cash Flow's totals and Cash at Hand, but sits in no account balance until you link it.";
      trackerToast(context, title, description: desc);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(
          context,
          _asLoan && signed > 0
              ? "Couldn't record the loan"
              : _asOwnerMoney
                  ? "Couldn't record the owner money"
                  : editing && _linked
                      ? "Couldn't link the adjustment"
                      : editing
                          ? "Couldn't update the adjustment"
                          : "Couldn't record the adjustment",
          description: e.message,
          error: true);
    }
  }

  Widget _section(String title, Color band, List<Widget> children) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: band,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
            ]),
          ),
        ]),
      );

  Widget _hint(String text, Color color) =>
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: TextStyle(fontSize: 11, color: color)));

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmtMoney;
    final signed = _signed;
    final editing = widget.editing != null;
    final acc = _active.where((a) => '${a.accountId}' == _account).firstOrNull?.accountName;

    String? landing;
    if (_entered && _type.isNotEmpty) {
      if (_asLoan && signed > 0) {
        final lender = _lender.text.trim().isEmpty ? 'the lender' : _lender.text.trim();
        landing = '${fmt(signed)} will be recorded as a loan you can repay, not just a cash entry — it appears on your Loans page with $lender against it. '
            '${_linked ? 'The money lands in $acc, moving its balance.' : 'Cash Flow counts the money in; no account balance changes until you link it.'}';
      } else if (_asOwnerMoney) {
        final owner = _owner.text.trim();
        landing = '${fmt(signed.abs())} will be recorded as owner money, not just a cash entry — ${signed < 0 ? 'a draw' : 'a contribution'} on your Owner Money page'
            '${owner.isNotEmpty ? ' from $owner' : ''}. '
            '${_linked ? 'The money moves ${signed < 0 ? 'out of' : 'into'} $acc, changing its balance, and Cash Flow counts it once.' : 'Pick the cash account it moved through first — owner money is recorded against one.'}';
      } else if (_linked && editing) {
        landing = '${fmt(signed.abs())} will be moved ${signed < 0 ? 'out of' : 'into'} $acc and the unlinked copy removed, so it is counted once. The account balance moves.';
      } else if (_linked) {
        landing = '${fmt(signed.abs())} will be posted ${signed < 0 ? 'out of' : 'into'} $acc, moving its balance. It appears in the ledger and can be reversed.';
      } else {
        landing = '${fmt(signed.abs())} will be recorded without a cash account. Cash Flow counts it in Money In/Out and Cash at Hand, but no account balance changes until you link it.';
      }
    }

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.add, color: TColors.emerald600),
          const SizedBox(width: 6),
          Flexible(child: Text(editing ? 'Edit Adjustment' : 'Add Adjustment')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Opening balance, owner injection, loan received, withdrawal or correction.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            _section('Adjustment', TColors.emerald600, [
              FilterLabel(
                'Type *',
                AppSelect<String>(
                  value: _type.isEmpty ? null : _type,
                  hintText: 'What kind of adjustment?',
                  items: [for (final (v, l) in adjustmentTypes) AppSelectItem(value: v, label: l)],
                  onChanged: (v) => setState(() => _type = v ?? ''),
                ),
              ),
              FilterLabel(
                'Date *',
                AppDateField(
                  value: businessDateAsDateTime(_when),
                  onChanged: (d) => setState(() => _when = d == null ? _when : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  hintText: '0',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  _asOwnerMoney ? 'Cash account *' : 'Cash account',
                  AppSelect<String>(
                    value: _account,
                    items: [
                      const AppSelectItem(value: 'none', label: 'Not linked to an account'),
                      for (final a in _active) AppSelectItem(value: '${a.accountId}', label: a.accountName),
                    ],
                    onChanged: (v) => setState(() => _account = v ?? 'none'),
                  ),
                ),
                if (_accountMissing)
                  _hint(
                      _type == 'Withdrawal'
                          ? 'Say which account the money came out of — owner money is recorded against a real account.'
                          : 'Say which account the money went into — owner money is recorded against a real account.',
                      TColors.rose600),
                if (editing && _linked)
                  _hint('This moves the adjustment into the account ledger. It cannot be changed back to unlinked afterwards.',
                      TColors.amber700),
              ]),
              if (_asLoan)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilterLabel('Lender *',
                      AppInput(controller: _lender, hintText: 'Who lent the money?', onChanged: (_) => setState(() {}))),
                  if (_lenderMissing) _hint('A loan needs a lender before it can be recorded.', TColors.rose600),
                ]),
              if (_asOwnerMoney)
                FilterLabel(
                  'Owner name (optional)',
                  AppInput(
                    controller: _owner,
                    hintText: _type == 'Withdrawal' ? 'Who took it?' : 'Who put it in?',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            _section('Description', TColors.slate600, [
              FilterLabel('Description (optional)', AppInput(controller: _desc, hintText: 'e.g. Start of cycle')),
            ]),
            if (landing != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: TColors.slate50,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(landing, style: const TextStyle(fontSize: 11.5, color: TColors.slate600)),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(_saving
                ? 'Saving…'
                : _asLoan && signed > 0
                    ? 'Record loan'
                    : _asOwnerMoney
                        ? (signed < 0 ? 'Record withdrawal' : 'Record injection')
                        : editing && _linked
                            ? 'Link to account'
                            : editing
                                ? 'Update adjustment'
                                : 'Save adjustment'),
          ),
        ],
      ),
    );
  }
}
