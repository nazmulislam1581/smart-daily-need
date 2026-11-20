import 'package:flutter/material.dart';
import '../utils/bangla.dart';

/// প্রশ্নে চাপ দিলে সঠিক/ভুল ও ব্যাখ্যা দেখায়, শেষে স্কোর
class QuizList extends StatefulWidget {
  final List<({String tag, Map<String, dynamic> q})> questions;
  final Color accent;
  const QuizList({super.key, required this.questions, this.accent = const Color(0xFF1864AB)});

  @override
  State<QuizList> createState() => _QuizListState();
}

class _QuizListState extends State<QuizList> {
  final Map<int, int> _picked = {};

  @override
  void didUpdateWidget(covariant QuizList old) {
    super.didUpdateWidget(old);
    if (old.questions.length != widget.questions.length ||
        (widget.questions.isNotEmpty &&
            old.questions.first.q['q'] != widget.questions.first.q['q'])) {
      _picked.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = widget.questions.length;
    var correct = 0;
    _picked.forEach((i, a) {
      if (widget.questions[i].q['answer'] == a) correct++;
    });
    const letters = ['ক', 'খ', 'গ', 'ঘ'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < total; i++) ...[
        Builder(builder: (_) {
          final item = widget.questions[i];
          final q = item.q;
          final options = (q['options'] as List).cast<String>();
          final answer = q['answer'] as int;
          final picked = _picked[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${Bangla.digits(i + 1)} • ${item.tag}',
                      style: TextStyle(
                          fontSize: 12, color: widget.accent, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(q['q'] as String,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.45)),
              const SizedBox(height: 10),
              for (var o = 0; o < options.length; o++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: picked != null ? null : () => setState(() => _picked[i] = o),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: picked == null
                            ? cs.surface
                            : o == answer
                                ? const Color(0xFF2F9E44).withValues(alpha: .15)
                                : o == picked
                                    ? const Color(0xFFE03131).withValues(alpha: .13)
                                    : cs.surface,
                        border: Border.all(
                          color: picked == null
                              ? cs.outlineVariant
                              : o == answer
                                  ? const Color(0xFF2F9E44)
                                  : o == picked
                                      ? const Color(0xFFE03131)
                                      : cs.outlineVariant,
                        ),
                      ),
                      child: Row(children: [
                        Text('${letters[o % 4]}) ',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Expanded(child: Text(options[o])),
                        if (picked != null && o == answer)
                          const Icon(Icons.check_circle, color: Color(0xFF2F9E44), size: 20),
                        if (picked != null && o == picked && o != answer)
                          const Icon(Icons.cancel, color: Color(0xFFE03131), size: 20),
                      ]),
                    ),
                  ),
                ),
              if (picked != null && (q['explain'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '${picked == answer ? '✅ সঠিক!' : '❌ ভুল।'} ${q['explain']}',
                      style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant, height: 1.5)),
                ),
            ]),
          );
        }),
      ],
      if (_picked.length == total && total > 0)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'আপনার স্কোর: ${Bangla.digits(correct)}/${Bangla.digits(total)}  ${correct == total ? '🏆 অসাধারণ!' : correct >= total - 1 ? '👏 খুব ভালো!' : '📚 আগামীকাল আবার চেষ্টা করুন!'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: widget.accent, fontSize: 15),
          ),
        ),
    ]);
  }
}
