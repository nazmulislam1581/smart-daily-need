/// অ্যাপের সাধারণ সেটিংস। দরকার হলে এখান থেকে বদলান।
class AppConfig {
  static const appName = 'Smart Daily Need';

  /// লোকেশন পাওয়া না গেলে ঢাকা ধরা হবে।
  static const defaultLat = 23.8103;
  static const defaultLng = 90.4125;
  static const defaultCity = 'ঢাকা';

  /// নামাজের সময়ের হিসাব পদ্ধতি (Aladhan API)।
  /// 1 = University of Islamic Sciences, Karachi (বাংলাদেশে প্রচলিত)
  static const prayerMethod = 1;

  /// 1 = হানাফি (আসরের সময়), 0 = শাফেয়ি
  static const asrSchool = 1;

  /// বাংলা খবরের RSS (Google News বাংলাদেশ)। অন্য পত্রিকার RSS দিতে চাইলে বদলান।
  static const newsRssUrl =
      'https://news.google.com/rss?hl=bn&gl=BD&ceid=BD:bn';

  /// বাংলাদেশে চাঁদ দেখা সাধারণত সৌদির চেয়ে এক দিন পরে হয়।
  /// অ্যাপে হিজরি তারিখে চাপ দিয়ে ব্যবহারকারী নিজেও এটা ঠিক করতে পারবেন।
  static const defaultHijriOffset = -1;

  /// প্রতিদিনের নোটিফিকেশনের ডিফল্ট সময় (সকাল ৬:০০)। অ্যাপের 🔔 বাটন থেকে বদলানো যায়।
  static const notifHour = 6;
  static const notifMinute = 0;
  static const timeZone = 'Asia/Dhaka';
}
