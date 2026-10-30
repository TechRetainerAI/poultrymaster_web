
import '../../design/ui/inputs.dart';
import '../page_extras.dart';

/// What the Restaurant web pages offer beyond Add / Edit / Delete.

final Map<String, List<ListExtra>> restaurantListExtras = {};

final Map<String, List<RecordExtra>> restaurantRecordExtras = {};

/// SEGMENTS in app/restaurant-crm/page.tsx.
const restaurantSegments = ['New', 'Regular', 'VIP', 'Lapsed'];

final Map<String, List<ListFilter>> restaurantListFilters = {
  // The "All Segments" picker above the customer list.
  'restaurant-crm-customers': [
    ListFilter(
      key: 'segment',
      label: 'Segment',
      allLabel: 'All Segments',
      options: (_, _, _) async => [
        for (final s in restaurantSegments) AppSelectItem(value: s, label: s),
      ],
      matches: (row, v) => '${row['segment']}' == v,
    ),
  ],
};

final Map<String, DeleteGuard> restaurantDeleteGuards = {};
