// 게임 방법 — 규칙을 한눈에

import 'package:flutter/material.dart';
import '../../core/cards.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = <(IconData, String, String)>[
      (
        Icons.touch_app_rounded,
        '손가락 올리기',
        '휴대폰을 쥔 손의 검지를 뒷면 카메라·플래시 위에 살짝 올려요. 꾹 누르지 말고 가볍게!',
      ),
      (
        Icons.self_improvement_rounded,
        '숨 고르기 ${GameRules.calibrateSeconds}초',
        '둘 다 잠시 조용히. 각자의 평소 심박(기준 심박)을 재요.',
      ),
      (
        Icons.style_rounded,
        '카드 고르기 ${GameRules.pickSeconds}초',
        '공격 차례인 사람이 서로 다른 카드 3장 중 하나를 골라요.',
      ),
      (
        Icons.record_voice_over_rounded,
        '공격 ${GameRules.attackSeconds}초',
        '공격자는 카드대로 말하고, 방어자는 듣기만 해요. 이때 방어자의 심박만 잽니다.',
      ),
      (
        Icons.swap_horiz_rounded,
        '공수 교대 × ${GameRules.totalTurns}턴',
        '${GameRules.rounds}라운드 동안 번갈아 공격해요. 한 판은 약 ${(GameRules.estimatedMatchSeconds / 60).round()}분.',
      ),
    ];

    return Scaffold(
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Text('게임 방법', style: AppText.display(26)),
              ],
            ),
            const SizedBox(height: 22),
            SoftCard(
              color: AppColors.coralSoft,
              borderColor: AppColors.coral.withValues(alpha: 0.2),
              child: Text(
                '말로 상대의 심장을 흔들고, 내 심장은 들키지 마세요.\n심장은 거짓말을 못 하니까요.',
                style: AppText.display(19, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++) ...[
              _Step(index: i + 1, icon: steps[i].$1, title: steps[i].$2, body: steps[i].$3),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            Text('점수 규칙', style: AppText.display(22)),
            const SizedBox(height: 10),
            const _Rule(
              icon: Icons.trending_up_rounded,
              text: '공격 중 1초마다, 방어자 심박이 기준보다 높은 만큼(%) 공격자가 점수를 얻어요.\n예) 기준 70 → 지금 77이면 +10%, 그 1초에 10점',
            ),
            const _Rule(
              icon: Icons.shield_moon_rounded,
              text: '1초에 최대 ${GameRules.maxRisePercentPerSecond ~/ 1}점. 측정이 한 번 튀어도 승부가 갈리지 않아요.',
            ),
            const _Rule(
              icon: Icons.back_hand_rounded,
              text: '방어자가 손가락을 떼면 ${GameRules.hideGraceSeconds}초까지는 봐줘요. 그 뒤로는 숨긴 걸로 간주해 1초마다 공격자 +${GameRules.hidePenaltyPerSecond ~/ 1}점.',
            ),
            const _Rule(
              icon: Icons.visibility_off_rounded,
              text: '공격자에게는 상대의 정확한 숫자 대신 "두근 미터"만 보여요. 정확한 기록은 게임이 끝나고 공개!',
            ),
            const _Rule(
              icon: Icons.emoji_events_rounded,
              text: '6턴이 끝나면 총점이 높은 사람이 승리.',
            ),
            const SizedBox(height: 18),
            Text('카드 종류', style: AppText.display(22)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in CardKind.values) Chip2('${k.label} · ${k.verb}', color: k.color, icon: k.icon),
              ],
            ),
            const SizedBox(height: 18),
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                '왜 듣는 사람만 잴까요?\n말하는 행동 자체가 심박을 올리기 때문이에요. 그래서 듣는 사람의 심장만 공정하게 잽니다.',
                style: AppText.body(13.5, color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String body;
  const _Step({required this.index, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.coral),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index. $title', style: AppText.display(18)),
              const SizedBox(height: 3),
              Text(body, style: AppText.body(13.5, color: AppColors.inkSoft)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.coral),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.body(14))),
      ],
    ),
  );
}
