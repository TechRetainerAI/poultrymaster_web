// Flock anomaly alerts (migration 338) — the display rules of
// `lib/production/flock-anomalies.ts`. Nothing here decides whether an anomaly
// happened: the server evaluates every signal and sends the lines it proved.

import 'package:flutter/material.dart';

import '../shared/business_dates.dart' show fmtNum;
import 'trackers/tracker_logic.dart' show tStr;
import 'trackers/tracker_widgets.dart' show TColors;

const _severityRank = {'Critical': 3, 'Warning': 2, 'Information': 1};

int severityRank(Object? s) => _severityRank[tStr(s)] ?? 0;

/// severityStyle: (label, badge border, badge bg, badge fg, left edge).
({String label, Color border, Color bg, Color fg, Color edge}) alertSeverityStyle(Object? s) => switch (s) {
      'Critical' => (label: 'Critical', border: TColors.rose200, bg: TColors.rose50, fg: TColors.rose700, edge: TColors.rose500),
      'Warning' => (label: 'Warning', border: TColors.amber200, bg: TColors.amber50, fg: TColors.amber800, edge: const Color(0xFFF59E0B)),
      'Information' => (label: 'Information', border: const Color(0xFFBAE6FD), bg: const Color(0xFFF0F9FF), fg: TColors.sky700, edge: const Color(0xFF0EA5E9)),
      _ => (label: '—', border: TColors.slate200, bg: TColors.slate50, fg: TColors.slate600, edge: TColors.slate300),
    };

/// statusStyle: (label, border, text) on a white badge.
({String label, Color border, Color fg}) alertStatusStyle(Object? s) => switch (s) {
      'Open' => (label: 'Open', border: TColors.rose200, fg: TColors.rose700),
      'Acknowledged' => (label: 'Acknowledged', border: TColors.amber200, fg: TColors.amber800),
      'Resolved' => (label: 'Resolved', border: TColors.emerald200, fg: TColors.emerald700),
      'Cleared' => (label: 'Cleared by data', border: TColors.slate200, fg: TColors.slate600),
      _ => (label: tStr(s), border: TColors.slate200, fg: TColors.slate600),
    };

String evaluationStatusText(Object? s) => switch (s) {
      'Fired' => 'Alert',
      'Normal' => 'Normal',
      'InsufficientBaseline' => 'Not enough history',
      'BelowMinimum' => 'Below minimum',
      'NoData' => 'Not recorded',
      'DuplicateRecords' => 'Duplicate records',
      'OnboardingDay' => 'First recorded day',
      _ => tStr(s),
    };

bool isActiveAlertStatus(Object? s) => s == 'Open' || s == 'Acknowledged';

/// Open before Acknowledged before Cleared before Resolved; then worst first; then newest.
List<Map> sortAlerts(List<Map> alerts) {
  const order = {'Open': 0, 'Acknowledged': 1, 'Cleared': 2, 'Resolved': 3};
  final out = [...alerts];
  out.sort((a, b) {
    var c = (order[a['status']] ?? 9) - (order[b['status']] ?? 9);
    if (c != 0) return c;
    c = severityRank(b['severity']) - severityRank(a['severity']);
    if (c != 0) return c;
    c = tStr(b['businessDate']).compareTo(tStr(a['businessDate']));
    if (c != 0) return c;
    return tStr(a['flockName']).compareTo(tStr(b['flockName']));
  });
  return out;
}

({int active, int open, int acknowledged, int critical, int warning, int information}) summarizeAlerts(List<Map> alerts) {
  final active = alerts.where((a) => isActiveAlertStatus(a['status'])).toList();
  return (
    active: active.length,
    open: alerts.where((a) => a['status'] == 'Open').length,
    acknowledged: alerts.where((a) => a['status'] == 'Acknowledged').length,
    critical: active.where((a) => a['severity'] == 'Critical').length,
    warning: active.where((a) => a['severity'] == 'Warning').length,
    information: active.where((a) => a['severity'] == 'Information').length,
  );
}

List<Map> alertSignals(Map a) => [for (final s in (a['signals'] as List? ?? const [])) if (s is Map) s];

/// "Mortality spike + Egg production decline" — the signals still firing, worst first.
String alertHeadline(Map alert) {
  final all = alertSignals(alert);
  final active = all.where((s) => s['isActive'] == true).toList();
  final shown = [...(active.isNotEmpty ? active : all)]..sort((a, b) => severityRank(b['severity']) - severityRank(a['severity']));
  final s = shown.map((x) => tStr(x['label'])).join(' + ');
  return s.isEmpty ? 'Anomaly' : s;
}

String alertFlockLabel(Map a) => tStr(a['houseName']).isNotEmpty ? '${tStr(a['flockName'])} · ${tStr(a['houseName'])}' : tStr(a['flockName']);

/// METHOD_OPTIONS: (value, label, unit, hint).
const methodOptions = [
  ('ratio', 'Times normal (×)', '×', "Compares today with the flock's normal as “so many times”. 2.5 means today is 2.5 times normal."),
  ('pctchange', 'Percent above or below normal (%)', '%',
      "Compares today with the flock's normal in percent. 10 means today is 10% higher or lower than normal."),
  ('zscore', 'How unusual for this flock (score)', 'σ',
      "Allows for flocks whose figures naturally jump around a lot. 2 = clearly unusual, 3 = very unusual. Most farms don't need this."),
];

String methodUnit(Object? m) {
  for (final (v, _, u, _) in methodOptions) {
    if (v == m) return u;
  }
  return '';
}

String? methodHint(Object? m) {
  for (final (v, _, _, h) in methodOptions) {
    if (v == m) return h;
  }
  return null;
}

/// The help line under the Information / Warning / Critical boxes.
String thresholdHelp(Map s) {
  final up = s['direction'] == 'up';
  if (s['method'] == 'ratio') {
    return up ? "Times normal. 2.5 = today is 2.5 times the flock's normal." : "Times normal. 2 = today is half of the flock's normal.";
  }
  if (s['method'] == 'pctchange') {
    return 'Percent ${up ? 'above' : 'below'} normal. 10 = today is 10% ${up ? 'higher' : 'lower'} than normal.';
  }
  return 'How unusual today is for this flock. 2 = clearly unusual, 3 = very unusual.';
}

String _fmtExample(num v) => fmtNum(num.parse(v.toStringAsFixed(1)), 3);

final Map<String, (num, String, String Function(num))> _exampleNormal = {
  'Mortality rate': (2, 'a flock that normally loses', (v) => '${_fmtExample(v)} bird${v == 1 ? '' : 's'} a day'),
  'Laying rate': (80, 'a flock normally at', (v) => '${_fmtExample(v)}% laying'),
  'Feed per bird': (115, 'a flock normally eating', (v) => '${_fmtExample(v)} g per bird a day'),
};

/// "For example, a flock that normally loses 2 birds a day: Warning at 5 …".
String? thresholdExample(Map s) {
  final ex = _exampleNormal[tStr(s['metricLabel'])];
  final w = s['warningThreshold'], c = s['criticalThreshold'];
  if (ex == null || w is! num || c is! num || !w.isFinite || !c.isFinite || w <= 0 || c <= 0) return null;
  if (s['method'] == 'zscore') return null;
  final (value, intro, say) = ex;
  final up = s['direction'] == 'up';
  num at(num t) {
    if (s['method'] == 'ratio') return up ? value * t : value / t;
    return up ? value * (1 + t / 100) : value * (1 - t / 100);
  }

  final word = up ? 'at' : 'at or below';
  return 'For example, $intro ${say(value)}: Warning $word ${say(at(w))}, Critical $word ${say(at(c))}.';
}

/// Plain label + help for the per-signal minimum (the "guard").
(String, String) guardText(Map s) => switch (s['guardField']) {
      'currentDeaths' => (
          'Only alert if at least this many birds died',
          'Stops tiny changes looking like a spike, e.g. 0 deaths one day and 1 the next.'
        ),
      'baselineMean' => ('Only check flocks normally laying at least (%)', 'Skips flocks not really in lay, such as young pullets or spent hens.'),
      _ => (tStr(s['guardLabel']).isEmpty ? 'Minimum' : tStr(s['guardLabel']), ''),
    };

/// Mirrors sppoultryanomalysettings_set so the form can say what is wrong before saving.
String? validateSetting(Map s) {
  bool n(Object? v) => v is num && v.isFinite;
  final bd = s['baselineDays'], mbd = s['minBaselineDays'];
  final w = s['warningThreshold'], c = s['criticalThreshold'], i = s['informationThreshold'];
  final g = s['guardMinimum'], f = s['baselineFloor'];
  if (!n(bd) || bd < 3 || bd > 90) return '“Work out normal from the last” must be 3 to 90 days.';
  if (!n(mbd) || mbd < 1 || mbd > bd) {
    return '“Days of records needed first” must be at least 1 and no more than the days used to work out normal.';
  }
  if (s['method'] == 'zscore' && mbd < 3) return '“How unusual for this flock” needs at least 3 days of records first.';
  if (!n(w) || !n(c) || w <= 0 || c <= w) return 'Critical must be higher than Warning, and both above zero.';
  if (i != null && (!n(i) || i <= 0 || i >= w)) return 'Information must be above zero and lower than Warning (or left empty).';
  if (g != null && (!n(g) || g < 0)) return 'The minimum cannot be negative.';
  if (!n(f) || f <= 0) return '“Treat normal as at least” must be above zero.';
  return null;
}

const _eventText = {
  'Detected': 'Detected',
  'SignalAdded': 'Another signal fired',
  'SignalReactivated': 'Signal fired again',
  'SeverityChanged': 'Severity changed',
  'EvidenceUpdated': 'Figures updated',
  'SignalCleared': 'Signal no longer firing',
  'AutoCleared': 'Cleared — the recorded figures no longer show it',
  'Reactivated': 'Reopened — it fired again',
  'Escalated': 'Reopened — severity rose above what was acknowledged',
  'Acknowledged': 'Acknowledged',
  'NoteAdded': 'Note',
  'Resolved': 'Resolved',
};

String eventText(Map e, [Map<String, String> signalLabels = const {}]) {
  final type = tStr(e['eventType']);
  final base = _eventText[type] ?? type;
  final key = e['signalKey'];
  final sig = key == null ? null : (signalLabels[tStr(key)] ?? tStr(key));
  final d = e['details'] is Map ? e['details'] as Map : const {};
  if (type == 'SeverityChanged' && d['fromSeverity'] != null && d['toSeverity'] != null) {
    return '${sig ?? 'Signal'}: ${d['fromSeverity']} → ${d['toSeverity']}';
  }
  if (type == 'Escalated' && d['acknowledgedSeverity'] != null && d['severity'] != null) {
    return '$base (${d['acknowledgedSeverity']} → ${d['severity']})';
  }
  if (type == 'Detected' && d['severity'] != null) return '$base — ${d['severity']}';
  return sig != null ? '$base: $sig' : base;
}

/// The page's fmtNum: dp decimals, then toLocaleString; "—" for nothing.
String alertNum(Object? v, [int dp = 1]) {
  if (v is! num || !v.isFinite) return '—';
  return fmtNum(num.parse(v.toStringAsFixed(dp)), dp);
}

/// YYYY-MM-DD from an API date.
String alertDay(Object? value) {
  final s = tStr(value);
  return s.length >= 10 ? s.substring(0, 10) : s;
}
