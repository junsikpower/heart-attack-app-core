// 심박 측정 장치 추상화 (Heart Rate Source)
// 게임은 '어디서 측정했는지'를 몰라도 되도록, 모든 측정 장치를 같은 모양(HeartReading 스트림)으로 맞춘다.
//
//   [카메라 PPG]  CameraPpgSource  ─┐
//   [스마트워치]   WatchHeartRateSource ─┼─▶ HeartRateSource ─▶ heartRateProvider ─▶ 게임
//   [(미래) BLE 밴드 등]             ─┘
//
// 새 장치를 붙일 때는 HeartRateSource를 구현하는 클래스 하나만 추가하면 되고,
// 게임 규칙/화면/멀티플레이 코드는 수정할 필요가 없다.

import 'package:flutter/material.dart';

/// 측정 장치 종류
enum HeartSourceKind { cameraPpg, watch }

extension HeartSourceKindLabel on HeartSourceKind {
  String get label => switch (this) {
    HeartSourceKind.cameraPpg => '카메라',
    HeartSourceKind.watch => '스마트워치',
  };

  IconData get icon => switch (this) {
    HeartSourceKind.cameraPpg => Icons.camera_rounded,
    HeartSourceKind.watch => Icons.watch_rounded,
  };
}

/// 측정 신호 상태
enum HeartSignal {
  idle, // 측정 꺼짐
  preparing, // 켜는 중 / 손가락은 닿았지만 아직 숫자를 계산하는 중
  measuring, // 정상 측정 중 (bpm 유효)
  lost, // 신호 없음 (손가락을 뗌 / 워치 연결 끊김)
  error, // 장치 오류
}

/// 측정 결과 한 건
@immutable
class HeartReading {
  final double bpm; // 0이면 아직 값 없음
  final HeartSignal signal;

  const HeartReading({this.bpm = 0, this.signal = HeartSignal.idle});

  /// 게임 점수에 써도 되는 값인지
  bool get isValid => signal == HeartSignal.measuring && bpm > 0;

  static const idle = HeartReading();
}

/// 모든 측정 장치가 지켜야 하는 약속
abstract class HeartRateSource {
  HeartSourceKind get kind;

  /// 이 기기에서 사용할 수 있는지 (예: 워치 미연결이면 false)
  bool get isAvailable;

  /// 실시간 측정값 스트림
  Stream<HeartReading> get readings;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
