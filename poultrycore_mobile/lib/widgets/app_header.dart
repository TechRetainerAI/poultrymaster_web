import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/web_mobile.dart';
import '../models/company.dart';
import '../widgets/company_type_badge.dart';

/// The dark app header the web shows on a phone: hamburger, the VisibilityCore
/// wordmark, a chat icon and the user avatar.
class WebAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const WebAppHeader({
    super.key,
    required this.onMenu,
    this.onAvatar,
    this.showLogoTile = true,
  });

  final VoidCallback onMenu;
  final VoidCallback? onAvatar;

  /// The loaded header shows a small rounded logo tile before the wordmark.
  final bool showLogoTile;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: WebMobile.header,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(),
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white, size: 22),
        onPressed: onMenu,
      ),
      titleSpacing: 0,
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogoTile) ...[
            Container(
              height: 26,
              width: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.visibility, size: 15, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          const Text(
            'VisibilityCore',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
          onPressed: () {},
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onAvatar,
            child: Container(
              height: 30,
              width: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF9333EA), // purple avatar
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 17, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dark strip under the header naming the active company.
class CompanyBar extends StatelessWidget {
  const CompanyBar({super.key, required this.company, required this.onTap});

  final Company company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = TypeColors.accent(company.type);

    return Material(
      color: WebMobile.companyBar,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Container(
                height: 30,
                width: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(Dim.radiusMd),
                ),
                child: Icon(CompanyTypeBadge.iconFor(company.type),
                    size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'COMPANY',
                      style: TextStyle(
                        color: accent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      company.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more, size: 18, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashboard stat card: uppercase label, large value, small description, and
/// a coloured rounded icon tile on the right.
class WebStatCard extends StatelessWidget {
  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(Dim.radiusXl),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebMobile.cardLabel,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: WebMobile.cardValue,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: WebMobile.cardHint, fontSize: 11, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
