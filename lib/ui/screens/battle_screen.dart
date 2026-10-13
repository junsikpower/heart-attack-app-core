// 배틀 화면 — 숨 고르기 → [카드 고르기 → 공격 → 결과 공개] × 6턴

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cards.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../multiplayer/room_models.dart';
import '../../providers/heart_rate_provider.dart';
import '../../providers/session_provider.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/game_dialogs.dart';
import '../widgets/heart_buddy.dart';
import '../widgets/pulse_heart.dart';
import 'result_screen.dart';

class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  Timer? _clock; // 남은 시간 표시용 (0.25초마다 다시 그림)
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _leave({bool ask = true}) async {
    if (_leaving) return;
    if (ask && !await confirmLeave(context)) return;
    _leaving = true;
    await ref.read(sessionProvider.notifier).leave();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final heart = ref.watch(heartRateProvider);
    final levels = ref.watch(voiceLevelsProvider).valueOrNull;
    final controller = ref.read(sessionProvider.notifier);

    ref.listen(sessionProvider.select((s) => s.room?.game?.phase), (prev, next) {
      if (next == GamePhase.result && mounted) {
        Navigator.of(context).pushReplacement(fadeRoute(const ResultScreen()));
      }
    });

    final room = session.room;
    final game = room?.game;
    if (room == null || game == null) {
      return const Scaffold(body: AppBackdrop(child: Center(child: CircularProgressIndicator())));
    }

    final myUid = controller.myUid;
    final oppUid = room.opponentOf(myUid);
    final me = room.player(myUid);
    final opp = room.player(oppUid);

    // ── 남은 시간 ──
    final remainMs = (game.endsAt - controller.serverNow).clamp(0, 1 << 31);
    final seconds = (remainMs / 1000).ceil();
    final phaseTotal = switch (game.phase) {
      GamePhase.calibrate => GameRules.calibrateSeconds,
      GamePhase.pick => GameRules.pickSeconds,
      GamePhase.attack => GameRules.attackSeconds,
      GamePhase.reveal => GameRules.revealSeconds,
      GamePhase.result => 1,
    };
    final progress = remainMs / (phaseTotal * 1000);

    // ── 심박 상승률 ──
    final myBaseline = room.baselines[myUid];
    final myRise = heart.isValid && myBaseline != null
        ? GameRules.risePercent(bpm: heart.bpm, baseline: myBaseline)
        : 0.0;
    final oppLive = room.live[oppUid];
    final oppBaseline = room.baselines[oppUid];
    final oppRise = oppLive != null && oppLive.ok && oppBaseline != null
        ? GameRules.risePercent(bpm: oppLive.bpm.toDouble(), baseline: oppBaseline)
        : 0.0;

    final isAttacker = game.attackerId == myUid;
    final defenderId = room.defenderOfTurn(game.turn);
    final attacking = game.phase == GamePhase.attack;
    final defenderLevel = GameRules.dokiLevel(defenderId == myUid ? myRise : oppRise);
    final card = CardDeck.byId(game.cardId);
    final record = room.turns[game.turn];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: AppBackdrop(
          tint: isAttacker ? AppColors.coral : AppColors.lilac,
          warmth: attacking ? defenderLevel / 5 : 0,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    // ── 상단 바 ──
                    Row(
                      children: [
                        RoundIconButton(icon: Icons.close_rounded, onPressed: _leave),
                        const Spacer(),
                        Chip2(
                          game.phase == GamePhase.calibrate
                              ? '준비'
                              : '라운드 ${GameRules.roundOf(game.turn)}/${GameRules.rounds} · 턴 ${game.turn + 1}/${GameRules.totalTurns}',
                          color: AppColors.ink,
                          icon: Icons.flag_circle_rounded,
                        ),
                        const Spacer(),
                        RoundIconButton(
                          icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: session.muted ? AppColors.coral : null,
                          onPressed: controller.toggleMute,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── 점수판 ──
                    _Scoreboard(
                      me: me,
                      opp: opp,
                      myScore: room.scoreOf(myUid),
                      oppScore: room.scoreOf(oppUid),
                      myFlush: attacking && defenderId == myUid ? defenderLevel / 4 : 0,
                      oppFlush: attacking && defenderId == oppUid ? defenderLevel / 4 : 0,
                      mySpeaking: levels?.mine ?? 0,
                      oppSpeaking: levels?.theirs ?? 0,
                      attackerId: game.phase == GamePhase.calibrate ? null : game.attackerId,
                    ),
                    const SizedBox(height: 14),

                    // ── 페이즈별 본문 ──
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('${game.gameId}-${game.phase.name}-${game.turn}'),
                          child: switch (game.phase) {
                            GamePhase.calibrate => _CalibrateView(
                              seconds: seconds,
                              progress: progress,
                              heart: heart,
                            ),
                            GamePhase.pick => _PickView(
                              isAttacker: isAttacker,
                              choices: game.choices.map(CardDeck.byId).whereType<TalkCard>().toList(),
                              pickedId: game.cardId,
                              opponentName: opp?.nickname ?? '상대',
                              seconds: seconds,
                              progress: progress,
                              onPick: controller.pickCard,
                            ),
                            GamePhase.attack => _AttackView(
                              isAttacker: isAttacker,
                              card: card,
                              level: defenderLevel,
                              myRise: myRise,
                              myBpm: heart.bpm,
                              points: record?.points ?? 0,
                              opponentName: opp?.nickname ?? '상대',
                              seconds: seconds,
                              progress: progress,
                            ),
                            GamePhase.reveal || GamePhase.result => _RevealView(
                              isAttacker: isAttacker,
                              record: record,
                              card: card,
                              attackerName: isAttacker ? '나' : (opp?.nickname ?? '상대'),
                              isLastTurn: game.turn + 1 >= GameRules.totalTurns,
                            ),
                          },
                        ),
                      ),
                    ),

                    // ── 하단: 내 센서 상태 ──
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SensorPill(heart: heart, showBpm: !attacking || defenderId == myUid),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _bottomHint(game.phase, isAttacker),
                            textAlign: TextAlign.right,
                            style: AppText.body(12, color: AppColors.inkFaint),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (session.abortReason != null)
                AbortOverlay(reason: session.abortReason!, onExit: () => _leave(ask: false)),
            ],
          ),
        ),
      ),
    );
  }

  String _bottomHint(GamePhase phase, bool isAttacker) => switch (phase) {
    GamePhase.calibrate => '잠시 조용히, 손가락은 그대로',
    GamePhase.pick => isAttacker ? '어떤 카드로 흔들어 볼까요?' : '마음의 준비를…',
    GamePhase.attack => isAttacker ? '말하는 내 심박은 점수에 안 들어가요' : '듣기만 하면서 포커페이스!',
    GamePhase.reveal || GamePhase.result => '곧 다음 턴',
  };
}

// ─────────────────────────────────────────────
// 점수판
// ─────────────────────────────────────────────
class _Scoreboard extends StatelessWidget {
  final RoomPlayer? me;
  final RoomPlayer? opp;
  final int myScore;
  final int oppScore;
  final double myFlush;
  final double oppFlush;
  final double mySpeaking;
  final double oppSpeaking;
  final String? attackerId;

  const _Scoreboard({
    required this.me,
    required this.opp,
    required this.myScore,
    required this.oppScore,
    required this.myFlush,
    required this.oppFlush,
    required this.mySpeaking,
    required this.oppSpeaking,
    required this.attackerId,
  });

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        Expanded(child: _side(me, myScore, myFlush, mySpeaking, '나', AppColors.coral)),
        Text('VS', style: AppText.display(16, color: AppColors.inkFaint)),
        Expanded(
          child: _side(opp, oppScore, oppFlush, oppSpeaking, opp?.nickname ?? '상대', AppColors.lilac,
              mirrored: true),
        ),
      ],
    ),
  );

  Widget _side(RoomPlayer? p, int score, double flush, double speaking, String name, Color color,
      {bool mirrored = false}) {
    final attacking = p != null && p.uid == attackerId;
    final children = [
      HeartBuddy(colorIndex: p?.colorIndex ?? 0, size: 46, flush: flush, speaking: speaking,
          dimmed: p != null && !p.online),
      const SizedBox(width: 6),
      Flexible(
        child: Column(
          crossAxisAlignment: mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attacking && mirrored) const _AttackBadge(),
                Flexible(
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppText.body(12.5, color: AppColors.inkSoft, weight: FontWeight.w700)),
                ),
                if (attacking && !mirrored) const _AttackBadge(),
              ],
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: score.toDouble()),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, _) => Text('${v.round()}', style: AppText.display(26, color: color)),
            ),
          ],
        ),
      ),
    ];
    return Row(
      mainAxisAlignment: mirrored ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: mirrored ? children.reversed.toList() : children,
    );
  }
}

class _AttackBadge extends StatelessWidget {
  const _AttackBadge();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Icon(Icons.campaign_rounded, size: 15, color: AppColors.coral),
  );
}

/// 페이즈 제목 + 타이머
class _PhaseHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int seconds;
  final double progress;
  final Color color;

  const _PhaseHeader({
    required this.title,
    required this.subtitle,
    required this.seconds,
    required this.progress,
    this.color = AppColors.coral,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.display(26)),
            const SizedBox(height: 2),
            Text(subtitle, style: AppText.body(13.5, color: AppColors.inkSoft)),
          ],
        ),
      ),
      TimerRing(progress: progress, seconds: seconds, color: color),
    ],
  );
}

// ─────────────────────────────────────────────
// 1) 숨 고르기
// ─────────────────────────────────────────────
class _CalibrateView extends StatelessWidget {
  final int seconds;
  final double progress;
  final HeartRateState heart;

  const _CalibrateView({required this.seconds, required this.progress, required this.heart});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PhaseHeader(
        title: '숨 고르기',
        subtitle: '둘 다 잠시 조용히. 평소 심박을 재고 있어요.',
        seconds: seconds,
        progress: progress,
        color: AppColors.mint,
      ),
      const Spacer(),
      PulseHeart(bpm: heart.isValid ? heart.bpm : 60, size: 150, active: heart.isMeasuring),
      const SizedBox(height: 18),
      Text(
        heart.isValid ? '${heart.bpm.round()}' : '—',
        style: AppText.display(54),
      ),
      Text('내 기준 심박 측정 중', style: AppText.body(14, color: AppColors.inkSoft)),
      const Spacer(),
      SoftCard(
        padding: const EdgeInsets.all(16),
        child: Text(
          '이 숫자가 오늘의 "평소"가 돼요. 이후엔 이보다 얼마나 올랐는지(%)로 점수가 매겨져요.',
          style: AppText.body(13.5, color: AppColors.inkSoft),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// 2) 카드 고르기
// ─────────────────────────────────────────────
class _PickView extends StatelessWidget {
  final bool isAttacker;
  final List<TalkCard> choices;
  final String? pickedId;
  final String opponentName;
  final int seconds;
  final double progress;
  final void Function(String id) onPick;

  const _PickView({
    required this.isAttacker,
    required this.choices,
    required this.pickedId,
    required this.opponentName,
    required this.seconds,
    required this.progress,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAttacker) {
      return Column(
        children: [
          _PhaseHeader(
            title: '방어 준비',
            subtitle: '$opponentName 님이 카드를 고르는 중…',
            seconds: seconds,
            progress: progress,
            color: AppColors.lilac,
          ),
          const Spacer(),
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Transform.translate(
                    offset: Offset((i - 1) * 56.0, (i - 1).abs() * 10.0),
                    child: Transform.rotate(angle: (i - 1) * 0.16, child: const _CardBack()),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('곧 공격이 시작돼요', style: AppText.display(22)),
          const SizedBox(height: 6),
          Text('듣기만 하면서 심장을 지키세요.\n손가락은 그대로!',
              textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.inkSoft)),
          const Spacer(),
        ],
      );
    }

    return Column(
      children: [
        _PhaseHeader(
          title: '내 공격 차례!',
          subtitle: '카드 한 장을 골라 주세요.',
          seconds: seconds,
          progress: progress,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: choices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => TalkCardView(
              card: choices[i],
              selected: choices[i].id == pickedId,
              onTap: pickedId == null ? () => onPick(choices[i].id) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    height: 160,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF9B8CFF), AppColors.lilac],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: AppShadows.lifted,
    ),
    child: const Center(child: PulseHeart(size: 40, bpm: 50)),
  );
}

// ─────────────────────────────────────────────
// 3) 공격 (30초)
// ─────────────────────────────────────────────
class _AttackView extends StatelessWidget {
  final bool isAttacker;
  final TalkCard? card;
  final int level;
  final double myRise;
  final double myBpm;
  final int points;
  final String opponentName;
  final int seconds;
  final double progress;

  const _AttackView({
    required this.isAttacker,
    required this.card,
    required this.level,
    required this.myRise,
    required this.myBpm,
    required this.points,
    required this.opponentName,
    required this.seconds,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PhaseHeader(
          title: isAttacker ? '흔들어라!' : '심장을 지켜라!',
          subtitle: isAttacker ? '카드대로 말해 보세요.' : '$opponentName 님의 공격이에요. 듣기만 하세요.',
          seconds: seconds,
          progress: progress,
          color: isAttacker ? AppColors.coral : AppColors.lilac,
        ),
        const SizedBox(height: 14),
        if (card != null) TalkCardView(card: card!, large: true),
        const Spacer(),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            children: [
              Row(
                children: [
                  Text(isAttacker ? '상대의 두근 미터' : '내 두근 미터',
                      style: AppText.body(13.5, color: AppColors.inkSoft, weight: FontWeight.w700)),
                  const Spacer(),
                  Text('이번 턴 ', style: AppText.body(13, color: AppColors.inkSoft)),
                  Text('+$points', style: AppText.display(20, color: AppColors.coral)),
                ],
              ),
              const SizedBox(height: 14),
              DokiMeter(level: level),
              if (!isAttacker) ...[
                const SizedBox(height: 8),
                Text(
                  myBpm > 0
                      ? '지금 ${myBpm.round()} · 평소보다 ${myRise >= 0 ? '+' : ''}${myRise.toStringAsFixed(0)}%'
                      : '측정값을 기다리는 중',
                  style: AppText.body(13, color: AppColors.inkSoft),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 4) 결과 공개 (4초)
// ─────────────────────────────────────────────
class _RevealView extends StatelessWidget {
  final bool isAttacker;
  final TurnRecord? record;
  final TalkCard? card;
  final String attackerName;
  final bool isLastTurn;

  const _RevealView({
    required this.isAttacker,
    required this.record,
    required this.card,
    required this.attackerName,
    required this.isLastTurn,
  });

  @override
  Widget build(BuildContext context) {
    final points = record?.points ?? 0;
    final peak = record?.peakRise ?? 0;
    final big = points >= 150;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isAttacker ? '내 공격 결과' : '$attackerName 님의 공격 결과',
              style: AppText.body(15, color: AppColors.inkSoft, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: points.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              '+${v.round()}',
              style: AppText.display(84, color: isAttacker ? AppColors.coral : AppColors.lilac),
            ),
          ),
          Text(
            big
                ? (isAttacker ? '제대로 흔들었어요!' : '심장이 들켰어요…')
                : (isAttacker ? '상대가 꽤 침착하네요' : '포커페이스 성공!'),
            style: AppText.display(24),
          ),
          const SizedBox(height: 14),
          if (card != null) Chip2(card!.title, color: card!.kind.color, icon: card!.kind.icon),
          const SizedBox(height: 8),
          Text('최고 상승 +$peak%', style: AppText.body(13.5, color: AppColors.inkSoft)),
          const SizedBox(height: 24),
          Text(isLastTurn ? '곧 최종 결과!' : '공수 교대!',
              style: AppText.body(14, color: AppColors.inkFaint, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
