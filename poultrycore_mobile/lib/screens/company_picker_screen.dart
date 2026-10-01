import 'package:flutter/material.dart';

import '../models/company.dart';
import '../state/session.dart';
import '../widgets/company_type_badge.dart';

class CompanyPickerScreen extends StatefulWidget {
  const CompanyPickerScreen({
    super.key,
    required this.session,
    required this.onPicked,
    this.allowBack = false,
  });

  final Session session;
  final VoidCallback onPicked;
  final bool allowBack;

  @override
  State<CompanyPickerScreen> createState() => _CompanyPickerScreenState();
}

class _CompanyPickerScreenState extends State<CompanyPickerScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.session.myCompanies.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() => widget.session.loadCompanies();

  Future<void> _choose(Company c) async {
    final ok = await widget.session.setActive(c);
    if (!mounted) return;
    if (ok) {
      widget.onPicked();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.session.error ?? 'Could not switch company.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a company'),
        automaticallyImplyLeading: widget.allowBack,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await session.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          if (session.busy && session.myCompanies.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (session.error != null && session.myCompanies.isEmpty) {
            return _Message(
              icon: Icons.cloud_off,
              title: 'Could not load your companies',
              detail: session.error!,
              actionLabel: 'Try again',
              onAction: _load,
            );
          }

          if (session.myCompanies.isEmpty) {
            return const _Message(
              icon: Icons.business_outlined,
              title: 'No companies yet',
              detail:
                  'This account is not linked to any company. Ask an administrator to grant access.',
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: session.myCompanies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = session.myCompanies[i];
                final isActive = session.active?.farmId == c.farmId;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          CompanyTypeBadge(type: c.type),
                          if (c.role != null) ...[
                            const SizedBox(width: 8),
                            Text(c.role!,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    trailing: session.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(isActive ? Icons.check_circle : Icons.chevron_right),
                    onTap: session.busy ? null : () => _choose(c),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
