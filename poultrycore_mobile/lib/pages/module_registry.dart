import 'custom_form.dart';
import 'form_spec.dart';
import 'generated_forms.dart';
import 'page_extras.dart';
import 'poultry/poultry_extras.dart';
import 'poultry/poultry_forms.dart';
import 'poultry/reports/report_routes.dart';
import 'poultry/trackers/tracker_routes.dart';
import 'restaurant/reports/restaurant_report_routes.dart';
import 'restaurant/restaurant_extras.dart';
import 'restaurant/restaurant_forms.dart';
import 'shared/shared_forms.dart';
import 'shared/staff_employee_link.dart';
import 'water/water_extras.dart';
import 'water/reports/water_report_routes.dart';
import 'water/water_forms.dart';

/// Every module's hand-made pieces in one place, for the list and record
/// screens. Each company type keeps its own in `pages/<module>/` — Poultry's
/// forms are never offered to Water, and the other way round — and this file
/// only joins them. Spec keys are module-prefixed (`water-staff`,
/// `poultry-staff`), so the maps cannot collide.

/// Hand-written forms that replace the ones extracted from the web markup.
const Map<String, FormDef> curatedForms = {...poultryForms, ...waterForms, ...restaurantForms};

/// Pages with a screen of their own instead of the shared FormScreen.
const Map<String, CustomFormBuilder> customForms = {
  ...sharedCustomForms,
  ...poultryCustomForms,
  ...waterCustomForms,
  ...restaurantCustomForms,
};

final Map<String, List<ListExtra>> listExtras = {
  ...poultryListExtras,
  ...waterListExtras,
  ...restaurantListExtras,
};
/// Merged per key, so a page keeps its own buttons (Staff → Attendance) beside
/// the shared ones (Staff → Make employee).
final Map<String, List<RecordExtra>> recordExtras = {
  for (final m in [poultryRecordExtras, waterRecordExtras, restaurantRecordExtras, staffLinkRecordExtras])
    for (final MapEntry(:key, :value) in m.entries) key: value,
}..updateAll((key, _) => [
    for (final m in [poultryRecordExtras, waterRecordExtras, restaurantRecordExtras, staffLinkRecordExtras]) ...?m[key],
  ]);
final Map<String, List<ListFilter>> listFilters = {
  ...poultryListFilters,
  ...waterListFilters,
  ...restaurantListFilters,
};
final Map<String, DeleteGuard> deleteGuards = {...waterDeleteGuards, ...restaurantDeleteGuards, ...poultryDeleteGuards};
final Map<String, BeforeLoad> beforeLoad = {...poultryBeforeLoad};
final Map<String, RowEnrich> rowEnrich = {...staffLinkRowEnrich};
final Map<String, RowBadge> rowBadges = {...staffLinkRowBadges};

/// Routes that are screens of their own, keyed by web href.
final Map<String, PageScreenBuilder> pageScreens = {
  ...sharedPageScreens,
  ...poultryPageScreens,
  ...poultryReportScreens,
  ...poultryTrackerScreens,
  ...waterPageScreens,
  ...waterReportScreens,
  ...restaurantPageScreens,
  ...restaurantReportScreens,
};

/// The form for a spec: the curated one when there is one, else the extracted.
FormDef? formForSpec(String specKey) {
  final curated = curatedForms[specKey];
  if (curated != null) return curated;
  for (final def in generatedForms.values) {
    if (def.specKey == specKey) return def;
  }
  return null;
}
