import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// প্রতিদিনের ডেটা ফোনে জমা রাখে, যাতে একই দিনে বারবার ইন্টারনেট না লাগে
/// এবং অফলাইনেও শেষ ডেটা দেখা যায়।
class Cache {
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<Map<String, dynamic>?> getToday(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('cache_$key');
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m['date'] == _today() ? m['data'] as Map<String, dynamic> : null;
  }

  /// তারিখ যাই হোক, শেষবার সেভ করা ডেটা (অফলাইন ব্যাকআপ)।
  static Future<Map<String, dynamic>?> getLast(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('cache_$key');
    if (raw == null) return null;
    return (jsonDecode(raw) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  static Future<void> put(String key, Map<String, dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cache_$key', jsonEncode({'date': _today(), 'data': data}));
  }

  static Future<int> getInt(String key, int def) async =>
      (await SharedPreferences.getInstance()).getInt(key) ?? def;

  static Future<void> setInt(String key, int v) async =>
      (await SharedPreferences.getInstance()).setInt(key, v);

  static Future<String> getString(String key, String def) async =>
      (await SharedPreferences.getInstance()).getString(key) ?? def;

  static Future<void> setString(String key, String v) async =>
      (await SharedPreferences.getInstance()).setString(key, v);
}

/// কেশ থেকে নেয়, না থাকলে ইন্টারনেট থেকে আনে, ব্যর্থ হলে শেষ ডেটা দেখায়।
Future<Map<String, dynamic>> cached(
  String key,
  Future<Map<String, dynamic>> Function() fetch, {
  bool force = false,
}) async {
  if (!force) {
    final c = await Cache.getToday(key);
    if (c != null) return c;
  }
  try {
    final data = await fetch();
    await Cache.put(key, data);
    return data;
  } catch (e) {
    final last = await Cache.getLast(key);
    if (last != null) return last;
    rethrow;
  }
}
