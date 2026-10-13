// 로비 — 앱의 첫 화면
// 멀티플레이(1:1 두근 배틀) 입장 / 스토리 모드(준비 중) / 게임 방법 / 측정 장치 표시

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../heart/heart_rate_source.dart';
import '../../providers/heart_rate_provider.dart';
import '../../providers/profile_provider.dart';
import '../nav.dart';
import '../sheets/coming_soon_sheet.dart';
import '../sheets/profile_sheet.dart';
import '../widgets/common.dart';
import '../widgets/heart_buddy.dart';
import '../widgets/pulse_heart.dart';
import 'how_to_play_screen.dart';
import 'multi_entry_screen.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    // 처음 실행이면 닉네임부터 정한다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(profileProvider.notifier).hasProfile) {
        showProfileSheet(context, force: true);
      }
    });
  }

  Future<void> _openMulti() async {
    if (!ref.read(profileProvider.notifier).hasProfile) {
      final ok = await showProfileSheet(context);
      if (!ok || !mounted) return;
    }
    Navigator.of(context).push(fadeRoute(const MultiEntryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final minutes = (GameRules.estimatedMatchSeconds / 60).round();

    return Scaffold(
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            // ── 상단: 내 프로필 + 게임 방법 ──
            Row(
              children: [
                GestureDetector(
                  onTap: () => showProfileSheet(context),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeartBuddy(colorIndex: profile?.colorIndex ?? 0, size: 30),
                        const SizedBox(width: 2),
                        Text(profile?.nickname ?? '닉네임 정하기',
                            style: AppText.body(14, weight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_rounded, size: 14, color: AppColors.inkFaint),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                RoundIconButton(
                  icon: Icons.menu_book_rounded,
                  tooltip: '게임 방법',
                  onPressed: () => Navigator.of(context).push(fadeRoute(const HowToPlayScreen())),
                ),
              ],
            ),

            // ── 타이틀 ──
            const SizedBox(height: 28),
            const Center(child: PulseHeart(bpm: 72, size: 92)),
            const SizedBox(height: 14),
            Center(child: Text('Heart Attack', style: AppText.display(44))),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '말로 상대의 심장을 두근거리게!\n내 심장은 들키지 말고.',
                textAlign: TextAlign.center,
                style: AppText.body(15.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(height: 30),

            // ── 멀티플레이 카드 ──
            _ModeCard(
              onTap: _openMulti,
              gradient: AppColors.heartGradient,
              title: '1:1 두근 배틀',
              subtitle: '목소리로만 · 카드로 대화 · 약 $minutes분',
              badge: '멀티플레이',
              trailing: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeartBuddy(colorIndex: 0, size: 42, flush: 0.2),
                  HeartBuddy(colorIndex: 5, size: 42, flush: 0.85),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── 스토리 모드 (준비 중) ──
            _ModeCard(
              onTap: () => showStoryComingSoon(context),
              title: '스토리 모드',
              subtitle: '캐릭터와 1:1 · 내 심박이 이야기를 바꿔요',
              badge: '곧 공개',
              light: true,
              trailing: const Icon(Icons.lock_clock_rounded, color: AppColors.lilac, size: 34),
            ),

            const SizedBox(height: 26),
            const _DeviceRow(),
            const SizedBox(height: 14),
            Center(
              child: Text(
                '영상·사진 없이, 대화와 심장으로만 노는 게임',
                style: AppText.body(12.5, color: AppColors.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final VoidCallback onTap;
  final Gradient? gradient;
  final String title;
  final String subtitle;
  final String badge;
  final Widget trailing;
  final bool light;

  const _ModeCard({
    required this.onTap,
    this.gradient,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.trailing,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = light ? AppColors.ink : Colors.white;
    final radius = BorderRadius.circular(28);
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        color: light ? AppColors.paper : null,
        borderRadius: radius,
        border: light ? Border.all(color: AppColors.line) : null,
        boxShadow: light ? AppShadows.soft : AppShadows.glow(AppColors.coral),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 14, 22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: light ? AppColors.lilacSoft : Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(badge,
                            style: AppText.body(11.5,
                                color: light ? AppColors.lilac : Colors.white, weight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      Text(title, style: AppText.display(27, color: fg)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: AppText.body(13.5, color: fg.withValues(alpha: light ? 0.6 : 0.88))),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 측정 장치 표시 — 지금은 카메라, 워치는 연동 준비 중
class _DeviceRow extends ConsumerWidget {
  const _DeviceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(heartSourcesProvider);
    final selected = ref.watch(heartSourceKindProvider);
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text('측정 장치', style: AppText.body(13.5, weight: FontWeight.w700)),
          ),
          for (final kind in HeartSourceKind.values) ...[
            Chip2(
              sources[kind]!.isAvailable ? kind.label : '${kind.label} · 준비 중',
              icon: kind.icon,
              color: kind == selected
                  ? AppColors.mint
                  : (sources[kind]!.isAvailable ? AppColors.inkSoft : AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
