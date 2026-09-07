import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../resources/resource_spec.dart';
import '../../services/farm_service.dart';
import '../../widgets/common.dart';
import 'resource_form_screen.dart';

class ResourceListScreen extends StatefulWidget {
  final ResourceSpec spec;
  const ResourceListScreen({super.key, required this.spec});

  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _query = '';

  ResourceSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await FarmService.list(spec.endpoint);
      // Newest entries first: the APIs mostly return insertion order.
      if (mounted) setState(() => _items = items.reversed.toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _visible {
    final items = _items ?? [];
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items.where((i) {
      final title = pickString(i, spec.titleKeys);
      final sub = spec.subtitle?.call(i) ?? '';
      return title.toLowerCase().contains(q) || sub.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ResourceFormScreen(spec: spec, item: item)),
    );
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final title = pickString(item, spec.titleKeys, spec.singular);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete ${spec.singular.toLowerCase()}?'),
        content: Text('"$title" will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FarmService.delete(spec.endpoint, pick(item, [spec.idKey]));
      if (mounted) {
        showSnack(context, '${spec.singular} deleted');
        _load();
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(spec.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Iconsax.add),
        label: Text('New ${spec.singular}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search ${spec.title.toLowerCase()}…',
                prefixIcon: const Icon(Iconsax.search_normal, size: 20),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildBody(TextTheme t) {
    if (_error != null) return ErrorRetry(message: _error!, onRetry: _load);
    if (_items == null) return const Center(child: CircularProgressIndicator());
    final items = _visible;
    if (items.isEmpty) {
      return EmptyState(
        icon: spec.icon,
        title: _query.isEmpty ? 'No ${spec.title.toLowerCase()} yet' : 'No matches',
        message: _query.isEmpty
            ? 'Tap "New ${spec.singular}" to add your first one.'
            : 'Try a different search.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final subtitle = spec.subtitle?.call(item) ?? '';
          final trailing = spec.trailing?.call(item) ?? '';
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openForm(item),
              onLongPress: () => _confirmDelete(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: spec.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(spec.icon, color: spec.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pickString(item, spec.titleKeys, spec.singular),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  t.titleMedium?.copyWith(fontSize: 15.5)),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall
                                      ?.copyWith(color: AppColors.inkMuted)),
                            ),
                        ],
                      ),
                    ),
                    if (trailing.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(trailing,
                            style: t.titleSmall?.copyWith(color: spec.color)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
