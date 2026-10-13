// 앱 진입점 (Entry Point)
// - .env(AGORA_APP_ID), Firebase, 저장소(SharedPreferences)를 준비한 뒤 로비를 띄운다.
// - Galaxy(Android 15/16, One UI 7/8) 기준: 앱이 시스템 바 뒤까지 그려지는 edge-to-edge가 기본이므로
//   시스템 바를 투명하게 두고, 각 화면은 SafeArea(AppBackdrop)로 내용을 안쪽에 배치한다.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'providers/profile_provider.dart';
import 'ui/screens/lobby_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();

  // 세로 화면 고정 (한 손으로 쥐고 뒷면 카메라에 검지를 대는 자세 기준)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // 밝은 배경 위 어두운 아이콘
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const HeartAttackApp(),
    ),
  );
}

class HeartAttackApp extends StatelessWidget {
  const HeartAttackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Attack',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LobbyScreen(),
    );
  }
}
