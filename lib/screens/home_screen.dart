import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../services/cache.dart';
import '../services/data_services.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../utils/bangla.dart';
import '../widgets/quiz_card.dart';
import '../widgets/section_card.dart';

// কার্ডের রং
const _cDibos = Color(0xFFD9480F);
const _cWeather = Color(0xFF1971C2);
const _cAmol = Color(0xFF0B7285);
const _cPrayer = Color(0xFF0E8C6C);
const _cNews = Color(0xFF5F3DC4);
const _cQuote = Color(0xFFE67700);
const _cQuran = Color(0xFF087F5B);
const _cHadith = Color(0xFF2B8A3E);
const _cStory = Color(0xFFC2255C);
const _cJoke = Color(0xFFF08C00);
const _cHealth = Color(0xFFE03131);
const _cQuiz = Color(0xFF1864AB);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _day = DateTime.now();
  int _hijriOffset = AppConfig.defaultHijriOffset;
  int _tab = 0;
  int _minutes = 0;

  Future<Map<String, dynamic>>? _weather, _prayer, _quran, _story, _hadith, _amol, _health;
  Future<List<NewsItem>>? _news;
  Future<String>? _quote, _joke;
  Future<({List<String> today, String? nextName, DateTime? nextDate})>? _days;
  Future<({String label, List<Map<String, dynamic>> bd, List<Map<String, dynamic>> world})>? _quiz;
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
    Cache.getInt('hijri_offset', AppConfig.defaultHijriOffset).then((v) {
      if (!mounted) return;
      setState(() => _hijriOffset = v);
      _days = LocalContent.days(v);
    });
    _load();
    // প্রতি মিনিটে: কাউন্টডাউন ও আমল হালনাগাদ, দিন বদলালে সব নতুন করে,
    // প্রতি ৩০ মিনিটে খবর এবং প্রতি ঘণ্টায় আবহাওয়া নিজে থেকে আপডেট
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    if (now.day != _day.day || now.month != _day.month || now.year != _day.year) {
      _day = now;
      _load();
      return;
    }
    _minutes++;
    setState(() {
      _amol = _prayer!.then((p) => LocalContent.amol(p), onError: (_) => LocalContent.amol(null));
      if (_minutes % 30 == 0) _news = NewsService.fetch(force: true);
      if (_minutes % 60 == 0) {
        _weather = _loc!.then((l) => WeatherService.fetch(l, force: true));
      }
    });
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _quote = LocalContent.quote();
      _story = LocalContent.story();
      _hadith = LocalContent.hadith();
      _joke = LocalContent.joke();
      _health = LocalContent.healthTip();
      _quiz = LocalContent.quiz();
      _days = LocalContent.days(_hijriOffset);
      _news = NewsService.fetch(force: force);
      _quran = QuranService.fetch(force: force);
      final loc = LocationService.get();
      _loc = loc;
      _weather = loc.then((l) => WeatherService.fetch(l, force: force));
      _prayer = loc.then((l) => PrayerService.fetch(l, force: force));
      _amol = _prayer!.then((p) => LocalContent.amol(p), onError: (_) => LocalContent.amol(null));
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
          final label =
              o == 0 ? 'কোনো পরিবর্তন নেই' : '${o > 0 ? '+' : '−'}${Bangla.digits(o.abs())} দিন';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(c, o),
            child: Text(
                '${o == _hijriOffset ? '✓ ' : '   '}$label  →  ${Bangla.hijriDate(DateTime.now(), o)}'),
          );
        }).toList(),
      ),
    );
    if (v != null) {
      await Cache.setInt('hijri_offset', v);
      setState(() {
        _hijriOffset = v;
        _days = LocalContent.days(v);
      });
      _scheduleNotifications();
    }
  }

  // ─────────────────────────────── সময় অনুযায়ী থিম
  ({String greet, List<Color> colors, String emoji}) _mood() {
    final h = DateTime.now().hour;
    if (h >= 4 && h < 7) {
      return (greet: 'শুভ ভোর', colors: const [Color(0xFF5F3DC4), Color(0xFFF76707)], emoji: '🌅');
    }
    if (h >= 7 && h < 12) {
      return (greet: 'শুভ সকাল', colors: const [Color(0xFF0B7285), Color(0xFF20C997)], emoji: '☀️');
    }
    if (h >= 12 && h < 16) {
      return (greet: 'শুভ দুপুর', colors: const [Color(0xFF087F5B), Color(0xFF51CF66)], emoji: '🌤️');
    }
    if (h >= 16 && h < 19) {
      return (greet: 'শুভ সন্ধ্যা', colors: const [Color(0xFFE8590C), Color(0xFF862E9C)], emoji: '🌇');
    }
    return (greet: 'শুভ রাত্রি', colors: const [Color(0xFF1B1F4B), Color(0xFF3B5BDB)], emoji: '🌙');
  }

  // ─────────────────────────────── BUILD
  @override
  Widget build(BuildContext context) {
    final pages = [_todayPage(), _prayerPage(), _newsPage(), _readPage()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'আজ'),
          NavigationDestination(
              icon: Icon(Icons.mosque), selectedIcon: Icon(Icons.mosque), label: 'নামাজ'),
          NavigationDestination(
              icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'খবর'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'পাঠ'),
        ],
      ),
    );
  }

  Widget _page(List<Widget> children, {Widget? header, String? title}) {
    final mood = _mood();
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (header != null)
            SliverToBoxAdapter(child: header)
          else
            SliverAppBar(
              pinned: true,
              expandedHeight: 110,
              foregroundColor: Colors.white,
              backgroundColor: mood.colors.first,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(title ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                background: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: mood.colors)),
                ),
              ),
              actions: _actions(),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverList.list(children: [...children, const SizedBox(height: 24)]),
        ],
      ),
    );
  }

  List<Widget> _actions() => [
        IconButton(
          tooltip: 'অ্যাপ সম্পর্কে',
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: _showAbout,
        ),
        IconButton(
          tooltip: 'নোটিফিকেশন',
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: _openNotificationSettings,
        ),
        IconButton(
          tooltip: 'রিফ্রেশ',
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () => _load(force: true),
        ),
      ];

  // ─────────────────────────────── হেডার
  Widget _hero() {
    final mood = _mood();
    final now = DateTime.now();
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 8, 8, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: mood.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text(AppConfig.appName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            ..._actions(),
          ]),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${mood.greet} • ${Bangla.weekday(now)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: .85))),
                  const SizedBox(height: 2),
                  Text(Bangla.englishDate(now),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                ]),
              ),
              Text(mood.emoji, style: const TextStyle(fontSize: 44)),
            ]),
          ),
          const SizedBox(height: 12),
          _glass(Column(children: [
            _dateRow('📅', Bangla.banglaDate(now)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _editHijri,
              child: _dateRow('🌙', '${Bangla.hijriDate(now, _hijriOffset)}  ✎'),
            ),
          ])),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, dynamic>>(
            future: _prayer,
            builder: (c, s) {
              if (!s.hasData) return const SizedBox.shrink();
              final st = PrayerService.status(s.data!);
              return InkWell(
                onTap: () => setState(() => _tab = 1),
                child: _glass(Row(children: [
                  const Text('🕌', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (st.current != null)
                        Text(
                            'এখন চলছে: ${st.current!.name} • শেষ ${PrayerService.fmt(st.current!.end)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(
                          'পরবর্তী ${st.next.name} ${PrayerService.fmt(st.next.start)} • বাকি ${PrayerService.duration(st.until)}',
                          style: TextStyle(color: Colors.white.withValues(alpha: .9))),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ])),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _glass(Widget child) => Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
        ),
        child: child,
      );

  Widget _dateRow(String icon, String text) => Row(children: [
        Text(icon),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
      ]);

  // ─────────────────────────────── ট্যাব ১: আজ
  Widget _todayPage() {
    final cs = Theme.of(context).colorScheme;
    return _page(header: _hero(), [
      // আজ কী দিবস
      SectionCard(
        icon: '🗓️',
        title: 'আজ কী দিবস',
        accent: _cDibos,
        child: AsyncSection<({List<String> today, String? nextName, DateTime? nextDate})>(
          future: _days,
          builder: (d) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (d.today.isEmpty)
              Text('আজ উল্লেখযোগ্য কোনো দিবস নেই।', style: TextStyle(color: cs.onSurfaceVariant))
            else
              ...d.today.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('✦ ', style: TextStyle(color: _cDibos, fontSize: 16)),
                      Expanded(
                        child: Text(t,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  )),
            if (d.nextName != null) ...[
              const SizedBox(height: 6),
              Pill('সামনে: ${d.nextName} • ${Bangla.digits(d.nextDate!.day)} ${Bangla.englishMonths[d.nextDate!.month - 1]}',
                  color: _cDibos),
            ],
          ]),
        ),
      ),

      // আবহাওয়া
      SectionCard(
        icon: '🌤️',
        title: 'আজকের আবহাওয়া',
        accent: _cWeather,
        child: AsyncSection<Map<String, dynamic>>(
          future: _weather,
          builder: (w) {
            final (emoji, desc) = WeatherService.describe(w['code'] as int);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 46)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${Bangla.digits(w['temp'])}°সে',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                    Text('$desc • 📍 ${w['city']}'),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                Pill('⬆️ ${Bangla.digits(w['max'])}° ⬇️ ${Bangla.digits(w['min'])}°', color: _cWeather),
                Pill('💧 ${Bangla.digits(w['humidity'])}%', color: _cWeather),
                Pill('🌧️ ${Bangla.digits(w['rain'])}%', color: _cWeather),
                Pill('💨 ${Bangla.digits(w['wind'])} কিমি/ঘ', color: _cWeather),
              ]),
              const SizedBox(height: 10),
              Text(WeatherService.tip(w), style: TextStyle(color: cs.onSurfaceVariant)),
            ]);
          },
        ),
      ),

      // স্বাস্থ্য টিপস
      SectionCard(
        icon: '🩺',
        title: 'আজকের স্বাস্থ্য টিপস',
        accent: _cHealth,
        child: AsyncSection<Map<String, dynamic>>(
          future: _health,
          builder: (h) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['icon'], style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h['title'],
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(h['text'], style: const TextStyle(fontSize: 15.5, height: 1.6)),
              ]),
            ),
          ]),
        ),
      ),

      // সময় অনুযায়ী আমল
      AsyncSection<Map<String, dynamic>>(
        future: _amol,
        builder: (a) => SectionCard(
          icon: '🤲',
          title: a['title'] as String,
          subtitle: a['note'] as String,
          accent: _cAmol,
          child: Column(
            children: (a['items'] as List).map((e) => _amolTile(e as Map<String, dynamic>)).toList(),
          ),
        ),
      ),

      // কৌতুক
      SectionCard(
        icon: '😄',
        title: 'আজকের কৌতুক',
        accent: _cJoke,
        child: AsyncSection<String>(
          future: _joke,
          builder: (j) => Text(j, style: const TextStyle(fontSize: 16, height: 1.6)),
        ),
      ),
      _developerCard(),
    ]);
  }

  Widget _amolTile(Map<String, dynamic> e) {
    final arabic = e['arabic'] as String;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Pill(e['count'] as String, color: _cAmol),
        children: [
          if (arabic.isNotEmpty)
            Text(arabic,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 21, height: 1.9)),
          if (arabic.isNotEmpty) const SizedBox(height: 6),
          Text(e['pron'] as String, style: const TextStyle(fontStyle: FontStyle.italic, height: 1.5)),
          const SizedBox(height: 6),
          Text('অর্থ/ফজিলত: ${e['meaning']}', style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }

  // ─────────────────────────────── ট্যাব ২: নামাজ
  Widget _prayerPage() {
    final cs = Theme.of(context).colorScheme;
    return _page(title: 'নামাজের সময়', [
      AsyncSection<Map<String, dynamic>>(
        future: _prayer,
        builder: (t) {
          final st = PrayerService.status(t);
          final slots = PrayerService.slots(t);
          final ramadan = Bangla.hijri(DateTime.now(), _hijriOffset).month == 9;
          final si = PrayerService.sehriIftar(t);
          return Column(children: [
            // কাউন্টডাউন
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF087F5B), Color(0xFF20C997)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (st.current != null)
                    Text('এখন চলছে: ${st.current!.name} • শেষ হবে ${PrayerService.fmt(st.current!.end)}',
                        style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('পরবর্তী: ${st.next.name}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text('শুরু ${PrayerService.fmt(st.next.start)} • বাকি ${PrayerService.duration(st.until)}',
                      style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
            if (ramadan)
              SectionCard(
                icon: '🌙',
                title: 'সেহরি ও ইফতার',
                accent: _cPrayer,
                child: Row(children: [
                  Expanded(child: _bigTime('সেহরির শেষ সময়', PrayerService.fmt(si.sehri))),
                  Expanded(child: _bigTime('ইফতার', PrayerService.fmt(si.iftar))),
                ]),
              ),
            SectionCard(
              icon: '🕌',
              title: 'আজকের ওয়াক্ত',
              subtitle: 'শুরু – শেষ',
              accent: _cPrayer,
              child: Column(
                children: slots.map((s) {
                  final now = s.isNow;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: now ? _cPrayer.withValues(alpha: .14) : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: now ? Border.all(color: _cPrayer, width: 1.5) : null,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Row(children: [
                            Text(s.name,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: s.fard ? FontWeight.w800 : FontWeight.w600)),
                            const SizedBox(width: 6),
                            if (now) const Pill('চলছে'),
                            if (!s.fard && !now) Pill('নফল', color: cs.outline),
                          ]),
                        ),
                        Text('${PrayerService.fmt(s.start)} – ${PrayerService.fmt(s.end)}',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      ]),
                      if (s.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(s.note!,
                              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ),
                    ]),
                  );
                }).toList(),
              ),
            ),
            SectionCard(
              icon: '⛔',
              title: 'নামাজের নিষিদ্ধ সময়',
              subtitle: 'আনুমানিক',
              accent: const Color(0xFFC92A2A),
              child: Column(
                children: PrayerService.forbidden(t)
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Expanded(child: Text(s.name)),
                            Text('${PrayerService.fmt(s.start)} – ${PrayerService.fmt(s.end)}'),
                          ]),
                        ))
                    .toList(),
              ),
            ),
          ]);
        },
      ),
    ]);
  }

  Widget _bigTime(String label, String time) => Column(children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text(time, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ]);

  // ─────────────────────────────── ট্যাব ৩: খবর
  void _openNews(NewsItem n) {
    if (n.link.isNotEmpty) launchUrl(Uri.parse(n.link), mode: LaunchMode.externalApplication);
  }

  Widget _newsImage(String url, {double? height, double? width, double radius = 14}) {
    final ph = Container(
      height: height,
      width: width,
      color: _cNews.withValues(alpha: .10),
      alignment: Alignment.center,
      child: const Text('📰', style: TextStyle(fontSize: 28)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? ph
          : Image.network(
              url,
              height: height,
              width: width,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ph,
              loadingBuilder: (c, child, p) => p == null ? child : ph,
            ),
    );
  }

  Widget _newsPage() {
    final cs = Theme.of(context).colorScheme;
    return _page(title: 'আজকের শীর্ষ খবর', [
      AsyncSection<List<NewsItem>>(
        future: _news,
        builder: (items) {
          if (items.isEmpty) return const SizedBox.shrink();
          final top = items.first;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // প্রধান খবর: বড় ছবি
            GestureDetector(
              onTap: () => _openNews(top),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .15),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Stack(children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: _newsImage(top.image, radius: 22),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: .80)],
                          stops: const [.35, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE03131),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('প্রধান খবর',
                            style: TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      Text(top.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              height: 1.35)),
                      const SizedBox(height: 4),
                      Text([top.source, top.ago].where((e) => e.isNotEmpty).join(' • '),
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (top.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Text(top.summary,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
              ),

            // বাকি খবর: পাশে ছোট ছবি
            for (var i = 1; i < items.length; i++)
              InkWell(
                onTap: () => _openNews(items[i]),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? cs.surfaceContainerHigh
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _cNews.withValues(alpha: .10)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _newsImage(items[i].image, width: 112, height: 84, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i].title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, height: 1.35)),
                        const SizedBox(height: 6),
                        Text(
                            '${Bangla.digits(i + 1)}. ${[items[i].source, items[i].ago].where((e) => e.isNotEmpty).join(' • ')}',
                            style: TextStyle(fontSize: 12, color: cs.outline)),
                      ]),
                    ),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('প্রতি ৩০ মিনিটে নিজে থেকে আপডেট হয় • খবরে চাপ দিলে পুরোটা পড়তে পারবেন',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
          ]);
        },
      ),
    ]);
  }

  Widget _quizCard() => SectionCard(
        icon: '🧠',
        title: 'আজকের কুইজ',
        subtitle: 'বাংলাদেশ ২টি + বিশ্ব ৩টি • উত্তর দিয়ে নিজেকে যাচাই করুন',
        accent: _cQuiz,
        child: AsyncSection<({String label, List<Map<String, dynamic>> bd, List<Map<String, dynamic>> world})>(
          future: _quiz,
          builder: (z) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: Pill(z.label, color: _cQuiz)),
            const SizedBox(height: 10),
            QuizList(accent: _cQuiz, questions: [
              ...z.bd.map((q) => (tag: 'বাংলাদেশ', q: q)),
              ...z.world.map((q) => (tag: 'বিশ্ব', q: q)),
            ]),
          ]),
        ),
      );

  // ─────────────────────────────── ট্যাব ৪: পাঠ
  Widget _readPage() {
    final cs = Theme.of(context).colorScheme;
    return _page(title: 'আজকের পাঠ', [
      _quizCard(),
      SectionCard(
        icon: '💡',
        title: 'আজকের নীতিবাক্য',
        accent: _cQuote,
        child: AsyncSection<String>(
          future: _quote,
          builder: (q) => Text('“$q”',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.5)),
        ),
      ),
      SectionCard(
        icon: '📖',
        title: 'কুরআনের বাণী',
        accent: _cQuran,
        child: AsyncSection<Map<String, dynamic>>(
          future: _quran,
          builder: (q) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if ((q['arabic'] as String).isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cQuran.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(q['arabic'],
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 23, height: 2)),
              ),
            const SizedBox(height: 10),
            Text(q['bangla'], style: const TextStyle(fontSize: 16.5, height: 1.65)),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: Pill(q['ref'], color: _cQuran)),
          ]),
        ),
      ),
      SectionCard(
        icon: '🕋',
        title: 'আজকের হাদিস',
        accent: _cHadith,
        child: AsyncSection<Map<String, dynamic>>(
          future: _hadith,
          builder: (h) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(h['text'], style: const TextStyle(fontSize: 16.5, height: 1.65)),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: Pill(h['ref'], color: _cHadith)),
          ]),
        ),
      ),
      SectionCard(
        icon: '📚',
        title: 'আজকের ছোট গল্প',
        accent: _cStory,
        child: AsyncSection<Map<String, dynamic>>(
          future: _story,
          builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(s['body'], style: const TextStyle(fontSize: 15.5, height: 1.7)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _cStory.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
              child: Text('শিক্ষা: ${s['moral']}',
                  style: const TextStyle(color: _cStory, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
      _developerCard(),
    ]);
  }

  // ─────────────────────────────── ডেভেলপার তথ্য
  static const _devName = 'Md. Nazmul Islam';
  static const _devEmail = 'mail@nislam.info.bd';
  static const _devWeb = 'nislam.info.bd';

  void _open(Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);

  Widget _developerCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Text('ডেভেলপ করেছেন', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        const Text(_devName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
          ActionChip(
            avatar: const Icon(Icons.email_outlined, size: 18),
            label: const Text(_devEmail),
            onPressed: () => _open(Uri(scheme: 'mailto', path: _devEmail)),
          ),
          ActionChip(
            avatar: const Icon(Icons.language, size: 18),
            label: const Text(_devWeb),
            onPressed: () => _open(Uri.parse('https://$_devWeb')),
          ),
        ]),
      ]),
    );
  }

  void _showAbout() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(AppConfig.appName,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('প্রতিদিনের দরকারি সব তথ্য এক অ্যাপে', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          _developerCard(),
        ]),
      ),
    );
  }
}
