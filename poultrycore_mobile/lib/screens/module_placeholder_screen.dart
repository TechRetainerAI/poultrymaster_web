import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/company.dart';
import '../models/module.dart';
import '../pages/list_screen.dart';
import '../pages/module_registry.dart';
import '../pages/registry.dart';
import '../state/session.dart';
import '../widgets/company_type_badge.dart';

/// Dashboard module keys whose web page has a different href.
const _moduleHrefs = {'feed-tracker': '/feed-tracker'};

/// Poultry tabs that are native pages (the bottom bar's Sales).
const _poultryModuleHrefs = {'sales': '/sales'};

/// Opens the real page for [module] when a spec exists, otherwise the
/// "not built yet" screen. One place decides, so navigation never has to know
/// which pages are done.
Widget pageFor({
  required AppModule module,
  required Company company,
  required Session session,
}) {
  // A module that is a native page of its own (More → Feed tracker).
  final href = _moduleHrefs[module.key] ??
      (company.type == CompanyType.poultry ? _poultryModuleHrefs[module.key] : null);
  final native = href == null ? null : pageScreens[href];
  if (native != null) return native(session, company);
  final spec = PageRegistry.of(module.key);
  if (spec != null) {
    return ListScreen(spec: spec, session: session, company: company);
  }
  return ModulePlaceholderScreen(module: module, company: company);
}

/// Stands in for a module whose screens are not built yet.
///
/// It says plainly what is missing and where the work currently lives, rather
/// than showing an empty list that reads like a bug or a loading failure.
class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({
    super.key,
    required this.module,
    required this.company,
  });

  final AppModule module;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = TypeColors.accent(company.type);

    return Scaffold(
      appBar: AppBar(title: Text(module.label)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 64,
                width: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(Dim.radiusXl),
                ),
                child: Icon(module.icon, size: 30, color: accent),
              ),
              const SizedBox(height: 18),
              Text(module.label,
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Not built on mobile yet. This module is available on the web '
                'for ${company.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5, height: 1.5, color: tokens.mutedForeground),
              ),
              const SizedBox(height: 18),
              CompanyTypeBadge(type: company.type, dense: false),
            ],
          ),
        ),
      ),
    );
  }
}
