import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/web_mobile.dart';
import 'page_headers.dart';

/// Tailwind 100/600 pairs for the page-header icon tile.
({Color bg, Color fg}) tileColors(String? family) {
  switch (family) {
    case 'green':
      return (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF16A34A));
    case 'blue':
      return (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF2563EB));
    case 'amber':
      return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFFD97706));
    case 'orange':
      return (bg: const Color(0xFFFFEDD5), fg: const Color(0xFFEA580C));
    case 'purple':
      return (bg: const Color(0xFFF3E8FF), fg: const Color(0xFF9333EA));
    case 'violet':
      return (bg: const Color(0xFFEDE9FE), fg: const Color(0xFF7C3AED));
    case 'rose':
      return (bg: const Color(0xFFFFE4E6), fg: const Color(0xFFE11D48));
    case 'sky':
      return (bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0284C7));
    case 'emerald':
      return (bg: const Color(0xFFD1FAE5), fg: const Color(0xFF059669));
    case 'indigo':
      return (bg: const Color(0xFFE0E7FF), fg: const Color(0xFF4F46E5));
    default:
      return (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF475569));
  }
}

/// Icon tile + title + description, as every web page opens.
class ListPageHeader extends StatelessWidget {
  const ListPageHeader({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.color,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? color;

  @override
  Widget build(BuildContext context) {
    final c = tileColors(color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // w-10 h-10 rounded-lg
        Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(Dim.radiusLg),
          ),
          child: Icon(icon, size: 20, color: c.fg),
        ),
        const SizedBox(width: 12), // gap-3
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // text-xl font-bold text-slate-900
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      height: 1.2)),
              const SizedBox(height: 2),
              // text-sm text-slate-600
              Text(description,
                  style: const TextStyle(
                      fontSize: 13.5, color: Color(0xFF475569), height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The blue primary action: full width on a phone, h-11.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;

  /// The web colours this per page — blue on Sales, green on Production. Uses
  /// the page header's own colour family so the two always agree.
  final String? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44, // h-11
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        style: FilledButton.styleFrom(
          backgroundColor: _buttonColor(color),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dim.radiusMd)),
        ),
      ),
    );
  }
}

/// Solid button colour for a page's colour family, matching the web's
/// `bg-{family}-600`.
Color _buttonColor(String? family) {
  switch (family) {
    case 'green':
      return const Color(0xFF16A34A);
    case 'emerald':
      return const Color(0xFF059669);
    case 'amber':
      return const Color(0xFFD97706);
    case 'orange':
      return const Color(0xFFEA580C);
    case 'purple':
      return const Color(0xFF9333EA);
    case 'violet':
      return const Color(0xFF7C3AED);
    case 'rose':
      return const Color(0xFFE11D48);
    case 'sky':
      return const Color(0xFF0284C7);
    case 'indigo':
      return const Color(0xFF4F46E5);
    default:
      return const Color(0xFF2563EB); // blue-600
  }
}

/// The Filters / PDF / Email row the web puts under the search box.
class ListActionRow extends StatelessWidget {
  const ListActionRow({
    super.key,
    this.onFilters,
    this.onExport,
    this.onEmail,
  });

  final VoidCallback? onFilters;
  final VoidCallback? onExport;
  final VoidCallback? onEmail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Btn(icon: Icons.filter_list, label: 'Filters', onTap: onFilters),
        const SizedBox(width: 8),
        // Labelled CSV rather than PDF: that is what the file actually is.
        _Btn(icon: Icons.download_outlined, label: 'CSV', onTap: onExport),
        const SizedBox(width: 8),
        _Btn(icon: Icons.mail_outline, label: 'Email', onTap: onEmail),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(Dim.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF334155)),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155))),
            ],
          ),
        ),
      ),
    );
  }
}

/// A summary card above the list: plain-case title with a small muted icon,
/// then the figure and a sub-line. Distinct from the dashboard's cards, which
/// use uppercase labels and a filled colour tile.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.sub,
    required this.icon,
    this.valueColor,
  });

  final String title;
  final String value;
  final String? sub;
  final IconData icon;

  /// The web colours some figures: emerald for totals that are good news,
  /// red for deaths and losses. Null keeps the default slate.
  final Color? valueColor;

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
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: WebMobile.cardValue)),
              ),
              Icon(icon, size: 16, color: tokens.mutedForeground),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: valueColor ?? WebMobile.cardValue)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!,
                style:
                    TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ],
      ),
    );
  }
}

/// Looks up the web's header for a page, falling back to the spec's own title.
PageHeaderDef headerFor(String specKey, String fallbackTitle) =>
    pageHeaders[specKey] ??
    PageHeaderDef(title: fallbackTitle, description: '');
