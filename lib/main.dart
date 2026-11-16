import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartDailyNeedApp());
}

class SmartDailyNeedApp extends StatelessWidget {
  const SmartDailyNeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) {
      final base = ThemeData(
        useMaterial3: true,
        brightness: b,
        colorSchemeSeed: const Color(0xFF0F7B5F),
      );
      return base.copyWith(
        textTheme: GoogleFonts.hindSiliguriTextTheme(base.textTheme),
      );
    }

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
