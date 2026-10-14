// Recurring Expenses (migration 348) — the rules of lib/recurring/recurring-expense.ts
// and the Poultry part of lib/api/recurring-expenses.ts.

const recurringFrequencies = [
  ('Weekly', 'Weekly'),
  ('Biweekly', 'Every 2 weeks'),
  ('Monthly', 'Monthly'),
  ('Quarterly', 'Quarterly'),
  ('SemiAnnual', 'Every 6 months'),
  ('Annual', 'Yearly'),
];

String frequencyLabel(Object? f) => recurringFrequencies.where((x) => x.$1 == '$f').map((x) => x.$2).firstOrNull ?? '${f ?? ''}';

/// The payment methods a recurring expense can use.
const recurringPaymentMethods = ['Cash', 'MoMo', 'Bank', 'Card', 'Credit'];
String recurringMethodLabel(String m) => m == 'Credit' ? 'Credit (pay later)' : m;

/// The same list the poultry New Expense page offers (categories are free text).
const poultryRecurringCategories = ['Feed', 'Veterinary', 'Equipment', 'Labor', 'Utilities', 'Rent', 'Security', 'Internet', 'Software', 'Other'];

/// The To review tab's Show filter.
const occurrenceViews = [('Open', 'To review'), ('Posted', 'Posted'), ('Skipped', 'Skipped'), ('All', 'Everything')];

String _pad(int n) => n.toString().padLeft(2, '0');
String _iso(int y, int m, int d) => '$y-${_pad(m)}-${_pad(d)}';
int _daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

String _addMonths(String start, int months) {
  final p = start.split('-').map(int.parse).toList();
  final total = p[0] * 12 + (p[1] - 1) + months;
  final ny = total ~/ 12, nm = total % 12 + 1;
  final d = p[2] < _daysInMonth(ny, nm) ? p[2] : _daysInMonth(ny, nm);
  return _iso(ny, nm, d);
}

String _addDays(String start, int days) {
  final p = start.split('-').map(int.parse).toList();
  final t = DateTime.utc(p[0], p[1], p[2] + days);
  return _iso(t.year, t.month, t.day);
}

/// Occurrence n (0-based), worked out from the START date (31 Jan → 28 Feb → 31 Mar).
String occurrenceDate(String start, String frequency, int n) => switch (frequency) {
      'Weekly' => _addDays(start, 7 * n),
      'Biweekly' => _addDays(start, 14 * n),
      'Monthly' => _addMonths(start, n),
      'Quarterly' => _addMonths(start, 3 * n),
      'SemiAnnual' => _addMonths(start, 6 * n),
      _ => _addMonths(start, 12 * n),
    };

/// The first [count] dates, stopping at the end date.
List<String> previewDates(String start, String frequency, int count, [String? end]) {
  final out = <String>[];
  for (var n = 0; out.length < count && n < 1000; n++) {
    final d = occurrenceDate(start, frequency, n);
    if (end != null && end.isNotEmpty && d.compareTo(end) > 0) break;
    out.add(d);
  }
  return out;
}

/// How a payment method reads on a draft.
String paymentEffect(String method, bool hasCashAccount, bool moduleApproves) {
  if (method == 'Credit') return 'Posted unpaid — it becomes a supplier balance, no cash moves.';
  if (!hasCashAccount) return 'Choose the cash account it is paid from.';
  return moduleApproves
      ? 'Paid — cash leaves the account when the expense is approved on the Expenses page.'
      : 'Paid — cash leaves the account when you post it.';
}

/// The database's refusals, in its words.
List<String> validateTemplate({
  required String name,
  required num amount,
  required String frequency,
  required String startDate,
  String? endDate,
  required bool categoryOk,
  required String paymentMethod,
  int? supplierId,
  int? cashAccountId,
  String? approvalMode,
}) {
  final e = <String>[];
  if (name.trim().isEmpty) e.add('Give the recurring expense a name.');
  if (!(amount > 0)) e.add('The amount must be greater than 0.');
  if (!recurringFrequencies.any((x) => x.$1 == frequency)) e.add('Choose how often it repeats.');
  if (startDate.isEmpty) e.add('Choose the first date it is due.');
  if ((endDate ?? '').isNotEmpty && startDate.isNotEmpty && endDate!.compareTo(startDate) < 0) {
    e.add('The end date ($endDate) is before the start date ($startDate).');
  }
  if (!categoryOk) e.add('Choose a category.');
  if (paymentMethod == 'Credit' && supplierId == null) {
    e.add('An expense bought on credit needs a supplier, so it can be owed to someone.');
  }
  // A draft can leave the account to be chosen when posting; an automatic post can't ask.
  if (approvalMode == 'AutoPost' && paymentMethod != 'Credit' && cashAccountId == null) {
    e.add('Automatic posting needs the cash account it is paid from.');
  }
  return e;
}

/// The yyyy-mm-dd part, or "—".
String recDay(Object? v) {
  final s = v == null ? '' : '$v';
  return s.length >= 10 ? s.substring(0, 10) : (s.isEmpty ? '—' : s);
}
