// 로비 화면 (Lobby Screen)
// 역할: 앱을 켰을 때 가장 먼저 보이는 화면. 심장 애니메이션과 매칭 시작 버튼을 보여준다.
// 아키텍처 플랜: ui/screens/lobby_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/pre_check_modal.dart';
import 'room_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin {
  // ── 버튼 눌렸을 때 살짝 커졌다 작아지는 애니메이션 컨트롤러 ──
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── 화면 진입 시 위에서 아래로 흘러내리는 페이드인 애니메이션 ──
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // 심장 박동처럼 1.5초 주기로 반복되는 펄스 애니메이션 설정
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true); // reverse: true → 커졌다가 다시 작아짐

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 화면 최초 진입 시 부드럽게 나타나는 페이드 + 슬라이드 애니메이션
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward(); // 한 번만 실행

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08), // 살짝 아래에서 시작
      end: Offset.zero,             // 원래 위치로 슬라이딩
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    // 화면 종료 시 애니메이션 리소스 해제 (메모리 누수 방지)
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── 매칭 시작 버튼을 눌렀을 때: 사전 확인 모달을 먼저 띄움 ──
  void _onMatchingStart() {
    showDialog(
      context: context,
      barrierDismissible: false, // 바깥 영역 터치로 닫기 금지 (준비 완료/취소 버튼으로만 가능)
      builder: (context) => const PreCheckModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 배경색: 거의 완전한 검정 (#0A0A0A) - 다크 테마의 핵심
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ── 앱 타이틀 ──
                  Text(
                    'HEART ATTACK',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFF2D55), // 네온 레드 포인트 컬러
                      letterSpacing: 6.0,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── 심장 아이콘 (Lottie 파일이 없으므로 AnimatedIcon으로 대체) ──
                  // TODO: 마일스톤 3 완성 후 assets/lottie/heartbeat.json 파일 추가 시 교체
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 심장 색상의 빛이 번지는 외곽 글로우 효과
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2D55).withValues(alpha: 0.35),
                            blurRadius: 60,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Color(0xFFFF2D55),
                        size: 100,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── 메인 헤드라인 ──
                  Text(
                    'HEART\nATTACK',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── 서브 설명 텍스트 ──
                  Text(
                    '익명의 상대와 연결되어\n심장이 얼마나 빨리 뛰는지 확인하세요',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.45),
                      height: 1.6,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── AI 모드 버튼 ──
                  GestureDetector(
                    onTap: _onMatchingStart,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF2D55),
                            Color(0xFFFF6B8A),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2D55).withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.smart_toy_outlined,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'AI와 대화하기',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── 멀티플레이 버튼 ──
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RoomScreen()),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline,
                              color: Color(0xFFFF2D55), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            '사람과 매칭하기',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFF2D55),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── 하단 안내 텍스트 ──
                  Text(
                    '매칭은 익명으로 진행됩니다',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
