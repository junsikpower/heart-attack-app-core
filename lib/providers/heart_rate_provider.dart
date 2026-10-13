// 심박수 전역 상태 (Heart Rate Provider)
// 역할: 현재 선택된 측정 장치(카메라/워치)의 측정값을 앱 전체에 공유한다.
// 화면과 게임 로직은 이 provider만 보며, 측정 장치가 무엇인지 신경 쓰지 않는다.

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../heart/camera_ppg_source.dart';
import '../heart/heart_rate_source.dart';
import '../heart/watch_heart_rate_source.dart';

/// 사용 가능한 측정 장치 목록 (워치는 연동 전이라 isAvailable=false)
final heartSourcesProvider = Provider<Map<HeartSourceKind, HeartRateSource>>((ref) {
  final sources = {
    HeartSourceKind.cameraPpg: CameraPpgSource(),
    HeartSourceKind.watch: WatchHeartRateSource(),
  };
  ref.onDispose(() {
    for (final s in sources.values) {
      s.dispose();
    }
  });
  return sources;
});

/// 지금 사용하는 측정 장치 (기본: 카메라)
final heartSourceKindProvider = StateProvider<HeartSourceKind>(
  (ref) => HeartSourceKind.cameraPpg,
);

@immutable
class HeartRateState {
  final HeartReading reading;
  final HeartSourceKind source;
  final bool isMeasuring;

  const HeartRateState({
    this.reading = HeartReading.idle,
    this.source = HeartSourceKind.cameraPpg,
    this.isMeasuring = false,
  });

  double get bpm => reading.bpm;
  HeartSignal get signal => reading.signal;
  bool get isValid => reading.isValid;

  HeartRateState copyWith({HeartReading? reading, HeartSourceKind? source, bool? isMeasuring}) =>
      HeartRateState(
        reading: reading ?? this.reading,
        source: source ?? this.source,
        isMeasuring: isMeasuring ?? this.isMeasuring,
      );
}

class HeartRateNotifier extends StateNotifier<HeartRateState> with WidgetsBindingObserver {
  HeartRateNotifier(this._ref) : super(const HeartRateState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;
  StreamSubscription<HeartReading>? _sub;
  HeartRateSource? _active;

  /// 측정 시작 (이미 측정 중이면 그대로 유지)
  Future<void> start() async {
    if (state.isMeasuring) return;
    final kind = _ref.read(heartSourceKindProvider);
    final source = _ref.read(heartSourcesProvider)[kind]!;
    _active = source;
    await _sub?.cancel();
    _sub = source.readings.listen((r) {
      if (mounted) state = state.copyWith(reading: r);
    });
    state = state.copyWith(
      source: kind,
      isMeasuring: true,
      reading: const HeartReading(signal: HeartSignal.preparing),
    );
    try {
      await source.start();
    } catch (e) {
      debugPrint('[HeartRate] 측정 시작 실패: $e');
      if (mounted) {
        state = state.copyWith(reading: const HeartReading(signal: HeartSignal.error));
      }
    }
  }

  /// 측정 종료 (플래시도 함께 꺼짐)
  Future<void> stop() async {
    if (!state.isMeasuring) return;
    state = state.copyWith(isMeasuring: false, reading: HeartReading.idle);
    await _sub?.cancel();
    _sub = null;
    await _active?.stop();
    _active = null;
  }

  // 앱이 백그라운드로 가면 카메라/플래시를 즉시 끈다 (발열·배터리 보호)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Android는 hidden → paused 순서로 두 번 알려주므로, 첫 번째 기록을 덮어쓰지 않는다
      if (this.state.isMeasuring) _wasMeasuringBeforePause = true;
      stop();
    } else if (state == AppLifecycleState.resumed && _wasMeasuringBeforePause) {
      _wasMeasuringBeforePause = false;
      start();
    }
  }

  bool _wasMeasuringBeforePause = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _active?.stop();
    super.dispose();
  }
}

final heartRateProvider = StateNotifierProvider<HeartRateNotifier, HeartRateState>(
  (ref) => HeartRateNotifier(ref),
);
