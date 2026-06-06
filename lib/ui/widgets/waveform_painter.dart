// 심전도 파형(Waveform) 그래픽 위젯
// 역할: CameraService에서 나오는 0~1 사이의 신호 값 배열을 받아 실시간 심전도 그래프를 화면에 그림
// 아키텍처 플랜: ui/widgets/waveform_painter.dart

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────
// WaveformPainter: CustomPainter를 상속하여 직접 캔버스에 선을 그리는 클래스
// Flutter의 CustomPaint 위젯이 이 클래스에게 '붓(Canvas)'을 건네면,
// 이 클래스가 그 붓으로 심전도 선을 그린다.
// ─────────────────────────────────────────────────────────
class WaveformPainter extends CustomPainter {
  final List<double> waveformData; // 0.0 ~ 1.0 사이로 정규화된 신호 값 목록
  final Color lineColor;           // 선 색상 (기본: 네온 레드)
  final double strokeWidth;        // 선 굵기

  WaveformPainter({
    required this.waveformData,
    this.lineColor = const Color(0xFFFF2D55), // 애플 스타일 핑크 레드
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 데이터가 2개 미만이면 선을 그릴 수 없으므로 종료
    if (waveformData.length < 2) return;

    // ── 네온 글로우 효과 (Neon Glow) ──
    // 실제 선보다 넓은 반투명 선을 먼저 그려서, 빛이 번지는 효과를 연출
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.25)
      ..strokeWidth = strokeWidth * 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0); // 블러 처리로 빛 번짐 효과

    // ── 메인 선 (Main Line) ──
    // 선명하고 밝은 메인 심전도 선
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // ── 경로(Path) 생성 ──
    // waveformData 배열을 순서대로 연결하여 꺾인 선 경로를 만든다
    final path = Path();
    final glowPath = Path();

    final double xStep = size.width / (waveformData.length - 1);

    for (int i = 0; i < waveformData.length; i++) {
      // x 좌표: 왼쪽에서 오른쪽으로 균등 배분
      final double x = i * xStep;

      // y 좌표: 신호 값(0~1)을 화면 높이에 맞게 변환
      // 값이 0이면 화면 하단(아래), 1이면 화면 상단(위)
      // 중앙 70% 범위만 사용하여 위아래 여백을 줌
      final double y = size.height * (1.0 - (waveformData[i] * 0.7 + 0.15));

      if (i == 0) {
        path.moveTo(x, y);
        glowPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        glowPath.lineTo(x, y);
      }
    }

    // 글로우(빛 번짐) 경로를 먼저 그리고, 메인 선을 그 위에 덧그림
    canvas.drawPath(glowPath, glowPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // 데이터가 바뀌었을 때만 화면을 다시 그려 성능 낭비 방지
    return oldDelegate.waveformData != waveformData;
  }
}

// ─────────────────────────────────────────────────────────
// WaveformWidget: WaveformPainter를 실제 위젯으로 감싼 편의 클래스
// game_screen.dart에서 WaveformWidget(waveformData: state.waveform) 형태로 사용
// ─────────────────────────────────────────────────────────
class WaveformWidget extends StatelessWidget {
  final List<double> waveformData;
  final double height;

  const WaveformWidget({
    super.key,
    required this.waveformData,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: WaveformPainter(waveformData: waveformData),
      ),
    );
  }
}
