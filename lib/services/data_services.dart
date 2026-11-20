import 'package:flutter/foundation.dart' show kIsWeb;
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
/// একটি ওয়াক্ত বা সময়সীমা: শুরু ও শেষ
class PrayerSlot {
  final String key, name;
  final DateTime start, end;
  final String? note;
  final bool fard;
  const PrayerSlot(this.key, this.name, this.start, this.end, {this.note, this.fard = false});
  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }
}

class PrayerService {
  static const _keys = [
    'Imsak', 'Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Sunset', 'Maghrib', 'Isha',
    'Midnight', 'Lastthird'
  ];

  static Future<Map<String, dynamic>> fetch(UserLocation loc, {bool force = false}) =>
      cached('prayer_v2', force: force, () async {
        final n = DateTime.now();
        final date = '${n.day.toString().padLeft(2, '0')}-${n.month.toString().padLeft(2, '0')}-${n.year}';
        final j = await _getJson(
          'https://api.aladhan.com/v1/timings/$date?latitude=${loc.lat}&longitude=${loc.lng}'
          '&method=${AppConfig.prayerMethod}&school=${AppConfig.asrSchool}',
        );
        final t = j['data']['timings'] as Map<String, dynamic>;
        return {
          for (final k in _keys)
            if (t[k] != null) k: (t[k] as String).split(' ').first,
        };
      });

  static DateTime _at(Map<String, dynamic> t, String key, {int addDays = 0}) {
    final p = (t[key] as String).split(':');
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + addDays, int.parse(p[0]), int.parse(p[1]));
  }

  /// আজকের সব ওয়াক্তের শুরু ও শেষ সময়
  static List<PrayerSlot> slots(Map<String, dynamic> t) {
    final friday = DateTime.now().weekday == DateTime.friday;
    final fajr = _at(t, 'Fajr'), sunrise = _at(t, 'Sunrise'), dhuhr = _at(t, 'Dhuhr');
    final asr = _at(t, 'Asr'), maghrib = _at(t, 'Maghrib'), isha = _at(t, 'Isha');
    final sunset = t['Sunset'] != null ? _at(t, 'Sunset') : maghrib;
    final nextFajr = _at(t, 'Fajr', addDays: 1);
    var midnight = t['Midnight'] != null ? _at(t, 'Midnight') : nextFajr;
    if (midnight.isBefore(isha)) midnight = midnight.add(const Duration(days: 1));
    var lastThird = t['Lastthird'] != null ? _at(t, 'Lastthird') : midnight;
    if (lastThird.isBefore(isha)) lastThird = lastThird.add(const Duration(days: 1));

    return [
      PrayerSlot('Fajr', 'ফজর', fajr, sunrise, fard: true),
      PrayerSlot('Ishraq', 'ইশরাক / চাশত', sunrise.add(const Duration(minutes: 20)),
          dhuhr.subtract(const Duration(minutes: 10)),
          note: 'নফল নামাজ'),
      PrayerSlot('Dhuhr', friday ? 'জুমা' : 'যোহর', dhuhr, asr,
          fard: true,
          note: friday ? 'জুমার খুতবার সময় স্থানীয় মসজিদে জেনে নিন' : null),
      PrayerSlot('Asr', 'আসর', asr, sunset,
          fard: true, note: 'সূর্যাস্তের আগের ১৫ মিনিট মাকরুহ'),
      PrayerSlot('Maghrib', 'মাগরিব', maghrib, isha, fard: true),
      PrayerSlot('Isha', 'এশা', isha, nextFajr,
          fard: true, note: 'মধ্যরাত (${Bangla.time12(_hm(midnight))}) এর আগে পড়া উত্তম'),
      PrayerSlot('Tahajjud', 'তাহাজ্জুদ', lastThird, nextFajr,
          note: 'রাতের শেষ তৃতীয়াংশ, সবচেয়ে উত্তম সময়'),
    ];
  }

  /// নামাজ পড়া নিষিদ্ধ সময় (আনুমানিক)
  static List<PrayerSlot> forbidden(Map<String, dynamic> t) {
    final sunrise = _at(t, 'Sunrise'), dhuhr = _at(t, 'Dhuhr');
    final sunset = t['Sunset'] != null ? _at(t, 'Sunset') : _at(t, 'Maghrib');
    return [
      PrayerSlot('f1', 'সূর্যোদয়', sunrise, sunrise.add(const Duration(minutes: 15))),
      PrayerSlot('f2', 'দ্বিপ্রহর', dhuhr.subtract(const Duration(minutes: 8)), dhuhr),
      PrayerSlot('f3', 'সূর্যাস্ত', sunset.subtract(const Duration(minutes: 15)), sunset),
    ];
  }

  /// রমজানে সেহরি ও ইফতার
  static ({DateTime sehri, DateTime iftar}) sehriIftar(Map<String, dynamic> t) =>
      (sehri: _at(t, 'Fajr'), iftar: _at(t, 'Maghrib'));

  static String _hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  static String fmt(DateTime d) => Bangla.time12(_hm(d));

  /// "6:12 AM"
  static String fmtEn(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// এখনকার ফরজ ওয়াক্ত (না থাকলে null) ও পরের ফরজ ওয়াক্ত
  static ({PrayerSlot? current, PrayerSlot next, Duration until}) status(Map<String, dynamic> t) {
    final all = slots(t).where((s) => s.fard).toList();
    final now = DateTime.now();
    PrayerSlot? current;
    for (final s in all) {
      if (s.isNow) current = s;
    }
    PrayerSlot? next;
    for (final s in all) {
      if (s.start.isAfter(now)) {
        next = s;
        break;
      }
    }
    if (next == null) {
      // এশার পরে → আগামীকালের ফজর
      final f = all.first;
      next = PrayerSlot(f.key, f.name, f.start.add(const Duration(days: 1)),
          f.end.add(const Duration(days: 1)), fard: true);
    }
    // ফজরের আগে গতকালের এশা চলছে
    if (current == null && now.isBefore(all.first.start)) {
      current = PrayerSlot('Isha', 'এশা', now, all.first.start, fard: true);
    }
    return (current: current, next: next, until: next.start.difference(now));
  }

  static String duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h > 0) return '${Bangla.digits(h)} ঘণ্টা ${Bangla.digits(m)} মিনিট';
    return '${Bangla.digits(d.inMinutes)} মিনিট';
  }
}

// ───────────────────────── খবর (প্রথম আলো RSS, ছবিসহ; ব্যর্থ হলে Google News)
class NewsItem {
  final String title, source, link, image, summary;
  final DateTime? time;
  NewsItem(this.title, this.source, this.link,
      {this.image = '', this.summary = '', this.time});
  Map<String, dynamic> toJson() => {
        't': title, 's': source, 'l': link, 'i': image, 'd': summary,
        'p': time?.toIso8601String(),
      };
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        (j['t'] ?? '') as String,
        (j['s'] ?? '') as String,
        (j['l'] ?? '') as String,
        image: (j['i'] ?? '') as String,
        summary: (j['d'] ?? '') as String,
        time: j['p'] == null ? null : DateTime.tryParse(j['p'] as String),
      );

  /// "৩ ঘণ্টা আগে"
  String get ago {
    if (time == null) return '';
    final d = DateTime.now().difference(time!.toLocal());
    if (d.inMinutes < 1) return 'এইমাত্র';
    if (d.inMinutes < 60) return '${Bangla.digits(d.inMinutes)} মিনিট আগে';
    if (d.inHours < 24) return '${Bangla.digits(d.inHours)} ঘণ্টা আগে';
    return '${Bangla.digits(d.inDays)} দিন আগে';
  }
}

class NewsService {
  static const _media = 'http://search.yahoo.com/mrss/';
  static final _imgRe = RegExp('<img[^>]+src="([^"]+)"');

  static String _strip(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'&nbsp;|&#160;'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static DateTime? _date(String? s) {
    if (s == null || s.isEmpty) return null;
    // RFC 822: "Fri, 20 Nov 2026 18:21:13 +0000"
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):?(\d{2})? ?([+-]\d{4}|GMT|UTC|Z)?')
        .firstMatch(s);
    if (m == null) return DateTime.tryParse(s);
    final mon = months.indexOf(m.group(2)!) + 1;
    if (mon == 0) return DateTime.tryParse(s);
    var dt = DateTime.utc(int.parse(m.group(3)!), mon, int.parse(m.group(1)!), int.parse(m.group(4)!),
        int.parse(m.group(5)!), int.parse(m.group(6) ?? '0'));
    final tz = m.group(7);
    if (tz != null && (tz.startsWith('+') || tz.startsWith('-'))) {
      final sign = tz.startsWith('-') ? -1 : 1;
      final off = Duration(hours: int.parse(tz.substring(1, 3)), minutes: int.parse(tz.substring(3, 5)));
      dt = sign > 0 ? dt.subtract(off) : dt.add(off);
    }
    return dt;
  }

  static String _image(XmlElement e) {
    final content = e.findElements('content', namespace: _media);
    if (content.isNotEmpty) {
      final u = content.first.getAttribute('url');
      if (u != null && u.isNotEmpty) return '${u.split('?').first}?w=720';
    }
    final thumb = e.findElements('thumbnail', namespace: _media);
    if (thumb.isNotEmpty) {
      final u = thumb.first.getAttribute('url');
      if (u != null && u.isNotEmpty) return u;
    }
    final enc = e.getElement('enclosure')?.getAttribute('url');
    if (enc != null && enc.isNotEmpty) return enc;
    final html = e.getElement('description')?.innerText ?? '';
    return _imgRe.firstMatch(html)?.group(1) ?? '';
  }

  static Future<List<Map<String, dynamic>>> _parse(String url, String defaultSource) async {
    final r = await http.get(Uri.parse(url)).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final doc = XmlDocument.parse(utf8.decode(r.bodyBytes));
    final google = defaultSource.isEmpty;
    return doc.findAllElements('item').take(10).map((e) {
      var title = e.getElement('title')?.innerText.trim() ?? '';
      final source = e.getElement('source')?.innerText ?? defaultSource;
      final cut = title.lastIndexOf(' - ');
      if (google && cut > 0) title = title.substring(0, cut);
      var summary = google ? '' : _strip(e.getElement('description')?.innerText ?? '');
      if (summary.length > 160) summary = '${summary.substring(0, 157)}...';
      return NewsItem(
        title,
        source,
        e.getElement('link')?.innerText.trim() ?? '',
        image: _image(e),
        summary: summary,
        time: _date(e.getElement('pubDate')?.innerText),
      ).toJson();
    }).toList();
  }

  static Future<List<NewsItem>> fetch({bool force = false}) async {
    final data = await cached('news_v2', force: force, () async {
      // ওয়েবসাইটে ব্রাউজারের নিয়মে সরাসরি RSS পড়া যায় না, তাই GitHub-এর news.json
      Future<List<Map<String, dynamic>>> fromJson() async {
        final r = await http.get(Uri.parse('${AppConfig.contentBaseUrl}news.json')).timeout(_timeout);
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        return ((jsonDecode(utf8.decode(r.bodyBytes))['items'] as List))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      List<Map<String, dynamic>> items;
      if (kIsWeb) {
        items = await fromJson();
      } else {
        try {
          items = await _parse(AppConfig.newsRssUrl, AppConfig.newsSourceName);
          if (items.isEmpty) throw Exception('empty');
        } catch (_) {
          try {
            items = await fromJson();
          } catch (_) {
            items = await _parse(AppConfig.newsFallbackRssUrl, '');
          }
        }
      }
      return {'items': items};
    });
    return (data['items'] as List)
        .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ───────────────────────── কুরআনের বাণী: ৪৫০টি বাছাই করা উপদেশমূলক আয়াত (আরবি + বাংলা, অফলাইন)
class QuranService {
  static Future<Map<String, dynamic>> fetch({bool force = false}) async {
    final list = jsonDecode(await rootBundle.loadString('assets/data/quran_verses.json')) as List;
    final v = list[(Bangla.dayIndex(DateTime.now()) * 7) % list.length] as Map<String, dynamic>;
    return {
      'arabic': (v['arabic'] ?? '') as String,
      'bangla': (v['bangla'] ?? '') as String,
      'ref': v['label'] as String,
    };
  }
}

// ───────────────────────── অ্যাপের ভেতরের কনটেন্ট (প্রতিদিন নিজে থেকে বদলায়)
class LocalContent {
  static Future<dynamic> _asset(String name) async =>
      jsonDecode(await rootBundle.loadString('assets/data/$name.json'));

  /// এই কনটেন্টগুলো GitHub থেকে প্রতিদিন হালনাগাদ হয় (নতুন আইটেম যোগ হতে থাকে)।
  /// ইন্টারনেট না থাকলে শেষ ডাউনলোড বা অ্যাপের ভেতরের কপি ব্যবহার হয়।
  static const _remoteBanks = {'quotes', 'stories', 'jokes', 'health_tips', 'gk_quiz', 'famous_quotes'};

  static Future<dynamic> _load(String name) async {
    if (_remoteBanks.contains(name)) {
      try {
        final m = await cached('bank_$name', () async {
          final r = await http
              .get(Uri.parse('${AppConfig.contentBaseUrl}banks/$name.json'))
              .timeout(_timeout);
          if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
          return {'v': jsonDecode(utf8.decode(r.bodyBytes))};
        });
        final local = await _asset(name);
        final remote = m['v'];
        // যেটায় বেশি আইটেম, সেটাই ব্যবহার
        if (remote is List && local is List) return remote.length >= local.length ? remote : local;
        if (remote is Map && local is Map) {
          final rl = ((remote['bd'] as List?)?.length ?? 0) + ((remote['world'] as List?)?.length ?? 0);
          final ll = ((local['bd'] as List?)?.length ?? 0) + ((local['world'] as List?)?.length ?? 0);
          return rl >= ll ? remote : local;
        }
      } catch (_) {}
    }
    return _asset(name);
  }

  /// আজকের কুইজ: সাম্প্রতিক বাংলাদেশ (২টি) + বিশ্ব (৩টি)।
  /// GitHub-এ প্রতিদিন নতুন প্রশ্ন আসে; না পেলে সাধারণ জ্ঞানের প্রশ্ন।
  static Future<({String label, List<Map<String, dynamic>> bd, List<Map<String, dynamic>> world})>
      quiz() async {
    List<Map<String, dynamic>> cast(dynamic l) =>
        ((l as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    try {
      final m = await cached('quiz_today', () async {
        final r = await http
            .get(Uri.parse('${AppConfig.contentBaseUrl}quiz.json'))
            .timeout(_timeout);
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      });
      final d = DateTime.tryParse('${m['date']}');
      final age = d == null ? 99 : DateTime.now().difference(d).inDays;
      final bd = cast(m['bd']), world = cast(m['world']);
      if (age <= 3 && bd.isNotEmpty && world.isNotEmpty) {
        return (
          label: 'সাম্প্রতিক • ${Bangla.digits(d!.day)} ${Bangla.englishMonths[d.month - 1]}',
          bd: bd,
          world: world,
        );
      }
    } catch (_) {}
    final g = await _load('gk_quiz') as Map;
    final bdAll = cast(g['bd']), wAll = cast(g['world']);
    final i = Bangla.dayIndex(DateTime.now());
    return (
      label: 'সাধারণ জ্ঞান',
      bd: [for (var k = 0; k < 2; k++) bdAll[(i * 2 + k) % bdAll.length]],
      world: [for (var k = 0; k < 3; k++) wAll[(i * 3 + k) % wAll.length]],
    );
  }

  static Future<T> _pick<T>(String name, {int salt = 0}) async {
    final list = await _load(name) as List;
    return list[(Bangla.dayIndex(DateTime.now()) + salt) % list.length] as T;
  }

  static Future<String> quote() => _pick<String>('quotes');
  static Future<Map<String, dynamic>> story() => _pick<Map<String, dynamic>>('stories');
  static Future<Map<String, dynamic>> hadith() => _pick<Map<String, dynamic>>('hadith', salt: 7);
  static Future<String> joke() => _pick<String>('jokes', salt: 3);
  static Future<Map<String, dynamic>> famousQuote() =>
      _pick<Map<String, dynamic>>('famous_quotes', salt: 5);
  static Future<Map<String, dynamic>> healthTip() =>
      _pick<Map<String, dynamic>>('health_tips', salt: 11);

  /// নির্দিষ্ট তারিখের দিবসগুলো (ক্যালেন্ডারের জন্যও)
  static Future<List<String>> daysOn(DateTime d, int hijriOffset) async {
    final m = await _load('days') as Map<String, dynamic>;
    final greg = (m['gregorian'] as Map<String, dynamic>);
    final hij = (m['hijri'] as Map<String, dynamic>);
    final gk = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = <String>[...((greg[gk] as List?) ?? const []).cast<String>()];
    final h = Bangla.hijri(d, hijriOffset);
    final hd = hij['${h.month}-${h.day}'] as List?;
    if (hd != null) r.addAll(hd.cast<String>().map((e) => '$e (চাঁদ দেখা সাপেক্ষে)'));
    return r;
  }

  /// আজকের দিবস। না থাকলে সামনের দিবসটি দেখায়।
  static Future<({List<String> today, String? nextName, DateTime? nextDate})> days(
      int hijriOffset) async {
    final now = DateTime.now();
    final today = await daysOn(now, hijriOffset);
    for (var i = 1; i <= 60; i++) {
      final d = DateTime(now.year, now.month, now.day + i);
      final l = await daysOn(d, hijriOffset);
      if (l.isNotEmpty) return (today: today, nextName: l.first, nextDate: d);
    }
    return (today: today, nextName: null, nextDate: null);
  }

  /// সময় অনুযায়ী আমল: সকাল / দিন / সন্ধ্যা / রাত
  static Future<Map<String, dynamic>> amol(Map<String, dynamic>? prayer) async {
    final m = await _load('amol') as Map<String, dynamic>;
    final now = DateTime.now();
    String period;
    if (prayer != null && prayer['Fajr'] != null) {
      DateTime at(String k) {
        final p = (prayer[k] as String).split(':');
        return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      }

      if (now.isBefore(at('Fajr'))) {
        period = 'night';
      } else if (now.isBefore(at('Dhuhr'))) {
        period = 'morning';
      } else if (now.isBefore(at('Asr'))) {
        period = 'day';
      } else if (now.isBefore(at('Isha'))) {
        period = 'evening';
      } else {
        period = 'night';
      }
    } else {
      final h = now.hour;
      period = h < 5 ? 'night' : h < 12 ? 'morning' : h < 16 ? 'day' : h < 20 ? 'evening' : 'night';
    }
    return m[period] as Map<String, dynamic>;
  }
}

// ───────────────────────── ইতিহাসে আজকের দিন (Wikipedia "On this day", ইংরেজি)
class HistoryService {
  static Future<List<({String year, String text})>> onThisDay({bool force = false}) async {
    final n = DateTime.now();
    final mm = n.month.toString().padLeft(2, '0'), dd = n.day.toString().padLeft(2, '0');
    final data = await cached('onthisday', force: force, () async {
      final j = await _getJson(
          'https://en.wikipedia.org/api/rest_v1/feed/onthisday/selected/$mm/$dd');
      final list = ((j['selected'] as List?) ?? const []).take(6).map((e) => {
            'y': '${e['year']}',
            't': '${e['text']}',
          }).toList();
      return {'items': list};
    });
    return (data['items'] as List)
        .map((e) => (year: '${e['y']}', text: '${e['t']}'))
        .toList();
  }
}
