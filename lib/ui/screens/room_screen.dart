// 대기실 — 상대를 기다리고, 둘 다 손가락 측정이 잡히면 자동으로 시작

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../multiplayer/room_models.dart';
import '../../providers/heart_rate_provider.dart';
import '../../providers/session_provider.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/game_dialogs.dart';
import '../widgets/heart_buddy.dart';
import 'battle_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  bool _leaving = false;

  Future<void> _leave({bool ask = true}) async {
    if (_leaving) return;
    if (ask && !await confirmLeave(context, message: '대기실에서 나갈까요?')) return;
    _leaving = true;
    await ref.read(sessionProvider.notifier).leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final heart = ref.watch(heartRateProvider);
    final levels = ref.watch(voiceLevelsProvider).valueOrNull;
    final controller = ref.read(sessionProvider.notifier);
    final room = session.room;

    // 게임이 시작되면 배틀 화면으로
    ref.listen(sessionProvider.select((s) => s.room?.status), (prev, next) {
      if (next == RoomStatus.playing && mounted) {
        Navigator.of(context).pushReplacement(fadeRoute(const BattleScreen()));
      }
    });

    final myUid = controller.myUid;
    final me = room?.player(myUid);
    final opponent = room?.player(room.opponentOf(myUid));
    final bothReady = (me?.ready ?? false) && (opponent?.ready ?? false) && (opponent?.online ?? false);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: AppBackdrop(
          tint: AppColors.mint,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Row(
                    children: [
                      RoundIconButton(icon: Icons.close_rounded, onPressed: _leave),
                      const SizedBox(width: 12),
                      Text('대기실', style: AppText.display(26)),
                      const Spacer(),
                      if (session.code != null) _CodeChip(code: session.code!),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // ── 두 사람 자리 ──
                  Row(
                    children: [
                      Expanded(
                        child: _Seat(
                          player: me,
                          isMe: true,
                          speaking: levels?.mine ?? 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Seat(
                          player: opponent,
                          isMe: false,
                          speaking: levels?.theirs ?? 0,
                          code: session.code,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── 진행 안내 ──
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: bothReady
                        ? SoftCard(
                            key: const ValueKey('go'),
                            color: AppColors.mintSoft,
                            borderColor: AppColors.mint.withValues(alpha: 0.3),
                            child: Row(
                              children: [
                                const Icon(Icons.favorite_rounded, color: AppColors.mint),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '둘 다 준비 완료! ${GameRules.lobbyReadyHoldSeconds}초 뒤 시작해요.\n손가락은 그대로 두세요.',
                                    style: AppText.body(14.5, weight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _FingerGuide(key: const ValueKey('guide'), waitingForOpponent: opponent == null),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (heart.isMeasuring) SensorPill(heart: heart) else const Chip2('상대가 오면 측정을 시작해요'),
                      const Spacer(),
                      RoundIconButton(
                        icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: session.muted ? AppColors.coral : null,
                        tooltip: '마이크',
                        onPressed: controller.toggleMute,
                      ),
                    ],
                  ),
                  if (session.voiceError != null) ...[
                    const SizedBox(height: 10),
                    Text('음성 연결 실패: ${session.voiceError}',
                        style: AppText.body(12.5, color: AppColors.coral)),
                  ],
                ],
              ),
              if (session.abortReason != null)
                AbortOverlay(reason: session.abortReason!, onExit: () => _leave(ask: false)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;
  const _CodeChip({required this.code});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      Clipboard.setData(ClipboardData(text: code));
      showToast(context, '방 코드 $code 를 복사했어요');
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(code, style: AppText.display(18).copyWith(letterSpacing: 3)),
          const SizedBox(width: 6),
          const Icon(Icons.copy_rounded, size: 16, color: AppColors.inkSoft),
        ],
      ),
    ),
  );
}

class _Seat extends StatelessWidget {
  final RoomPlayer? player;
  final bool isMe;
  final double speaking;
  final String? code;

  const _Seat({required this.player, required this.isMe, this.speaking = 0, this.code});

  @override
  Widget build(BuildContext context) {
    final p = player;
    if (p == null) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        color: AppColors.paper.withValues(alpha: 0.7),
        child: Column(
          children: [
            const SizedBox(
              width: 70,
              height: 70,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.inkFaint)),
            ),
            const SizedBox(height: 12),
            Text('기다리는 중', style: AppText.display(18, color: AppColors.inkSoft)),
            const SizedBox(height: 4),
            Text(code != null ? '친구에게 코드 $code' : '',
                textAlign: TextAlign.center, style: AppText.body(12, color: AppColors.inkFaint)),
          ],
        ),
      );
    }
    final ready = p.ready && p.online;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      borderColor: ready ? AppColors.mint.withValues(alpha: 0.5) : null,
      child: Column(
        children: [
          HeartBuddy(colorIndex: p.colorIndex, size: 70, speaking: speaking, dimmed: !p.online),
          const SizedBox(height: 6),
          Text(p.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(18)),
          const SizedBox(height: 6),
          Chip2(
            !p.online
                ? '연결 끊김'
                : ready
                ? '준비 완료'
                : (isMe ? '손가락 대기' : '측정 준비 중'),
            color: !p.online ? AppColors.inkFaint : (ready ? AppColors.mint : AppColors.amber),
            icon: ready ? Icons.check_circle_rounded : Icons.touch_app_rounded,
          ),
          if (isMe) ...[
            const SizedBox(height: 4),
            Text('나', style: AppText.body(11.5, color: AppColors.inkFaint)),
          ],
        ],
      ),
    );
  }
}

/// 후면 카메라 손가락 위치 안내
class _FingerGuide extends StatelessWidget {
  final bool waitingForOpponent;
  const _FingerGuide({super.key, required this.waitingForOpponent});

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Row(
      children: [
        const _PhoneBackIllustration(),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('손가락을 뒷면 카메라에', style: AppText.display(19)),
              const SizedBox(height: 6),
              Text(
                '휴대폰을 쥔 손의 검지를 카메라와 플래시 위에 살짝 덮어주세요. 꾹 누르면 오히려 잘 안 잡혀요.',
                style: AppText.body(13.5, color: AppColors.inkSoft),
              ),
              if (waitingForOpponent) ...[
                const SizedBox(height: 8),
                Text('플래시는 상대가 들어오면 켜져요.',
                    style: AppText.body(12.5, color: AppColors.inkFaint, weight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _PhoneBackIllustration extends StatelessWidget {
  const _PhoneBackIllustration();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 104,
    child: Stack(
      children: [
        // 휴대폰 뒷면
        Container(
          width: 64,
          height: 104,
          decoration: BoxDecoration(
            color: AppColors.lilacSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.lilac.withValues(alpha: 0.4), width: 2),
          ),
        ),
        // 카메라 섬 (갤럭시처럼 세로 렌즈 배열)
        Positioned(
          left: 10,
          top: 10,
          child: Column(
            children: List.generate(
              3,
              (i) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        // 손가락
        Positioned(
          left: 2,
          top: 4,
          child: Container(
            width: 30,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC9B0).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFF4A98A), width: 1.5),
            ),
          ),
        ),
      ],
    ),
  );
}
