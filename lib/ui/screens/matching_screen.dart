// 매칭 대기 화면 (Matching Screen)
// 역할: 상대방을 찾는 동안 보여주는 화면. 레이더 물결 애니메이션과 대기 중 텍스트를 표시.
// 아키텍처 플랜: ui/screens/matching_screen.dart
// 주의: 마일스톤 4(Firebase 연동) 전까지는 임시로 3초 대기 후 자동으로 게임 화면으로 넘어감

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/heart_rate_provider.dart';
import 'game_screen.dart';

class MatchingScreen extends ConsumerStatefulWidget {
  const MatchingScreen({super.key});

  @override
  ConsumerState<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends ConsumerState<MatchingScreen>
    with TickerProviderStateMixin {
  // ── 레이더 물결 이펙트를 만드는 애니메이션 컨트롤러 ──
  // 3개의 물결이 시간 차를 두고 순서대로 바깥으로 퍼져나감
  late List<AnimationController> _rippleControllers;
  late List<Animation<double>> _rippleAnimations;

  // ── 매칭 중 텍스트 점(...)이 번갈아 나타나는 애니메이션 ──
  late AnimationController _dotController;
  int _dotCount = 1;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[화면추적] MatchingScreen 생성 id=${identityHashCode(this)}');

    // 트랜지션 쉴드 해제: 이제 이 화면에서 정상적으로 Riverpod 업데이트를 받음
    Future.microtask(() {
      if (!mounted || _isLeaving) return;

      debugPrint('[화면추적] MatchingScreen 신호 반영 재개 id=${identityHashCode(this)}');
      ref.read(heartRateProvider.notifier).setTransitioning(false);
    });

    // 3개의 물결 애니메이션 컨트롤러 초기화
    // 각 물결은 0.6초씩 시간 차를 두고 시작하여 순서대로 퍼져나가는 효과를 줌
    _rippleControllers = List.generate(3, (index) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 2000),
        vsync: this,
      );

      // 인덱스에 따라 시작 시점을 0.6초씩 지연
      Future.delayed(Duration(milliseconds: index * 600), () {
        if (mounted) {
          controller.repeat(); // 무한 반복
        }
      });

      return controller;
    });

    // 각 컨트롤러에 대응하는 0.0 → 1.0 크기 애니메이션 생성
    _rippleAnimations = _rippleControllers.map((controller) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
    }).toList();

    // 점(.) 개수를 1→2→3→1 순으로 반복하는 애니메이션
    _dotController =
        AnimationController(
          duration: const Duration(milliseconds: 500),
          vsync: this,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() => _dotCount = (_dotCount % 3) + 1);
            _dotController.reset();
            _dotController.forward();
          }
        });
    _dotController.forward();

    // ── 임시 매칭 로직 ──
    // 마일스톤 4(Firebase 연동) 전까지: 3초 대기 후 자동으로 게임 화면으로 전환
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isLeaving) {
        debugPrint(
          '[화면추적] MatchingScreen 게임 화면 이동 id=${identityHashCode(this)}',
        );
        // 트랜지션 쉴드 발동: 매칭 성공 후 게임 화면으로 넘어갈 때 비활성 에러 방어
        ref.read(heartRateProvider.notifier).setTransitioning(true);

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, _, secondaryAnimation) => const GameScreen(),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    debugPrint('[화면추적] MatchingScreen 종료 id=${identityHashCode(this)}');
    for (final controller in _rippleControllers) {
      controller.dispose();
    }
    _dotController.dispose();
    super.dispose();
  }

  // ── 매칭 취소 ──
  Future<void> _cancelMatching() async {
    if (_isLeaving) return;
    _isLeaving = true;
    debugPrint('[화면추적] MatchingScreen 취소 시작 id=${identityHashCode(this)}');

    await ref.read(heartRateProvider.notifier).endMeasurementSession();

    if (mounted) {
      debugPrint('[화면추적] MatchingScreen 취소 완료 id=${identityHashCode(this)}');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 레이더 물결의 최대 반지름: 화면 짧은 쪽의 65%
    final maxRadius = size.shortestSide * 0.65;

    return PopScope(
      canPop: false, // 시스템 뒤로가기 가로채기
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _cancelMatching();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── 레이더 물결 이펙트 (3개 동심원이 바깥으로 퍼짐) ──
              ...List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _rippleAnimations[index],
                  builder: (context, child) {
                    final progress = _rippleAnimations[index].value;
                    // 진행도(0→1)에 따라 반지름이 커지고 투명도가 줄어듦
                    final radius = maxRadius * progress;
                    final opacity = (1.0 - progress).clamp(0.0, 1.0);

                    return Center(
                      child: Container(
                        width: radius * 2,
                        height: radius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFFFF2D55,
                            ).withValues(alpha: opacity * 0.6),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),

              // ── 중앙 심장 아이콘 (레이더의 발신원) ──
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A1A1A),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Color(0xFFFF2D55),
                      size: 38,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // ── 매칭 중 텍스트 ──
                  Text(
                    '상대를 찾는 중${'.' * _dotCount}',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    '익명의 상대방과 연결합니다',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),

              // ── 우상단 취소 버튼 ──
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: _cancelMatching,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      '취소',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5),
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
}
