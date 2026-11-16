import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../config.dart';
import '../utils/bangla.dart';
import 'cache.dart';
import 'location_service.dart';

const _timeout = Duration(seconds: 15);

Future<dynamic> _getJson(String url) async {
  final r = await http.get(Uri.parse(url)).timeout(_timeout);
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

// ───────────────────────── আবহাওয়া (Open-Meteo, কোনো API key লাগে না)
class WeatherService {
  static Future<Map<String, dynamic>> fetch(UserLocation loc, {bool force = false}) =>
      cached('weather', force: force, () async {
        final j = await _getJson(
          'https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lng}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'
          '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset'
          '&timezone=auto&forecast_days=1',
        );
        final c = j['current'], d = j['daily'];
        return {
          'city': loc.city,
          'temp': (c['temperature_2m'] as num).round(),
          'feels': (c['apparent_temperature'] as num).round(),
          'humidity': (c['relative_humidity_2m'] as num).round(),
          'wind': (c['wind_speed_10m'] as num).round(),
          'code': c['weather_code'],
          'max': (d['temperature_2m_max'][0] as num).round(),
          'min': (d['temperature_2m_min'][0] as num).round(),
          'rain': (d['precipitation_probability_max'][0] as num? ?? 0).round(),
        };
      });

  static (String, String) describe(int code) {
    if (code == 0) return ('☀️', 'আকাশ পরিষ্কার');
    if (code <= 2) return ('🌤️', 'আংশিক মেঘলা');
    if (code == 3) return ('☁️', 'মেঘলা আকাশ');
    if (code == 45 || code == 48) return ('🌫️', 'কুয়াশা');
    if (code >= 51 && code <= 57) return ('🌦️', 'গুঁড়ি গুঁড়ি বৃষ্টি');
    if (code >= 61 && code <= 67) return ('🌧️', 'বৃষ্টি');
    if (code >= 71 && code <= 77) return ('❄️', 'তুষারপাত');
    if (code >= 80 && code <= 82) return ('🌦️', 'থেমে থেমে বৃষ্টি');
    if (code >= 95) return ('⛈️', 'বজ্রসহ বৃষ্টি');
    return ('🌡️', 'আবহাওয়া');
  }

  /// এক লাইনের ছোট পরামর্শ
  static String tip(Map<String, dynamic> w) {
    final rain = w['rain'] as int, max = w['max'] as int, min = w['min'] as int;
    if (rain >= 60) return 'আজ বৃষ্টির সম্ভাবনা বেশি, ছাতা সঙ্গে রাখুন।';
    if (max >= 35) return 'আজ অনেক গরম, পর্যাপ্ত পানি পান করুন।';
    if (min <= 15) return 'আজ ঠান্ডা পড়বে, গরম কাপড় রাখুন।';
    if (rain >= 30) return 'হালকা বৃষ্টি হতে পারে।';
    return 'আজকের আবহাওয়া মোটামুটি আরামদায়ক।';
  }
}

// ───────────────────────── নামাজের সময় (Aladhan API)
class PrayerService {
  static const names = {
    'Fajr': 'ফজর',
    'Sunrise': 'সূর্যোদয়',
    'Dhuhr': 'যোহর',
    'Asr': 'আসর',
    'Maghrib': 'মাগরিব',
    'Isha': 'এশা',
  };

  static Future<Map<String, dynamic>> fetch(UserLocation loc, {bool force = false}) =>
      cached('prayer', force: force, () async {
        final n = DateTime.now();
        final date = '${n.day.toString().padLeft(2, '0')}-${n.month.toString().padLeft(2, '0')}-${n.year}';
        final j = await _getJson(
          'https://api.aladhan.com/v1/timings/$date?latitude=${loc.lat}&longitude=${loc.lng}'
          '&method=${AppConfig.prayerMethod}&school=${AppConfig.asrSchool}',
        );
        final t = j['data']['timings'] as Map<String, dynamic>;
        return {for (final k in names.keys) k: (t[k] as String).split(' ').first};
      });

  /// পরের ওয়াক্তের key (সূর্যোদয় বাদে)
  static String? next(Map<String, dynamic> times) {
    final now = DateTime.now();
    for (final k in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha']) {
      final p = (times[k] as String).split(':');
      final t = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      if (t.isAfter(now)) return k;
    }
    return 'Fajr'; // এশার পরে → পরের দিনের ফজর
  }
}

// ───────────────────────── খবর (Google News RSS)
class NewsItem {
  final String title, source, link;
  NewsItem(this.title, this.source, this.link);
  Map<String, dynamic> toJson() => {'t': title, 's': source, 'l': link};
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(j['t'], j['s'], j['l']);
}

class NewsService {
  static Future<List<NewsItem>> fetch({bool force = false}) async {
    final data = await cached('news', force: force, () async {
      final r = await http.get(Uri.parse(AppConfig.newsRssUrl)).timeout(_timeout);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final doc = XmlDocument.parse(utf8.decode(r.bodyBytes));
      final items = doc.findAllElements('item').take(10).map((e) {
        var title = e.getElement('title')?.innerText ?? '';
        final source = e.getElement('source')?.innerText ?? '';
        final cut = title.lastIndexOf(' - ');
        if (cut > 0) title = title.substring(0, cut);
        return NewsItem(title.trim(), source, e.getElement('link')?.innerText ?? '').toJson();
      }).toList();
      return {'items': items};
    });
    return (data['items'] as List).map((e) => NewsItem.fromJson(e)).toList();
  }
}

// ───────────────────────── কুরআনের বাণী (alquran.cloud, আরবি + বাংলা অনুবাদ)
class QuranService {
  static Future<Map<String, dynamic>> fetch({bool force = false}) async {
    try {
      return await cached('quran', force: force, () async {
        // প্রতিদিন আলাদা আয়াত (মোট ৬২৩৬ আয়াত)
        final n = (Bangla.dayIndex(DateTime.now()) * 97) % 6236 + 1;
        final j = await _getJson(
            'https://api.alquran.cloud/v1/ayah/$n/editions/quran-uthmani,bn.bengali');
        final list = j['data'] as List;
        final ar = list[0], bn = list[1];
        return {
          'arabic': ar['text'],
          'bangla': bn['text'],
          'ref': 'সূরা ${ar['surah']['englishName']} (${Bangla.digits(ar['surah']['number'])}:${Bangla.digits(ar['numberInSurah'])})',
        };
      });
    } catch (_) {
      final list = jsonDecode(await rootBundle.loadString('assets/data/quran_fallback.json')) as List;
      final v = list[Bangla.dayIndex(DateTime.now()) % list.length];
      return {'arabic': '', 'bangla': v['bangla'], 'ref': v['ref']};
    }
  }
}

// ───────────────────────── নীতিবাক্য ও ছোট গল্প (অ্যাপের ভেতরেই রাখা, প্রতিদিন বদলায়)
class LocalContent {
  static Future<String> quote() async {
    final list = jsonDecode(await rootBundle.loadString('assets/data/quotes.json')) as List;
    return list[Bangla.dayIndex(DateTime.now()) % list.length];
  }

  static Future<Map<String, dynamic>> story() async {
    final list = jsonDecode(await rootBundle.loadString('assets/data/stories.json')) as List;
    return list[Bangla.dayIndex(DateTime.now()) % list.length];
  }
}
