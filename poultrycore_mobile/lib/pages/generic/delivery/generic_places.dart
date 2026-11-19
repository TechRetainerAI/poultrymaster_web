// The web's place helpers on Generic Deliveries and Routes: "Search"
// (OpenStreetMap's place search) and the route's travel time and distance
// (the public OSRM router). No live location: the app never reads where the
// phone is. The same public services the web
// calls, straight from the phone. Tests swap [GenericPlaces.backend].

import 'dart:convert';

import 'package:http/http.dart' as http;

/// A found place: its display name and where it is.
typedef Place = ({String name, double lat, double lon});

/// Where the places come from (the phone in the app, a fake in tests).
abstract class PlacesBackend {
  Future<Place?> search(String query);

  /// Driving time in seconds and distance in metres, or null.
  Future<({num seconds, num metres})?> drive(Place from, Place to);
}

class GenericPlaces {
  static PlacesBackend backend = _PhonePlaces();

  static Future<Place?> search(String query) => backend.search(query);

  /// The web's calcRoute text: "1h 5m (52.3 km)" or "25 min (12.0 km)".
  static Future<({String time, String km})?> travel(Place from, Place to) async {
    try {
      final d = await backend.drive(from, to);
      return d == null ? null : travelText(d.seconds, d.metres);
    } catch (_) {
      return null;
    }
  }
}

({String time, String km}) travelText(num seconds, num metres) {
  final km = '${(metres / 1000).toStringAsFixed(1)} km';
  final hrs = seconds ~/ 3600;
  final mins = ((seconds % 3600) / 60).round();
  final t = hrs > 0 ? '${hrs}h ${mins}m' : '$mins min';
  return (time: '$t ($km)', km: km);
}

class _PhonePlaces implements PlacesBackend {
  static const _headers = {'User-Agent': 'VisibilityCore-mobile'};

  @override
  Future<Place?> search(String query) async {
    final r = await http.get(
      Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1'),
      headers: _headers,
    );
    final d = jsonDecode(r.body);
    if (d is! List || d.isEmpty) return null;
    final f = d.first as Map;
    return (name: '${f['display_name']}', lat: double.parse('${f['lat']}'), lon: double.parse('${f['lon']}'));
  }

  @override
  Future<({num seconds, num metres})?> drive(Place from, Place to) async {
    final r = await http.get(Uri.parse('https://router.project-osrm.org/route/v1/driving/${from.lon},${from.lat};${to.lon},${to.lat}?overview=false'));
    final d = jsonDecode(r.body);
    final routes = d is Map ? d['routes'] : null;
    if (routes is! List || routes.isEmpty) return null;
    return (seconds: routes.first['duration'] as num, metres: routes.first['distance'] as num);
  }
}
