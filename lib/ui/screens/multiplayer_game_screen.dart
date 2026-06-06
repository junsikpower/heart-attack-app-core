// 멀티플레이 게임 화면 (Multiplayer Game Screen)
// 역할: 실제 사람과 음성 통화를 하면서 서로의 심박수를 실시간으로 보는 화면.
// Firebase RTDB로 심박수 동기화, Agora로 음성 통화, Firestore로 데이터 하베스팅.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/heart_rate_provider.dart';
import '../../providers/multiplayer_provider.dart';
import '../widgets/waveform_painter.dart';

class MultiplayerGameScreen extends ConsumerStatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  ConsumerState<MultiplayerGameScreen> createState() =>
      _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends ConsumerState<MultiplayerGameScreen>
    with TickerProviderStateMixin {
  late final Stopwatch _stopwatch;
  late AnimationController _timerController;
  String _elapsedTime = '0:00';

  // 내 심박수를 Firebase에 1초마다 동기화하는 타이머
  Timer? _bpmSyncTimer;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[화면추적] MultiplayerGameScreen 생성 id=${identityHashCode(this)}');

    // ── 경과 시간 카운터 ──
    _stopwatch = Stopwatch()..start();
    _timerController =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..addListener(() {
            final elapsed = _stopwatch.elapsed;
            setState(() {
              _elapsedTime =
                  '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
            });
          })
          ..repeat();

    // ── 심박수 측정 시작 ──
    Future.microtask(() {
      if (!mounted || _isLeaving) return;

      ref.read(heartRateProvider.notifier).setTransitioning(false);
      ref.read(heartRateProvider.notifier).startMeasurement();

      // 1초마다 내 BPM을 Firebase에 Push
      _bpmSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _isLeaving) return;

        final myBpm = ref.read(heartRateProvider).bpm.round();
        if (myBpm > 0) {
          ref.read(multiplayerProvider.notifier).syncMyBpm(myBpm);
        }
      });
    });
  }

  @override
  void dispose() {
    debugPrint('[화면추적] MultiplayerGameScreen 종료 id=${identityHashCode(this)}');
    // 예기치 않은 화면 제거에서도 새 신호가 UI에 전달되지 않도록 차단한다.
    ref.read(heartRateProvider.notifier).setTransitioning(true);
    _timerController.dispose();
    _stopwatch.stop();
    _bpmSyncTimer?.cancel();
    super.dispose();
  }

  // ── 연결 종료 ──
  Future<void> _leaveGame() async {
    if (_isLeaving) return;
    _isLeaving = true;
    debugPrint(
      '[화면추적] MultiplayerGameScreen 연결 종료 시작 id=${identityHashCode(this)}',
    );

    // 화면이 없어지기 전에 반복 작업과 측정을 먼저 종료한다.
    _bpmSyncTimer?.cancel();
    _bpmSyncTimer = null;

    await ref.read(multiplayerProvider.notifier).disconnect();
    await ref.read(heartRateProvider.notifier).endMeasurementSession();

    if (mounted) {
      debugPrint(
        '[화면추적] MultiplayerGameScreen 연결 종료 완료 id=${identityHashCode(this)}',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heartState = ref.watch(heartRateProvider);
    final multiState = ref.watch(multiplayerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveGame();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Column(
            children: [
              // ══════════════════════════════════════
              // 상단 헤더: 두 아바타 + 경과 시간
              // ══════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ── 상대방 아바타 ──
                    _buildAvatar(
                      label: '상대방',
                      isMe: false,
                      bpm: multiState.opponentBpm > 0
                          ? multiState.opponentBpm
                          : null,
                    ),

                    // ── 중앙: 경과 시간 ──
                    Column(
                      children: [
                        Text(
                          _elapsedTime,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF30D158),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              multiState.roomId != null
                                  ? '방 ${multiState.roomId}'
                                  : '연결 중...',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF30D158),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // ── 내 아바타 ──
                    _buildAvatar(
                      label: '나',
                      isMe: true,
                      bpm: heartState.bpm > 0 ? heartState.bpm.round() : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),

              // ══════════════════════════════════════
              // 중앙 영역: 심박수 + 통화 컨트롤
              // ══════════════════════════════════════
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── 내 심박수 메인 숫자 ──
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Text(
                          heartState.bpm > 0
                              ? '${heartState.bpm.round()}'
                              : '--',
                          key: ValueKey(heartState.bpm.round()),
                          style: GoogleFonts.outfit(
                            fontSize: 96,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                      ),

                      Text(
                        'BPM',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 3.0,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // ── 통화 컨트롤 버튼 ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 마이크 음소거 버튼
                          _buildControlButton(
                            icon: multiState.isMuted
                                ? Icons.mic_off
                                : Icons.mic,
                            label: multiState.isMuted ? '음소거 해제' : '음소거',
                            color: multiState.isMuted
                                ? const Color(0xFFFF9F0A)
                                : const Color(0xFF2C2C2E),
                            onTap: () => ref
                                .read(multiplayerProvider.notifier)
                                .toggleMute(),
                          ),

                          const SizedBox(width: 24),

                          // 상대방 심박수 표시 버튼 (읽기 전용)
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1C1C1E),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF2D55,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  multiState.opponentBpm > 0
                                      ? '${multiState.opponentBpm}'
                                      : '--',
                                  style: GoogleFonts.outfit(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFF2D55),
                                  ),
                                ),
                                Text(
                                  '상대 BPM',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // ── 에러 메시지 ──
                      if (multiState.errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          multiState.errorMessage,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: const Color(0xFFFF2D55),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ══════════════════════════════════════
              // 하단: 심전도 파형
              // ══════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        '내 심박 파형',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.25),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    WaveformWidget(
                      waveformData: heartState.waveform,
                      height: 90,
                    ),
                  ],
                ),
              ),

              // ── 종료 버튼 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: GestureDetector(
                  onTap: _leaveGame,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '연결 종료',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF2D55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ), // Scaffold 끝
    ); // PopScope 끝
  }

  // ── 아바타 위젯 ──
  Widget _buildAvatar({
    required String label,
    required bool isMe,
    required int? bpm,
  }) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1C1C1E),
            border: Border.all(
              color: isMe
                  ? const Color(0xFFFF2D55).withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Icon(
            isMe ? Icons.person : Icons.person_outline,
            color: isMe
                ? const Color(0xFFFF2D55)
                : Colors.white.withValues(alpha: 0.3),
            size: 26,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        if (bpm != null) ...[
          const SizedBox(height: 2),
          Text(
            '$bpm',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFF2D55),
            ),
          ),
        ],
      ],
    );
  }

  // ── 통화 컨트롤 버튼 ──
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
