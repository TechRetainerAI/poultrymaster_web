// `components/cash/cash-account-vocabulary.ts`: you count a cash box, check a
// bank account against a statement, and read a MoMo balance off the phone —
// so the words follow the account type.

class CashVocabulary {
  const CashVocabulary({
    required this.category,
    required this.action,
    required this.amountLabel,
    required this.balanceTerm,
    required this.helper,
    required this.shortHelper,
    required this.recordNoun,
    required this.emptyHistory,
  });
  final String category, action, amountLabel, balanceTerm, helper, shortHelper, recordNoun, emptyHistory;

  /// "Cash count", "Bank reconciliation"…
  String get recordNounTitle => '${recordNoun[0].toUpperCase()}${recordNoun.substring(1)}';
}

const _cashTypes = ['factorycashbox', 'farmcashbox', 'ownercash', 'pettycash', 'drivercash', 'cash'];

const _vocab = {
  'cash': CashVocabulary(
    category: 'cash',
    action: 'Reconcile Cash Balance',
    amountLabel: 'Amount Counted',
    balanceTerm: 'Physical Cash Balance',
    helper: 'Count what is physically in the drawer, box or safe, and enter the total.',
    shortHelper: 'What you physically counted.',
    recordNoun: 'cash count',
    emptyHistory: 'This account has never been counted.',
  ),
  'bank': CashVocabulary(
    category: 'bank',
    action: 'Reconcile Bank Account',
    amountLabel: 'Statement Balance',
    balanceTerm: 'Bank Balance',
    helper: 'Check the bank statement or banking app, and enter the balance it shows.',
    shortHelper: 'The balance on the statement or in the banking app.',
    recordNoun: 'bank reconciliation',
    emptyHistory: 'This account has never been reconciled against a statement.',
  ),
  'momo': CashVocabulary(
    category: 'momo',
    action: 'Reconcile MoMo Account',
    amountLabel: 'MoMo Balance',
    balanceTerm: 'MoMo Balance',
    helper: 'Check the current MoMo balance on the phone or app, and enter it.',
    shortHelper: 'The balance currently showing on MoMo.',
    recordNoun: 'MoMo reconciliation',
    emptyHistory: 'This account has never been reconciled against MoMo.',
  ),
  'other': CashVocabulary(
    category: 'other',
    action: 'Reconcile Account',
    amountLabel: 'Actual Balance',
    balanceTerm: 'Actual Balance',
    helper: 'Enter the balance this account actually holds.',
    shortHelper: 'What this account actually holds.',
    recordNoun: 'reconciliation',
    emptyHistory: 'This account has never been reconciled.',
  ),
};

String cashAccountCategory(Object? accountType) {
  final t = '${accountType ?? ''}'.trim().toLowerCase();
  if (t.isEmpty) return 'other';
  if (t == 'bankaccount' || t == 'bank') return 'bank';
  if (t == 'momowallet' || t == 'momo') return 'momo';
  if (_cashTypes.contains(t)) return 'cash';
  return 'other';
}

CashVocabulary cashAccountVocabulary(Object? accountType) => _vocab[cashAccountCategory(accountType)]!;
