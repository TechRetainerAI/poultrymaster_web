import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/company.dart';
import '../state/session.dart';
import 'company_type_badge.dart';

/// Company switching as a bottom sheet.
///
/// Switching companies is frequent for multi-office users, and a full-screen
/// push for a three-item list is heavier than the task deserves. A sheet keeps
/// the current screen visible behind it and puts the choices under the thumb.
///
/// Returns true when the active company changed.
Future<bool> showCompanySwitcher(BuildContext context, Session session) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.tokens.card,
    builder: (sheetContext) => _CompanySwitcher(session: session),
  );
  return changed ?? false;
}

class _CompanySwitcher extends StatefulWidget {
  const _CompanySwitcher({required this.session});
  final Session session;

  @override
  State<_CompanySwitcher> createState() => _CompanySwitcherState();
}

class _CompanySwitcherState extends State<_CompanySwitcher> {
  String? _switchingTo;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final tokens = context.tokens;

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Switch company',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  if (session.organisationName != null)
                    Flexible(
                      child: Text(session.organisationName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: tokens.mutedForeground)),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                itemCount: session.myCompanies.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final c = session.myCompanies[i];
                  final isActive = session.active?.farmId == c.farmId;
                  final isBusy = _switchingTo == c.farmId;
                  return _CompanyTile(
                    company: c,
                    active: isActive,
                    busy: isBusy,
                    onTap: _switchingTo != null
                        ? null
                        : () async {
                            if (isActive) {
                              Navigator.of(context).pop(false);
                              return;
                            }
                            setState(() => _switchingTo = c.farmId);
                            final ok = await session.setActive(c);
                            if (!context.mounted) return;
                            if (ok) {
                              Navigator.of(context).pop(true);
                            } else {
                              setState(() => _switchingTo = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(session.error ??
                                        'Could not switch company.')),
                              );
                            }
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.company,
    required this.active,
    required this.busy,
    required this.onTap,
  });

  final Company company;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = TypeColors.accent(company.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusLg),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusLg),
            border: Border.all(color: active ? accent : tokens.border),
            color: active ? accent.withValues(alpha: .06) : null,
          ),
          child: Row(
            children: [
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(Dim.radiusMd),
                ),
                child: Icon(CompanyTypeBadge.iconFor(company.type),
                    size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(company.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        CompanyTypeBadge(type: company.type),
                        if (company.role != null) ...[
                          const SizedBox(width: 6),
                          Text(company.role!,
                              style: TextStyle(
                                  fontSize: 11.5, color: tokens.mutedForeground)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else if (active)
                Icon(Icons.check_circle, size: 20, color: accent)
              else
                Icon(Icons.chevron_right, size: 18, color: tokens.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
