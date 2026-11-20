import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// পছন্দের লেখা (হাদিস, আয়াত, নীতিবাক্য, গল্প ইত্যাদি) সংরক্ষণ
class Bookmark {
  final String type, title, text, ref;
  const Bookmark(this.type, this.title, this.text, {this.ref = ''});
  String get id => '$type|$text'.hashCode.toString();
  Map<String, dynamic> toJson() => {'y': type, 't': title, 'x': text, 'r': ref};
  factory Bookmark.fromJson(Map<String, dynamic> j) =>
      Bookmark(j['y'] as String, j['t'] as String, j['x'] as String, ref: (j['r'] ?? '') as String);
}

class Bookmarks {
  static const _key = 'bookmarks_v1';
  static final ValueNotifier<List<Bookmark>> items = ValueNotifier(const []);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    items.value = (jsonDecode(raw) as List)
        .map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static bool has(Bookmark b) => items.value.any((e) => e.id == b.id);

  static Future<void> toggle(Bookmark b) async {
    final list = [...items.value];
    final i = list.indexWhere((e) => e.id == b.id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.insert(0, b);
    }
    items.value = list;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}
