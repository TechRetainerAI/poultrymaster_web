import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import 'breed_picker.dart' show breedCatalog;

import 'package:poultrycore_mobile/design/tone.dart';

/// Layer and Broiler flocks (migration 399), as the web's
/// `lib/poultry/flock-type.ts` and `components/poultry/flock-type-select.tsx`.
///
/// Every flock is one or the other. The company's business type (Layers |
/// Broilers | Both) is only the DEFAULT for a new flock: a farm may run both
/// at once, so the flock is what decides whether its screens ask about eggs.
const flockTypes = ['Layer', 'Broiler'];

const flockTypeLabels = {
  'Layer': 'Layers (eggs)',
  'Broiler': 'Broilers (meat)',
};

/// Anything the API did not send (a database before 399) is a Layer flock.
String flockTypeOf(Map? flock) {
  final t = flock?['flockType'] ?? flock?['FlockType'];
  return t == 'Broiler' ? 'Broiler' : 'Layer';
}

bool isBroilerFlock(Map? flock) => flockTypeOf(flock) == 'Broiler';

/// breeds.ts `breedKey`.
String breedKey(String? raw) => (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

final Set<String> _broilerBreeds = {
  for (final (group, breeds) in breedCatalog)
    if (group == 'Broilers')
      for (final b in breeds) breedKey(b),
};

/// A breed that only makes sense as a meat bird: the catalog's Broilers
/// group, plus the same name fragments the database matches, so "Cobb",
/// "ross 308" and the misspelt "Broiller" all count.
bool isBroilerBreed(String? breed) {
  final key = breedKey(breed);
  if (key.isEmpty) return false;
  return _broilerBreeds.contains(key) || RegExp('(broil|cobb|ross|arbor|hubbard)').hasMatch(key);
}

/// The type a new flock starts with: a broiler breed, else the company's
/// business type, else Layer. Same order as fnpoultry_defaultflocktype.
String defaultFlockType(String? breed, String? businessType) {
  if (isBroilerBreed(breed)) return 'Broiler';
  if (businessType == 'Broilers') return 'Broiler';
  return 'Layer';
}

bool _closedOrDeleted(Map f) => '${f['closedDate'] ?? ''}'.isNotEmpty || f['isDeleted'] == true;

/// Should the egg screens (sorting, egg tracker, broken eggs, egg settings,
/// the egg section of a production record) be offered at all?
///
/// Yes while ANY open flock lays. Only when no open flock is a layer AND
/// there is a positive sign the farm is a broiler farm (an open broiler
/// flock, or a company set to Broilers) are they hidden. With nothing loaded
/// yet, or an empty farm with no business type, the answer is yes.
bool showEggFeatures(List<Map>? flocks, String? businessType) {
  final open = (flocks ?? const <Map>[]).where((f) => !_closedOrDeleted(f)).toList();
  if (open.any((f) => flockTypeOf(f) == 'Layer')) return true;
  if (open.any((f) => flockTypeOf(f) == 'Broiler')) return false;
  return businessType != 'Broilers';
}

/// Should the broiler screens (Broiler performance) be offered? Yes once the
/// company has ever had a broiler flock, or is set to Broilers or Both. With
/// nothing known the answer is yes, as for eggs.
bool showBroilerFeatures(List<Map>? flocks, String? businessType) {
  if (flocks == null) return true;
  if (flocks.any((f) => f['isDeleted'] != true && flockTypeOf(f) == 'Broiler')) return true;
  return businessType == 'Broilers' || businessType == 'Both';
}

/// Whether a batch is a broiler batch for the sale form: every one of its
/// flocks is a Broiler flock; a batch not yet divided into flocks goes by its
/// breed. A batch mixing layers and broilers is not -- the form cannot guess
/// which birds are being sold.
bool isBroilerBatch(int batchId, List<Map> flocks, String? batchBreed) {
  if (batchId == 0) return false;
  final own = flocks.where((f) => int.tryParse('${f['batchId'] ?? ''}') == batchId).toList();
  if (own.isNotEmpty) return own.every(isBroilerFlock);
  return isBroilerBreed(batchBreed);
}

/// The sale product for broiler birds: the "Chicken" option on the sale form.
const broilerSaleProduct = 'Chicken';

/// Picking a broiler flock or batch switches the sale's product to Chicken,
/// but only away from an egg product or a blank one, which a broiler never
/// sells. Anything else the seller already chose is left alone.
bool shouldSwitchToChicken(String? currentProduct) {
  final p = (currentProduct ?? '').trim().toLowerCase();
  return p.isEmpty || (p.contains('egg') && !p.contains('broken'));
}

final Map<String, (DateTime, String?)> _businessTypes = {};

/// usePoultryBusinessType: the company profile's business type (Layers |
/// Broilers | Both), or null when there is no profile. Kept ten minutes per
/// company, as the web's query does.
Future<String?> loadPoultryBusinessType(Session session, Company company) async {
  final hit = _businessTypes[company.farmId];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 10)) return hit.$2;
  String? type;
  try {
    final p = await session.farmClient.get('/api/Poultry/company', query: {'farmId': company.farmId});
    final m = p is Map && p['data'] is Map ? p['data'] as Map : p;
    if (m is Map) {
      final t = '${m['businessType'] ?? m['BusinessType'] ?? ''}';
      type = t.isEmpty ? null : t;
    }
  } catch (_) {
    // No profile (404) or no answer: the web's hook gives null too.
    return null;
  }
  _businessTypes[company.farmId] = (DateTime.now(), type);
  return type;
}

/// For tests: forget the cached business types.
void clearPoultryBusinessTypes() => _businessTypes.clear();

/// The Layer / Broiler picker.
///
/// On a NEW flock it starts "automatic": it shows the type the server will
/// give the flock and sends nothing, so the database rule stays the one
/// authority. Choosing a type makes it explicit. On an existing flock the
/// stored type is always explicit.
class FlockTypeSelect extends StatelessWidget {
  const FlockTypeSelect({
    super.key,
    required this.value,
    required this.onChanged,
    this.automatic = false,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// True while the value is the automatic default rather than a choice.
  final bool automatic;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          for (final t in flockTypes) ...[
            if (t != flockTypes.first) const SizedBox(width: 8),
            Expanded(child: _option(t)),
          ],
        ]),
        const SizedBox(height: 6),
        Text(
          automatic
              ? "Set from the breed and your company type. Change it if it's wrong."
              : value == 'Broiler'
                  ? 'Meat birds: no egg records for this flock.'
                  : 'Laying birds: egg records are kept for this flock.',
          style: const TextStyle(fontSize: 12, color: _slate500),
        ),
      ],
    );
  }

  Widget _option(String t) {
    final selected = value == t;
    final fg = selected ? _orange700 : _slate600;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: Material(
          color: selected ? _orange50 : Tone.bg(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: selected ? _orange500 : _slate200),
          ),
          child: InkWell(
            key: ValueKey('flock-type-$t'),
            borderRadius: BorderRadius.circular(6),
            onTap: enabled ? () => onChanged(t) : null,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(t == 'Broiler' ? Icons.set_meal_outlined : Icons.egg_outlined, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      flockTypeLabels[t]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: fg),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orange "Broiler" badge on a flock's name.
class BroilerBadge extends StatelessWidget {
  const BroilerBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: _orange100,
          border: Border.all(color: _orange200),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('Broiler', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _orange800)),
      );
}

const _orange50 = Tone.bg(0xFFFFF7ED);
const _orange100 = Tone.bg(0xFFFFEDD5);
const _orange200 = Tone.line(0xFFFED7AA);
const _orange500 = Tone.line(0xFFF97316);
const _orange700 = Tone.fg(0xFFC2410C);
const _orange800 = Tone.fg(0xFF9A3412);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
