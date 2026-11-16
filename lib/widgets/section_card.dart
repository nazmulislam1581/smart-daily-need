import 'package:flutter/material.dart';

/// প্রতিটি অংশের জন্য একই রকম কার্ড
class SectionCard extends StatelessWidget {
  final String icon, title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700, color: cs.primary)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
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
