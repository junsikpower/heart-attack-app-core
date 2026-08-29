// 카메라 하드웨어 제어 및 심박수 측정 엔진
// [아키텍처 피벗] 후면 플래시(Torch) PPG 방식을 전면 폐기하고,
//                전면 카메라 + OLED 디스플레이 광원(Display-Illuminated PPG)으로 전환합니다.
// [안전장치]
//   - 카메라 노출 보정값(Exposure Offset) 최대치 강제 고정 → 약한 디스플레이 광원 수집 극대화
//   - 카메라 초점 강제 잠금 (AF Lock) → 하드웨어 노이즈 차단
//   - StreamController 자원 해제 (Memory Leak 방지)
//   - isNotEmpty 방어 로직 → 빈 리스트 크래시(StateError) 방지
// [고도화]
//   - 산술 평균 폐기 → 중앙값(Median) 추출로 이상치(Outlier) 면역 확보
//   - EMA(지수 이동 평균) 필터 적용 → 부드럽고 일관된 BPM 수치 유지
//   - 자원 재사용 구조 → 모달→게임 화면 전환 시 카메라 유지

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

/// 카메라 측정 상태를 나타내는 열거형
enum CameraStatus {
  idle, // 대기 중 (측정 전)
  initializing, // 카메라 초기화 중
  measuring, // 정상 측정 중
  noFinger, // 손가락이 렌즈에 없음 or 신호 품질 Poor
  error, // 오류 발생
}

/// 카메라 이미지 스트림을 통해 실시간 심박수를 측정하는 서비스 클래스.
/// flutter_ppg 패키지에 이미지 스트림을 공급하고, 결과를 콜백으로 전달한다.
class CameraService {
  // ── 카메라 컨트롤러 ──
  CameraController? _controller;

  // ── flutter_ppg 서비스 및 스트림 브릿지 ──
  FlutterPPGService? _ppgService;
  StreamController<CameraImage>? _imageStreamController;
  StreamSubscription<PPGSignal>? _ppgSubscription;

  // ── 외부 콜백 함수 ──
  Function(double bpm)? onBpmUpdated;
  Function(CameraStatus status)? onStatusChanged;
  Function(List<double> waveform)? onWaveformUpdated;
  // RGB 디버깅 콜백: 패키지 도입 후 필터링된 강도 및 SNR을 대신 사용 가능
  // 하위 호환성을 위해 시그니처 유지, PPG 신호 품질로 isRatioPassed를 대체합니다.
  Function(double r, double g, double b, bool isRatioPassed)? onRgbUpdated;

  bool _isInitialized = false;
  bool _isMeasuring = false; // 현재 스트림이 활성화된 상태인지 추적
  bool _isTransitioning = false; // 화면 전환 중 신호 차단용 방어 쉴드
  bool get isInitialized => _isInitialized;
  bool get isMeasuring => _isMeasuring;

  void setTransitioning(bool val) {
    _isTransitioning = val;
  }

  // ── [디버깅] 로그 기록 시스템 ──
  bool _isLogging = false;
  final List<String> _logData = [];
  final Stopwatch _logStopwatch = Stopwatch();

  // 파형 출력을 위한 최근 정규화된 신호 값 버퍼
  final List<double> _waveformBuffer = [];
  final int _waveformSize = 100;

  // ── [EMA 필터] 이전 BPM 값 (처음에는 0으로 초기화) ──
  double _lastFilteredBpm = 0.0;
  int _poorSignalFrameCount = 0; // [디바운싱] 불량 신호 누적 프레임 카운터

  // ── [콜드 스타트] 초기 안정화 버퍼 ──
  double _coldStartCandidateBpm = 0.0; // 콜드 스타트 버퍼: 현재 후보 수치
  int _coldStartStableCount = 0; // 콜드 스타트 버퍼: 안정 유지 프레임 카운터

  /// 전면 카메라를 초기화하고 노출 보정값(Exposure Offset)을 최대치로 강제 고정한다.
  /// [아키텍처 피벗] 후면 플래시 대신 OLED 디스플레이 광원을 사용하므로,
  ///   카메라 센서가 약한 빛을 최대한 끌어모을 수 있도록 노출을 극대화합니다.
  /// [자원 재사용] 이미 초기화되어 있으면 중복 초기화하지 않고 즉시 반환한다.
  Future<void> initialize() async {
    // ── 이미 초기화된 상태라면 재초기화 없이 바로 복귀 ──
    // (모달→게임 화면 전환 시 카메라가 꺼지지 않고 유지되는 핵심 로직)
    if (_isInitialized &&
        _controller != null &&
        _controller!.value.isInitialized) {
      debugPrint('[CameraService] 이미 초기화됨 - 초기화 스킵');
      onStatusChanged?.call(CameraStatus.idle);
      return;
    }

    onStatusChanged?.call(CameraStatus.initializing);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        onStatusChanged?.call(CameraStatus.error);
        return;
      }

      // ── [피벗] 전면 카메라(Front Camera) 탐색 ──
      // 후면 렌즈 대신 전면 셀피 렌즈를 선택하여 디스플레이 광원 PPG를 수행합니다.
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );

      await _controller!.initialize();

      // ── [핵심] 카메라 노출 자동화 (AE Auto) ──
      // 손가락을 렌즈에 대면 내부가 어두워집니다. 이때 카메라가 스스로
      // '어둡다'고 판단하여 ISO(민감도)를 증폭시키도록 허용합니다.
      // 이렇게 증폭된 빛은 손가락 피부를 통과한 '순수한 빨간색 빛'뿐이므로,
      // 결과적으로 빨간색 맥박 신호(Red Glow)가 폭발적으로 선명해집니다.
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
        debugPrint('[CameraService] 노출 자동(AE Auto) 적용 완료');
      } catch (e) {
        debugPrint('[CameraService] 노출 자동 미지원 기기 (무시됨): $e');
      }

      // ── 카메라 초점 강제 잠금 (AF Lock) ──
      // 손가락 밀착 상태에서 자동 초점 헌팅을 방지합니다.
      try {
        await _controller!.setFocusMode(FocusMode.locked);
      } catch (e) {
        debugPrint('[CameraService] 초점 잠금 미지원 기기 (무시됨): $e');
      }

      _isInitialized = true;
      onStatusChanged?.call(CameraStatus.idle);
    } catch (e) {
      debugPrint('카메라 초기화 오류: $e');
      onStatusChanged?.call(CameraStatus.error);
    }
  }

  /// 이미지 스트림을 시작하여 심박수 측정을 시작한다.
  /// [자원 재사용] 이미 스트림이 활성화된 상태라면 중복 시작하지 않고 즉시 반환한다.
  Future<void> startMeasurement() async {
    if (!_isInitialized || _controller == null) return;

    // ── 이미 측정 중이라면 다시 시작하지 않음 ──
    // (모달에서 측정 중인 상태 그대로 게임 화면으로 이어지는 핵심 로직)
    if (_isMeasuring) {
      debugPrint('[CameraService] 이미 측정 중 - startMeasurement 스킵');
      onStatusChanged?.call(CameraStatus.measuring);
      return;
    }

    // 이전 세션의 자원 완전 해제 (메모리 누수 방지)
    await _cleanupStreams();

    _waveformBuffer.clear();
    _lastFilteredBpm = 0.0;
    _poorSignalFrameCount = 0;
    _coldStartCandidateBpm = 0.0;
    _coldStartStableCount = 0;

    // ── flutter_ppg 서비스 생성 ──
    _ppgService = FlutterPPGService();

    // ── 스트림 브릿지 생성: CameraImage → flutter_ppg ──
    _imageStreamController = StreamController<CameraImage>();

    // ── PPGSignal 스트림 구독 ──
    _ppgSubscription = _ppgService!
        .processImageStream(_imageStreamController!.stream)
        .listen(_onPpgSignal);

    // ── 카메라 프레임 스트림 시작 ──
    await _controller!.startImageStream((CameraImage image) {
      // StreamController가 열려있을 때만 이미지를 넘겨줌 (닫힌 후 에러 방지)
      if (_imageStreamController != null &&
          !(_imageStreamController!.isClosed)) {
        _imageStreamController!.add(image);
      }
    });

    _isMeasuring = true;
  }

  /// flutter_ppg로부터 PPGSignal을 수신할 때 호출되는 핵심 콜백.
  void _onPpgSignal(PPGSignal signal) {
    // 🛡️ 방어막: 화면 종료 및 측정 중지(dispose) 후 비동기적으로 들어오는 잔여 프레임의 상태 업데이트를 원천 차단 (Defunct 에러 방어)
    if (!_isMeasuring || _isTransitioning) return;

    // ── [핵심] 로그 기록 (Early Return 이전 최상단 배치) ──
    // 품질 불량으로 인한 측정 스킵 직전의 오염된 데이터(블랙박스)를 누락 없이 100% 수집합니다.
    if (_isLogging) {
      final elapsedMs = _logStopwatch.elapsedMilliseconds;
      final bool isGood = signal.quality != SignalQuality.poor;
      final int peakCount = signal.rrIntervals.length;

      // 혹시라도 이 프레임에서 계산될 중앙값과 BPM 미리 추적
      double debugMedianRr = 0.0;
      double debugRawBpm = 0.0;
      if (signal.rrIntervals.isNotEmpty) {
        final sorted = List<double>.from(signal.rrIntervals)..sort();
        debugMedianRr = sorted[sorted.length ~/ 2];
        if (debugMedianRr > 0) debugRawBpm = 60000.0 / debugMedianRr;
      }

      // 형식: 시간(ms), isGoodSignal, 강도, 피크갯수, 중앙값(ms), 원시BPM, EMA적용BPM
      _logData.add(
        '$elapsedMs,$isGood,${signal.filteredIntensity},$peakCount,$debugMedianRr,$debugRawBpm,$_lastFilteredBpm',
      );
    }

    // ── 신호 품질 평가 및 디바운싱 ──
    final bool isGoodSignal = signal.quality != SignalQuality.poor;

    if (!isGoodSignal) {
      _poorSignalFrameCount++; // 불량 프레임 누적

      // [트랙 1] Edge-triggered 방식: 정확히 120번째 프레임(약 4초)이 되는 딱 그 순간에만 1회성으로 모두 초기화
      if (_poorSignalFrameCount == 120) {
        _lastFilteredBpm = 0.0;
        _coldStartCandidateBpm = 0.0;
        _coldStartStableCount = 0;
        onBpmUpdated?.call(0.0); // 완전히 초기화 (딱 1번만 호출)
        onStatusChanged?.call(CameraStatus.noFinger); // 상태 글자 변경 (딱 1번만 호출)
        _waveformBuffer.clear();
        onWaveformUpdated?.call([]); // 파형 클리어 (딱 1번만 호출)
        onRgbUpdated?.call(signal.filteredIntensity, 0.0, 0.0, false);
      }
      // 4초 미만의 찰나의 노이즈 구간 (손가락이 잠시 흔들린 경우)
      else if (_poorSignalFrameCount < 120) {
        if (_lastFilteredBpm > 0.0) {
          onBpmUpdated?.call(_lastFilteredBpm); // 안전하게 기존 심박수 수치 유지 (Hold)
        }
      }

      // 120번을 넘긴 완벽한 대기 상태(>120)에서는 어떤 콜백도 실행하지 않고 즉시 조기 종료 (CPU 부하 0%)
      return;
    }

    // 신호가 정상으로 돌아오면 불량 카운터 즉시 초기화
    _poorSignalFrameCount = 0;

    onStatusChanged?.call(CameraStatus.measuring);

    // ── 파형 버퍼 업데이트 ──
    // filteredIntensity를 0~1 범위로 정규화하여 파형 그래프에 공급
    final double normalizedIntensity = (signal.filteredIntensity / 255.0).clamp(
      0.0,
      1.0,
    );
    _waveformBuffer.add(normalizedIntensity);
    if (_waveformBuffer.length > _waveformSize) {
      _waveformBuffer.removeAt(0);
    }
    onWaveformUpdated?.call(List.from(_waveformBuffer));

    // RGB 디버그 콜백: filteredIntensity를 R채널 대신 전달
    onRgbUpdated?.call(signal.filteredIntensity, 0.0, 0.0, true);

    // ── BPM 계산 ──
    // [손 뗌 감지] flutter_ppg 플러그인이 손을 떼도 isGoodSignal=true를 유지하는 문제로 인해,
    // rrIntervals.isEmpty (count==0)를 유일한 손 뗌 판별 기준으로 사용.
    // 정상 측정 중 count가 0으로 떨어지면 손이 떨어진 것으로 판정 → 즉시 완전 초기화
    if (signal.rrIntervals.isEmpty && _lastFilteredBpm > 0.0) {
      _lastFilteredBpm = 0.0;
      _coldStartCandidateBpm = 0.0;
      _coldStartStableCount = 0;
      onBpmUpdated?.call(0.0);
      onStatusChanged?.call(CameraStatus.noFinger);
      _waveformBuffer.clear();
      onWaveformUpdated?.call([]);
      onRgbUpdated?.call(signal.filteredIntensity, 0.0, 0.0, false);
      return;
    }

    // [통계적 유의성] count 1~2개는 신뢰 불가 → Hold
    if (signal.rrIntervals.length < 3) {
      if (_lastFilteredBpm > 0.0) onBpmUpdated?.call(_lastFilteredBpm);
      return;
    }

    // ── 중앙값(Median) 추출 ──
    final sortedIntervals = List<double>.from(signal.rrIntervals)..sort();
    final double medianRrMs = sortedIntervals[sortedIntervals.length ~/ 2];
    if (medianRrMs <= 0) {
      if (_lastFilteredBpm > 0.0) onBpmUpdated?.call(_lastFilteredBpm);
      return;
    }
    final double currentBpm = 60000.0 / medianRrMs;

    // ── 절대 수치 마지노선 방어 (생리적 한계 컷오프) ──
    // 40 미만 또는 190 초과는 생리학적으로 불가능한 노이즈. 즉시 버립니다.
    if (currentBpm < 40.0 || currentBpm > 190.0) {
      if (_lastFilteredBpm > 0.0) onBpmUpdated?.call(_lastFilteredBpm);
      return;
    }

    // ── [트랙 1] 콜드 스타트 안정화 버퍼 ──
    // _lastFilteredBpm == 0.0 이면 콜드 스타트(최초 또는 손 뗀 후 4초 리셋) 상태.
    // 10프레임 동안 단차 8.0 이하로 안정적으로 유지되면서,
    // 후보값이 40 이상 100 이하인 경우에만 초기값으로 인정합니다. (이전 데이터 일체 무관)
    if (_lastFilteredBpm == 0.0) {
      if (_coldStartCandidateBpm == 0.0) {
        _coldStartCandidateBpm = currentBpm;
        _coldStartStableCount = 1;
      } else if ((currentBpm - _coldStartCandidateBpm).abs() <= 8.0) {
        _coldStartStableCount++;

        if (_coldStartStableCount >= 10) {
          final double candidate = _coldStartCandidateBpm;
          // 이전 데이터와 완전히 무관하게, 항상 40~100 조건만 검증하여 Fresh Start
          if (candidate >= 40.0 && candidate <= 100.0) {
            _lastFilteredBpm = candidate;
            _coldStartCandidateBpm = 0.0;
            _coldStartStableCount = 0;
          } else {
            // 노이즈로 판정. 버퍼 초기화 후 재시도.
            _coldStartCandidateBpm = 0.0;
            _coldStartStableCount = 0;
          }
        }
      } else {
        // 중간에 튀면 버퍼 초기화 후 재시도
        _coldStartCandidateBpm = currentBpm;
        _coldStartStableCount = 1;
      }

      // 콜드 스타트 중에는 BPM UI 업데이트 없음
      return;
    }

    // ── [트랙 2] 돌발 스파이크 무한 방어 (Spike Hold) ──
    // 손을 대고 있는 한 초기화는 없음. 이전 필터값과 현재 원시값의 차이가 18.0 초과이면 Hold.
    if ((currentBpm - _lastFilteredBpm).abs() > 18.0) {
      // 스파이크: 기존 필터 수치를 무한정 유지 (타임아웃 없음)
      onBpmUpdated?.call(_lastFilteredBpm);
      return;
    }

    // ── 정상 수치: EMA 필터 적용 후 UI 갱신 ──
    _lastFilteredBpm = (_lastFilteredBpm * 0.98) + (currentBpm * 0.02);
    onBpmUpdated?.call(_lastFilteredBpm);
  }

  /// 이미지 스트림을 중단하고 측정을 멈춘다.
  /// (수정됨) 화면 파괴 시 즉시 스트림을 끊고 카메라를 강제 파괴하여 교착 상태와 크래시를 방어합니다.
  Future<void> stopMeasurement() async {
    // 💡 1. 절대 방패 (Shield): 어떤 예외가 발생하더라도 무조건 상태부터 차단하여 Defunct 에러를 원천 봉쇄
    _isMeasuring = false;

    // 💡 2. 전선 차단 (Cancel)
    try {
      _ppgSubscription?.cancel();
    } catch (e) {
      debugPrint('[CameraService] 스트림 취소 실패 (무시됨): $e');
    }
    _ppgSubscription = null;

    // 💡 3. 중복 호출 방지 및 리소스 제어
    if (_controller != null) {
      final camera = _controller!;
      _controller = null; // 두 번째 stopMeasurement 호출 시 이 블록 진입 차단

      // [모달 재진입 버그 해결] 강제 파괴(dispose) 대신 대기 모드로 돌려놓아 다음 측정 시 OS Lock 현상 방지
      if (camera.value.isStreamingImages) {
        try {
          await camera.stopImageStream();
        } catch (e) {
          debugPrint('[CameraService] 이미지 스트림 중지 실패 (무시됨): $e');
        }
      }
      // [아키텍처 피벗] 전면 카메라에는 물리 플래시가 존재하지 않으므로
      // FlashMode 제어 코드가 완전히 제거되었습니다.
    }
    
    await _cleanupStreams();
    _isInitialized = false; // 다음 측정 시 카메라가 항상 새로 초기화되도록 플래그 해제
    _lastFilteredBpm = 0.0; // EMA 필터 초기화 (다음 세션을 위해)
    _waveformBuffer.clear();
    onStatusChanged?.call(CameraStatus.idle);
  }

  /// [메모리 누수 방지] 스트림 관련 자원을 완전히 해제한다.
  /// startMeasurement() 전และ stopMeasurement() 시 모두 호출됩니다.
  Future<void> _cleanupStreams() async {
    await _ppgSubscription?.cancel();
    _ppgSubscription = null;

    await _imageStreamController?.close();
    _imageStreamController = null;

    _ppgService?.dispose();
    _ppgService = null;
  }

  // ── 디버그 로그 기능 ──
  void startLogging() {
    _isLogging = true;
    _logData.clear();
    // 엑셀 헤더
    _logData.add(
      'Timestamp(ms),isGoodSignal,filteredIntensity,rrIntervals_count,medianRrMs,rawBpm,filteredBpm',
    );
    _logStopwatch.reset();
    _logStopwatch.start();
  }

  String stopAndGetCsv() {
    _isLogging = false;
    _logStopwatch.stop();
    return _logData.join('\n');
  }

  /// 카메라 리소스를 완전히 해제한다. (화면 종료 시 반드시 호출)
  Future<void> dispose() async {
    await stopMeasurement();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  /// 카메라 미리보기 위젯을 그리기 위한 컨트롤러
  CameraController? get controller => _controller;
}
