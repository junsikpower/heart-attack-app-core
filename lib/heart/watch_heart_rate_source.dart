// 스마트워치 측정 장치 (자리만 마련, 아직 미구현)
//
// 구현 시 후보 경로 (기기별로 하나씩 HeartRateSource 구현체를 추가하면 된다):
//   1) BLE 표준 심박 프로필 (Heart Rate Service 0x180D)
//      - 가민/폴라/샤오미 밴드 등 '심박 브로드캐스트'를 지원하는 기기. 가장 범용적.
//   2) Wear OS (갤럭시 워치 등) — 워치용 동반 앱이 Health Services로 측정 → Data Layer로 폰에 전송
//   3) Apple Watch — watchOS 동반 앱의 HKWorkoutSession 실시간 심박 → WatchConnectivity로 폰에 전송
//
// 어떤 경로든 결과를 HeartReading(bpm, signal) 스트림으로만 내보내면
// 게임 규칙/멀티플레이 코드는 한 줄도 바꾸지 않고 워치로 플레이할 수 있다.

import 'heart_rate_source.dart';

class WatchHeartRateSource implements HeartRateSource {
  @override
  HeartSourceKind get kind => HeartSourceKind.watch;

  /// 아직 연동 전이므로 항상 사용 불가
  @override
  bool get isAvailable => false;

  @override
  Stream<HeartReading> get readings => const Stream.empty();

  @override
  Future<void> start() async {
    throw UnsupportedError('스마트워치 연동은 준비 중입니다.');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
