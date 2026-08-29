// 앱 진입점 (Entry Point)
// 마일스톤 3: 테스트용 화면에서 실제 로비 화면으로 교체
// Riverpod의 ProviderScope로 앱 전체를 감싸고, 다크 테마를 적용한다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'ui/screens/lobby_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수(.env) 로드
  await dotenv.load(fileName: ".env");

  // Firebase 초기화
  await Firebase.initializeApp();

  // ── [Edge-to-Edge 모드] 안드로이드 시스템 스크림(Scrim) 제거 ──
  // 안드로이드 OS가 상태바 뒤에 까만 반투명 배경을 덧칠하는 행위를 원천 차단합니다.
  // 상태바 아이콘(배터리, 시계)은 그대로 보이되, 우리 앱의 UI(하얀색 PPG 바)가
  // 아이콘 뒤에서 완전히 비쳐 보이게 되어 펀치홀 카메라 옆까지 빛이 채워집니다.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 상태바와 내비게이션 바를 투명하게 만들어 화면을 더 넓게 사용
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // 다크 배경 위 흰색 아이콘
      systemNavigationBarColor: Colors.transparent, // 하단 내비게이션 바도 투명화
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // ProviderScope: Riverpod이 작동하기 위한 필수 래퍼(Wrapper)
  // 이것 없이는 앱 어디서도 ref.watch(heartRateProvider)를 사용할 수 없음
  runApp(
    const ProviderScope(
      child: HeartAttackApp(),
    ),
  );
}

class HeartAttackApp extends StatelessWidget {
  const HeartAttackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Attack',
      debugShowCheckedModeBanner: false, // 개발 중 'DEBUG' 배너 제거

      // ── 전체 앱 다크 테마 설정 ──
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A), // 기본 배경색
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2D55),    // 포인트 컬러: 네온 레드
          surface: Color(0xFF1C1C1E),   // 카드/컨테이너 배경
          onSurface: Colors.white,       // 텍스트 기본 색상
        ),
        // 앱 전체 기본 폰트를 Outfit으로 설정
        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData.dark().textTheme,
        ),
        // 앱바(상단바) 기본 스타일
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        useMaterial3: true,
      ),

      // ── 시작 화면: 로비 화면 ──
      home: const LobbyScreen(),
    );
  }
}
