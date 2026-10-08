import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../shared/business_dates.dart';
import '../sales/balances_logic.dart' show entryTimestamp;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'money_widgets.dart';

/// `components/cash/loan-repayment-dialog.tsx`, the Loans-page way in: the
/// loan is already chosen. A repayment is never one number — the dialog asks
/// for principal, interest, fees and other, and SHOWS the total.

const repaymentMethods = ['Cash', 'BankTransfer', 'MoMo', 'Cheque', 'Card', 'Other'];

/// isRepayableLoan: a real loan record, Active or Overdue, with debt left.
/// A Cash-Flow "Loan received" row (source CashAdjustment, id 0) never is.
bool isRepayableLoan(Map l) {
  if ((tStr(l['source']).isEmpty ? 'Loan' : tStr(l['source'])) != 'Loan') return false;
  if ((tIntOrNull(l['poultryLoanId']) ?? 0) == 0) return false;
  final st = tStr(l['status']);
  if (st != 'Active' && st != 'Overdue') return false;
  return tNum(l['outstandingPrincipal']) > 0;
}

typedef LoanRepaymentInput = ({
  int loanId,
  int accountId,
  num principalAmount,
  num interestAmount,
  num feeAmount,
  num otherAmount,
  String? paymentDate,
  String? paymentMethod,
  String? referenceNumber,
  String? notes,
  String? nextPaymentDate,
});

class LoanRepaymentDialog extends StatefulWidget {
  const LoanRepaymentDialog({
    super.key,
    required this.loan,
    required this.accounts,
    required this.fmtMoney,
    required this.onSubmit,
    this.entityLabel = 'business',
  });

  /// The loan row (PoultryLoan).
  final Map loan;

  /// PoultryCashAccount rows.
  final List<Map> accounts;
  final String Function(num) fmtMoney;
  final String entityLabel;
  final Future<void> Function(LoanRepaymentInput input) onSubmit;

  @override
  State<LoanRepaymentDialog> createState() => _LoanRepaymentDialogState();
}

class _LoanRepaymentDialogState extends State<LoanRepaymentDialog> {
  final _principal = TextEditingController(text: '0');
  final _interest = TextEditingController(text: '0');
  final _fee = TextEditingController(text: '0');
  final _other = TextEditingController(text: '0');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  late String _account = (tIntOrNull(widget.loan['poultryCashAccountId']) ?? 0) > 0 ? tStr(widget.loan['poultryCashAccountId']) : '';
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String _next = '';
  String _method = 'BankTransfer';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_principal, _interest, _fee, _other, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _selected => isRepayableLoan(widget.loan) ? widget.loan : null;
  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;
  num get _total => _n(_principal) + _n(_interest) + _n(_fee) + _n(_other);
  num get _cost => _n(_interest) + _n(_fee);
  num get _owed => tNum(_selected?['outstandingPrincipal']);
  num get _after => _selected == null ? 0 : _owed - _n(_principal);
  Map? get _acc => widget.accounts.where((a) => tStr(a['poultryCashAccountId']) == _account).firstOrNull;
  bool get _overdraw =>
      _account.isNotEmpty && _total > 0 && tNum(_acc?['currentBalance']) - _total < 0 && _acc?['allowNegativeBalance'] != true;

  String _label(Map l) {
    final n = tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tStr(l['poultryLoanId'])}';
    return '$n · ${tStr(l['lenderName']).isEmpty ? '–' : tStr(l['lenderName'])}';
  }

  Future<void> _save() async {
    final sel = _selected;
    if (sel == null) return trackerToast(context, 'Pick a loan', error: true);
    if (_account.isEmpty) return trackerToast(context, 'Pick a cash account', error: true);
    if (_total <= 0) return trackerToast(context, 'Enter the repayment', error: true);
    if (_n(_principal) > _owed) return trackerToast(context, 'Principal is more than is owed', error: true);
    setState(() => _saving = true);
    final fmt = widget.fmtMoney;
    final total = _total, cost = _cost;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await widget.onSubmit((
        loanId: tIntOrNull(sel['poultryLoanId'])!,
        accountId: int.parse(_account),
        principalAmount: _n(_principal),
        interestAmount: _n(_interest),
        feeAmount: _n(_fee),
        otherAmount: _n(_other),
        paymentDate: entryTimestamp(_date),
        paymentMethod: _method.isEmpty ? null : _method,
        referenceNumber: opt(_ref),
        notes: opt(_notes),
        nextPaymentDate: _next.isEmpty ? null : _next,
      ));
      if (!mounted) return;
      trackerToast(context, 'Repayment recorded',
          description: cost > 0
              ? '${fmt(total)} left the account; only ${fmt(cost)} of it is a cost.'
              : '${fmt(total)} off the debt. None of it is an expense.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record the repayment', description: e.message, error: true);
    }
  }

  Widget _money(String label, TextEditingController c, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(
          label,
          AppInput(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (hint != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
      ]);

  Widget _line(String label, Widget value, {bool top = false}) => Container(
        padding: EdgeInsets.only(top: top ? 4 : 0),
        decoration: top ? const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200))) : null,
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          Flexible(child: Align(alignment: Alignment.centerRight, child: value)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmtMoney;
    final sel = _selected;
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    final blocked = _saving || sel == null || _total <= 0 || _after < 0 || _overdraw;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.payments_outlined, color: Color(0xFF7C3AED)),
          SizedBox(width: 6),
          Flexible(child: Text('Record a Repayment')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Split the payment into what it was actually for. The total is worked out for you — only the interest and the fees are a cost to the ${widget.entityLabel}.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Loan', TColors.slate600, [
              sel != null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_label(sel), style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Still owed ${fmt(_owed)}', style: const TextStyle(color: TColors.slate600)),
                    ])
                  : const Text(
                      'This borrowing was recorded as a cash adjustment, not a loan, so there is nothing here to repay against.',
                      style: TextStyle(fontSize: 13, color: TColors.slate600)),
            ]),
            if (sel != null) ...[
              const SizedBox(height: 12),
              formSection('What the payment is for', const Color(0xFF7C3AED), [
                _money('Principal', _principal, hint: 'Off the debt. Not an expense.'),
                _money('Interest', _interest, hint: 'A cost. Reaches the P&L.'),
                _money('Fees', _fee, hint: 'Also a cost.'),
                _money('Other', _other),
              ]),
              const SizedBox(height: 12),
              formSection('What this does', TColors.slate600, [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _line('Leaves the account', Text(fmt(_total), style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(height: 4),
                  _line('Of which a cost', Text(fmt(_cost), style: const TextStyle(color: TColors.amber700))),
                  const SizedBox(height: 4),
                  _line(
                    'Debt after',
                    Text.rich(TextSpan(children: [
                      TextSpan(text: fmt(_owed), style: const TextStyle(color: TColors.slate400)),
                      const TextSpan(text: ' → '),
                      TextSpan(text: fmt(_after < 0 ? 0 : _after), style: const TextStyle(fontWeight: FontWeight.w500)),
                    ])),
                    top: true,
                  ),
                  if (_after == 0 && _n(_principal) > 0)
                    const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('This clears the loan.', style: TextStyle(fontSize: 12, color: TColors.emerald700))),
                  if (_after < 0)
                    const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('That is more principal than is still owed.', style: TextStyle(fontSize: 12, color: TColors.rose600))),
                  if (_overdraw)
                    const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('The account does not hold this much and cannot go negative.',
                            style: TextStyle(fontSize: 12, color: TColors.rose600))),
                ]),
              ]),
              const SizedBox(height: 12),
              formSection('Payment details', const Color(0xFF2563EB), [
                FilterLabel(
                  'Paid from *',
                  AppSelect<String>(
                    value: _account.isEmpty ? null : _account,
                    hintText: 'Which account?',
                    items: [
                      for (final a in active)
                        AppSelectItem(
                          value: tStr(a['poultryCashAccountId']),
                          label: '${tStr(a['accountName'])} — ${fmt(tNum(a['currentBalance']))}',
                        ),
                    ],
                    onChanged: (v) => setState(() => _account = v ?? ''),
                  ),
                ),
                FilterLabel(
                  'Date',
                  AppDateField(
                    value: businessDateAsDateTime(_date),
                    onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                  ),
                ),
                FilterLabel(
                  'Next payment due',
                  AppDateField(
                    value: _next.isEmpty ? null : businessDateAsDateTime(_next),
                    hintText: 'dd/mm/yyyy',
                    onChanged: (d) => setState(() => _next = d == null ? '' : isoDay(d)),
                  ),
                ),
                FilterLabel(
                  'Method',
                  AppSelect<String>(
                    value: _method,
                    items: [for (final m in repaymentMethods) AppSelectItem(value: m, label: m)],
                    onChanged: (v) => setState(() => _method = v ?? 'BankTransfer'),
                  ),
                ),
                FilterLabel('Reference', AppInput(controller: _ref)),
                FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
              ]),
            ],
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: blocked ? null : _save,
            child: Text(_saving ? 'Recording...' : 'Record ${fmt(_total)}'),
          ),
        ],
      ),
    );
  }
}
