import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../trackers/tracker_logic.dart' show tNum, tStr;
import '../trackers/tracker_widgets.dart';
import 'money_widgets.dart';

/// The Cash Account pages' dialogs, from `app/poultry-cash-accounts/page.tsx`,
/// `[id]/page.tsx` and `components/cash/record-cash-adjustment-dialog.tsx`.

const cashAccountTypes = ['FarmCashBox', 'OwnerCash', 'MoMoWallet', 'BankAccount', 'PettyCash', 'Other'];

/// POULTRY_CASH_REASONS — why the cash differed. Stored as text.
const cashReasons = [
  'Cash shortage', 'Cash overage', 'Bank charge', 'MoMo charge', 'Unrecorded expense', 'Unrecorded income',
  'Wrong cash account used', 'Owner draw not recorded', 'Owner contribution not recorded', 'Driver shortage',
  'Driver overage', 'Rounding difference', 'Opening balance correction', 'Other',
];

/// POULTRY_CASH_TRANSFER_REASONS — why money moves between the farm's own accounts.
const cashTransferReasons = [
  'Bank deposit', 'Bank withdrawal', 'MoMo cash-out', 'MoMo top-up', 'Driver float issued', 'Driver float returned',
  'Petty cash top-up', 'Funding payroll', 'Funding supplier payment', 'Consolidating balances', 'Safe keeping', 'Other',
];

const _sky600 = Color(0xFF0284C7);
const _blue600 = Color(0xFF2563EB);
const _indigo600 = Color(0xFF4F46E5);

Widget _numberField(TextEditingController c, VoidCallback changed) => AppInput(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
      onChanged: (_) => changed(),
    );

Widget _switchRow(String text, bool value, ValueChanged<bool> on) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: TColors.slate700))),
        Switch(value: value, onChanged: on),
      ]),
    );

Widget _dialogTitle(IconData icon, Color color, String text) => Row(children: [
      Icon(icon, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(text)),
    ]);

/// New cash account / Edit account.
class CashAccountFormDialog extends StatefulWidget {
  const CashAccountFormDialog({super.key, required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;

  @override
  State<CashAccountFormDialog> createState() => _CashAccountFormDialogState();
}

class _CashAccountFormDialogState extends State<CashAccountFormDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: tStr(_e?['accountName']));
  late final _notes = TextEditingController(text: tStr(_e?['notes']));
  final _opening = TextEditingController(text: '0');
  late String _type = tStr(_e?['accountType']).isEmpty ? 'FarmCashBox' : tStr(_e?['accountType']);
  late bool _allowNeg = _e?['allowNegativeBalance'] == true;
  late bool _active = _e == null ? true : _e['isActive'] == true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _notes, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    try {
      if (_e != null) {
        final id = tStr(_e['poultryCashAccountId']);
        await api.put('/api/Poultry/cash-accounts/$id', body: {
          'accountName': _name.text,
          'accountType': _type,
          'allowNegativeBalance': _allowNeg,
          'isActive': _active,
          'notes': _notes.text,
          'poultryCashAccountId': int.parse(id),
          'farmId': farmId,
        });
        if (mounted) trackerToast(context, 'Account updated');
      } else {
        await api.post('/api/Poultry/cash-accounts', body: {
          'accountName': _name.text,
          'accountType': _type,
          'openingBalance': num.tryParse(_opening.text) ?? 0,
          'allowNegativeBalance': _allowNeg,
          'notes': _notes.text,
          'farmId': farmId,
        });
        if (mounted) trackerToast(context, 'Account created');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _e != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: _dialogTitle(editing ? Icons.edit_outlined : Icons.account_balance_wallet_outlined, _blue600,
            editing ? 'Edit account' : 'New cash account'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Configure where cash flows into or out of', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Identity', _indigo600, [
              FilterLabel('Name *', AppInput(controller: _name)),
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  items: [for (final t in cashAccountTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              if (!editing) FilterLabel('Opening balance', _numberField(_opening, () => setState(() {}))),
            ]),
            const SizedBox(height: 12),
            formSection('Behavior', TColors.amber600, [
              FilterLabel('Allow negative balance',
                  _switchRow('Allow this account to go below zero', _allowNeg, (v) => setState(() => _allowNeg = v))),
              if (editing) FilterLabel('Active', _switchRow('Active', _active, (v) => setState(() => _active = v))),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [FilterLabel('Notes', AppInput(controller: _notes))]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}

/// Cash transfer (Draft → Approved): created, then approved in the same click.
class CashTransferQuickDialog extends StatefulWidget {
  const CashTransferQuickDialog({super.key, required this.session, required this.company, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> accounts;

  @override
  State<CashTransferQuickDialog> createState() => _CashTransferQuickDialogState();
}

class _CashTransferQuickDialogState extends State<CashTransferQuickDialog> {
  String _from = '0', _to = '0', _reason = '';
  final _amount = TextEditingController(text: '0');
  final _other = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _other.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_from == _to) return trackerToast(context, 'From and To must differ', error: true);
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'Amount required', error: true);
    if (_reason == 'Other' && _other.text.trim().isEmpty) return trackerToast(context, 'Say what happened', error: true);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    try {
      final res = await api.post('/api/Poultry/cash-transfers', body: {
        'fromPoultryCashAccountId': int.parse(_from),
        'toPoultryCashAccountId': int.parse(_to),
        'amount': amount,
        'notes': _reason == 'Other' ? _other.text.trim() : _reason,
        'farmId': farmId,
        'createdBy': widget.session.tokens.userId,
      });
      final id = res is Map ? tStr(res['poultryCashTransferId']) : '';
      await api.post('/api/Poultry/cash-transfers/$id/approve',
          query: {'farmId': farmId, 'approvedBy': widget.session.tokens.userId ?? ''});
      if (!mounted) return;
      trackerToast(context, 'Transfer approved');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Transfer failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    AppSelect<String> pick(String value, String hint, ValueChanged<String> on) => AppSelect<String>(
          value: active.any((a) => tStr(a['poultryCashAccountId']) == value) ? value : null,
          hintText: hint,
          items: [for (final a in active) AppSelectItem(value: tStr(a['poultryCashAccountId']), label: tStr(a['accountName']))],
          onChanged: (v) => setState(() => on(v ?? '0')),
        );
    return AlertDialog(
      scrollable: true,
      title: _dialogTitle(Icons.swap_horiz, _blue600, 'Cash transfer (Draft → Approved)'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Move funds between two cash accounts', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          formSection('Accounts', _indigo600, [
            FilterLabel('From', pick(_from, 'From account', (v) => _from = v)),
            FilterLabel('To', pick(_to, 'To account', (v) => _to = v)),
          ]),
          const SizedBox(height: 12),
          formSection('Amount', TColors.amber600, [
            FilterLabel('Amount', _numberField(_amount, () => setState(() {}))),
            FilterLabel(
              'Reason',
              AppSelect<String>(
                value: _reason.isEmpty ? null : _reason,
                hintText: 'Why is the money moving?',
                items: [for (final r in cashTransferReasons) AppSelectItem(value: r, label: r)],
                onChanged: (v) => setState(() {
                  _reason = v ?? '';
                  _other.clear();
                }),
              ),
            ),
            if (_reason == 'Other')
              FilterLabel('Say what happened *',
                  AppInput(controller: _other, autofocus: true, hintText: 'e.g. Moved to the depot safe overnight')),
          ]),
        ]),
      ),
      actions: [
        redCancelButton(() => Navigator.pop(context, false)),
        FilledButton(onPressed: _save, child: const Text('Create & approve')),
      ],
    );
  }
}

/// Record Cash Adjustment: the account is required; a shortage or overage is
/// steered to Reconcile instead.
class RecordCashAdjustmentDialog extends StatefulWidget {
  const RecordCashAdjustmentDialog({
    super.key,
    required this.session,
    required this.company,
    required this.accounts,
    required this.fmt,
  });
  final Session session;
  final Company company;
  final List<Map> accounts;
  final FarmMoney fmt;

  @override
  State<RecordCashAdjustmentDialog> createState() => _RecordCashAdjustmentDialogState();
}

class _RecordCashAdjustmentDialogState extends State<RecordCashAdjustmentDialog> {
  late final List<Map> _active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
  late String? _account = _active.length == 1 ? tStr(_active.first['poultryCashAccountId']) : null;
  String _direction = 'in', _reason = '';
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  num? get _value => num.tryParse(_amount.text);
  bool get _entered => _value != null && _value! > 0;
  bool get _needsNote => _reason == 'Other';
  bool get _steer => _reason == 'Cash shortage' || _reason == 'Cash overage';
  bool get _canSubmit =>
      _account != null && _entered && _reason.isNotEmpty && !_steer && (!_needsNote || _note.text.trim().isNotEmpty) && !_saving;
  num get _signed => _entered ? (_direction == 'out' ? -_value!.abs() : _value!.abs()) : 0;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final signed = _signed;
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/cash-accounts/$_account/adjust',
        query: {'farmId': widget.company.farmId},
        body: {'amount': signed, 'reason': _needsNote ? _note.text.trim() : _reason, 'createdBy': widget.session.tokens.userId},
      );
      if (!mounted) return;
      trackerToast(context, 'Adjustment recorded',
          description: '${widget.fmt(signed.abs())} ${_direction == 'out' ? 'removed from' : 'added to'} the account.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, "Couldn't record the adjustment", description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: _dialogTitle(Icons.balance, _sky600, 'Record Cash Adjustment'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Posts a cash transaction against one account. Balances are never edited directly.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Adjustment', _sky600, [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  'Cash account *',
                  AppSelect<String>(
                    value: _account,
                    hintText: 'Which account?',
                    items: [for (final a in _active) AppSelectItem(value: tStr(a['poultryCashAccountId']), label: tStr(a['accountName']))],
                    onChanged: (v) => setState(() => _account = v),
                  ),
                ),
                if (_active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('This company has no active cash account. Create one before recording an adjustment.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFBE123C))),
                  ),
              ]),
              FilterLabel(
                'Direction *',
                AppSelect<String>(
                  value: _direction,
                  items: const [
                    AppSelectItem(value: 'in', label: 'Add money (cash in)'),
                    AppSelectItem(value: 'out', label: 'Remove money (cash out)'),
                  ],
                  onChanged: (v) => setState(() => _direction = v ?? 'in'),
                ),
              ),
              FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  'Reason *',
                  AppSelect<String>(
                    value: _reason.isEmpty ? null : _reason,
                    hintText: 'Why is the balance changing?',
                    items: [for (final r in cashReasons) AppSelectItem(value: r, label: r)],
                    onChanged: (v) => setState(() {
                      _reason = v ?? '';
                      _note.clear();
                    }),
                  ),
                ),
                if (_needsNote) ...[
                  const SizedBox(height: 8),
                  AppInput(controller: _note, autofocus: true, hintText: 'Say what happened', onChanged: (_) => setState(() {})),
                ],
              ]),
            ]),
            if (_steer) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'A ${_reason.toLowerCase()} means reality disagreed with the books, and reconciling the account records that properly — with the balance you actually checked, the evidence, and the ability to reverse it. An adjustment here would move the balance and lose all of that.',
                    style: const TextStyle(fontSize: 12, color: TColors.amber900),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, false);
                      openAppHref(context, widget.session, widget.company, '/poultry-cash-reconciliation', label: 'Reconciliation');
                    },
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 14),
                    label: const Text('Reconcile this account'),
                  ),
                ]),
              ),
            ],
            if (_entered && !_steer) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'A ${_direction == 'out' ? 'money-out' : 'money-in'} transaction of ${widget.fmt(_signed.abs())} will be posted to this account. It appears in the ledger and can be reversed.',
                  style: const TextStyle(fontSize: 11.5, color: TColors.slate600),
                ),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_saving ? 'Saving…' : 'Record adjustment')),
        ],
      ),
    );
  }
}

/// The detail page's "Adjust balance": the new balance is shown before saving.
class AdjustBalanceDialog extends StatefulWidget {
  const AdjustBalanceDialog({super.key, required this.session, required this.company, required this.account, required this.fmt});
  final Session session;
  final Company company;
  final Map account;
  final FarmMoney fmt;

  @override
  State<AdjustBalanceDialog> createState() => _AdjustBalanceDialogState();
}

class _AdjustBalanceDialogState extends State<AdjustBalanceDialog> {
  String _direction = 'in', _reason = '';
  final _amount = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  num get _value => num.tryParse(_amount.text) ?? 0;

  Future<void> _save() async {
    if (_value <= 0) return trackerToast(context, 'Enter an amount greater than 0', error: true);
    if (_reason.isEmpty) return trackerToast(context, 'Pick a reason', error: true);
    if (_reason == 'Other' && _note.text.trim().isEmpty) return trackerToast(context, 'Say what happened', error: true);
    setState(() => _saving = true);
    final signed = _direction == 'out' ? -_value.abs() : _value.abs();
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/cash-accounts/${tStr(widget.account['poultryCashAccountId'])}/adjust',
        query: {'farmId': widget.company.farmId},
        body: {'amount': signed, 'reason': _reason == 'Other' ? _note.text.trim() : _reason, 'createdBy': widget.session.tokens.userId},
      );
      if (!mounted) return;
      trackerToast(context, 'Balance adjusted', description: '${_direction == 'out' ? 'Removed' : 'Added'} ${widget.fmt(_value)}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Adjustment failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final cur = tNum(widget.account['currentBalance']);
    final next = cur + (_direction == 'out' ? -_value.abs() : _value.abs());
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: _dialogTitle(Icons.balance, _sky600, 'Adjust balance'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Posts an adjustment transaction and moves the balance — it is never edited directly.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Adjustment', _indigo600, [
              FilterLabel(
                'Direction',
                AppSelect<String>(
                  value: _direction,
                  items: const [
                    AppSelectItem(value: 'in', label: 'Add money (cash in)'),
                    AppSelectItem(value: 'out', label: 'Remove money (cash out)'),
                  ],
                  onChanged: (v) => setState(() => _direction = v ?? 'in'),
                ),
              ),
              FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  'Reason *',
                  AppSelect<String>(
                    value: _reason.isEmpty ? null : _reason,
                    hintText: 'Why is the balance changing?',
                    items: [for (final r in cashReasons) AppSelectItem(value: r, label: r)],
                    onChanged: (v) => setState(() {
                      _reason = v ?? '';
                      _note.clear();
                    }),
                  ),
                ),
                if (_reason == 'Other') ...[
                  const SizedBox(height: 8),
                  AppInput(controller: _note, autofocus: true, hintText: 'Say what happened'),
                ],
              ]),
            ]),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'New balance will be '),
                TextSpan(text: fmt(next), style: const TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(text: ' (from ${fmt(cur)}).'),
              ]),
              style: const TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save adjustment')),
        ],
      ),
    );
  }
}
