// lib/reversal-reasons.ts and components/ui/reason-select.tsx: every reverse,
// cancel, reopen or refund picks its reason from a list, and "Other" opens a
// text box for the user's own words. The chosen value is what is stored, so the
// wording here IS the stored vocabulary — keep it the same as the web's.

import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';

/// Money entries: payments, refunds, transfers, owner money, debts, loans.
const reversalReasons = [
  'Duplicate entry',
  'Wrong amount',
  'Wrong date',
  'Wrong account',
  'Wrong customer or supplier',
  'Posted by mistake',
  'Test or training entry',
  'Other',
];

/// Stock movements, receipts and production postings.
const stockReversalReasons = [
  'Duplicate entry',
  'Wrong quantity',
  'Wrong product',
  'Wrong date',
  'Wrong flock or batch',
  'Posted by mistake',
  'Test or training entry',
  'Other',
];

/// Capital assets: capitalised costs, depreciation, in-service changes.
const assetReversalReasons = [
  'Duplicate entry',
  'Wrong amount',
  'Wrong asset',
  'Wrong month',
  'Posted by mistake',
  'Test or training entry',
  'Other',
];

/// Cash counts and cash account adjustments.
const cashCountReversalReasons = [
  'Miscounted',
  'Counted the wrong account',
  'Wrong amount entered',
  'Wrong date',
  'Duplicate count',
  'Cash located afterwards',
  'Posted by mistake',
  'Other',
];

/// Cancelling a draft, a run, a schedule or a campaign.
const cancelReasons = [
  'Created by mistake',
  'Duplicate entry',
  'Wrong details',
  'No longer needed',
  'Plans changed',
  'Test or training entry',
  'Other',
];

/// Reopening a closed day, an approved payroll run or a record.
const reopenReasons = [
  'Correction needed',
  'Missing entry to add',
  'Wrong amount',
  'Wrong date',
  'Document arrived late',
  'Closed too early',
  'Other',
];

/// Reopening a closed flock.
const flockReopenReasons = [
  'Closed by mistake',
  'Birds still on the farm',
  'Late sale or record to enter',
  'Wrong close date',
  'Wrong closing figures',
  'Other',
];

/// Reopening a lifecycle task.
const taskReopenReasons = [
  'Marked done by mistake',
  'Task not actually done',
  'Needs to be done again',
  'Other',
];

/// Loans and staff advances.
const loanReversalReasons = [
  'Duplicate entry',
  'Wrong amount',
  'Wrong date',
  'Wrong employee or lender',
  'Wrong account',
  'Posted by mistake',
  'Other',
];

/// Rejecting a submitted daily closing or stock adjustment.
const rejectReasons = [
  'Figures do not match',
  'Cash difference not explained',
  'Missing entries',
  'Wrong date',
  'Needs more detail',
  'Other',
];

/// Turning down a guest's online order (ORDER_REJECT_REASONS).
const orderRejectReasons = [
  'Item not available',
  'Kitchen is closed',
  'Kitchen is too busy right now',
  'Outside our delivery area',
  'Could not reach you',
  'Duplicate order',
  'Other',
];

/// Refunding a restaurant order (ORDER_REFUND_REASONS).
const orderRefundReasons = [
  'Wrong dish served',
  'Item not available',
  'Quality complaint',
  'Long wait',
  'Overcharged',
  'Order cancelled',
  'Other',
];

/// Skipping a scheduled task or a recurring expense this time.
const skipReasons = [
  'Not needed this time',
  'Already done another way',
  'Postponed',
  'Supplier or service not available',
  'Other',
];

/// Ending a recurring expense.
const endReasons = [
  'No longer needed',
  'Contract ended',
  'Replaced by another arrangement',
  'Paying it differently now',
  'Other',
];

/// Unapproving an approved record (Water loss records).
const unapproveReasons = [
  'Wrong quantity',
  'Wrong cause',
  'Wrong date',
  'Approved by mistake',
  'Other',
];

/// Adjusting stock by hand.
const stockAdjustmentReasons = [
  'Stocktake correction',
  'Damaged',
  'Expired',
  'Spoiled',
  'Theft or missing',
  'Found extra stock',
  'Opening stock',
  'Data entry correction',
  'Other',
];

/// Recording a loss.
const lossReasons = [
  'Damaged',
  'Spoiled',
  'Expired',
  'Breakage',
  'Spillage or leak',
  'Pest damage',
  'Theft',
  'Other',
];

/// Why a treatment campaign is run.
const treatmentReasons = [
  'Routine vaccination',
  'Vet diagnosis',
  'Disease outbreak',
  'Preventive treatment',
  'Deworming',
  'Vitamins or supplements',
  'Other',
];

/// Adjusting a sized-egg class by hand.
const eggAdjustmentReasons = [
  'Tray dropped',
  'Breakage found',
  'Miscount',
  'Spoiled',
  'Found extra eggs',
  'Other',
];

/// Correcting an asset's original cost.
const costCorrectionReasons = [
  'Wrong amount entered',
  'Supplier invoice corrected',
  'Missing cost added',
  'Duplicate cost removed',
  'Other',
];

/// Recording a manual deferred cost on stock no purchase covers.
const deferredCostReasons = [
  'Stock on hand before using the system',
  'Opening stock cost',
  'Cost not captured on the purchase',
  'Correction',
  'Other',
];

/// Refunding a customer's credit.
const customerRefundReasons = [
  'Customer asked for their money',
  'Overpayment returned',
  'Order cancelled',
  'Customer no longer buying',
  'Other',
];

/// A supplier refunding our credit.
const supplierRefundReasons = [
  'Unused advance returned',
  'Overpayment returned',
  'Order cancelled',
  'Goods returned',
  'Other',
];

/// Customer credit added by hand, by kind.
const customerCreditReasons = {
  'OpeningCredit': ['Balance carried from old books', 'Prepaid balance', 'Other'],
  'Deposit': ['Advance for next order', 'Prepayment for a bulk order', 'Deposit to hold an order', 'Other'],
  'CreditNote': ['Damaged goods', 'Short delivery', 'Returned goods', 'Price adjustment', 'Goodwill', 'Other'],
};

/// Supplier credit added by hand (credit note, opening or manual credit).
const supplierCreditReasons = [
  'Short delivery',
  'Damaged goods',
  'Returned goods',
  'Price adjustment',
  'Balance carried from old books',
  'Other',
];

/// Changing the billing market.
const marketChangeReasons = [
  'Business relocated',
  'Wrong country was set',
  'Billing currency change',
  'Other',
];

/// Explaining a cash difference at closing.
const cashDifferenceReasons = [
  'Miscount',
  'Wrong change given',
  'Expense not recorded',
  'Sale not recorded',
  'Cash taken by the owner',
  'Other',
];

/// [ReasonSelect] over a [TextEditingController], for the forms that already
/// keep their reason in one: the controller holds the picked option, or what
/// was typed under "Other", so the code that reads it is unchanged.
class ReasonSelectField extends StatefulWidget {
  const ReasonSelectField({super.key, required this.controller, required this.options, this.multiline = false, this.onChanged});
  final TextEditingController controller;
  final List<String> options;
  final bool multiline;
  final ValueChanged<String>? onChanged;
  @override
  State<ReasonSelectField> createState() => _ReasonSelectFieldState();
}

class _ReasonSelectFieldState extends State<ReasonSelectField> {
  @override
  Widget build(BuildContext context) => ReasonSelect(
        options: widget.options,
        value: widget.controller.text,
        multiline: widget.multiline,
        onChanged: (v) {
          setState(() => widget.controller.text = v);
          widget.onChanged?.call(v);
        },
      );
}

/// PromptDialog `options`: what a list-prompt submits, or the error to show.
/// A picked option submits itself; "Other" submits what was typed (subject to
/// [allowEmpty]); nothing picked is "[label] is required.".
({String? value, String? error}) promptReasonValue(List<String>? options, String choice, String typed,
    {required String label, bool allowEmpty = false}) {
  final t = typed.trim();
  if (options != null) {
    if (choice.isEmpty) return (value: null, error: '$label is required.');
    if (choice != 'Other') return (value: choice, error: null);
  }
  if (!allowEmpty && t.isEmpty) return (value: null, error: '$label is required.');
  return (value: t, error: null);
}

/// A reason picked from [options]; "Other" shows a text box for the user's own
/// words. The parent holds ONE string, as with a plain text field: the picked
/// option, or what was typed under "Other" (empty until something is typed, so
/// a `reason.trim().isNotEmpty` check keeps working unchanged).
class ReasonSelect extends StatefulWidget {
  const ReasonSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Select a reason',
    this.otherPlaceholder = 'Type the reason',
    this.otherValue = 'Other',
    this.multiline = false,
    this.enabled = true,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String otherPlaceholder;
  final String otherValue;
  final bool multiline;
  final bool enabled;

  @override
  State<ReasonSelect> createState() => _ReasonSelectState();
}

class _ReasonSelectState extends State<ReasonSelect> {
  late String _choice;
  final _text = TextEditingController();

  bool _inList(String v) => v != widget.otherValue && widget.options.contains(v);

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _choice = _inList(v) ? v : (v.isNotEmpty ? widget.otherValue : '');
    if (!_inList(v)) _text.text = v;
  }

  // Follow the parent when it sets or clears the value itself (e.g. a reset on
  // open). An empty value while "Other" is open just means nothing typed yet.
  @override
  void didUpdateWidget(ReasonSelect old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v == old.value) return;
    if (_inList(v)) {
      _choice = v;
    } else if (v.isEmpty && _choice != widget.otherValue) {
      _choice = '';
    } else if (v.isNotEmpty && _choice != widget.otherValue) {
      _choice = widget.otherValue;
    }
    if (_choice == widget.otherValue && _text.text != v) _text.text = v;
    if (_choice != widget.otherValue) _text.clear();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(String? v) {
    if (v == null) return;
    setState(() => _choice = v);
    if (v == widget.otherValue) {
      _text.clear();
      widget.onChanged('');
    } else {
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSelect<String>(
            value: _choice.isEmpty ? null : _choice,
            hintText: widget.placeholder,
            enabled: widget.enabled,
            items: [for (final o in widget.options) AppSelectItem(value: o, label: o)],
            onChanged: widget.enabled ? _pick : null,
          ),
          if (_choice == widget.otherValue) ...[
            const SizedBox(height: 6),
            AppInput(
              controller: _text,
              hintText: widget.otherPlaceholder,
              autofocus: true,
              enabled: widget.enabled,
              minLines: widget.multiline ? 2 : null,
              maxLines: widget.multiline ? 4 : 1,
              onChanged: widget.onChanged,
            ),
          ],
        ],
      );
}
