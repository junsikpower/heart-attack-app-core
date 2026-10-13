// 디자인 시스템 (Design Tokens + ThemeData)
// 콘셉트: "Warm Paper" — 따뜻한 크림색 종이 위에 코랄 하트.
//   - 화상/랜덤채팅의 어두운 네온 톤 대신, 보드게임·파티게임처럼 밝고 깨끗한 톤을 사용한다.
//   - 제목/숫자는 둥글고 귀여운 Jua, 본문은 가독성 좋은 Noto Sans KR.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 색상 토큰
class AppColors {
  AppColors._();

  static const cream = Color(0xFFFFF7F2); // 기본 배경
  static const paper = Color(0xFFFFFFFF); // 카드 배경
  static const ink = Color(0xFF221A2E); // 기본 글자 (짙은 자두색)
  static const inkSoft = Color(0xFF6E6478); // 보조 글자
  static const inkFaint = Color(0xFFA79EAF); // 비활성 글자
  static const line = Color(0xFFF0E4DD); // 구분선/테두리

  static const coral = Color(0xFFFF4F6D); // 메인 포인트 (나, 하트)
  static const coralSoft = Color(0xFFFFE3E8);
  static const peach = Color(0xFFFFA97A); // 그라데이션 보조
  static const lilac = Color(0xFF7B6CF6); // 상대방 포인트
  static const lilacSoft = Color(0xFFEAE7FF);
  static const mint = Color(0xFF22B07D); // 정상/준비 완료
  static const mintSoft = Color(0xFFDDF5EC);
  static const amber = Color(0xFFF5A524); // 주의

  /// 메인 그라데이션 (버튼, 하트)
  static const heartGradient = LinearGradient(
    colors: [Color(0xFFFF7A6B), coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 캐릭터(하트 버디) 색상 팔레트 — 프로필 대신 사용하는 추상 캐릭터
  static const buddies = [
    Color(0xFFFF8A9B), // 딸기
    Color(0xFFFFB86B), // 귤
    Color(0xFFFFD866), // 레몬
    Color(0xFF7DD3A8), // 민트
    Color(0xFF6EC1F0), // 하늘
    Color(0xFF9B8CFF), // 라벤더
    Color(0xFFE48AE0), // 자두
    Color(0xFFB9A48C), // 쿠키
  ];
}

/// 텍스트 스타일
class AppText {
  AppText._();

  static TextStyle display(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.jua(fontSize: size, color: color, height: 1.15);

  static TextStyle body(
    double size, {
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w500,
    double height = 1.45,
  }) => GoogleFonts.notoSansKr(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
  );
}

/// 공통 그림자
class AppShadows {
  AppShadows._();

  static const soft = [
    BoxShadow(color: Color(0x14221A2E), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const lifted = [
    BoxShadow(color: Color(0x22221A2E), blurRadius: 32, offset: Offset(0, 14)),
  ];
  static List<BoxShadow> glow(Color c) => [
    BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
  ];
}

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.cream,
    colorScheme: const ColorScheme.light(
      primary: AppColors.coral,
      secondary: AppColors.lilac,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
    ),
    textTheme: GoogleFonts.notoSansKrTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.ink,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: AppText.body(14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}
