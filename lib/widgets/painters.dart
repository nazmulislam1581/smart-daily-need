import 'dart:math' as math;
import 'package:flutter/material.dart';

/// রাতের/দিনের আকাশ: তারা, চাঁদ বা সূর্য, আর মসজিদের সিলুয়েট
class SkyPainter extends CustomPainter {
  final bool night;
  final Color silhouette;
  SkyPainter({required this.night, required this.silhouette});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rnd = math.Random(7);

    if (night) {
      // তারা
      final star = Paint()..color = Colors.white.withValues(alpha: .8);
      for (var i = 0; i < 45; i++) {
        final x = rnd.nextDouble() * w, y = rnd.nextDouble() * h * .65;
        canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.4 + .3, star);
      }
      // চাঁদ (অর্ধচন্দ্র)
      final c = Offset(w * .58, h * .26);
      final r = h * .16;
      canvas.drawCircle(c, r * 1.9,
          Paint()..color = const Color(0xFFFFE8A3).withValues(alpha: .10));
      final moon = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      final cut = Path()
        ..addOval(Rect.fromCircle(center: c + Offset(r * .45, -r * .25), radius: r * .88));
      canvas.drawPath(Path.combine(PathOperation.difference, moon, cut),
          Paint()..color = const Color(0xFFFFE28A));
    } else {
      final c = Offset(w * .6, h * .28);
      final r = h * .13;
      canvas.drawCircle(c, r * 2.2,
          Paint()..color = const Color(0xFFFFF3BF).withValues(alpha: .25));
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFD43B));
    }

    // মসজিদের সিলুয়েট (ডান পাশে)
    final p = Paint()..color = silhouette;
    final base = h;
    final mx = w * .80;
    final s = h * .0095; // স্কেল
    // মূল ভবন
    canvas.drawRect(Rect.fromLTWH(mx - 34 * s, base - 30 * s, 68 * s, 30 * s), p);
    // গম্বুজ
    canvas.drawOval(Rect.fromCenter(center: Offset(mx, base - 34 * s), width: 46 * s, height: 40 * s), p);
    canvas.drawRect(Rect.fromLTWH(mx - 1.2 * s, base - 64 * s, 2.4 * s, 12 * s), p);
    canvas.drawCircle(Offset(mx, base - 66 * s), 2.4 * s, p);
    // ছোট গম্বুজ
    for (final dx in [-26.0, 26.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(mx + dx * s, base - 32 * s), width: 18 * s, height: 16 * s), p);
    }
    // মিনার
    for (final dx in [-48.0, 48.0]) {
      canvas.drawRect(Rect.fromLTWH(mx + dx * s - 3.5 * s, base - 62 * s, 7 * s, 62 * s), p);
      final tip = Path()
        ..moveTo(mx + dx * s - 4.5 * s, base - 62 * s)
        ..lineTo(mx + dx * s, base - 74 * s)
        ..lineTo(mx + dx * s + 4.5 * s, base - 62 * s)
        ..close();
      canvas.drawPath(tip, p);
    }
    // জানালার আলো
    if (night) {
      final win = Paint()..color = const Color(0xFFFFD27A).withValues(alpha: .85);
      for (var i = -2; i <= 2; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(mx + i * 11 * s - 2.5 * s, base - 20 * s, 5 * s, 9 * s),
                Radius.circular(2.5 * s)),
            win);
      }
    }
    // গাছ (বাঁ পাশে)
    final tree = Paint()..color = silhouette;
    for (var i = 0; i < 4; i++) {
      final tx = w * (.02 + i * .045), th = h * (.18 + (i % 2) * .06);
      canvas.drawCircle(Offset(tx, base - th), th * .45, tree);
    }
    canvas.drawRect(Rect.fromLTWH(0, base - h * .06, w, h * .06), tree);
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => old.night != night || old.silhouette != silhouette;
}

/// "আজকের বিশেষ" ব্যানার: সবুজ মাঠ, লাল সূর্য, উড়ন্ত পাখি
class DayBannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9AD0F5), Color(0xFFE7F5FF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    canvas.drawCircle(Offset(w * .32, h * .52), h * .30, Paint()..color = const Color(0xFFE03131));
    // স্মৃতিসৌধের আদলে ত্রিভুজ
    final mon = Paint()..color = Colors.white.withValues(alpha: .92);
    final edge = Paint()
      ..color = const Color(0xFF868E96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final half = w * (.13 - i * .025);
      final top = h * (.20 + i * .07);
      final path = Path()
        ..moveTo(w * .32 - half, h * .80)
        ..lineTo(w * .32, top)
        ..lineTo(w * .32 + half, h * .80)
        ..close();
      canvas.drawPath(path, mon);
      canvas.drawPath(path, edge);
    }
    // মাঠ
    final grass = Paint()..color = const Color(0xFF2F9E44);
    canvas.drawPath(
        Path()
          ..moveTo(0, h * .78)
          ..quadraticBezierTo(w * .5, h * .70, w, h * .80)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        grass);
    canvas.drawPath(
        Path()
          ..moveTo(0, h * .88)
          ..quadraticBezierTo(w * .4, h * .82, w, h * .90)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = const Color(0xFF237032));
    // পাখি
    final bird = Paint()
      ..color = const Color(0xFF343A40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final b in [Offset(w * .12, h * .25), Offset(w * .2, h * .33)]) {
      canvas.drawPath(
          Path()
            ..moveTo(b.dx - 8, b.dy)
            ..quadraticBezierTo(b.dx - 4, b.dy - 6, b.dx, b.dy)
            ..quadraticBezierTo(b.dx + 4, b.dy - 6, b.dx + 8, b.dy),
          bird);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// আবহাওয়া কার্ডের নিচে শহরের সিলুয়েট
class SkylinePainter extends CustomPainter {
  final Color color;
  SkylinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final rnd = math.Random(3);
    var x = 0.0;
    while (x < size.width) {
      final bw = 10 + rnd.nextDouble() * 18;
      final bh = size.height * (.25 + rnd.nextDouble() * .6);
      canvas.drawRect(Rect.fromLTWH(x, size.height - bh, bw - 2, bh), p);
      x += bw;
    }
  }

  @override
  bool shouldRepaint(covariant SkylinePainter old) => old.color != color;
}
