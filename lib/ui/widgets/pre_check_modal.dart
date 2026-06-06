// 사전 측정 및 캘리브레이션 모달 (Pre-Check Modal)
// 역할: 매칭 전에 사용자가 카메라 렌즈에 손가락을 올바르게 댔는지 직접 시각적으로 확인하고 영점 조절을 돕는 팝업창
// 아키텍처 플랜: ui/widgets/pre_check_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import '../../providers/heart_rate_provider.dart';
import '../screens/matching_screen.dart';

class PreCheckModal extends ConsumerStatefulWidget {
  const PreCheckModal({super.key});

  @override
  ConsumerState<PreCheckModal> createState() => _PreCheckModalState();
}

class _PreCheckModalState extends ConsumerState<PreCheckModal> {
  bool _isClosing = false;
  bool _keepMeasurementOnClose = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[화면추적] PreCheckModal 생성 id=${identityHashCode(this)}');
    // 모달이 열리면 카메라를 켜고 측정을 시작한다.
    // Future.microtask를 사용하여 위젯 트리가 빌드된 직후에 상태 변경을 요청함.
    Future.microtask(() {
      if (!mounted) return;

      // 이전 화면의 종료 차단 상태를 해제하고 새 사전 측정 결과를 받는다.
      ref.read(heartRateProvider.notifier).setTransitioning(false);
      ref.read(heartRateProvider.notifier).startMeasurement();
    });
  }

  @override
  void dispose() {
    debugPrint(
      '[화면추적] PreCheckModal 종료 id=${identityHashCode(this)} '
      '측정유지=$_keepMeasurementOnClose 닫는중=$_isClosing',
    );
    // 취소 처리 없이 모달이 제거되는 예외 경로만 여기에서 정리한다.
    if (!_keepMeasurementOnClose && !_isClosing) {
      ref.read(heartRateProvider.notifier).endMeasurementSession();
    }
    super.dispose();
  }

  // ── 준비 완료 (매칭 화면으로 이동) ──
  void _onConfirm() {
    if (_isClosing) return;
    _isClosing = true;
    _keepMeasurementOnClose = true;
    debugPrint('[화면추적] PreCheckModal 매칭 시작 선택 id=${identityHashCode(this)}');

    // 매칭 화면으로 전달하는 동안 측정 신호의 UI 반영만 잠시 차단한다.
    ref.read(heartRateProvider.notifier).setTransitioning(true);

    // 모달 닫기
    Navigator.of(context).pop();

    // [핵심] 카메라를 끄지 않습니다!
    // 웜업이 완료된 flutter_ppg와 켜진 플래시를
    // 매칭 화면 → 게임 화면까지 그대로 유지합니다.

    // 매칭 화면으로 이동
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, _, secondaryAnimation) => const MatchingScreen(),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ── 취소 (모달만 닫음) ──
  Future<void> _onCancel() async {
    if (_isClosing) return;
    _isClosing = true;
    debugPrint('[화면추적] PreCheckModal 취소 시작 id=${identityHashCode(this)}');

    // 모달이 살아 있는 동안 종료를 완료하여 폐기된 화면에 상태가 전달되지 않게 한다.
    await ref.read(heartRateProvider.notifier).endMeasurementSession();

    if (mounted) {
      debugPrint('[화면추적] PreCheckModal 취소 종료 완료 id=${identityHashCode(this)}');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 상태 구독
    final heartRateState = ref.watch(heartRateProvider);
    final notifier = ref.read(heartRateProvider.notifier);

    final bpm = heartRateState.bpm;
    final isCameraReady =
        notifier.isCameraInitialized && notifier.cameraController != null;

    // 기준 통과 여부 (비율 공식을 카메라 서비스에서 계산해서 보내줌)
    final bool isStable = heartRateState.isRatioPassed;
    final Color valueColor = isStable
        ? Colors.greenAccent
        : const Color(0xFFFF2D55);

    // BPM이 1번이라도 측정되어야 확인 버튼 활성화
    final bool canStart = bpm > 0;

    return PopScope(
      canPop: false, // 커스텀 로직 수행 후 pop 할 것이므로 일단 막음
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onCancel();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // 내용물 크기만큼만 세로 길이 차지
            children: [
              Text(
                '카메라 사전 확인',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '플래시가 켜진 후면 카메라 렌즈를\n손가락 끝으로 완전히 덮어주세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // ── 동그란 카메라 미리보기 (프로토타입 재현) ──
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(
                    color: isStable
                        ? Colors.greenAccent
                        : Colors.white.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                // 카메라 화면을 동그랗게 오려냄
                child: ClipOval(
                  child: isCameraReady
                      ? CameraPreview(notifier.cameraController!)
                      : const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF2D55),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // ── 실시간 원시 RGB 수치 및 통과 상태 (디버깅용) ──
              Text(
                '통과 상태: ${heartRateState.isRatioPassed ? "True" : "False"}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '신호 강도: ${heartRateState.currentRedValue.toStringAsFixed(1)}',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),

              const SizedBox(height: 16),

              // ── BPM 표시 ──
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      color: canStart
                          ? const Color(0xFFFF2D55)
                          : Colors.white.withValues(alpha: 0.2),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      canStart ? '${bpm.toInt()} BPM' : '측정 대기 중...',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: canStart
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 디버그 로그 기록 기능 ──
              if (heartRateState.isLogging)
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(heartRateProvider.notifier).stopAndShareLog();
                  },
                  icon: const Icon(Icons.share, color: Colors.white, size: 18),
                  label: Text(
                    '기록 종료 및 공유',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(heartRateProvider.notifier).startLogging();
                  },
                  icon: const Icon(
                    Icons.bug_report,
                    color: Colors.white70,
                    size: 18,
                  ),
                  label: Text(
                    '디버그 로그 기록 시작',
                    style: GoogleFonts.outfit(color: Colors.white70),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // ── 버튼 영역 ──
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _onCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '취소',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canStart ? _onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2D55),
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: 0.1,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: canStart ? 8 : 0,
                        shadowColor: const Color(
                          0xFFFF2D55,
                        ).withValues(alpha: 0.5),
                      ),
                      child: Text(
                        '매칭 시작',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: canStart
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ), // Dialog 끝
    ); // PopScope 끝
  }
}
