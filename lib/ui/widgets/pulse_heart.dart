// 박동하는 하트 — 실제 BPM 속도에 맞춰 뛴다 (bpm 0이면 느린 기본 박동)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PulseHeart extends StatefulWidget {
  final double bpm;
  final double size;
  final Gradient gradient;
  final bool active;

  const PulseHeart({
    super.key,
    this.bpm = 0,
    this.size = 64,
    this.gradient = AppColors.heartGradient,
    this.active = true,
  });

  @override
  State<PulseHeart> createState() => _PulseHeartState();
}

class _PulseHeartState extends State<PulseHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: _period())
    ..repeat();

  Duration _period() {
    final bpm = widget.bpm > 30 ? widget.bpm : 60.0;
    return Duration(milliseconds: (60000 / bpm).round());
  }

  @override
  void didUpdateWidget(PulseHeart old) {
    super.didUpdateWidget(old);
    final p = _period();
    if ((p.inMilliseconds - (_beat.duration?.inMilliseconds ?? 0)).abs() > 40) {
      _beat.duration = p;
      if (_beat.isAnimating) _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// 심장 박동처럼 '쿵-쿵' 두 번 뛰고 쉬는 곡선
  double _scale(double t) {
    double bump(double center, double width, double h) {
      final d = (t - center) / width;
      return h * math.exp(-d * d);
    }

    return 1.0 + bump(0.08, 0.05, 0.14) + bump(0.24, 0.05, 0.07);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _beat,
        builder: (context, child) => Transform.scale(
          scale: widget.active ? _scale(_beat.value) : 1.0,
          child: child,
        ),
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: HeartPainter(widget.active ? widget.gradient : null),
        ),
      ),
    );
  }
}

class HeartPainter extends CustomPainter {
  final Gradient? gradient;
  HeartPainter(this.gradient);

  static Path heartPath(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.9)
      ..cubicTo(w * 0.12, h * 0.66, w * -0.02, h * 0.38, w * 0.2, h * 0.17)
      ..cubicTo(w * 0.34, h * 0.04, w * 0.47, h * 0.12, w * 0.5, h * 0.25)
      ..cubicTo(w * 0.53, h * 0.12, w * 0.66, h * 0.04, w * 0.8, h * 0.17)
      ..cubicTo(w * 1.02, h * 0.38, w * 0.88, h * 0.66, w * 0.5, h * 0.9)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = heartPath(size);
    final rect = Offset.zero & size;
    canvas.drawPath(
      path.shift(Offset(0, size.height * 0.05)),
      Paint()
        ..color = (gradient == null ? AppColors.inkFaint : AppColors.coral).withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = (gradient ??
                const LinearGradient(colors: [Color(0xFFE4DDE8), Color(0xFFCFC6D6)]))
            .createShader(rect),
    );
    // 반짝이 하이라이트
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.22, size.height * 0.22, size.width * 0.16, size.height * 0.1),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(HeartPainter old) => old.gradient != gradient;
}
