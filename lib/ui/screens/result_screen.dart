// 결과 화면 — 승패, 오늘의 두근 모먼트, 턴별 기록(심박 상승 그래프), 한 판 더

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cards.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../multiplayer/room_models.dart';
import '../../providers/session_provider.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/heart_buddy.dart';
import 'battle_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _leaving = false;

  Future<void> _toLobby() async {
    if (_leaving) return;
    _leaving = true;
    await ref.read(sessionProvider.notifier).leave();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);

    // 둘 다 '한 판 더'를 누르면 새 판이 시작된다
    ref.listen(sessionProvider.select((s) => s.room?.status), (prev, next) {
      if (prev == RoomStatus.finished && next == RoomStatus.playing && mounted) {
        Navigator.of(context).pushReplacement(fadeRoute(const BattleScreen()));
      }
    });

    final room = session.room;
    if (room == null) {
      return Scaffold(
        body: AppBackdrop(
          child: Center(child: BigButton(label: '로비로', onPressed: _toLobby)),
        ),
      );
    }

    final myUid = controller.myUid;
    final oppUid = room.opponentOf(myUid);
    final me = room.player(myUid);
    final opp = room.player(oppUid);
    final myScore = room.scoreOf(myUid);
    final oppScore = room.scoreOf(oppUid);
    final outcome = GameRules.compareScores(myScore, oppScore);
    final turns = room.turns.values.toList()..sort((a, b) => a.turn.compareTo(b.turn));
    final best = turns.isEmpty ? null : turns.reduce((a, b) => b.points > a.points ? b : a);

    final (String title, String sub) = switch (outcome) {
      1 => ('심장 털기 성공!', '상대의 심장을 더 크게 흔들었어요'),
      -1 => ('내 심장이 들켰어요', '이번엔 상대가 한 수 위!'),
      _ => ('막상막하!', '두 심장이 똑같이 흔들렸어요'),
    };

    final iWantRematch = me?.rematch ?? false;
    final oppWantsRematch = opp?.rematch ?? false;
    final oppGone = opp == null || !opp.online;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toLobby();
      },
      child: Scaffold(
        body: AppBackdrop(
          tint: outcome >= 0 ? AppColors.coral : AppColors.lilac,
          warmth: outcome > 0 ? 0.35 : 0,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              // ── 승패 배너 ──
              Center(child: Text(title, style: AppText.display(36))),
              const SizedBox(height: 4),
              Center(child: Text(sub, style: AppText.body(14.5, color: AppColors.inkSoft))),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Player(player: me, name: '나', score: myScore, color: AppColors.coral,
                      // 진 사람 = 심장이 더 흔들린 사람 → 빨개진 표정
                      flush: outcome < 0 ? 1 : 0.1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(':', style: AppText.display(40, color: AppColors.inkFaint)),
                  ),
                  _Player(player: opp, name: opp?.nickname ?? '상대', score: oppScore,
                      color: AppColors.lilac, flush: outcome > 0 ? 1 : 0.1),
                ],
              ),
              const SizedBox(height: 22),

              // ── 오늘의 두근 모먼트 ──
              if (best != null && best.points > 0) ...[
                _MomentCard(
                  record: best,
                  attackerName: best.attackerId == myUid ? '나' : (opp?.nickname ?? '상대'),
                  defenderName: best.defenderId == myUid ? '나' : (opp?.nickname ?? '상대'),
                ),
                const SizedBox(height: 18),
              ],

              // ── 턴별 기록 ──
              Text('턴별 기록', style: AppText.display(20)),
              const SizedBox(height: 10),
              for (final t in turns) ...[
                _TurnRow(record: t, mine: t.attackerId == myUid, opponentName: opp?.nickname ?? '상대'),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 18),

              // ── 버튼 ──
              BigButton(
                label: oppGone
                    ? '상대가 떠났어요'
                    : iWantRematch
                    ? (oppWantsRematch ? '곧 시작!' : '상대를 기다리는 중…')
                    : (oppWantsRematch ? '상대가 한 판 더 원해요!' : '한 판 더'),
                icon: Icons.replay_rounded,
                onPressed: oppGone || iWantRematch ? null : controller.requestRematch,
              ),
              const SizedBox(height: 10),
              BigButton(label: '로비로', secondary: true, onPressed: _toLobby),
            ],
          ),
        ),
      ),
    );
  }
}

class _Player extends StatelessWidget {
  final RoomPlayer? player;
  final String name;
  final int score;
  final Color color;
  final double flush;

  const _Player({required this.player, required this.name, required this.score, required this.color, required this.flush});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      HeartBuddy(colorIndex: player?.colorIndex ?? 0, size: 76, flush: flush),
      SizedBox(
        width: 110,
        child: Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppText.body(13, color: AppColors.inkSoft, weight: FontWeight.w700)),
      ),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score.toDouble()),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text('${v.round()}', style: AppText.display(40, color: color)),
      ),
    ],
  );
}

class _MomentCard extends StatelessWidget {
  final TurnRecord record;
  final String attackerName;
  final String defenderName;
  const _MomentCard({required this.record, required this.attackerName, required this.defenderName});

  @override
  Widget build(BuildContext context) {
    final card = CardDeck.byId(record.cardId);
    return SoftCard(
      color: AppColors.coralSoft,
      borderColor: AppColors.coral.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Chip2('오늘의 두근 모먼트', color: AppColors.coral, icon: Icons.auto_awesome_rounded),
          const SizedBox(height: 10),
          Text(
            '$attackerName의 "${card?.title ?? '공격'}"에\n$defenderName의 심장이 +${record.peakRise}%까지!',
            style: AppText.display(20),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 56, child: _Sparkline(samples: record.samples, color: AppColors.coral)),
        ],
      ),
    );
  }
}

class _TurnRow extends StatelessWidget {
  final TurnRecord record;
  final bool mine;
  final String opponentName;
  const _TurnRow({required this.record, required this.mine, required this.opponentName});

  @override
  Widget build(BuildContext context) {
    final card = CardDeck.byId(record.cardId);
    final color = mine ? AppColors.coral : AppColors.lilac;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text('${record.turn + 1}', style: AppText.display(17, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card?.title ?? '카드 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(16)),
                Text('${mine ? '나' : opponentName}의 공격 · 최고 +${record.peakRise}%',
                    style: AppText.body(12, color: AppColors.inkSoft)),
              ],
            ),
          ),
          SizedBox(width: 64, height: 28, child: _Sparkline(samples: record.samples, color: color)),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text('+${record.points}', textAlign: TextAlign.right, style: AppText.display(18, color: color)),
          ),
        ],
      ),
    );
  }
}

/// 1초 단위 상승률 기록을 작은 곡선으로
class _Sparkline extends StatelessWidget {
  final List<int> samples;
  final Color color;
  const _Sparkline({required this.samples, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SparkPainter(samples, color));
}

class _SparkPainter extends CustomPainter {
  final List<int> samples;
  final Color color;
  _SparkPainter(this.samples, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1),
          Paint()..color = AppColors.line..strokeWidth = 2);
      return;
    }
    final maxV = math.max(10, samples.reduce(math.max)).toDouble();
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = size.height - (samples[i].clamp(0, maxV) / maxV) * (size.height - 3) - 1.5;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.samples != samples || old.color != color;
}
