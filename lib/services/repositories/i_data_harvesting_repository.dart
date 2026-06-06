// ── 데이터 하베스팅(수집) 인터페이스 ──
// 구현체: FirestoreDataHarvestingServiceImpl
// Firestore를 쓰든, 자체 DB를 쓰든 이 인터페이스를 implement하면 됨.

abstract class IDataHarvestingRepository {
  // 하베스팅 시작 (통화 시작 시 호출)
  // roomId: 어떤 방의 데이터인지 식별자
  // myUserId: 내 사용자 ID
  // opponentBpmGetter: 매 저장 시점마다 상대방 현재 BPM을 가져오는 콜백
  Future<void> startHarvesting({
    required String roomId,
    required String myUserId,
    required int Function() myBpmGetter,
    required int Function() opponentBpmGetter,
  });

  // 하베스팅 중지 (통화 종료 시 호출)
  Future<void> stopHarvesting();

  // 한 발화 세트를 수동으로 즉시 저장 (내부적으로 STT finalResult 시 호출됨)
  // [텍스트, 내BPM, 상대BPM, 타임스탬프]
  Future<void> saveConversationLog({
    required String roomId,
    required String myUserId,
    required String spokenText,
    required int myBpm,
    required int opponentBpm,
    required DateTime timestamp,
  });
}
