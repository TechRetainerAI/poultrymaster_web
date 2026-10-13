// Flock Lifecycle Assistant (migration 347) — presentation rules, as
// `lib/poultry/lifecycle.ts`. The schedule is worked out in the database;
// nothing here recomputes a due date or a status.

import 'package:flutter/material.dart';

import 'trackers/tracker_logic.dart' show tNum, tStr;
import 'trackers/tracker_widgets.dart' show TColors;

/// AGE_UNITS, with the editor's labels.
const lifecycleAgeUnits = [('Week', 'Weeks'), ('Day', 'Days')];

/// Suggestions for the free-text category field — a farm may type its own.
const lifecycleCategorySuggestions = ['Housing', 'Health', 'Feeding', 'Lighting', 'Production', 'Review', 'Other'];

/// ACTION_TYPES: (value, label, hint).
const lifecycleActionTypes = [
  ('FlockDetails', 'Flock details', 'Opens the flock'),
  ('FlockTransfer', 'Move house', 'Opens the flock, where its house is changed'),
  ('MedicationCampaign', 'Treatment records', 'Opens Health records to record a treatment'),
  ('Production', 'Production record', 'Opens a new production record for the flock'),
  ('Closeout', 'Flock closeout', "Opens the flock's lifetime page, where it is closed"),
];

/// The task views: (value, label).
const lifecycleViews = [
  ('Open', 'Needs attention'),
  ('Overdue', 'Overdue'),
  ('Due', 'Due'),
  ('Upcoming', 'Upcoming'),
  ('Scheduled', 'Later'),
  ('Completed', 'Completed'),
  ('Skipped', 'Skipped'),
  ('All', 'Everything'),
];

/// Where a task's action link goes. A link, never an action.
String? lifecycleActionHref(Map task) {
  final id = tStr(task['flockId']);
  switch (tStr(task['actionType'])) {
    case 'FlockDetails':
    case 'FlockTransfer':
      return '/flocks/$id';
    case 'MedicationCampaign':
      return '/health';
    case 'Production':
      return '/production-records/new?flockId=$id';
    case 'Closeout':
      return '/flock-closeout/$id';
    default:
      return null;
  }
}

String? lifecycleActionLabel(Object? type) {
  for (final (v, l, _) in lifecycleActionTypes) {
    if (v == tStr(type)) return l;
  }
  return null;
}

/// "Week 16" / "Day 3".
String milestoneAgeLabel(Object? unit, Object? value) => '${tStr(unit) == 'Day' ? 'Day' : 'Week'} ${tNum(value).toInt()}';

/// A flock's age in days as weeks + days: 107 → "15w 2d", 112 → "16w".
String formatAgeDays(num? days) {
  if (days == null || !days.isFinite || days < 0) return '—';
  final w = days ~/ 7;
  final d = (days % 7).toInt();
  if (w == 0) return '${d}d';
  return d == 0 ? '${w}w' : '${w}w ${d}d';
}

/// Plain-words timing: "in 5 days", "Due today", "3 days overdue".
String dueLabel(Map task) {
  final n = tNum(task['daysUntilDue']).toInt();
  final status = tStr(task['status']);
  if (status == 'Completed') return 'Completed';
  if (status == 'Skipped') return 'Skipped';
  if (status == 'Due') {
    if (n == 0) return 'Due today';
    return tStr(task['ageUnit']) == 'Week' ? 'Due this week' : 'Due today';
  }
  if (n > 0) return n == 1 ? 'in 1 day' : 'in $n days';
  final late = -n;
  return late == 1 ? '1 day overdue' : '$late days overdue';
}

/// "B3 (Flock A) reaches Week 16 in 5 days".
String taskSentence(Map task) {
  final batch = tStr(task['batchCode']);
  final who = batch.isNotEmpty ? '$batch (${tStr(task['flockName'])})' : tStr(task['flockName']);
  final age = milestoneAgeLabel(task['ageUnit'], task['ageValue']);
  final days = tNum(task['daysUntilDue']).toInt();
  switch (tStr(task['status'])) {
    case 'Upcoming':
      return '$who reaches $age ${days == 1 ? 'tomorrow' : 'in $days days'}';
    case 'Due':
      return '$who is at $age now';
    case 'Overdue':
      return '$who passed $age';
    default:
      return '$who — $age';
  }
}

/// STATUS_TONE: (background, text, border).
(Color, Color, Color) lifecycleStatusTone(Object? status) => switch (tStr(status)) {
      'Overdue' => (TColors.rose100, TColors.rose800, const Color(0xFFFDA4AF)),
      'Due' => (TColors.amber100, TColors.amber800, TColors.amber300),
      'Upcoming' => (TColors.blue100, const Color(0xFF1E40AF), TColors.blue300),
      'Completed' => (TColors.emerald100, TColors.emerald800, TColors.emerald300),
      'Skipped' => (TColors.slate100, TColors.slate500, TColors.slate300),
      _ => (TColors.slate100, TColors.slate600, TColors.slate300),
    };

const _statusOrder = {'Overdue': 0, 'Due': 1, 'Upcoming': 2, 'Scheduled': 3, 'Completed': 4, 'Skipped': 5};

/// Most urgent first, then by due date, then by flock.
List<Map> sortTasks(List<Map> tasks) {
  final out = [...tasks];
  out.sort((a, b) {
    final s = (_statusOrder[tStr(a['status'])] ?? 9) - (_statusOrder[tStr(b['status'])] ?? 9);
    if (s != 0) return s;
    final d = tStr(a['dueDate']).compareTo(tStr(b['dueDate']));
    if (d != 0) return d;
    return tStr(a['flockName']).compareTo(tStr(b['flockName']));
  });
  return out;
}

/// Age at start entered as weeks + days, stored as days.
int ageAtStartDays(num weeks, num days) {
  int f(num v) => v.isFinite && v > 0 ? v.floor() : 0;
  return f(weeks) * 7 + f(days);
}

/// The database's refusals, in its words.
List<String> validatePlan(String name, List<({String title, String ageUnit, num ageValue, num leadTimeDays})> milestones) {
  final errs = <String>[];
  if (name.trim().isEmpty) errs.add('Give the lifecycle plan a name.');
  if (milestones.isEmpty) errs.add('Add at least one milestone.');
  bool isInt(num v) => v == v.roundToDouble();
  for (var i = 0; i < milestones.length; i++) {
    final m = milestones[i];
    final n = i + 1;
    if (m.title.trim().isEmpty) errs.add('Milestone $n: give it a title.');
    if (m.ageUnit != 'Day' && m.ageUnit != 'Week') errs.add('Milestone $n: age must be in days or weeks.');
    if (!isInt(m.ageValue) || m.ageValue < 0 || m.ageValue > 5000) errs.add('Milestone $n: enter an age between 0 and 5000.');
    if (!isInt(m.leadTimeDays) || m.leadTimeDays < 0 || m.leadTimeDays > 365) {
      errs.add('Milestone $n: lead time must be between 0 and 365 days.');
    }
  }
  return errs;
}
