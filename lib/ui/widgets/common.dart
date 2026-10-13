// 공통 UI 부품 모음

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/cards.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../heart/heart_rate_source.dart';
import '../../providers/heart_rate_provider.dart';

/// 크림 배경 + 은은한 색 덩어리(blob) 배경.
/// Android 15+는 화면이 시스템 바 뒤까지 그려지므로(edge-to-edge), 내용은 SafeArea 안에 둔다.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  final Color tint; // 오른쪽 위 blob 색 (화면 분위기)
  final double warmth; // 0~1, 두근거릴수록 배경이 붉게 달아오름

  const AppBackdrop({
    super.key,
    required this.child,
    this.tint = AppColors.lilac,
    this.warmth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      color: Color.lerp(AppColors.cream, const Color(0xFFFFE6E4), warmth.clamp(0.0, 1.0)),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _Blob(color: tint.withValues(alpha: 0.13), size: 300),
          ),
          Positioned(
            bottom: -140,
            left: -110,
            child: _Blob(color: AppColors.coral.withValues(alpha: 0.10 + warmth * 0.12), size: 340),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

/// 흰 종이 카드
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color = AppColors.paper,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        boxShadow: AppShadows.soft,
        border: Border.all(color: borderColor ?? AppColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 메인 버튼 (코랄 그라데이션, 눌리면 살짝 들어감)
class BigButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool secondary;

  const BigButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.secondary = false,
  });

  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = widget.secondary ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedOpacity(
          opacity: enabled || widget.busy ? 1 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: widget.secondary ? null : AppColors.heartGradient,
              color: widget.secondary ? AppColors.paper : null,
              borderRadius: BorderRadius.circular(20),
              border: widget.secondary ? Border.all(color: AppColors.line, width: 1.5) : null,
              boxShadow: widget.secondary ? AppShadows.soft : AppShadows.glow(AppColors.coral),
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: fg, size: 22),
                        const SizedBox(width: 8),
                      ],
                      Text(widget.label, style: AppText.display(19, color: fg)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 둥근 아이콘 버튼 (상단 바용)
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;

  const RoundIconButton({super.key, required this.icon, this.onPressed, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Material(
      color: AppColors.paper,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: color ?? AppColors.ink),
        ),
      ),
    ),
  );
}

/// 작은 라벨 칩
class Chip2 extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Chip2(this.text, {super.key, this.color = AppColors.inkSoft, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Text(text, style: AppText.body(12, color: color, weight: FontWeight.w700)),
      ],
    ),
  );
}

/// 내 심박 센서 상태 표시
class SensorPill extends StatelessWidget {
  final HeartRateState heart;
  final bool showBpm;
  const SensorPill({super.key, required this.heart, this.showBpm = true});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color, IconData icon) = switch (heart.signal) {
      HeartSignal.measuring => (
        showBpm ? '측정 중 · ${heart.bpm.round()}' : '측정 중',
        AppColors.mint,
        Icons.favorite_rounded,
      ),
      HeartSignal.preparing => ('맥박 찾는 중…', AppColors.amber, Icons.hourglass_top_rounded),
      HeartSignal.lost => ('뒷면 카메라에 손가락을!', AppColors.coral, Icons.touch_app_rounded),
      HeartSignal.error => ('카메라 오류', AppColors.coral, Icons.error_outline_rounded),
      HeartSignal.idle => ('측정 꺼짐', AppColors.inkFaint, Icons.favorite_border_rounded),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: AppText.body(13, color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 남은 시간 원형 타이머
class TimerRing extends StatelessWidget {
  final double progress; // 1 → 0
  final int seconds;
  final Color color;
  final double size;

  const TimerRing({
    super.key,
    required this.progress,
    required this.seconds,
    this.color = AppColors.coral,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _RingPainter(progress.clamp(0.0, 1.0), seconds <= 5 ? AppColors.coral : color),
      child: Center(
        child: Text(
          '$seconds',
          style: AppText.display(size * 0.38, color: seconds <= 5 ? AppColors.coral : AppColors.ink),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double p;
  final Color color;
  _RingPainter(this.p, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()
          ..color = AppColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * p, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p || old.color != color;
}

/// 두근 미터: 상대의 정확한 심박 대신 5단계로만 보여준다
class DokiMeter extends StatelessWidget {
  final int level; // 0~4
  final bool compact;
  const DokiMeter({super.key, required this.level, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final h = compact ? 10.0 : 14.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(5, (i) {
            final on = i <= level && level > 0 || i == 0;
            final c = Color.lerp(AppColors.peach, AppColors.coral, i / 4)!;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: on ? h + i * (compact ? 2 : 4) : h,
                decoration: BoxDecoration(
                  color: on ? c : AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          }),
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text(
              GameRules.dokiLabels[level.clamp(0, 4)],
              key: ValueKey(level),
              style: AppText.display(28, color: level >= 3 ? AppColors.coral : AppColors.ink),
            ),
          ),
        ],
      ],
    );
  }
}

/// 토크 카드
class TalkCardView extends StatelessWidget {
  final TalkCard card;
  final bool large;
  final VoidCallback? onTap;
  final bool selected;

  const TalkCardView({
    super.key,
    required this.card,
    this.large = false,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = card.kind;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? k.color : AppColors.line, width: selected ? 2.5 : 1),
        boxShadow: selected ? AppShadows.glow(k.color) : AppShadows.soft,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(large ? 22 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: k.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(k.icon, size: large ? 22 : 18, color: k.color),
                    ),
                    const SizedBox(width: 8),
                    Text('${k.label} · ${k.verb}',
                        style: AppText.body(12.5, color: k.color, weight: FontWeight.w800)),
                  ],
                ),
                SizedBox(height: large ? 16 : 10),
                Text(card.title, style: AppText.display(large ? 30 : 21)),
                SizedBox(height: large ? 10 : 6),
                Text(card.prompt,
                    style: AppText.body(large ? 16 : 13.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 공통 스낵바
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
