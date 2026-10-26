import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app_appearance.dart';
import '../data/prayer_models.dart';

/// Continuous angles keep 359 -> 0 on the one-degree path. A missing or stale
/// sensor removes the pointer immediately instead of animating a fake result.
class QiblaDial extends StatefulWidget {
  const QiblaDial({super.key, required this.angle, this.aligned = false});
  final double? angle;
  final bool aligned;
  @override
  State<QiblaDial> createState() => _QiblaDialState();
}

class _QiblaDialState extends State<QiblaDial>
    with SingleTickerProviderStateMixin {
  double _turn = 0;
  double _energy = 0;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..value = 1;
  @override
  void initState() {
    super.initState();
    _turn = widget.angle ?? 0;
  }

  @override
  void didUpdateWidget(QiblaDial old) {
    super.didUpdateWidget(old);
    if (widget.angle case final angle?) {
      final delta = headingDifference(angle, _turn);
      _turn = old.angle == null ? angle : _turn + delta;
      if (old.angle != null && delta.abs() > .5) {
        _energy = (delta.abs() / 20).clamp(.12, 1);
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: widget.angle == null
          ? 'لا يوجد سهم اتجاه حي'
          : 'اتجاه القبلة من قراءة الحساس',
      value: widget.angle != null && widget.aligned
          ? 'أنت تستقبل القبلة'
          : null,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: _turn),
          duration: reduce || widget.angle == null
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              key: const ValueKey('qibla-dial'),
              painter: QiblaDialPainter(
                angle: widget.angle == null ? null : value,
                aligned: widget.aligned,
                teal: p.tealHeading,
                gold: p.gold,
                motion: reduce || widget.angle == null
                    ? 0
                    : _energy * (1 - _motion.value),
                ink: p.heading,
                surface: p.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QiblaDialPainter extends CustomPainter {
  const QiblaDialPainter({
    required this.angle,
    required this.aligned,
    required this.teal,
    required this.gold,
    required this.ink,
    required this.surface,
    this.motion = 0,
  });
  final double? angle;
  final bool aligned;
  final double motion;
  final Color teal, gold, ink, surface;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * .405;
    final color = aligned ? teal : gold;
    final rect = Rect.fromCircle(center: center, radius: r);
    // Faceted light follows the actual interpolated bearing. Movement briefly
    // raises the glow; there is no autonomous rotating or pulsing compass.
    if (angle != null) {
      final turn = angle! * math.pi / 180;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(turn * .18);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final facet = Path()
          ..moveTo(0, 0)
          ..lineTo(math.sin(a) * r * 1.12, -math.cos(a) * r * 1.12)
          ..lineTo(
            math.sin(a + math.pi / 4) * r * 1.12,
            -math.cos(a + math.pi / 4) * r * 1.12,
          )
          ..close();
        canvas.drawPath(
          facet,
          Paint()
            ..color = (i.isEven ? gold : teal).withValues(
              alpha: .015 + motion * (i.isEven ? .12 : .055),
            ),
        );
      }
      canvas.restore();
      final focus =
          center + Offset(math.sin(turn) * r * .4, -math.cos(turn) * r * .4);
      canvas.drawCircle(
        focus,
        r * .85,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (aligned ? .18 : .04) + motion * .15),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: focus, radius: r * .85)),
      );
    }
    canvas.drawCircle(
      center,
      r * 1.1,
      Paint()
        ..shader = RadialGradient(
          colors: [teal.withValues(alpha: .10), teal.withValues(alpha: .015)],
        ).createShader(rect),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, r, stroke..color = color.withValues(alpha: .35));
    canvas.drawCircle(
      center,
      r * .90,
      stroke..color = color.withValues(alpha: .12),
    );
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi / 36;
      final inner = r - (i % 6 == 0 ? 11 : 4);
      canvas.drawLine(
        center + Offset(math.sin(a) * inner, -math.cos(a) * inner),
        center + Offset(math.sin(a) * r, -math.cos(a) * r),
        stroke..color = color.withValues(alpha: i % 6 == 0 ? .65 : .23),
      );
    }
    final kaaba = center + Offset(0, -r);
    canvas.drawCircle(kaaba, 23, Paint()..color = surface);
    canvas.drawCircle(kaaba, 23, stroke..color = gold.withValues(alpha: .6));
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: kaaba, width: 24, height: 25),
      const Radius.circular(3),
    );
    canvas.drawRRect(box, Paint()..color = ink);
    canvas.drawRect(
      Rect.fromLTWH(kaaba.dx - 12, kaaba.dy - 6, 24, 4),
      Paint()..color = gold,
    );
    canvas.drawRect(
      Rect.fromLTWH(kaaba.dx + 3, kaaba.dy + 2, 5, 10),
      Paint()..color = gold,
    );
    if (angle case final degrees?) {
      final a = degrees * math.pi / 180;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        headingDifference(degrees, 0) * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      canvas.drawCircle(
        center + Offset(math.sin(a) * r, -math.cos(a) * r),
        6,
        Paint()..color = color,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy - 4);
      canvas.rotate(a);
      canvas.drawPath(
        Path()
          ..moveTo(0, -37)
          ..lineTo(-21, 20)
          ..quadraticBezierTo(-19, 24, -15, 21)
          ..lineTo(0, 11)
          ..lineTo(15, 21)
          ..quadraticBezierTo(19, 24, 21, 20)
          ..close(),
        Paint()..color = teal,
      );
      canvas.restore();
    } else {
      final text = TextPainter(
        text: TextSpan(
          text: '—',
          style: TextStyle(color: gold, fontSize: 42),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(QiblaDialPainter old) =>
      angle != old.angle ||
      aligned != old.aligned ||
      teal != old.teal ||
      gold != old.gold ||
      ink != old.ink ||
      surface != old.surface ||
      motion != old.motion;
}
