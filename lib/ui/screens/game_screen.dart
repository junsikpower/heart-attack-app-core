// 게임 화면 (Game Screen) - 음성 통화 + 심박수 측정 메인 화면
// 역할: 매칭 완료 후 진입하는 핵심 화면. 심박수 측정, 파형 그래프, 상대방 아바타를 보여줌.
// 아키텍처 플랜: ui/screens/game_screen.dart
// 주의: 마일스톤 4(Firebase + Agora) 연동 전까지는 내 심박수 측정만 작동, 상대방 데이터는 임시값

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/heart_rate_provider.dart';
import '../../services/camera_service.dart';
import '../../services/ai_voice_service.dart'; // AI 서비스 임포트
import '../widgets/waveform_painter.dart';
import '../widgets/ppg_light_bar.dart'; // [피벗] 전면 카메라 PPG 전용 초록색 광원 바

class GameScreen extends ConsumerStatefulWidget {
  // ConsumerStatefulWidget: Riverpod의 ref를 사용할 수 있는 StatefulWidget의 Riverpod 버전
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin {
  // ── 경과 시간 표시 타이머 ──
  late final Stopwatch _stopwatch;
  late AnimationController _timerController;
  String _elapsedTime = '0:00';
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[화면추적] GameScreen 생성 id=${identityHashCode(this)}');

    // ── 경과 시간 카운터 초기화 ──
    _stopwatch = Stopwatch()..start();
    _timerController =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..addListener(() {
            // 1초마다 경과 시간 텍스트 업데이트
            final elapsed = _stopwatch.elapsed;
            final minutes = elapsed.inMinutes;
            final seconds = elapsed.inSeconds % 60;
            setState(() {
              _elapsedTime = '$minutes:${seconds.toString().padLeft(2, '0')}';
            });
          })
          ..repeat();

    // ── 게임 화면 진입 시 심박수 측정 시작 ──
    // [자원 재사용] 모달에서 이미 측정 중이라면 CameraService 내부에서
    // 자동으로 스킵됩니다. 플래시 꺼짐 없이 즉시 이어서 측정합니다.
    Future.microtask(() {
      if (!mounted || _isLeaving) return;

      ref.read(heartRateProvider.notifier).setTransitioning(false);
      ref.read(heartRateProvider.notifier).startMeasurement();
    });
  }

  @override
  void dispose() {
    debugPrint('[화면추적] GameScreen 종료 id=${identityHashCode(this)}');
    // 화면 종료 시 타이머 리소스 해제
    _timerController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  // ── AI 게임 종료 ──
  Future<void> _leaveGame() async {
    if (_isLeaving) return;
    _isLeaving = true;
    debugPrint('[화면추적] GameScreen 연결 종료 시작 id=${identityHashCode(this)}');

    _timerController.stop();
    _stopwatch.stop();
    await ref.read(heartRateProvider.notifier).endMeasurementSession();

    if (mounted) {
      debugPrint('[화면추적] GameScreen 연결 종료 완료 id=${identityHashCode(this)}');
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ── 현재 CameraStatus를 한국어 안내 텍스트로 변환 ──
  String _statusToGuide(CameraStatus status) {
    switch (status) {
      case CameraStatus.idle:
        return '카메라 준비 중...';
      case CameraStatus.initializing:
        return '카메라 초기화 중...';
      case CameraStatus.measuring:
        return '심박수 측정 중';
      case CameraStatus.noFinger:
        return '손가락을 카메라 렌즈에 올려주세요';
      case CameraStatus.error:
        return '카메라 오류 - 권한을 확인하세요';
    }
  }

  // ── 상태에 따라 다른 색상을 반환 ──
  Color _statusColor(CameraStatus status) {
    switch (status) {
      case CameraStatus.measuring:
        return const Color(0xFF30D158); // 초록: 측정 중 (정상)
      case CameraStatus.noFinger:
        return const Color(0xFFFF9F0A); // 주황: 손가락 없음 (경고)
      case CameraStatus.error:
        return const Color(0xFFFF2D55); // 빨강: 오류
      default:
        return Colors.white.withValues(alpha: 0.4); // 회색: 대기/초기화
    }
  }

  @override
  Widget build(BuildContext context) {
    // heartRateProvider를 구독(watch): 상태가 바뀔 때마다 이 위젯이 자동으로 다시 그려짐
    final heartState = ref.watch(heartRateProvider);

    return PopScope(
      canPop: false, // 커스텀 뒤로가기 로직 적용
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveGame();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          children: [
            // ── [피벗] 전면 카메라 PPG 광원 바 (OLED 초록색 발광 영역) ──
            // 상태바 영역까지 초록색으로 가득 채워 전면 렌즈 주변을 환하게 밝힘
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: PpgLightBar(),
            ),
            // ── 기존 게임 UI (초록색 바 아래에 배치) ──
            SafeArea(
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
                    // 마일스톤 4-A: AI 페르소나 아바타
                    _buildAvatar(
                      label: 'AI 파트너',
                      isMe: false,
                      bpm: ref
                          .watch(aiVoiceServiceProvider)
                          .aiBpm, // AI의 가상 심박수
                    ),

                    // ── 중앙: 경과 시간 + VS 텍스트 ──
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
                        Text(
                          '연결됨',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF30D158), // 초록색: 연결 중
                            fontWeight: FontWeight.w500,
                          ),
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

              // ── 구분선 ──
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),

              // ══════════════════════════════════════
              // 중앙 영역: 음성 통화 + 심박수 표시
              // ══════════════════════════════════════
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── 내 심박수 메인 숫자 표시 ──
                      AnimatedSwitcher(
                        // 숫자가 바뀔 때 부드럽게 교체되는 애니메이션
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: Text(
                          heartState.bpm > 0
                              ? '${heartState.bpm.round()}'
                              : '--',
                          key: ValueKey(
                            heartState.bpm.round(),
                          ), // 값이 바뀔 때 애니메이션 트리거
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

                      const SizedBox(height: 20),

                      // ── 측정 상태 안내 텍스트 (색상이 상태에 따라 바뀜) ──
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: _statusColor(heartState.cameraStatus),
                          fontWeight: FontWeight.w500,
                        ),
                        child: Text(_statusToGuide(heartState.cameraStatus)),
                      ),

                      const SizedBox(height: 48),

                      // ── [마일스톤 4-A] AI 음성 통화 (임시 UI) ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Column(
                          children: [
                            // 1. AI 상태 텍스트
                            Text(
                              ref
                                      .watch(aiVoiceServiceProvider)
                                      .errorMessage
                                      .isNotEmpty
                                  ? ref
                                        .watch(aiVoiceServiceProvider)
                                        .errorMessage
                                  : ref.watch(aiVoiceServiceProvider).isThinking
                                  ? '상대방이 타이밍을 엿보는 중...'
                                  : ref
                                        .watch(aiVoiceServiceProvider)
                                        .lastAiReply,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color:
                                    ref.watch(aiVoiceServiceProvider).isThinking
                                    ? const Color(0xFF0A84FF)
                                    : Colors.white.withValues(alpha: 0.85),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // 2. 마이크 버튼 (PTT)
                            GestureDetector(
                              onTapDown: (_) => ref
                                  .read(aiVoiceServiceProvider.notifier)
                                  .startListening(),
                              onTapUp: (_) => ref
                                  .read(aiVoiceServiceProvider.notifier)
                                  .stopListening(),
                              onTapCancel: () => ref
                                  .read(aiVoiceServiceProvider.notifier)
                                  .stopListening(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      ref
                                          .watch(aiVoiceServiceProvider)
                                          .isListening
                                      ? const Color(0xFFFF2D55)
                                      : const Color(0xFF2C2C2E),
                                  boxShadow:
                                      ref
                                          .watch(aiVoiceServiceProvider)
                                          .isListening
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFF2D55,
                                            ).withValues(alpha: 0.6),
                                            blurRadius: 16,
                                            spreadRadius: 4,
                                          ),
                                        ]
                                      : [],
                                ),
                                child: const Icon(
                                  Icons.mic,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              ref.watch(aiVoiceServiceProvider).isListening
                                  ? '듣고 있어요...'
                                  : '버튼을 누른 채로 말하세요',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ══════════════════════════════════════
              // 하단: 실시간 심전도 파형 그래프
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
                    // WaveformWidget: 실시간으로 들어오는 파형 데이터를 그래프로 렌더링
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
          ],
        ),
      ), // Scaffold 끝
    ); // PopScope 끝
  }

  // ── 아바타 위젯 빌더 ──
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
              // 나: 네온 레드 테두리, 상대방: 반투명 흰색
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
        // BPM 수치가 있을 때만 표시
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
}
