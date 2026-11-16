# Smart Daily Need 📱

প্রতিদিনের দরকারি তথ্য এক অ্যাপে:
- আজকের তারিখ: ইংরেজি, বাংলা (বঙ্গাব্দ) ও হিজরি
- ছোট আবহাওয়া আপডেট (তাপমাত্রা, বৃষ্টি, পরামর্শ)
- নামাজের সময় (পরের ওয়াক্ত হাইলাইট করা থাকে)
- শীর্ষ ১০টি বাংলা খবর (চাপ দিলে খবরটি খুলবে)
- নীতিবাক্য, কুরআনের বাণী (আরবি + বাংলা) ও ছোট গল্প

সব তথ্য প্রতিদিন নিজে থেকে বদলায়। দিনের ডেটা ফোনে জমা থাকে, তাই অফলাইনেও শেষ ডেটা দেখা যায়।
নিচে টেনে (pull to refresh) নতুন করে আনা যায়।

## ব্যবহৃত ফ্রি API (কোনো API key লাগে না)
| অংশ | সোর্স |
|---|---|
| আবহাওয়া | Open-Meteo |
| নামাজের সময় | Aladhan (করাচি পদ্ধতি, হানাফি আসর) |
| খবর | Google News RSS (বাংলাদেশ, বাংলা) |
| কুরআন | alquran.cloud (উসমানি আরবি + বাংলা অনুবাদ) |
| বাংলা ও হিজরি তারিখ | অ্যাপের ভেতরে হিসাব করা হয় (অফলাইন) |
| নীতিবাক্য ও গল্প | `assets/data/` এর JSON ফাইল |

## 🔔 প্রতিদিন সকালের নোটিফিকেশন
প্রতিদিন সকাল ৬টায় (🔔 বাটন থেকে সময় বদলানো যায়) একটি নোটিফিকেশন আসে। তাতে থাকে:
তিন রকম তারিখ, আজকের ৫ ওয়াক্ত নামাজের সময়, আর আজকের নীতিবাক্য।
অ্যাপ খুললেই সামনের ৭ দিনের নোটিফিকেশন আগে থেকে সাজানো হয়, তাই প্রতিদিন অ্যাপ খুলতে হয় না।

## সেটআপ

```bash
flutter create --org bd.bats smart_daily_need_app
cd smart_daily_need_app
# এই zip-এর lib/, assets/, pubspec.yaml কপি করে বসান (আগেরগুলো বদলে দিন)
flutter pub get
```

### Android
1. `android_setup/AndroidManifest.xml` দিয়ে `android/app/src/main/AndroidManifest.xml` বদলে দিন
   (ইন্টারনেট, লোকেশন, নোটিফিকেশন পারমিশন ও রিসিভার এতে আছে)
2. `android_setup/build.gradle.kts.snippet` অনুযায়ী `android/app/build.gradle.kts`-এ desugaring যোগ করুন

### iOS: `ios/Runner/Info.plist`
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>আপনার এলাকার আবহাওয়া ও নামাজের সময় দেখাতে লোকেশন দরকার।</string>
```

### আইকন ও স্প্ল্যাশ স্ক্রিন
```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter run
```
আইকন ফাইলগুলো `assets/icon/` এ আছে। নিজের ডিজাইন দিতে চাইলে একই নামে বদলে আবার কমান্ড দুটি চালান।

লোকেশন অনুমতি না দিলে অ্যাপ ঢাকার তথ্য দেখাবে।

## কাস্টমাইজ
- `lib/config.dart`: ডিফল্ট শহর, নামাজের হিসাব পদ্ধতি, খবরের RSS, হিজরি অফসেট
- হিজরি তারিখে চাপ দিয়ে ±১/২ দিন ঠিক করা যায় (চাঁদ দেখা অনুযায়ী)
- নতুন নীতিবাক্য/গল্প যোগ করতে `assets/data/quotes.json` ও `stories.json` এ লিখুন

## ফাইল কাঠামো
```
lib/
  main.dart                  থিম ও অ্যাপ শুরু
  config.dart                সেটিংস
  utils/bangla.dart          বাংলা সংখ্যা, বঙ্গাব্দ, হিজরি, ১২ ঘণ্টার সময়
  services/cache.dart        প্রতিদিনের ক্যাশ ও অফলাইন ব্যাকআপ
  services/location_service.dart
  services/data_services.dart  আবহাওয়া, নামাজ, খবর, কুরআন, লোকাল কনটেন্ট
  screens/home_screen.dart   মূল স্ক্রিন
  widgets/section_card.dart
assets/data/                 quotes, stories, quran_fallback
```
