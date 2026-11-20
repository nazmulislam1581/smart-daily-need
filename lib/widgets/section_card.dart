import 'package:flutter/material.dart';

/// প্রতিটি অংশের জন্য রঙিন আইকনসহ কার্ড
class SectionCard extends StatelessWidget {
  final String icon, title;
  final Widget child;
  final Widget? trailing;
  final Color accent;
  final String? subtitle;
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
    this.accent = const Color(0xFF0E8C6C),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: dark ? cs.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: dark ? .25 : .12)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: .10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: .22), accent.withValues(alpha: .08)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: dark ? Colors.white : accent)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// FutureBuilder-এর লোডিং/এরর অবস্থা একসাথে সামলায়
class AsyncSection<T> extends StatelessWidget {
  final Future<T>? future;
  final Widget Function(T data) builder;
  const AsyncSection({super.key, required this.future, required this.builder});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        if (s.hasError || !s.hasData) {
          return const Text('তথ্য আনা যায়নি। ইন্টারনেট চালু করে নিচে টেনে রিফ্রেশ করুন।',
              style: TextStyle(color: Colors.grey));
        }
        return builder(s.data as T);
      },
    );
  }
}

/// ছোট গোলাকার ট্যাগ
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = const Color(0xFF0E8C6C)});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
      );
}
