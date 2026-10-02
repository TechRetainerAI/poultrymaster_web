import 'package:flutter/material.dart';

import '../config/env.dart';
import '../design/tokens.dart';

/// Always-visible reminder of which backend the build is talking to.
///
/// This has no web counterpart — the web has an address bar, a phone does not,
/// and the project has a documented history of builds silently pointing at the
/// wrong API. Colours come from the ported token set (muted for dev, destructive
/// for production) rather than anything invented, so it still reads as part of
/// the same design.
class EnvBanner extends StatelessWidget {
  const EnvBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final prod = Env.isProd;
    final tokens = context.tokens;

    final bg = prod ? tokens.destructive.withValues(alpha: .10) : tokens.muted;
    final fg = prod ? tokens.destructive : tokens.mutedForeground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        border: prod ? Border.all(color: tokens.destructive.withValues(alpha: .35)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(prod ? Icons.warning_amber_rounded : Icons.science_outlined,
              size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            prod ? 'PRODUCTION — live data' : 'DEV environment',
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
