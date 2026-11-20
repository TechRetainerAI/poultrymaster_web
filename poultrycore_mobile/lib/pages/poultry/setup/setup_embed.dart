// Lets one setup view show in two places: its own page, and a tab inside the
// Farm Setup page (/poultry-setup), as the web's
// components/setup/setup-embed.tsx and setup-task-bar.tsx.
//
// When embedded a view:
//   * drops its own app bar and title block (Farm Setup shows one line instead),
//   * hands its buttons to Farm Setup's task bar through [SetupTaskBar],
//   * tells Farm Setup when it holds unsaved edits ([reportSetupDirty]).
// Everything else (lists, forms, checks, API calls) is the same code in both
// places.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// One button of a view, as data.
class SetupTask {
  const SetupTask({
    required this.id,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = false,
    this.disabled = false,
    this.hidden = false,
    this.more = false,
    this.group,
    this.tooltip,
  });

  /// Stable within the view.
  final String id;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// The tab's main task: filled button, kept on the bar longest.
  final bool primary;
  final bool disabled;

  /// Left out entirely (e.g. no permission).
  final bool hidden;

  /// Always in the More menu.
  final bool more;

  /// A divider separates tasks of different groups.
  final String? group;

  /// Why it is disabled, say.
  final String? tooltip;

  String get _shape => '$id|$label|${primary ? 1 : 0}|${disabled ? 1 : 0}|${hidden ? 1 : 0}|${more ? 1 : 0}|${group ?? ''}|${icon?.codePoint}';
}

/// What Farm Setup hands its open tab.
class SetupEmbedController extends ChangeNotifier {
  final Map<Object, List<SetupTask>> _tasks = {};
  final Set<Object> _dirty = {};
  bool _scheduled = false;

  /// Every registered view's tasks, in registration order.
  List<SetupTask> get tasks => [for (final l in _tasks.values) ...l];
  bool get anyDirty => _dirty.isNotEmpty;

  void _notifyLater() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (hasListeners) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Registers (or, with null, removes) one view's tasks. The newest handlers
  /// are always kept; the bar only redraws when something visible changed.
  void setTasks(Object owner, List<SetupTask>? tasks) {
    final before = _tasks[owner];
    if (tasks == null) {
      if (_tasks.remove(owner) != null) _notifyLater();
      return;
    }
    _tasks[owner] = tasks;
    final changed = before == null || before.map((t) => t._shape).join('#') != tasks.map((t) => t._shape).join('#');
    if (changed) _notifyLater();
  }

  void setDirty(Object key, bool dirty) {
    final changed = dirty ? _dirty.add(key) : _dirty.remove(key);
    if (changed) _notifyLater();
  }

  /// A new tab, company or Reload: start empty.
  void clear() {
    _tasks.clear();
    _dirty.clear();
    _notifyLater();
  }
}

class SetupEmbed extends InheritedWidget {
  const SetupEmbed({super.key, required this.controller, required super.child});
  final SetupEmbedController controller;

  static SetupEmbedController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SetupEmbed>()?.controller;

  @override
  bool updateShouldNotify(SetupEmbed old) => old.controller != controller;
}

/// True when the view is shown inside the Farm Setup page.
bool isSetupEmbedded(BuildContext context) => SetupEmbed.of(context) != null;

/// Tells Farm Setup that the view under [key] holds unsaved edits, so a tab or
/// section change asks first. Does nothing on the view's own page.
void reportSetupDirty(BuildContext context, Object key, bool dirty) =>
    context.getInheritedWidgetOfExactType<SetupEmbed>()?.controller.setDirty(key, dirty);

/// The view's buttons. On its own page: drawn in place (a light row).
/// Embedded: handed to Farm Setup's task bar, and nothing is drawn here.
class SetupTaskBar extends StatefulWidget {
  const SetupTaskBar({super.key, required this.tasks, this.alignEnd = true});
  final List<SetupTask> tasks;
  final bool alignEnd;

  @override
  State<SetupTaskBar> createState() => _SetupTaskBarState();
}

class _SetupTaskBarState extends State<SetupTaskBar> with AutomaticKeepAliveClientMixin {
  final Object _owner = Object();
  SetupEmbedController? _ctl;

  /// Inside a scrolling list, stay alive when scrolled out of view: the
  /// buttons must not leave Farm Setup's bar because the list moved.
  @override
  bool get wantKeepAlive => _ctl != null;

  @override
  void dispose() {
    _ctl?.setTasks(_owner, null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read before the first build, so the keep-alive below applies from it.
    _ctl = SetupEmbed.of(context) ?? _ctl;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = SetupEmbed.of(context);
    if (ctl != null) {
      _ctl = ctl;
      ctl.setTasks(_owner, widget.tasks);
      return const SizedBox.shrink();
    }
    return TaskBarRow(tasks: widget.tasks, align: widget.alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start);
  }
}

const _gap = 8.0;

/// The buttons of one task bar, folding into "More" when the row is too narrow.
/// [dark]: on Farm Setup's dark dock; otherwise on a white page.
class TaskBarRow extends StatelessWidget {
  const TaskBarRow({super.key, required this.tasks, this.dark = false, this.align = MainAxisAlignment.start});
  final List<SetupTask> tasks;
  final bool dark;
  final MainAxisAlignment align;

  static double _width(SetupTask t, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(text: TextSpan(text: t.label, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
    return tp.width + 24 + (t.icon != null ? 22 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final live = tasks.where((t) => !t.hidden).toList();
    final inline = live.where((t) => !t.more).toList();
    final pinnedMore = live.where((t) => t.more).toList();
    // Primary tasks go first, so a narrow bar keeps the main button.
    final ordered = [...inline.where((t) => t.primary), ...inline.where((t) => !t.primary)];
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final widths = [for (final t in ordered) _width(t, style, scaler)];
      final all = widths.fold<double>(0, (a, w) => a + w) + _gap * (widths.length - 1).clamp(0, 999);
      const moreW = 36.0;
      var fit = ordered.length;
      if (all + (pinnedMore.isNotEmpty ? _gap + moreW : 0) > box.maxWidth) {
        var used = moreW;
        var n = 0;
        for (final w in widths) {
          if (used + _gap + w > box.maxWidth) break;
          used += _gap + w;
          n++;
        }
        fit = n < 1 ? 1 : n;
      }
      final shown = ordered.take(fit).toList();
      final folded = [...ordered.skip(fit), ...pinnedMore];
      bool divider(List<SetupTask> list, int i) => i > 0 && (list[i].group ?? '') != (list[i - 1].group ?? '');
      return Row(mainAxisAlignment: align, children: [
        for (final (i, t) in shown.indexed) ...[
          if (i > 0) const SizedBox(width: _gap),
          if (divider(shown, i)) ...[_Divider(dark: dark), const SizedBox(width: _gap)],
          Flexible(child: _TaskButton(task: t, dark: dark)),
        ],
        if (folded.isNotEmpty) ...[
          if (shown.isNotEmpty) const SizedBox(width: _gap),
          _MoreButton(tasks: folded, dark: dark, divider: divider),
        ],
      ]);
    });
  }
}

class _TaskButton extends StatelessWidget {
  const _TaskButton({required this.task, required this.dark});
  final SetupTask task;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final onTap = t.disabled ? null : t.onTap;
    final label = Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final icon = t.icon == null ? null : Icon(t.icon, size: 16);
    final style = t.primary
        ? FilledButton.styleFrom(
            backgroundColor: Tone.button(dark ? const Tone.bg(0xFFF97316) : const Tone.bg(0xFF2563EB)),
            foregroundColor: Colors.white,
            // Greyed out on the dark dock (e.g. Save with nothing to save):
            // the default greys are dark ink, unreadable on the dock.
            disabledBackgroundColor: dark ? const Tone.bg(0x1AFFFFFF) : null,
            disabledForegroundColor: dark ? const Tone.fg(0x80FFFFFF) : null,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          )
        : OutlinedButton.styleFrom(
            backgroundColor: dark ? const Tone.bg(0x1AFFFFFF) : Tone.button(const Tone.bg(0xFFFFFFFF)),
            foregroundColor: dark ? Colors.white : const Tone.fg(0xFF0F172A),
            disabledForegroundColor: dark ? const Tone.fg(0x80FFFFFF) : null,
            side: BorderSide(color: dark ? const Tone.line(0x33FFFFFF) : const Tone.line(0xFFE2E8F0)),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          );
    final Widget button = t.primary
        ? (icon == null
            ? FilledButton(key: ValueKey('task-${t.id}'), style: style, onPressed: onTap, child: label)
            : FilledButton.icon(key: ValueKey('task-${t.id}'), style: style, onPressed: onTap, icon: icon, label: label))
        : (icon == null
            ? OutlinedButton(key: ValueKey('task-${t.id}'), style: style, onPressed: onTap, child: label)
            : OutlinedButton.icon(key: ValueKey('task-${t.id}'), style: style, onPressed: onTap, icon: icon, label: label));
    return t.tooltip == null ? button : Tooltip(message: t.tooltip!, child: button);
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: dark ? const Tone.line(0x33FFFFFF) : const Tone.line(0xFFE2E8F0));
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.tasks, required this.dark, required this.divider});
  final List<SetupTask> tasks;
  final bool dark;
  final bool Function(List<SetupTask>, int) divider;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('task-more'),
      tooltip: 'More tasks',
      onSelected: (id) => tasks.where((t) => t.id == id).firstOrNull?.onTap?.call(),
      itemBuilder: (_) => [
        for (final (i, t) in tasks.indexed) ...[
          if (divider(tasks, i)) const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: t.id,
            enabled: !t.disabled && t.onTap != null,
            child: Row(children: [
              if (t.icon != null) ...[Icon(t.icon, size: 16), const SizedBox(width: 8)],
              Flexible(child: Text(t.label)),
            ]),
          ),
        ],
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? const Tone.bg(0x1AFFFFFF) : const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: dark ? const Tone.line(0x33FFFFFF) : const Tone.line(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.more_horiz, size: 16, color: dark ? Colors.white : const Tone.fg(0xFF0F172A)),
      ),
    );
  }
}
