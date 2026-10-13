// 카메라 PPG 측정 장치
// 기존 CameraService(측정 알고리즘 그대로)를 HeartRateSource 모양으로 감싸는 '어댑터'.

import 'dart:async';
import 'camera_service.dart';
import 'heart_rate_source.dart';

class CameraPpgSource implements HeartRateSource {
  final CameraService _camera = CameraService();
  final StreamController<HeartReading> _controller =
      StreamController<HeartReading>.broadcast();

  double _bpm = 0;
  CameraStatus _status = CameraStatus.idle;

  CameraPpgSource() {
    _camera.onBpmUpdated = (bpm) {
      _bpm = bpm;
      _emit();
    };
    _camera.onStatusChanged = (status) {
      _status = status;
      if (status == CameraStatus.noFinger) _bpm = 0;
      _emit();
    };
  }

  @override
  HeartSourceKind get kind => HeartSourceKind.cameraPpg;

  @override
  bool get isAvailable => true;

  @override
  Stream<HeartReading> get readings => _controller.stream;

  /// CameraService 상태 → 공통 신호 상태로 변환
  void _emit() {
    final signal = switch (_status) {
      CameraStatus.idle => HeartSignal.idle,
      CameraStatus.initializing => HeartSignal.preparing,
      // 손가락은 닿았지만 콜드스타트(안정화) 중이면 bpm이 0 → 준비 중으로 표시
      CameraStatus.measuring => _bpm > 0 ? HeartSignal.measuring : HeartSignal.preparing,
      CameraStatus.noFinger => HeartSignal.lost,
      CameraStatus.error => HeartSignal.error,
    };
    if (!_controller.isClosed) {
      _controller.add(HeartReading(bpm: _bpm, signal: signal));
    }
  }

  @override
  Future<void> start() async {
    _camera.setTransitioning(false);
    await _camera.initialize();
    await _camera.startMeasurement();
  }

  @override
  Future<void> stop() async {
    await _camera.stopMeasurement();
    _bpm = 0;
    _status = CameraStatus.idle;
    _emit();
  }

  @override
  Future<void> dispose() async {
    await _camera.dispose();
    await _controller.close();
  }
}
