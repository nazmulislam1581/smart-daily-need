import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';

class UserLocation {
  final double lat, lng;
  final String city;
  const UserLocation(this.lat, this.lng, this.city);
}

class LocationService {
  static Future<UserLocation> get() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _fallback;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return _fallback;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      var city = 'আপনার এলাকা';
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          city = [p.locality, p.subAdministrativeArea, p.administrativeArea]
              .firstWhere((s) => s != null && s.isNotEmpty, orElse: () => city)!;
        }
      } catch (_) {}
      return UserLocation(pos.latitude, pos.longitude, city);
    } catch (_) {
      return _fallback;
    }
  }

  static const _fallback =
      UserLocation(AppConfig.defaultLat, AppConfig.defaultLng, AppConfig.defaultCity);
}
