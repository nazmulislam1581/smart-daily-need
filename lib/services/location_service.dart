import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
      return UserLocation(pos.latitude, pos.longitude,
          await _cityName(pos.latitude, pos.longitude));
    } catch (_) {
      return _fallback;
    }
  }

  /// শহরের নাম (BigDataCloud-এর ফ্রি রিভার্স জিওকোডিং, কোনো API key লাগে না)
  static Future<String> _cityName(double lat, double lng) async {
    try {
      final r = await http
          .get(Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client'
              '?latitude=$lat&longitude=$lng&localityLanguage=bn'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        for (final k in ['city', 'locality', 'principalSubdivision']) {
          final v = j[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return 'আপনার এলাকা';
  }

  static const _fallback =
      UserLocation(AppConfig.defaultLat, AppConfig.defaultLng, AppConfig.defaultCity);
}
