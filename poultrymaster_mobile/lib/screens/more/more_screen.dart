import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../resources/resources.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../resource/resource_list_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final app = context.watch<AppState>();
    final session = app.session;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const AppLogo(size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session?.farmName ?? 'My Farm',
                            style: t.titleMedium, overflow: TextOverflow.ellipsis),
                        Text('@${session?.username ?? ''}',
                            style: t.bodySmall?.copyWith(color: AppColors.inkMuted)),
                        if (session?.isStaff == true)
                          Text('Staff account',
                              style: t.labelSmall?.copyWith(color: AppColors.info)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Farm setup', style: t.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (final (i, spec) in farmSetupSpecs.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 60),
                  ListTile(
                    leading: Icon(spec.icon, color: spec.color),
                    title: Text(spec.title),
                    trailing: const Icon(Iconsax.arrow_right_3, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ResourceListScreen(spec: spec)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Account', style: t.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Iconsax.logout, color: AppColors.danger),
              title: const Text('Sign out'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: const Text('Sign out?'),
                    content: const Text('You will need to sign in again to see your farm.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AppState>().signOut();
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('${AppConfig.appName} for Android',
                style: t.labelSmall?.copyWith(color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }
}
