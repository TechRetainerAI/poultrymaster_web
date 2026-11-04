// Searching the Help Center: lib/search/fuzzy.ts (the matcher) and
// lib/help/help-search.ts (the help scorer and highlighter), ported line for
// line so a question finds the same answers on the phone as on the web.
//
// Help questions are sentences, so an entry is kept when at least half of the
// MEANINGFUL words land in it (title worth 3, keywords 2.5, body 1), with
// typos tolerated word by word.

import 'dart:math' as math;

import 'help_types.dart';

// ------------------------------------------------------------- fuzzy.ts

/// Lowercase, drop apostrophes, `&` -> `and`, punctuation to spaces.
String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[\'’”»]'), '')
    .replaceAll('&', ' and ')
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim();

List<String> tokenize(String s) {
  final n = normalize(s);
  return n.isEmpty ? <String>[] : n.split(' ');
}

const stopWords = {'the', 'a', 'an', 'of', 'to', 'for', 'my', 'and', 'in', 'on', 'page', 'show', 'me'};

/// Damerau-Levenshtein distance, bailing out once it is beyond [max].
int editDistance(String a, String b, [int max = 2]) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > max) return max + 1;
  final rows = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    var rowMin = 1 << 30;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1), rows[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, rows[i - 2][j - 2] + 1);
      }
      rows[i][j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
  }
  return rows[a.length][b.length];
}

int _typoBudget(int len) => len >= 8 ? 2 : (len >= 4 ? 1 : 0);

/// 'prefix', 'typo' or null: does query word [q] loosely match text word [w]?
String? wordMatches(String q, String w) {
  if (w.startsWith(q)) return 'prefix';
  final budget = _typoBudget(q.length);
  if (budget == 0) return null;
  if (editDistance(q, w, budget) <= budget) return 'typo';
  for (final len in [q.length, q.length + 1, q.length - 1]) {
    if (len > 0 && w.length > len && editDistance(q, w.substring(0, len), budget) <= budget) return 'typo';
  }
  return null;
}

/// Score one query against one text. 0 = no match.
double scoreText(String query, String text) {
  final q = normalize(query);
  final t = normalize(text);
  if (q.isEmpty || t.isEmpty) return 0;
  if (q == t) return 100;
  if (t.startsWith(q)) return 90;
  final qAll = q.split(' ');
  final qWords = qAll.where((w) => !stopWords.contains(w) || qAll.length == 1).toList();
  final tWords = t.split(' ');
  if (qWords.isEmpty) return 0;
  if (qWords.every((qw) => tWords.any((tw) => tw.startsWith(qw)))) return 80;
  if (t.contains(q)) return 70;
  if (q.length >= 2 && !q.contains(' ')) {
    final initials = tWords.where((w) => !stopWords.contains(w)).map((w) => w[0]).join();
    if (initials.startsWith(q)) return 65;
  }
  var typoHits = 0;
  final allLand = qWords.every((qw) => tWords.any((tw) {
        final m = wordMatches(qw, tw);
        if (m == 'typo') typoHits++;
        return m != null;
      }));
  if (allLand) return typoHits > 0 ? 55 : 80;
  final compactQ = q.replaceAll(' ', '');
  if (compactQ.length >= 3) {
    var ti = 0, first = -1, last = -1;
    for (final ch in compactQ.split('')) {
      final found = t.indexOf(ch, ti);
      if (found == -1) return 0;
      if (first == -1) first = found;
      last = found;
      ti = found + 1;
    }
    final density = compactQ.length / (last - first + 1);
    if (density < 0.35) return 0;
    return (20 + density * 20).roundToDouble();
  }
  return 0;
}

/// Best score across weighted fields (page-index.ts scoreFields).
double scoreFields(String query, List<(String, double)> fields) {
  var best = 0.0;
  for (final (text, weight) in fields) {
    if (text.isEmpty) continue;
    final s = scoreText(query, text) * weight;
    if (s > best) best = s;
  }
  return best;
}

// ------------------------------------------------------- help-search.ts

const _questionWords = {
  'how', 'do', 'does', 'did', 'i', 'we', 'can', 'cant', 'cannot', 'what', 'whats', 'why', 'where', 'when',
  'which', 'who', 'is', 'are', 'was', 'it', 'its', 'this', 'that', 'be', 'should', 'would', 'will', 'with',
  'doesnt', 'dont', 'isnt', 'arent', 'not', 'no', 'there', 'get', 'got', 'use', 'using', 'help', 'please',
  'you', 'your', 'our', 'app', 'system',
};

/// The words worth matching; a query of only question words keeps them all.
List<String> meaningfulWords(String query) {
  final words = tokenize(query).where((w) => !stopWords.contains(w) && !_questionWords.contains(w)).toList();
  return words.isNotEmpty ? words : tokenize(query);
}

class PreparedHelp {
  PreparedHelp(this.entry)
      : title = _words(entry.title),
        keywords = [for (final k in entry.keywords) ..._words(k)],
        body = _words('${entry.body} ${entry.category}');
  final HelpEntry entry;
  final List<String> title, keywords, body;
  static List<String> _words(String s) => normalize(s).split(' ').where((w) => w.isNotEmpty).toList();
}

List<PreparedHelp> prepareHelpIndex(List<HelpEntry> entries) => [for (final e in entries) PreparedHelp(e)];

double _land(String q, List<String> ws) {
  var best = 0.0;
  for (final w in ws) {
    final m = wordMatches(q, w);
    if (m == 'prefix') return 1;
    if (m == 'typo') best = 0.7;
  }
  return best;
}

class HelpHit {
  HelpHit(this.entry, this.score, this.matched);
  final HelpEntry entry;
  final double score;

  /// The query words that matched, for highlighting.
  final List<String> matched;
}

List<HelpHit> searchHelp(String query, List<PreparedHelp> index, {int limit = 30}) {
  final qs = meaningfulWords(query);
  if (qs.isEmpty) return [];
  final hits = <HelpHit>[];
  for (final p in index) {
    var total = 0.0;
    var landed = 0;
    final matched = <String>[];
    for (final q in qs) {
      final s = math.max(math.max(_land(q, p.title) * 3, _land(q, p.keywords) * 2.5), _land(q, p.body));
      if (s > 0) {
        landed++;
        matched.add(q);
      }
      total += s;
    }
    if (landed == 0 || landed < (qs.length / 2).ceil()) continue;
    final score = (total / (qs.length * 3)) * 100 + scoreText(query, p.entry.title) * 0.3;
    hits.add(HelpHit(p.entry, score, matched));
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.take(limit).toList();
}

/// Plain and highlighted runs for the matched words; matches word STARTS only.
List<({String text, bool hit})> highlightRuns(String text, List<String> matched) {
  final escaped = [for (final m in matched) if (m.length >= 2) RegExp.escape(m)];
  if (escaped.isEmpty) return [(text: text, hit: false)];
  final re = RegExp('\\b(${escaped.join('|')})[a-z]*', caseSensitive: false);
  final out = <({String text, bool hit})>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) out.add((text: text.substring(last, m.start), hit: false));
    out.add((text: m[0]!, hit: true));
    last = m.end;
  }
  if (last < text.length) out.add((text: text.substring(last), hit: false));
  return out;
}

// ------------------------------------------------------ page-index.ts

const _navVerbs = ['go to', 'goto', 'open', 'show', 'view', 'find', 'search', 'see'];
const _createVerbs = ['new', 'add', 'record', 'create', 'log', 'enter', 'make'];

/// parseQuery: "new sale" and "go to cash flow" match on what is left.
String parseQuery(String raw) {
  var text = normalize(raw);
  for (final v in _navVerbs) {
    if (text.startsWith('$v ')) {
      text = text.substring(v.length + 1);
      break;
    }
  }
  for (final v in _createVerbs) {
    if (text.startsWith('$v ')) {
      text = text.substring(v.length + 1);
      break;
    }
  }
  return text.replaceFirst(RegExp(r'^(a|an|the)\s+'), '');
}

/// The synonyms a page title picks up (withSynonyms).
List<String> pageKeywords(String title) {
  final t = normalize(title);
  return [
    for (final (needle, words) in titleSynonyms)
      if (needle.startsWith('=') ? t == needle.substring(1) : t.contains(needle)) ...words,
  ];
}

/// rankPages: the "Go to page" chips. [pages] are (title, href, group).
List<({String title, String href})> rankPages(String raw, List<({String title, String href, String group})> pages, {int limit = 5}) {
  final text = parseQuery(raw);
  if (text.isEmpty) return [];
  final ranked = <({String title, String href, double score})>[];
  for (final p in pages) {
    var score = scoreFields(text, [(p.title, 1), for (final k in pageKeywords(p.title)) (k, 0.85), (p.group, 0.45)]);
    if (score <= 0) continue;
    score -= math.min(4, p.title.length / 12);
    ranked.add((title: p.title, href: p.href, score: score));
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return [for (final r in ranked.take(limit)) (title: r.title, href: r.href)];
}

/// TITLE_SYNONYMS: words people use for a page that are not in its title.
/// A leading `=` means the whole title, not a substring.
const titleSynonyms = <(String, List<String>)>[
  ('flock group', ['birds', 'chickens', 'layers', 'broilers', 'flock', 'flocks']),
  ('flock purchases', ['batch', 'batches', 'chicks', 'day old', 'bird purchase']),
  ('production records', ['eggs collected', 'mortality', 'deaths', 'daily production', 'egg collection']),
  ('egg sorting', ['grading', 'egg sizes', 'crates', 'trays']),
  ('egg tracker', ['eggs at hand', 'egg stock', 'egg inventory']),
  ('birds tracker', ['birds left', 'bird count', 'how many birds']),
  ('dead birds', ['mortality', 'deaths', 'carcass']),
  ('broken eggs', ['cracked eggs', 'damaged eggs']),
  ('feed usage', ['feeding', 'feed consumed', 'feed given']),
  ('feed tracker', ['feed at hand', 'feed stock', 'feed consumption']),
  ('feed formulas', ['ration', 'recipe', 'mix']),
  ('health records', ['vaccination', 'vaccine', 'medication', 'treatment', 'disease', 'vet']),
  ('medication tracker', ['drugs', 'medicine', 'treatment log']),
  ('treatment campaigns', ['vaccination programme', 'deworming']),
  ('sales', ['sell', 'sold', 'revenue', 'invoice', 'receipt', 'orders']),
  ('customer payments', ['collections', 'money received', 'paid', 'receive payment']),
  ('payments', ['collections', 'money received']),
  ('customer balances', ['debtors', 'receivables', 'who owes', 'owing', 'debt', 'outstanding']),
  ('customer credits', ['deposit', 'advance', 'overpayment', 'prepaid']),
  ('supplier balances', ['creditors', 'payables', 'we owe', 'bills']),
  ('supplier payments', ['pay supplier', 'bills paid']),
  ('supplier credits', ['supplier advance', 'prepayment']),
  ('suppliers', ['vendor', 'vendors']),
  ('customers', ['clients', 'buyers']),
  ('expenses', ['costs', 'spending', 'spent', 'bills']),
  ('recurring expenses', ['rent', 'subscription', 'monthly bills', 'standing order']),
  ('cash flow', ['money in', 'money out', 'cash movement']),
  ('cash account', ['bank', 'mobile money', 'momo', 'till']),
  ('cash transfers', ['move money', 'bank deposit', 'withdrawal']),
  ('reconciliation', ['cash count', 'balance check', 'shortage']),
  ('profit and loss', ['pnl', 'p and l', 'income statement', 'profit', 'loss', 'margin']),
  ('financial activity', ['cash vs profit', 'why is profit different', 'profit impact']),
  ('daily closing', ['end of day', 'close day', 'eod', 'close the day']),
  ('owner money', ['drawings', 'capital', 'owner withdrawal', 'investment']),
  ('loans', ['borrowing', 'financing', 'repayment']),
  ('employee loans', ['salary advance', 'staff loan']),
  ('payroll', ['salaries', 'wages', 'pay staff']),
  ('staff', ['workers', 'employees', 'team']),
  ('users and permissions', ['access', 'roles', 'employees', 'login', 'accounts']),
  ('inventory', ['stock', 'items', 'store']),
  ('supply purchases', ['buy', 'purchase', 'restock', 'procurement']),
  ('receive purchase', ['goods received', 'grn', 'delivery from supplier']),
  ('stock movement', ['stock ledger', 'stock history', 'adjustment']),
  ('internal use', ['consumed', 'used on farm', 'own use']),
  ('loss and damage', ['theft', 'spoilage', 'write off', 'breakage']),
  ('damages and loss', ['theft', 'spoilage', 'write off', 'breakage']),
  ('deliveries', ['driver returns', 'load vehicle', 'dispatch']),
  ('drivers', ['riders']),
  ('vehicles', ['trucks', 'vans', 'tricycle']),
  ('capital investments', ['assets', 'equipment', 'depreciation']),
  ('houses', ['pen', 'pens', 'barn', 'coop']),
  ('activity log', ['audit', 'history', 'who changed']),
  ('=account', ['profile', 'password', 'my details', 'settings']),
  ('farm alerts', ['warnings', 'notifications', 'attention']),
  ('restock forecast', ['running out', 'reorder', 'low stock']),
  ('lifecycle', ['schedule', 'milestones', 'tasks']),
  ('closeout', ['end flock', 'depopulate', 'close flock']),
  ('water production', ['bags', 'sachets', 'bottles produced']),
  ('boreholes', ['water source', 'well']),
  ('maintenance', ['repairs', 'service', 'breakdown']),
  ('billing', ['subscription', 'plan', 'paystack']),
  ('help', ['support', 'how to', 'guide']),
  ('reports', ['analytics', 'summary']),
];
