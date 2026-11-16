import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../services/cache.dart';
import '../services/data_services.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../utils/bangla.dart';
import '../widgets/section_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _day = DateTime.now();
  int _hijriOffset = AppConfig.defaultHijriOffset;

  Future<Map<String, dynamic>>? _weather, _prayer, _quran, _story;
  Future<List<NewsItem>>? _news;
  Future<String>? _quote;
  Future<UserLocation>? _loc;
  Timer? _ticker;

  /// প্রথমবার অনুমতি চায়, তারপর সামনের ৭ দিনের সকালের নোটিফিকেশন সাজায়
  Future<void> _scheduleNotifications() async {
    try {
      final asked = await Cache.getInt('notif_asked', 0);
      if (asked == 0) {
        await NotificationService.init();
        await NotificationService.requestPermission();
        await Cache.setInt('notif_asked', 1);
      }
      final l = await _loc!;
      await NotificationService.reschedule(l, hijriOffset: _hijriOffset);
    } catch (e) {
      debugPrint('Notification schedule failed: $e');
    }
  }

  Future<void> _openNotificationSettings() async {
    final s = await NotificationService.settings();
    if (!mounted) return;
    var enabled = s.enabled;
    var time = TimeOfDay(hour: s.hour, minute: s.minute);
    String fmt(TimeOfDay t) =>
        Bangla.time12('${t.hour}:${t.minute.toString().padLeft(2, '0')}');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔔 প্রতিদিনের নোটিফিকেশন',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('প্রতিদিন সকালে আজকের তারিখ, নামাজের সময় ও নীতিবাক্য পাবেন।',
                textAlign: TextAlign.center),
            SwitchListTile(
              title: const Text('নোটিফিকেশন চালু'),
              value: enabled,
              onChanged: (v) => setSheet(() => enabled = v),
            ),
            ListTile(
              enabled: enabled,
              leading: const Icon(Icons.schedule),
              title: const Text('সময়'),
              trailing: Text(fmt(time), style: const TextStyle(fontSize: 16)),
              onTap: () async {
                final t = await showTimePicker(context: c, initialTime: time);
                if (t != null) setSheet(() => time = t);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await NotificationService.requestPermission();
                    await NotificationService.showTest();
                  },
                  child: const Text('পরীক্ষা করুন'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('সেভ করুন'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (saved == true) {
      await NotificationService.saveSettings(enabled, time.hour, time.minute);
      if (enabled) await NotificationService.requestPermission();
      await _scheduleNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(enabled
              ? 'প্রতিদিন ${fmt(time)} নোটিফিকেশন আসবে'
              : 'নোটিফিকেশন বন্ধ করা হয়েছে'),
        ));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Cache.getInt('hijri_offset', AppConfig.defaultHijriOffset)
        .then((v) { if (mounted) setState(() => _hijriOffset = v); });
    _load();
    // প্রতি মিনিটে দেখে: পরের নামাজ বদলেছে কিনা, বা দিন বদলেছে কিনা
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _checkNewDay());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// অ্যাপ আবার খুললে নতুন দিন হলে সব আপডেট হবে
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNewDay();
  }

  void _checkNewDay() {
    final now = DateTime.now();
    if (now.day != _day.day || now.month != _day.month || now.year != _day.year) {
      _day = now;
      _load();
    } else {
      setState(() {}); // পরের ওয়াক্ত হাইলাইট আপডেট
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _quote = LocalContent.quote();
      _story = LocalContent.story();
      _news = NewsService.fetch(force: force);
      _quran = QuranService.fetch(force: force);
      final loc = LocationService.get();
      _loc = loc;
      _weather = loc.then((l) => WeatherService.fetch(l, force: force));
      _prayer = loc.then((l) => PrayerService.fetch(l, force: force));
    });
    _scheduleNotifications();
    await Future.wait(<Future<Object>>[_news!, _weather!, _prayer!, _quran!]
        .map((f) => f.then<void>((_) {}, onError: (_) {})));
  }

  Future<void> _editHijri() async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('হিজরি তারিখ ঠিক করুন'),
        children: [-2, -1, 0, 1, 2].map((o) {
          final label = o == 0 ? 'কোনো পরিবর্তন নেই' : '${o > 0 ? '+' : '−'}${Bangla.digits(o.abs())} দিন';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(c, o),
            child: Text('${o == _hijriOffset ? '✓ ' : '   '}$label  →  ${Bangla.hijriDate(DateTime.now(), o)}'),
          );
        }).toList(),
      ),
    );
    if (v != null) {
      await Cache.setInt('hijri_offset', v);
      setState(() => _hijriOffset = v);
      _scheduleNotifications();
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'শুভ রাত্রি';
    if (h < 12) return 'শুভ সকাল';
    if (h < 17) return 'শুভ দুপুর';
    if (h < 20) return 'শুভ সন্ধ্যা';
    return 'শুভ রাত্রি';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text(AppConfig.appName, style: TextStyle(fontWeight: FontWeight.w800)),
              actions: [
                IconButton(
                  tooltip: 'নোটিফিকেশন',
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _openNotificationSettings,
                ),
                IconButton(
                  tooltip: 'রিফ্রেশ',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _load(force: true),
                ),
              ],
            ),
            SliverList.list(children: [
              // ── তারিখ
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                ),
                child: DefaultTextStyle(
                  style: TextStyle(color: cs.onPrimary, fontSize: 15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_greeting()} • ${Bangla.weekday(now)}',
                        style: TextStyle(color: cs.onPrimary.withValues(alpha: .85))),
                    const SizedBox(height: 6),
                    Text(Bangla.englishDate(now),
                        style: TextStyle(color: cs.onPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    _dateRow('📅', Bangla.banglaDate(now)),
                    InkWell(
                      onTap: _editHijri,
                      child: _dateRow('🌙', '${Bangla.hijriDate(now, _hijriOffset)}  ✎'),
                    ),
                  ]),
                ),
              ),

              // ── আবহাওয়া
              SectionCard(
                icon: '🌤️',
                title: 'আজকের আবহাওয়া',
                child: AsyncSection<Map<String, dynamic>>(
                  future: _weather,
                  builder: (w) {
                    final (emoji, desc) = WeatherService.describe(w['code'] as int);
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(emoji, style: const TextStyle(fontSize: 44)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${Bangla.digits(w['temp'])}°সে • $desc',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            Text('📍 ${w['city']}  •  সর্বোচ্চ ${Bangla.digits(w['max'])}° / সর্বনিম্ন ${Bangla.digits(w['min'])}°'),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _chip('💧 আর্দ্রতা ${Bangla.digits(w['humidity'])}%'),
                        _chip('🌧️ বৃষ্টি ${Bangla.digits(w['rain'])}%'),
                        _chip('💨 বাতাস ${Bangla.digits(w['wind'])} কিমি/ঘ'),
                      ]),
                      const SizedBox(height: 8),
                      Text(WeatherService.tip(w), style: TextStyle(color: cs.secondary)),
                    ]);
                  },
                ),
              ),

              // ── নামাজের সময়
              SectionCard(
                icon: '🕌',
                title: 'আজকের নামাজের সময়',
                child: AsyncSection<Map<String, dynamic>>(
                  future: _prayer,
                  builder: (t) {
                    final next = PrayerService.next(t);
                    return Column(
                      children: PrayerService.names.entries.map((e) {
                        final isNext = e.key == next;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isNext ? cs.primaryContainer : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(e.value + (isNext ? '  (পরবর্তী)' : ''),
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w500)),
                            ),
                            Text(Bangla.time12(t[e.key]),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isNext ? FontWeight.w700 : FontWeight.w500)),
                          ]),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),

              // ── খবর
              SectionCard(
                icon: '📰',
                title: 'আজকের শীর্ষ ১০ খবর',
                child: AsyncSection<List<NewsItem>>(
                  future: _news,
                  builder: (items) => Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => launchUrl(Uri.parse(items[i].link),
                              mode: LaunchMode.externalApplication),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: cs.secondaryContainer,
                                child: Text(Bangla.digits(i + 1), style: const TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(items[i].title,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  if (items[i].source.isNotEmpty)
                                    Text(items[i].source,
                                        style: TextStyle(fontSize: 12, color: cs.outline)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── নীতিবাক্য
              SectionCard(
                icon: '💡',
                title: 'আজকের নীতিবাক্য',
                child: AsyncSection<String>(
                  future: _quote,
                  builder: (q) => Text('“$q”',
                      style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, height: 1.5)),
                ),
              ),

              // ── কুরআনের বাণী
              SectionCard(
                icon: '📖',
                title: 'কুরআনের বাণী',
                child: AsyncSection<Map<String, dynamic>>(
                  future: _quran,
                  builder: (q) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if ((q['arabic'] as String).isNotEmpty)
                      Text(q['arabic'],
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontSize: 22, height: 1.9)),
                    const SizedBox(height: 8),
                    Text(q['bangla'], style: const TextStyle(fontSize: 16, height: 1.6)),
                    const SizedBox(height: 6),
                    Text('— ${q['ref']}', style: TextStyle(color: cs.outline)),
                  ]),
                ),
              ),

              // ── ছোট গল্প
              SectionCard(
                icon: '📚',
                title: 'আজকের ছোট গল্প',
                child: AsyncSection<Map<String, dynamic>>(
                  future: _story,
                  builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(s['body'], style: const TextStyle(fontSize: 15.5, height: 1.65)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Text('শিক্ষা: ${s['moral']}',
                          style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _dateRow(String icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Text(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: const TextStyle(fontSize: 13)),
      );
}
