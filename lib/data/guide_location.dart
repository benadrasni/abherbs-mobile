import 'package:abherbs_flutter/data/guide_results.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

final Map<String, Future<String?>> _countryLookups = {};

/// This phone's position, for a photo taken now. Never asks for permission.
/// Null when location is not granted, switched off, or has no fix in time.
Future<({double latitude, double longitude})?> locateGuidePhone() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) return null;
    return (latitude: position.latitude, longitude: position.longitude);
  } catch (error) {
    debugPrint('guide phone position: $error');
    return null;
  }
}

/// Reads this phone's place and returns its floristic region code.
/// Throws [GuideLocationRefused] when location permission is denied. A phone
/// with no fix, indoors or on a simulator, would otherwise wait forever, so
/// both lookups time out.
Future<String?> locateGuideRegion() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const GuideLocationRefused();
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.low,
      timeLimit: Duration(seconds: 15),
    ),
  );
  final marks = await Geocoding()
      .placemarkFromCoordinates(position.latitude, position.longitude)
      .timeout(const Duration(seconds: 10));
  if (marks.isEmpty) return null;
  final place = marks.first;
  return guideRegionForPlace(
    countryCode: place.isoCountryCode,
    adminArea: place.administrativeArea,
    latitude: position.latitude,
    longitude: position.longitude,
  );
}

/// ISO country of a find. 0, 0 is no place and does not ask. One lookup is
/// shared by every photo at the same thousandth of a degree.
Future<String?> guideCountryCode(double latitude, double longitude) {
  if (!_onGlobe(latitude, longitude)) return Future<String?>.value(null);
  final key = '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
  final existing = _countryLookups[key];
  if (existing != null) return existing;
  final lookup = _readCountry(latitude, longitude).then((code) {
    if (code == null) _countryLookups.remove(key);
    return code;
  });
  _countryLookups[key] = lookup;
  return lookup;
}

bool _onGlobe(double latitude, double longitude) {
  if (!latitude.isFinite || !longitude.isFinite) return false;
  if (latitude == 0 && longitude == 0) return false;
  if (latitude.abs() > 90 || longitude.abs() > 180) return false;
  return true;
}

Future<String?> _readCountry(double latitude, double longitude) async {
  try {
    final marks = await Geocoding()
        .placemarkFromCoordinates(latitude, longitude)
        .timeout(const Duration(seconds: 10));
    if (marks.isEmpty) return null;
    return guideRowCountry(marks.first.isoCountryCode);
  } catch (error) {
    debugPrint('guide country: $error');
    return null;
  }
}
