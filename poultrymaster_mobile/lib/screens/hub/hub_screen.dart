import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme.dart';
import '../../resources/resource_spec.dart';
import '../resource/resource_list_screen.dart';

/// A tab that presents a group of modules as large tappable tiles.
class HubScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ResourceSpec> specs;
  const HubScreen({super.key, required this.title, required this.subtitle, required this.specs});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(subtitle, style: t.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [for (final s in specs) _ModuleTile(spec: s)],
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final ResourceSpec spec;
  const _ModuleTile({required this.spec});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ResourceListScreen(spec: spec)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(spec.icon, color: spec.color, size: 24),
              ),
              const Spacer(),
              Text(spec.title, style: t.titleMedium?.copyWith(fontSize: 15.5)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('Open',
                      style: t.labelSmall?.copyWith(color: AppColors.inkMuted)),
                  const SizedBox(width: 4),
                  const Icon(Iconsax.arrow_right_3, size: 14, color: AppColors.inkMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
