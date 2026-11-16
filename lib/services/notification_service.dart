import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../config.dart';
import '../utils/bangla.dart';
import 'location_service.dart';

/// প্রতিদিন সকালে একটি নোটিফিকেশন: আজকের তারিখ, নামাজের সময় ও নীতিবাক্য।
///
/// ফোন বন্ধ থাকলেও কাজ করে, কারণ অ্যাপ খোলার সময় সামনের ৭ দিনের নোটিফিকেশন
/// আগেই সাজিয়ে রাখা হয় (প্রতিদিনের আলাদা কনটেন্টসহ)।
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _kEnabled = 'notif_enabled';
  static const _kHour = 'notif_hour';
  static const _kMinute = 'notif_minute';

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConfig.timeZone));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final a = await android?.requestNotificationsPermission();
    final i = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return (a ?? true) && (i ?? true);
  }

  // ── সেটিংস
  static Future<({bool enabled, int hour, int minute})> settings() async {
    final p = await SharedPreferences.getInstance();
    return (
      enabled: p.getBool(_kEnabled) ?? true,
      hour: p.getInt(_kHour) ?? AppConfig.notifHour,
      minute: p.getInt(_kMinute) ?? AppConfig.notifMinute,
    );
  }

  static Future<void> saveSettings(bool enabled, int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setInt(_kHour, hour);
    await p.setInt(_kMinute, minute);
  }

  /// সামনের ৭ দিনের নোটিফিকেশন নতুন করে সাজায়। অ্যাপ খোলার সময় ডাকা হয়।
  static Future<void> reschedule(UserLocation loc, {int hijriOffset = 0}) async {
    await init();
    await _plugin.cancelAll();
    final s = await settings();
    if (!s.enabled) return;

    final quotes = (jsonDecode(await rootBundle.loadString('assets/data/quotes.json')) as List)
        .cast<String>();
    final times = await _weekPrayerTimes(loc);
    final now = tz.TZDateTime.now(tz.local);

    for (var i = 0; i < 7; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, s.hour, s.minute);
      if (at.isBefore(now)) continue;

      final t = times[_key(day)];
      final prayerLine = t == null
          ? ''
          : '🕌 ফজর ${Bangla.time12(t['Fajr']!)} • যোহর ${Bangla.time12(t['Dhuhr']!)} • '
              'আসর ${Bangla.time12(t['Asr']!)} • মাগরিব ${Bangla.time12(t['Maghrib']!)} • '
              'এশা ${Bangla.time12(t['Isha']!)}\n';
      final quote = quotes[Bangla.dayIndex(day) % quotes.length];

      final title = '${Bangla.weekday(day)}, ${Bangla.englishDate(day)}';
      final body = '📅 ${Bangla.banglaDate(day)}\n'
          '🌙 ${Bangla.hijriDate(day, hijriOffset)}\n'
          '$prayerLine'
          '💡 $quote';

      await _plugin.zonedSchedule(
        100 + i,
        title,
        body,
        at,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_brief',
            'প্রতিদিনের আপডেট',
            channelDescription: 'প্রতিদিন সকালে তারিখ, নামাজের সময় ও নীতিবাক্য',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// এখনই একটি নমুনা নোটিফিকেশন (সেটিংস থেকে পরীক্ষার জন্য)
  static Future<void> showTest() async {
    await init();
    await _plugin.show(
      99,
      AppConfig.appName,
      'নোটিফিকেশন চালু আছে ✅ প্রতিদিন সকালে আজকের আপডেট পাবেন।',
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_brief', 'প্রতিদিনের আপডেট'),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static String _key(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  /// Aladhan মাসিক ক্যালেন্ডার থেকে সামনের দিনগুলোর নামাজের সময়।
  /// ইন্টারনেট না থাকলে নোটিফিকেশনে নামাজের লাইনটি বাদ যাবে, বাকিটা থাকবে।
  static Future<Map<String, Map<String, String>>> _weekPrayerTimes(UserLocation loc) async {
    final result = <String, Map<String, String>>{};
    final now = DateTime.now();
    final months = {
      (now.year, now.month),
      (now.add(const Duration(days: 6)).year, now.add(const Duration(days: 6)).month),
    };
    for (final (y, m) in months) {
      try {
        final r = await http
            .get(Uri.parse('https://api.aladhan.com/v1/calendar/$y/$m'
                '?latitude=${loc.lat}&longitude=${loc.lng}'
                '&method=${AppConfig.prayerMethod}&school=${AppConfig.asrSchool}'))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) continue;
        for (final d in (jsonDecode(utf8.decode(r.bodyBytes))['data'] as List)) {
          final t = d['timings'] as Map<String, dynamic>;
          result[d['date']['gregorian']['date'] as String] = {
            for (final k in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'])
              k: (t[k] as String).split(' ').first,
          };
        }
      } catch (_) {}
    }
    return result;
  }
}
