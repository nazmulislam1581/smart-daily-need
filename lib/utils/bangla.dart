import 'package:hijri/hijri_calendar.dart';

/// বাংলা সংখ্যা, বঙ্গাব্দ ও হিজরি তারিখের সাহায্যকারী ফাংশন।
class Bangla {
  static const _digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  static String digits(Object input) {
    final s = input.toString();
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final d = int.tryParse(ch);
      b.write(d != null && ch.codeUnitAt(0) < 128 ? _digits[d] : ch);
    }
    return b.toString();
  }

  static const weekdays = [
    'সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'
  ];

  static String weekday(DateTime d) => weekdays[d.weekday - 1];

  static const englishMonths = [
    'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
  ];

  static const _bnMonths = [
    'বৈশাখ', 'জ্যৈষ্ঠ', 'আষাঢ়', 'শ্রাবণ', 'ভাদ্র', 'আশ্বিন',
    'কার্তিক', 'অগ্রহায়ণ', 'পৌষ', 'মাঘ', 'ফাল্গুন', 'চৈত্র'
  ];

  static const _seasons = [
    'গ্রীষ্মকাল', 'গ্রীষ্মকাল', 'বর্ষাকাল', 'বর্ষাকাল', 'শরৎকাল', 'শরৎকাল',
    'হেমন্তকাল', 'হেমন্তকাল', 'শীতকাল', 'শীতকাল', 'বসন্তকাল', 'বসন্তকাল'
  ];

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  /// বাংলাদেশের সংশোধিত বঙ্গাব্দ (২০১৯): ১৪ এপ্রিল পহেলা বৈশাখ,
  /// প্রথম ছয় মাস ৩১ দিন, বাকিগুলো ৩০ দিন, ফাল্গুন ২৯ দিন (অধিবর্ষে ৩০)।
  static String banglaDate(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    var gYear = d.year;
    if (d.isBefore(DateTime.utc(gYear, 4, 14))) gYear -= 1;
    final bnYear = gYear - 593;
    var offset = d.difference(DateTime.utc(gYear, 4, 14)).inDays;

    final falgunLeap = _isLeap(gYear + 1);
    final lengths = [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, falgunLeap ? 30 : 29, 30];

    var m = 0;
    while (m < 11 && offset >= lengths[m]) {
      offset -= lengths[m];
      m++;
    }
    final day = offset + 1;
    return '${digits(day)} ${_bnMonths[m]}, ${digits(bnYear)} বঙ্গাব্দ (${_seasons[m]})';
  }

  static String englishDate(DateTime d) =>
      '${digits(d.day)} ${englishMonths[d.month - 1]}, ${digits(d.year)}';

  static const _hijriMonths = [
    'মুহাররম', 'সফর', 'রবিউল আউয়াল', 'রবিউস সানি', 'জমাদিউল আউয়াল',
    'জমাদিউস সানি', 'রজব', 'শাবান', 'রমজান', 'শাওয়াল', 'জিলকদ', 'জিলহজ'
  ];

  static ({int day, int month, int year}) hijri(DateTime d, int offsetDays) {
    final h = HijriCalendar.fromDate(d.add(Duration(days: offsetDays)));
    return (day: h.hDay, month: h.hMonth, year: h.hYear);
  }

  static String hijriDate(DateTime d, int offsetDays) {
    final h = HijriCalendar.fromDate(d.add(Duration(days: offsetDays)));
    return '${digits(h.hDay)} ${_hijriMonths[h.hMonth - 1]}, ${digits(h.hYear)} হিজরি';
  }

  /// "16:45" → "বিকাল ৪:৪৫"
  static String time12(String hhmm) {
    final parts = hhmm.split(' ').first.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    String period;
    if (h >= 4 && h < 6) {
      period = 'ভোর';
    } else if (h >= 6 && h < 12) {
      period = 'সকাল';
    } else if (h >= 12 && h < 15) {
      period = 'দুপুর';
    } else if (h >= 15 && h < 18) {
      period = 'বিকাল';
    } else if (h >= 18 && h < 20) {
      period = 'সন্ধ্যা';
    } else {
      period = 'রাত';
    }
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period ${digits(h12)}:${digits(m.toString().padLeft(2, '0'))}';
  }

  /// বছরের দিনের সংখ্যা — প্রতিদিন আলাদা কনটেন্ট বাছাই করতে।
  static int dayIndex(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(2024, 1, 1)).inDays;

  static const _seasonEn = {
    'গ্রীষ্মকাল': 'Summer', 'বর্ষাকাল': 'Monsoon', 'শরৎকাল': 'Autumn',
    'হেমন্তকাল': 'Late Autumn', 'শীতকাল': 'Winter', 'বসন্তকাল': 'Spring',
  };

  /// ঋতু: (বাংলা, ইংরেজি)
  static ({String bn, String en}) season(DateTime d) {
    final s = banglaDate(d);
    final bn = s.substring(s.indexOf('(') + 1, s.indexOf(')'));
    return (bn: bn, en: _seasonEn[bn] ?? '');
  }

  static const _arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  static String arabicDigits(int n) =>
      n.toString().split('').map((c) => _arDigits[int.parse(c)]).join();

  static const _hijriMonthsAr = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
    'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'
  ];

  /// "٠٢ جمادى الأولى"
  static String hijriArabic(DateTime d, int offsetDays) {
    final h = hijri(d, offsetDays);
    return '${arabicDigits(h.day).padLeft(2, '٠')} ${_hijriMonthsAr[h.month - 1]}';
  }

  static const englishMonthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// শুধু দিন ও মাস: "৭ অগ্রহায়ণ"
  static String banglaDayMonth(DateTime d) {
    final s = banglaDate(d);
    return s.substring(0, s.indexOf(','));
  }
}
