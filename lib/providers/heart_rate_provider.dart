// 심박수 전역 상태 관리 파일
// 역할: CameraService가 수신한 심박수(BPM) 값을 Riverpod을 통해 앱 전체 화면에서 공유
// [리팩토링] flutter_ppg 패키지 도입에 따라 불필요해진 로그 기능 제거

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/camera_service.dart';

// ─────────────────────────────────────────────────────────
// HeartRateState: 심박수 관련 모든 상태를 하나의 묶음으로 정의
// ─────────────────────────────────────────────────────────
class HeartRateState {
  final double bpm; // 현재 심박수 (0이면 미측정 상태)
  final CameraStatus cameraStatus; // 카메라 상태 (측정 중, 손 없음, 오류 등)
  final List<double> waveform; // 화면 하단에 그릴 심전도 파형 데이터 목록
  final bool isMeasuring; // 현재 측정 중인지 여부
  final double currentRedValue; // 실시간 신호 강도 (filteredIntensity 대체)
  final bool isRatioPassed; // 신호 품질 통과 여부 (Good/Fair = true)
  final bool isLogging; // CSV 로그 기록 중 여부

  const HeartRateState({
    this.bpm = 0.0,
    this.cameraStatus = CameraStatus.idle,
    this.waveform = const [],
    this.isMeasuring = false,
    this.currentRedValue = 0.0,
    this.isRatioPassed = false,
    this.isLogging = false,
  });

  HeartRateState copyWith({
    double? bpm,
    CameraStatus? cameraStatus,
    List<double>? waveform,
    bool? isMeasuring,
    double? currentRedValue,
    bool? isRatioPassed,
    bool? isLogging,
  }) {
    return HeartRateState(
      bpm: bpm ?? this.bpm,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      waveform: waveform ?? this.waveform,
      isMeasuring: isMeasuring ?? this.isMeasuring,
      currentRedValue: currentRedValue ?? this.currentRedValue,
      isRatioPassed: isRatioPassed ?? this.isRatioPassed,
      isLogging: isLogging ?? this.isLogging,
    );
  }
}

// ─────────────────────────────────────────────────────────
// HeartRateNotifier: HeartRateState 값을 변경하는 로직이 담긴 클래스
// ─────────────────────────────────────────────────────────
class HeartRateNotifier extends StateNotifier<HeartRateState>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();

  HeartRateNotifier() : super(const HeartRateState()) {
    _cameraService.onBpmUpdated = _onBpmUpdated;
    _cameraService.onStatusChanged = _onStatusChanged;
    _cameraService.onWaveformUpdated = _onWaveformUpdated;
    _cameraService.onRgbUpdated = _onRgbUpdated;

    // [우주 방어 1] 앱 생명주기 레이더 장착 (홈 버튼, 전원 버튼 감지)
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱이 백그라운드로 숨거나(홈 버튼) 화면이 꺼질 때 즉각 카메라 셧다운
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (this.state.isMeasuring) {
        stopMeasurement();
      }
    }
  }

  // ── 트랜지션 쉴드 제어 ──
  void setTransitioning(bool val) {
    _cameraService.setTransitioning(val);
  }

  // ── BPM 업데이트: 패키지가 이미 안정화된 값을 주므로 그대로 전달 ──
  void _onBpmUpdated(double bpm) {
    state = state.copyWith(bpm: bpm);
  }

  // ── 카메라 상태 변경: 딜레이(Throttle) 없이 즉각 반영 ──
  void _onStatusChanged(CameraStatus status) {
    state = state.copyWith(cameraStatus: status);
  }

  void _onWaveformUpdated(List<double> waveform) {
    state = state.copyWith(waveform: waveform);
  }

  // ── 신호 강도 및 품질 업데이트 ──
  void _onRgbUpdated(double r, double g, double b, bool passed) {
    state = state.copyWith(currentRedValue: r, isRatioPassed: passed);
  }

  // ── 측정 시작 ──
  Future<void> startMeasurement() async {
    state = state.copyWith(isMeasuring: true, bpm: 0.0, waveform: []);
    await _cameraService.initialize();
    await _cameraService.startMeasurement();
  }

  // ── 측정 중지 ──
  Future<void> stopMeasurement() async {
    await _cameraService.stopMeasurement();
    state = state.copyWith(
      isMeasuring: false,
      bpm: 0.0,
      waveform: [],
      cameraStatus: CameraStatus.idle,
    );
  }

  // ── 화면 이탈 시 사용하는 공통 측정 종료 절차 ──
  Future<void> endMeasurementSession() async {
    setTransitioning(true);
    await stopMeasurement();
  }

  // ── 로깅 기능 ──
  void startLogging() {
    _cameraService.startLogging();
    state = state.copyWith(isLogging: true);
  }

  Future<void> stopAndShareLog() async {
    final String csvData = _cameraService.stopAndGetCsv();
    state = state.copyWith(isLogging: false);

    if (csvData.isEmpty) return;

    try {
      final directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/ppg_debug_log.csv';
      final File file = File(filePath);
      await file.writeAsString(csvData);

      // share_plus 패키지 (파일 공유)
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: '심박수 30대 저하 원인 디버그 로그 데이터 (CSV)',
        ),
      );
    } catch (e) {
      debugPrint('로그 공유 오류: $e');
    }
  }

  // ── 카메라 컨트롤러 접근자 ──
  CameraController? get cameraController => _cameraService.controller;
  bool get isCameraInitialized => _cameraService.isInitialized;

  @override
  void dispose() {
    // [우주 방어 2] 프로바이더 소멸 시 무조건 카메라를 끄도록 생명주기 단단히 결속
    _cameraService.stopMeasurement();
    _cameraService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────
// heartRateProvider: 앱 전체에서 심박수 상태에 접근할 때 사용하는 전역 변수
// ─────────────────────────────────────────────────────────
final heartRateProvider =
    StateNotifierProvider<HeartRateNotifier, HeartRateState>(
      (ref) => HeartRateNotifier(),
    );
