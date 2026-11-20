import 'package:flutter/material.dart';
import '../config.dart';
import '../services/data_services.dart';
import '../utils/bangla.dart';

/// মাসিক ক্যালেন্ডার: ইংরেজি তারিখের নিচে বাংলা তারিখ, দিবসের দিনে চিহ্ন
class CalendarPage extends StatefulWidget {
  final int hijriOffset;
  const CalendarPage({super.key, required this.hijriOffset});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  Map<int, List<String>> _events = {};

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final m = <int, List<String>>{};
    for (var d = 1; d <= days; d++) {
      final l = await LocalContent.daysOn(DateTime(_month.year, _month.month, d), widget.hijriOffset);
      if (l.isNotEmpty) m[d] = l;
    }
    if (mounted) setState(() => _events = m);
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _events = {};
    });
    _loadEvents();
  }

  void _showDay(DateTime d) {
    final ev = _events[d.day] ?? const [];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${Bangla.weekday(d)}, ${Bangla.englishDate(d)}',
              style: const TextStyle(fontFamily: AppConfig.handFont, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('📅 ${Bangla.banglaDate(d)}'),
          const SizedBox(height: 4),
          Text('🌙 ${Bangla.hijriDate(d, widget.hijriOffset)}'),
          const SizedBox(height: 12),
          if (ev.isEmpty)
            const Text('এই দিনে উল্লেখযোগ্য কোনো দিবস নেই।')
          else
            ...ev.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('✦ $e', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final lead = first.weekday % 7; // রবিবার থেকে শুরু
    final today = DateTime.now();
    const heads = ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি'];
    final last = DateTime(_month.year, _month.month, days);

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      Row(children: [
        IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Column(children: [
            Text('${Bangla.englishMonths[_month.month - 1]} ${Bangla.digits(_month.year)}',
                style: const TextStyle(fontFamily: AppConfig.handFont, fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
                '${Bangla.banglaDayMonth(first)} – ${Bangla.banglaDayMonth(last)} • ${Bangla.hijriDate(first, widget.hijriOffset).split(',').first} – ${Bangla.hijriDate(last, widget.hijriOffset)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 8),
      Row(
        children: heads
            .map((h) => Expanded(
                  child: Center(
                    child: Text(h,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: h == 'শুক্র' ? const Color(0xFF2F9E44) : cs.onSurfaceVariant)),
                  ),
                ))
            .toList(),
      ),
      const SizedBox(height: 6),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lead + days,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: .78, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemBuilder: (c, i) {
          if (i < lead) return const SizedBox.shrink();
          final day = i - lead + 1;
          final d = DateTime(_month.year, _month.month, day);
          final isToday = DateUtils.isSameDay(d, today);
          final hasEvent = _events.containsKey(day);
          final friday = d.weekday == DateTime.friday;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showDay(d),
            child: Container(
              decoration: BoxDecoration(
                color: isToday ? cs.primary : (hasEvent ? const Color(0xFFFFF4E6) : cs.surfaceContainerLow),
                borderRadius: BorderRadius.circular(12),
                border: hasEvent && !isToday ? Border.all(color: const Color(0xFFF08C00)) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(Bangla.digits(day),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isToday
                            ? cs.onPrimary
                            : friday
                                ? const Color(0xFF2F9E44)
                                : (hasEvent ? const Color(0xFF1A1B1E) : null))),
                Text(Bangla.banglaDayMonth(d).split(' ').first,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: isToday ? cs.onPrimary.withValues(alpha: .85) : cs.onSurfaceVariant)),
                if (hasEvent)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: isToday ? cs.onPrimary : const Color(0xFFF08C00), shape: BoxShape.circle),
                  ),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      if (_events.isNotEmpty) ...[
        const Text('এই মাসের দিবস',
            style: TextStyle(fontFamily: AppConfig.handFont, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...(_events.keys.toList()..sort()).map((day) => Card(
              elevation: 0,
              color: cs.surfaceContainerLow,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFE8CC),
                  child: Text(Bangla.digits(day),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD9480F))),
                ),
                title: Text(_events[day]!.join(' • ')),
                subtitle: Text(Bangla.banglaDayMonth(DateTime(_month.year, _month.month, day))),
                onTap: () => _showDay(DateTime(_month.year, _month.month, day)),
              ),
            )),
      ],
    ]);
  }
}
