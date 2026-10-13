// 하트 버디 (Heart Buddy) — 사진 대신 쓰는 말랑한 캐릭터
// 얼굴 사진이 없으니 외모 평가가 없고, 캐릭터 표정이 '두근 정도'에 따라 변해 게임다운 피드백을 준다.
//   flush 0.0 : 평온 (점 눈, 옅은 볼터치)
//   flush 1.0 : 심쿵 (> < 눈, 진한 볼터치, 동그란 입, 살짝 떨림)
//   speaking  : 말하는 중이면 바깥에 음성 파동 링

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class HeartBuddy extends StatefulWidget {
  final int colorIndex;
  final double size;
  final double flush; // 0.0 ~ 1.0
  final double speaking; // 0.0 ~ 1.0 (음량)
  final bool dimmed; // 연결 끊김 등

  const HeartBuddy({
    super.key,
    required this.colorIndex,
    this.size = 72,
    this.flush = 0,
    this.speaking = 0,
    this.dimmed = false,
  });

  @override
  State<HeartBuddy> createState() => _HeartBuddyState();
}

class _HeartBuddyState extends State<HeartBuddy> with SingleTickerProviderStateMixin {
  // 숨 쉬듯 살짝 부풀었다 줄어드는 기본 애니메이션
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.buddies[widget.colorIndex % AppColors.buddies.length];
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size * 1.3,
        height: widget.size * 1.3,
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, _) => CustomPaint(
            painter: _BuddyPainter(
              color: widget.dimmed ? const Color(0xFFD9D3DD) : color,
              t: _breath.value,
              flush: widget.flush.clamp(0.0, 1.0),
              speaking: widget.speaking.clamp(0.0, 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuddyPainter extends CustomPainter {
  final Color color;
  final double t;
  final double flush;
  final double speaking;

  _BuddyPainter({required this.color, required this.t, required this.flush, required this.speaking});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 1.3;
    final wave = math.sin(t * math.pi * 2);

    // 1) 말하는 중: 음량에 비례한 파동 링
    if (speaking > 0.05) {
      final ringR = base * (0.62 + speaking * 0.14);
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..color = color.withValues(alpha: 0.18 + speaking * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = base * 0.05,
      );
    }

    // 2) 몸통: 말랑한 떡 모양 (숨쉬기 + 두근거릴수록 떨림)
    final shake = flush > 0.6 ? math.sin(t * math.pi * 24) * base * 0.012 * flush : 0.0;
    final w = base * (0.98 + wave * 0.015);
    final h = base * (0.9 - wave * 0.015);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c.translate(shake, base * 0.02), width: w, height: h),
      Radius.circular(base * 0.44),
    );
    // 바닥 그림자
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, h * 0.52), width: w * 0.7, height: base * 0.08),
      Paint()..color = const Color(0x14221A2E),
    );
    canvas.drawRRect(body, Paint()..color = color);
    // 위쪽 하이라이트로 입체감
    canvas.drawRRect(
      body.deflate(base * 0.06).shift(Offset(-base * 0.04, -base * 0.06)),
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
          center: const Alignment(-0.5, -0.7),
          radius: 0.8,
        ).createShader(body.outerRect),
    );

    final face = c.translate(shake, base * 0.04);
    final ink = Paint()
      ..color = AppColors.ink
      ..strokeCap = StrokeCap.round
      ..strokeWidth = base * 0.045
      ..style = PaintingStyle.stroke;

    // 3) 볼터치: 두근거릴수록 진하고 커진다
    final blush = Paint()..color = AppColors.coral.withValues(alpha: 0.18 + flush * 0.45);
    for (final dx in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: face.translate(dx * base * 0.26, base * 0.06),
          width: base * (0.16 + flush * 0.06),
          height: base * (0.09 + flush * 0.03),
        ),
        blush,
      );
    }

    // 4) 눈: 평온하면 점, 심쿵이면 > <
    final eyeY = face.dy - base * 0.06;
    for (final dx in [-1.0, 1.0]) {
      final ex = face.dx + dx * base * 0.17;
      if (flush > 0.75) {
        final s = base * 0.055;
        final path = Path()
          ..moveTo(ex - dx * s, eyeY - s)
          ..lineTo(ex + dx * s * 0.2, eyeY)
          ..lineTo(ex - dx * s, eyeY + s);
        canvas.drawPath(path, ink);
      } else {
        // 깜빡임: 주기 끝에서 잠깐 감음
        final blink = t > 0.93 ? 0.15 : 1.0;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, eyeY), width: base * 0.07, height: base * 0.1 * blink),
          Paint()..color = AppColors.ink,
        );
      }
    }

    // 5) 입: 평온하면 미소, 두근거리면 작은 'o'
    final mouthC = face.translate(0, base * 0.1);
    if (flush > 0.45) {
      canvas.drawOval(
        Rect.fromCenter(center: mouthC, width: base * 0.08, height: base * (0.06 + flush * 0.04)),
        Paint()..color = AppColors.ink,
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(center: mouthC.translate(0, -base * 0.02), width: base * 0.14, height: base * 0.09),
        0.2,
        math.pi - 0.4,
        false,
        ink..strokeWidth = base * 0.035,
      );
    }
  }

  @override
  bool shouldRepaint(_BuddyPainter old) =>
      old.t != t || old.flush != flush || old.speaking != speaking || old.color != color;
}
