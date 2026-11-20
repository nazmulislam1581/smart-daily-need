import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../services/cache.dart';
import '../services/data_services.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../utils/bangla.dart';
import '../services/bookmarks.dart';
import '../widgets/painters.dart';
import '../widgets/quiz_card.dart';
import 'calendar_page.dart';
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
  Future<Map<String, dynamic>>? _famous;
  Future<List<({String year, String text})>>? _history;
  String _name = '';
  String _city = AppConfig.defaultCity;
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
    Cache.getString('user_name', '').then((v) {
      if (mounted) setState(() => _name = v);
    });
    Bookmarks.load();
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
      _famous = LocalContent.famousQuote();
      _history = HistoryService.onThisDay(force: force);
      _days = LocalContent.days(_hijriOffset);
      _news = NewsService.fetch(force: force);
      _quran = QuranService.fetch(force: force);
      final loc = LocationService.get();
      _loc = loc;
      loc.then((l) {
        if (mounted) setState(() => _city = l.city);
      });
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
  static const _navItems = [
    (Icons.home_rounded, 'হোম'),
    (Icons.grid_view_rounded, 'সকল বিভাগ'),
    (Icons.bookmark_border_rounded, 'সংরক্ষিত'),
    (Icons.calendar_month_outlined, 'ক্যালেন্ডার'),
    (Icons.more_horiz_rounded, 'আরও'),
  ];

  bool get _wide => MediaQuery.of(context).size.width >= 900;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _homeTab(),
      _sectionsTab(),
      _bookmarksTab(),
      _simpleTab('ক্যালেন্ডার', CalendarPage(hijriOffset: _hijriOffset)),
      _moreTab(),
    ];
    if (_wide) {
      return Scaffold(
        body: Column(children: [
          _topNav(),
          Expanded(child: IndexedStack(index: _tab, children: tabs)),
        ]),
      );
    }
    return Scaffold(
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _appLogo(double size) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .22),
        child: Image.asset('assets/icon/icon.png', width: size, height: size),
      );

  Widget _brand({Color color = Colors.white, double size = 22}) => Row(mainAxisSize: MainAxisSize.min, children: [
        _appLogo(size * 1.9),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(AppConfig.appName,
              style: TextStyle(
                  fontFamily: AppConfig.handFont, fontSize: size, fontWeight: FontWeight.w700, color: color, height: 1.1)),
          Text(AppConfig.appNameEn,
              style: TextStyle(fontSize: size * .55, color: const Color(0xFFFFD43B), fontWeight: FontWeight.w600)),
        ]),
      ]);

  /// বড় স্ক্রিনে (ওয়েবসাইট/ট্যাব/ডেস্কটপ) উপরের মেনু
  Widget _topNav() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 10, 24, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0B1641), Color(0xFF14317A)]),
      ),
      child: Row(children: [
        _brand(size: 20),
        const Spacer(),
        for (var i = 0; i < _navItems.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _tab == i ? Colors.white.withValues(alpha: .15) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () => setState(() => _tab = i),
              icon: Icon(_navItems[i].$1, size: 20),
              label: Text(_navItems[i].$2, style: const TextStyle(fontSize: 15)),
            ),
          ),
        const SizedBox(width: 8),
        _bellButton(),
      ]),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0B1E4A), Color(0xFF14317A)]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(children: [
            for (var i = 0; i < _navItems.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _tab == i ? const Color(0xFF2B5FD9) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_navItems[i].$1, color: Colors.white, size: 26),
                      const SizedBox(height: 2),
                      FittedBox(
                        child: Text(_navItems[i].$2,
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _bellButton() => FutureBuilder<({List<String> today, String? nextName, DateTime? nextDate})>(
        future: _days,
        builder: (c, s) {
          final n = s.data?.today.length ?? 0;
          return IconButton(
            tooltip: 'নোটিফিকেশন',
            onPressed: _openNotificationSettings,
            icon: Badge(
              isLabelVisible: n > 0,
              label: Text(Bangla.digits(n)),
              child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
            ),
          );
        },
      );

  // ─────────────────────────────── হোম
  Widget _homeTab() {
    final wide = _wide;
    final children = <Widget>[
      Stack(clipBehavior: Clip.none, children: [
        _hero(),
        Positioned(left: 12, right: 12, bottom: -48, child: _infoStrip()),
      ]),
      const SizedBox(height: 60),
    ];
    if (wide) {
      children.addAll([
        _row([_prayerCard(), _specialCard(), _weatherTile()], flex: const [5, 3, 3]),
        _row([_healthTile(), _newsTile(), _quranTile()], flex: const [3, 4, 4]),
        _smallGrid(true),
        _row([_quizCard(), _amolCard(), _jokeCard()], flex: const [1, 1, 1], padded: false),
      ]);
    } else {
      children.addAll([
        _prayerCard(),
        _weatherTile(),
        _row([_healthTile(compact: true), _specialCard(compact: true)]),
        _newsTile(),
        _quranTile(),
        _smallGrid(false),
        _quizCard(),
        _amolCard(),
        _jokeCard(),
      ]);
    }
    children.addAll([_developerCard(), const SizedBox(height: 16)]);

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }

  /// এক সারিতে কয়েকটি কার্ড, সমান উচ্চতায়
  Widget _row(List<Widget> items, {List<int>? flex, bool padded = true}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                flex: flex == null ? 1 : flex[i],
                child: padded ? items[i] : MediaQuery.removePadding(context: context, child: items[i]),
              ),
            ],
          ]),
        ),
      );

  // ─────────────────────────────── হেডার
  Widget _hero() {
    final mood = _mood();
    final h = DateTime.now().hour;
    final night = h >= 18 || h < 5;
    final top = _wide ? 0.0 : MediaQuery.of(context).padding.top;
    return SizedBox(
      height: (_wide ? 210 : 250) + top,
      child: ClipRRect(
        borderRadius: _wide ? BorderRadius.zero : const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: night ? const [Color(0xFF0B1641), Color(0xFF1E3A8A)] : mood.colors,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: SkyPainter(
                night: night,
                silhouette: night ? const Color(0xFF0A1233) : Colors.black.withValues(alpha: .22),
              ),
            ),
          ),
          if (!_wide)
            Positioned(
              left: 16,
              right: 4,
              top: top + 8,
              child: Row(children: [
                _brand(size: 20),
                const Spacer(),
                _bellButton(),
                IconButton(
                  tooltip: 'সেটিংস',
                  onPressed: () => setState(() => _tab = 4),
                  icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                ),
              ]),
            ),
          Positioned(
            left: _wide ? 0 : 20,
            right: _wide ? 0 : null,
            top: top + (_wide ? 34 : 78),
            child: Column(
              crossAxisAlignment: _wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(mood.greet,
                      style: TextStyle(
                        fontFamily: AppConfig.handFont,
                        fontSize: _wide ? 46 : 38,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFFD43B),
                        height: 1.1,
                      )),
                  const SizedBox(width: 8),
                  Text(mood.emoji, style: const TextStyle(fontSize: 30)),
                ]),
                const SizedBox(height: 4),
                Text('আল্লাহর রহমত আপনার উপর বর্ষিত হোক',
                    style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 15)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _editName,
                  child: Text(_name.isEmpty ? '👤 আপনার নাম লিখুন ✎' : '👤 স্বাগতম, $_name',
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoStrip() {
    final now = DateTime.now();
    final season = Bangla.season(now);
    final hj = Bangla.hijriDate(now, _hijriOffset).replaceAll(' হিজরি', '');
    final bdate = Bangla.banglaDate(now);
    Widget cell(IconData icon, String main, String sub, {VoidCallback? onTap}) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: const Color(0xFF1E3A8A), size: 22),
                const SizedBox(height: 4),
                Text(main,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF1A1B1E), height: 1.3)),
                Text(sub,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF495057))),
              ]),
            ),
          ),
        );
    Widget div() => Container(width: 1, height: 54, color: const Color(0xFF1E3A8A).withValues(alpha: .2));
    final cells = <Widget>[
      cell(Icons.calendar_month,
          '${Bangla.weekday(now).replaceAll('বার', '')}, ${Bangla.digits(now.day)} ${Bangla.englishMonths[now.month - 1]} ${Bangla.digits(now.year)}',
          '(${Bangla.weekday(now)})'),
      div(),
      cell(Icons.event_note, bdate.substring(0, bdate.indexOf('(')).replaceAll(',', '').trim(), 'বাংলা তারিখ'),
      div(),
      cell(Icons.nightlight_round, hj.replaceAll(',', ''), 'হিজরি', onTap: _editHijri),
      if (_wide) ...[
        div(),
        cell(Icons.eco, season.bn, '(ঋতু)'),
        div(),
        Expanded(child: _LiveClock(city: _city)),
      ],
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5FF),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(children: cells),
        ),
      ),
    );
  }

  // ─────────────────────────────── নামাজ কার্ড (লাইভ কাউন্টডাউন)
  Widget _prayerCard() {
    return Container(
      margin: _wide ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF4FCE3), Color(0xFFFFF9DB)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8F5A2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _prayer,
        builder: (c, s) {
          final header = Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 24, 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2B8A3E), Color(0xFF69DB7C)]),
              borderRadius: BorderRadius.only(bottomRight: Radius.circular(30)),
            ),
            child: const Text('🕌  আজকের নামাজের সময়',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          );
          if (!s.hasData) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header,
              SizedBox(
                height: 120,
                child: Center(
                  child: s.connectionState == ConnectionState.done
                      ? const Text('নামাজের সময় আনা যায়নি', style: TextStyle(color: Colors.grey))
                      : const CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ]);
          }
          final t = s.data!;
          final st = PrayerService.status(t);
          final fard = PrayerService.slots(t).where((e) => e.fard).toList();
          final cur = st.current;
          final target = cur?.end ?? st.next.start;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: header),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(children: [
                const Text('🕌', style: TextStyle(fontSize: 46)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cur != null ? '${cur.name} নামাজ' : '${st.next.name} আসছে',
                        style: const TextStyle(
                            fontFamily: AppConfig.handFont,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B3D20))),
                    Text(
                        cur != null
                            ? 'সময় শেষ: ${PrayerService.fmt(cur.end)}'
                            : 'শুরু: ${PrayerService.fmt(st.next.start)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF2B8A3E))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B5D2A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    Text(cur != null ? 'বাকি' : 'শুরু হতে',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    _Countdown(target: target, onDone: () => setState(() {})),
                  ]),
                ),
              ]),
            ),
            if (cur != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('পরবর্তী নামাজ: ${st.next.name}  |  শুরু: ${PrayerService.fmt(st.next.start)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF343A40))),
              ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD3F9D8)),
              ),
              child: Row(children: [
                for (var i = 0; i < fard.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => _push(_prayerPage),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: fard[i].isNow ? const Color(0xFF2B8A3E).withValues(alpha: .15) : null,
                          border: i > 0 ? const Border(left: BorderSide(color: Color(0xFFD3F9D8))) : null,
                        ),
                        child: Column(children: [
                          Text(fard[i].name,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF1A1B1E))),
                          FittedBox(
                            child: Text(PrayerService.fmtEn(fard[i].start),
                                style: const TextStyle(fontSize: 13, color: Color(0xFF343A40))),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  // ─────────────────────────────── আজকের বিশেষ দিন
  Widget _specialCard({bool compact = false}) {
    return FutureBuilder<({List<String> today, String? nextName, DateTime? nextDate})>(
      future: _days,
      builder: (c, s) {
        final d = s.data;
        final today = d?.today ?? const <String>[];
        final has = today.isNotEmpty;
        final headline = has ? today.first : (d?.nextName ?? '...');
        final sub = has
            ? (today.length > 1 ? today.skip(1).join(' • ') : 'আজ ${Bangla.englishDate(DateTime.now())}')
            : (d?.nextDate != null
                ? 'আসছে ${Bangla.digits(d!.nextDate!.day)} ${Bangla.englishMonths[d.nextDate!.month - 1]}'
                : '');
        return _tile(
          colors: const [Color(0xFFFFF9DB), Color(0xFFFFF3BF)],
          border: const Color(0xFFFFE066),
          onTap: _showSpecialDetails,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tileTitle('⭐', has ? 'আজকের বিশেষ দিন' : 'সামনের বিশেষ দিন', const Color(0xFF5C3D00)),
            const SizedBox(height: 8),
            if (!compact)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 90, width: double.infinity, child: CustomPaint(painter: DayBannerPainter())),
              ),
            if (!compact) const SizedBox(height: 8),
            Text(headline,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppConfig.handFont,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0B3D20))),
            const SizedBox(height: 4),
            Text(sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF495057))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF1C4FB8), borderRadius: BorderRadius.circular(20)),
              child: const Text('বিস্তারিত দেখুন →', style: TextStyle(color: Colors.white, fontSize: 12.5)),
            ),
          ]),
        );
      },
    );
  }

  void _showSpecialDetails() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(
          title: const Text('আজকের বিশেষ দিন',
              style: TextStyle(fontFamily: AppConfig.handFont, fontWeight: FontWeight.w700)),
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF2B8A3E),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(height: 160, child: CustomPaint(painter: DayBannerPainter())),
          ),
          const SizedBox(height: 14),
          FutureBuilder<({List<String> today, String? nextName, DateTime? nextDate})>(
            future: _days,
            builder: (c, s) {
              final d = s.data;
              if (d == null) return const LinearProgressIndicator();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.today.isEmpty)
                  const Text('আজ উল্লেখযোগ্য কোনো দিবস নেই।', style: TextStyle(fontSize: 16))
                else
                  ...d.today.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('✦ $e',
                            style: const TextStyle(
                                fontFamily: AppConfig.handFont, fontSize: 24, fontWeight: FontWeight.w700)),
                      )),
                if (d.nextName != null) ...[
                  const SizedBox(height: 6),
                  Pill('সামনে: ${d.nextName} • ${Bangla.digits(d.nextDate!.day)} ${Bangla.englishMonths[d.nextDate!.month - 1]}',
                      color: _cDibos),
                ],
              ]);
            },
          ),
          const SizedBox(height: 20),
          const Text('ইতিহাসে আজকের দিনে',
              style: TextStyle(fontFamily: AppConfig.handFont, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<List<({String year, String text})>>(
            future: _history,
            builder: (c, h) {
              if (h.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              final items = h.data ?? const [];
              if (items.isEmpty) return const Text('তথ্য পাওয়া যায়নি।');
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...items.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Pill(Bangla.digits(e.year), color: const Color(0xFF2B8A3E)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.text, style: const TextStyle(height: 1.5))),
                      ]),
                    )),
                Text('সূত্র: Wikipedia (ইংরেজি)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              ]);
            },
          ),
        ]),
      ),
    ));
  }

  // ─────────────────────────────── আবহাওয়া
  Widget _weatherTile() => Padding(
        padding: _wide ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _tile(
          colors: const [Color(0xFF1864AB), Color(0xFF339AF0)],
          child: Stack(children: [
            Positioned(
              left: -12,
              right: -12,
              bottom: -12,
              height: 40,
              child: CustomPaint(painter: SkylinePainter(Colors.white.withValues(alpha: .12))),
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: _weather,
              builder: (c, s) {
                final w = s.data;
                if (w == null) {
                  return Column(children: [
                    _tileTitle('🌤️', 'আজকের আবহাওয়া', Colors.white),
                    const SizedBox(height: 30),
                    s.connectionState == ConnectionState.done
                        ? const Text('তথ্য পাওয়া যায়নি', style: TextStyle(color: Colors.white70))
                        : const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    const SizedBox(height: 30),
                  ]);
                }
                final (emoji, desc) = WeatherService.describe(w['code'] as int);
                final umbrella = (w['rain'] as int) >= 50;
                final details = DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'SolaimanLipi', height: 1.6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('☔ বৃষ্টি: ${Bangla.digits(w['rain'])}%  |  💧 আর্দ্রতা: ${Bangla.digits(w['humidity'])}%'),
                    Text('💨 বাতাস: ${Bangla.digits(w['wind'])} কিমি/ঘ.'),
                    Text('🌡️ ${Bangla.digits(w['min'])}° – ${Bangla.digits(w['max'])}°সে  •  📍 ${w['city']}'),
                  ]),
                );
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _tileTitle('🌤️', 'আজকের আবহাওয়া', Colors.white),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 46)),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${Bangla.digits(w['temp'])}°C',
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(desc, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  details,
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFD43B), borderRadius: BorderRadius.circular(20)),
                      child: Text(umbrella ? '☂️ আজ ছাতা লাগবে!' : '😎 আজ ছাতা লাগবে না',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A1B1E))),
                    ),
                  ),
                  const SizedBox(height: 8),
                ]);
              },
            ),
          ]),
        ),
      );

  Widget _healthTile({bool compact = false}) => FutureBuilder<Map<String, dynamic>>(
        future: _health,
        builder: (c, s) {
          final h = s.data;
          return _tile(
            colors: const [Color(0xFFEBFBEE), Color(0xFFF4FCE3)],
            border: const Color(0xFFB2F2BB),
            onTap: h == null
                ? null
                : () => _openDetail('🩺', 'আজকের স্বাস্থ্য পরামর্শ', '${h['title']}\n\n${h['text']}', '', 'স্বাস্থ্য', _cHealth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tileTitle('❤️', compact ? 'স্বাস্থ্য পরামর্শ' : 'আজকের স্বাস্থ্য পরামর্শ', const Color(0xFFC92A2A)),
              const SizedBox(height: 8),
              if (h != null)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h['icon'] as String, style: TextStyle(fontSize: compact ? 30 : 44)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h['title'] as String,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1B1E))),
                      const SizedBox(height: 2),
                      Text(h['text'] as String,
                          maxLines: compact ? 3 : 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF343A40))),
                    ]),
                  ),
                ]),
            ]),
          );
        },
      );

  // ─────────────────────────────── খবর
  Widget _newsTile() => Padding(
        padding: _wide ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _tile(
          colors: const [Color(0xFF14317A), Color(0xFF1C4FB8)],
          child: FutureBuilder<List<NewsItem>>(
            future: _news,
            builder: (c, s) {
              final items = s.data ?? const <NewsItem>[];
              final head = Row(children: [
                const Expanded(
                  child: Text('📰  আজকের শীর্ষ ১০ সংবাদ',
                      style: TextStyle(
                          fontFamily: AppConfig.handFont, fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                InkWell(
                  onTap: () => _push(_newsPage),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: const Text('সব দেখুন →',
                        style: TextStyle(color: Color(0xFF1C4FB8), fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]);
              if (items.isEmpty) {
                return Column(children: [
                  head,
                  const SizedBox(height: 30),
                  s.connectionState == ConnectionState.done
                      ? const Text('খবর পাওয়া যায়নি', style: TextStyle(color: Colors.white70))
                      : const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  const SizedBox(height: 30),
                ]);
              }
              final top = items.first;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                head,
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _openNews(top),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _newsImage(top.image, width: 120, height: 86, radius: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(top.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.35)),
                        const SizedBox(height: 4),
                        Text([top.ago, top.source].where((e) => e.isNotEmpty).join(' • '),
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                for (var i = 1; i < items.length && i < (_wide ? 4 : 5); i++)
                  InkWell(
                    onTap: () => _openNews(items[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${Bangla.digits(i + 1)}. ',
                            style: const TextStyle(color: Color(0xFFFFD43B), fontWeight: FontWeight.w800)),
                        Expanded(
                          child: Text(items[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35)),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      );

  // ─────────────────────────────── কুরআন
  Widget _quranTile() => Padding(
        padding: _wide ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _quran,
          builder: (c, s) {
            final q = s.data;
            return _tile(
              colors: const [Color(0xFFF8F9FA), Color(0xFFEBFBEE)],
              border: const Color(0xFFB2F2BB),
              onTap: q == null
                  ? null
                  : () => _openDetail('📖', 'কুরআনের বাণী', q['bangla'] as String, q['ref'] as String, 'কুরআন',
                      _cQuran, arabic: q['arabic'] as String),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _tileTitle('📖', 'আজকের কুরআনের বাণী', const Color(0xFF087F5B)),
                const SizedBox(height: 8),
                if (q != null) ...[
                  if ((q['arabic'] as String).isNotEmpty)
                    Text(q['arabic'] as String,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, height: 1.8, color: Color(0xFF1A1B1E))),
                  const SizedBox(height: 4),
                  Text('“${q['bangla']}”',
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, height: 1.5, color: Color(0xFF1A1B1E))),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('— ${q['ref']}', style: const TextStyle(fontSize: 12, color: Color(0xFF087F5B))),
                  ),
                ],
              ]),
            );
          },
        ),
      );

  Widget _amolCard() => AsyncSection<Map<String, dynamic>>(
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
      );

  Widget _jokeCard() => SectionCard(
        icon: '😄',
        title: 'আজকের কৌতুক',
        accent: _cJoke,
        trailing: FutureBuilder<String>(
          future: _joke,
          builder: (c, s) => s.hasData
              ? _bookmarkButton(Bookmark('কৌতুক', 'আজকের কৌতুক', s.data!), _cJoke)
              : const SizedBox.shrink(),
        ),
        child: AsyncSection<String>(
          future: _joke,
          builder: (j) => Text(j, style: const TextStyle(fontSize: 16, height: 1.6)),
        ),
      );

  /// সাব-পেজ / ট্যাবের সাধারণ কাঠামো (গ্রেডিয়েন্ট অ্যাপবার)
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
                title: Text(title ?? '',
                    style: const TextStyle(fontFamily: AppConfig.handFont, fontWeight: FontWeight.w700)),
                background: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: mood.colors)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverList.list(children: [...children, const SizedBox(height: 24)]),
        ],
      ),
    );
  }

  Widget _simpleTab(String title, Widget body) {
    final mood = _mood();
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontFamily: AppConfig.handFont, fontWeight: FontWeight.w700)),
        foregroundColor: Colors.white,
        flexibleSpace: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: mood.colors))),
      ),
      body: body,
    );
  }

  /// নতুন পাতায় খোলে (নামাজ, খবর, পাঠ ইত্যাদি)
  void _push(Widget Function() page) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(body: page()),
    ));
  }

  Widget _pair(Widget left, Widget right, {int leftFlex = 1, int rightFlex = 1}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: 10),
            Expanded(flex: rightFlex, child: right),
          ]),
        ),
      );

  Widget _tile({
    required Widget child,
    required List<Color> colors,
    Color border = Colors.transparent,
    VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: child,
          ),
        ),
      );

  Widget _tileTitle(String icon, String title, Color color) => Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppConfig.handFont, fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ),
      ]);

  Widget _famousTile() => FutureBuilder<Map<String, dynamic>>(
        future: _famous,
        builder: (c, s) {
          final f = s.data;
          return _tile(
            colors: const [Color(0xFFF3D9FA), Color(0xFFE5DBFF)],
            border: const Color(0xFFD0BFFF),
            onTap: f == null
                ? null
                : () => _openDetail('💬', 'মনীষীদের বাণী', f['text'] as String, f['by'] as String, 'বাণী', const Color(0xFF7048E8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tileTitle('💬', 'মনীষীদের বাণী', const Color(0xFF5F3DC4)),
              const SizedBox(height: 6),
              if (f != null) ...[
                Text('“${f['text']}”',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF1A1B1E))),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('— ${f['by']}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF5F3DC4))),
                ),
              ],
            ]),
          );
        },
      );

  Widget _smallGrid(bool wide) {
    Widget card(String icon, String title, Color bg, Color fg, Future<dynamic>? future,
        String Function(dynamic) preview, void Function(dynamic) open, {String? button}) {
      return FutureBuilder<dynamic>(
        future: future,
        builder: (c, s) => _tile(
          colors: [bg, bg.withValues(alpha: .7)],
          border: fg.withValues(alpha: .25),
          onTap: s.hasData ? () => open(s.data) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tileTitle(icon, title, fg),
            const SizedBox(height: 6),
            if (s.hasData)
              Text(preview(s.data),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF1A1B1E))),
            if (button != null && s.hasData) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(20)),
                child: Text(button, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
            ],
          ]),
        ),
      );
    }

    final cards = [
      card('🕋', 'আজকের হাদিস', const Color(0xFFFFF4E6), const Color(0xFFD9480F), _hadith,
          (h) => '“${h['text']}”\n— ${h['ref']}',
          (h) => _openDetail('🕋', 'আজকের হাদিস', h['text'] as String, h['ref'] as String, 'হাদিস', _cHadith)),
      card('📚', 'শিক্ষণীয় গল্প', const Color(0xFFE3FAFC), const Color(0xFF0B7285), _story,
          (s) => s['title'] as String,
          (s) => _openDetail('📚', s['title'] as String, '${s['body']}\n\nশিক্ষা: ${s['moral']}', '', 'গল্প', _cStory),
          button: 'পড়ুন →'),
      card('💡', 'আজকের নীতিবাক্য', const Color(0xFFEBFBEE), const Color(0xFF2B8A3E), _quote,
          (q) => '“$q”',
          (q) => _openDetail('💡', 'আজকের নীতিবাক্য', q as String, '', 'নীতিবাক্য', _cQuote)),
      card('💬', 'মনীষীর বাণী', const Color(0xFFFFF0F6), const Color(0xFFC2255C), _famous,
          (f) => '“${f['text']}”\n— ${f['by']}',
          (f) => _openDetail('💬', 'মনীষীর বাণী', f['text'] as String, f['by'] as String, 'বাণী', const Color(0xFFC2255C))),
    ];
    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ]),
        ),
      );
    }
    return Column(children: [_pair(cards[0], cards[1]), _pair(cards[2], cards[3])]);
  }

  // ─────────────────────────────── বিস্তারিত পাতা ও বুকমার্ক
  Widget _bookmarkButton(Bookmark b, Color color) => ValueListenableBuilder<List<Bookmark>>(
        valueListenable: Bookmarks.items,
        builder: (c, _, __) {
          final saved = Bookmarks.has(b);
          return IconButton(
            tooltip: saved ? 'বুকমার্ক থেকে সরান' : 'বুকমার্ক করুন',
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: color),
            onPressed: () => Bookmarks.toggle(b),
          );
        },
      );

  void _openDetail(String icon, String title, String text, String ref, String type, Color accent,
      {String arabic = ''}) {
    final b = Bookmark(type, title, text, ref: ref);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontFamily: AppConfig.handFont, fontWeight: FontWeight.w700)),
          foregroundColor: Colors.white,
          backgroundColor: accent,
          actions: [_bookmarkButton(b, Colors.white)],
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          if (arabic.isNotEmpty) ...[
            Text(arabic,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 24, height: 2)),
            const SizedBox(height: 12),
          ],
          Text(text, style: const TextStyle(fontSize: 18, height: 1.7)),
          if (ref.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerRight, child: Pill(ref, color: accent)),
          ],
        ]),
      ),
    ));
  }

  // ─────────────────────────────── সব বিভাগ
  Widget _sectionsTab() {
    final items = <(String, String, Color, VoidCallback)>[
      ('🕌', 'নামাজের সময়', _cPrayer, () => _push(_prayerPage)),
      ('📰', 'শীর্ষ খবর', _cNews, () => _push(_newsPage)),
      ('🧠', 'আজকের কুইজ', _cQuiz, () => _push(() => _page(title: 'আজকের কুইজ', [_quizCard()]))),
      ('📖', 'কুরআন, হাদিস ও পাঠ', _cQuran, () => _push(_readPage)),
      ('🗓️', 'ক্যালেন্ডার ও দিবস', _cDibos, () => setState(() => _tab = 3)),
      ('🤲', 'আজকের আমল', _cAmol, () => _push(() => _page(title: 'আজকের আমল', [
            AsyncSection<Map<String, dynamic>>(
              future: _amol,
              builder: (a) => SectionCard(
                icon: '🤲',
                title: a['title'] as String,
                subtitle: a['note'] as String,
                accent: _cAmol,
                child: Column(children: (a['items'] as List).map((e) => _amolTile(e as Map<String, dynamic>)).toList()),
              ),
            ),
          ]))),
      ('🔖', 'বুকমার্ক', const Color(0xFF1C4FB8), () => setState(() => _tab = 2)),
      ('⚙️', 'সেটিংস', const Color(0xFF495057), () => setState(() => _tab = 4)),
    ];
    return _simpleTab(
      'সব বিভাগ',
      GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: items
            .map((e) => _tile(
                  colors: [e.$3.withValues(alpha: .16), e.$3.withValues(alpha: .06)],
                  border: e.$3.withValues(alpha: .3),
                  onTap: e.$4,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(e.$1, style: const TextStyle(fontSize: 38)),
                    const SizedBox(height: 8),
                    Text(e.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: AppConfig.handFont, fontSize: 18, fontWeight: FontWeight.w700, color: e.$3)),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  // ─────────────────────────────── বুকমার্ক
  Widget _bookmarksTab() => _simpleTab(
        'বুকমার্ক',
        ValueListenableBuilder<List<Bookmark>>(
          valueListenable: Bookmarks.items,
          builder: (c, list, _) {
            if (list.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('এখনো কিছু সংরক্ষণ করা হয়নি।\nহাদিস, আয়াত, গল্প বা নীতিবাক্য খুলে 🔖 চাপ দিন।',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.6)),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final b = list[i];
                return Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${b.text}${b.ref.isNotEmpty ? '\n— ${b.ref}' : ''}',
                        maxLines: 4, overflow: TextOverflow.ellipsis),
                    leading: Pill(b.type),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => Bookmarks.toggle(b),
                    ),
                    onTap: () => _openDetail('🔖', b.title, b.text, b.ref, b.type, const Color(0xFF1C4FB8)),
                  ),
                );
              },
            );
          },
        ),
      );

  // ─────────────────────────────── আরও / সেটিংস
  Widget _moreTab() => _simpleTab(
        'আরও',
        ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('আপনার নাম'),
            subtitle: Text(_name.isEmpty ? 'যোগ করা হয়নি' : _name),
            onTap: _editName,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('প্রতিদিনের নোটিফিকেশন'),
            subtitle: const Text('সময় বদলান বা বন্ধ করুন'),
            onTap: _openNotificationSettings,
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_round),
            title: const Text('হিজরি তারিখ ঠিক করুন'),
            subtitle: Text(Bangla.hijriDate(DateTime.now(), _hijriOffset)),
            onTap: _editHijri,
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('সব তথ্য রিফ্রেশ করুন'),
            onTap: () => _load(force: true),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('অ্যাপ সম্পর্কে'),
            onTap: _showAbout,
          ),
          const SizedBox(height: 12),
          _developerCard(),
        ]),
      );

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('আপনার নাম'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'যেমন: Md. Nazmul Islam'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('সেভ')),
        ],
      ),
    );
    if (v != null) {
      await Cache.setString('user_name', v);
      setState(() => _name = v);
    }
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
              style: const TextStyle(
                  fontFamily: AppConfig.handFont, fontSize: 23, height: 1.5)),
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
            Text(s['title'],
                style: const TextStyle(
                    fontFamily: AppConfig.handFont, fontSize: 22, fontWeight: FontWeight.w700)),
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

/// লাইভ ঘড়ি (প্রতি সেকেন্ডে)
class _LiveClock extends StatefulWidget {
  final String city;
  const _LiveClock({this.city = ''});
  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final t = '${Bangla.digits(h12)}:${Bangla.digits(n.minute.toString().padLeft(2, '0'))}:${Bangla.digits(n.second.toString().padLeft(2, '0'))} ${n.hour < 12 ? 'AM' : 'PM'}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.schedule, color: Color(0xFF1E3A8A), size: 22),
      const SizedBox(height: 4),
      FittedBox(
        child: Text(t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1B1E))),
      ),
      Text(widget.city.isEmpty ? '(বর্তমান সময়)' : '📍 ${widget.city}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF495057))),
    ]);
  }
}

/// নামাজের লাইভ কাউন্টডাউন (ঘণ্টা:মিনিট:সেকেন্ড)
class _Countdown extends StatefulWidget {
  final DateTime target;
  final VoidCallback onDone;
  const _Countdown({required this.target, required this.onDone});
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _t;
  bool _fired = false;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_fired && !widget.target.isAfter(DateTime.now())) {
        _fired = true;
        widget.onDone();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _Countdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _fired = false;
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var d = widget.target.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    String two(int v) => v.toString().padLeft(2, '0');
    return Text('${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800));
  }
}
