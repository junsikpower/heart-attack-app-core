// ── 멀티플레이 방 관리 & 심박수 동기화 인터페이스 ──
// 구현체: FirebaseMultiplayerServiceImpl
// 이 인터페이스에만 의존하여 코딩하므로, 나중에 자체 서버로 교체 시
// 이 파일을 implement하는 새 구현체만 만들면 UI 코드는 전혀 수정 불필요.

abstract class IMultiplayerRepository {
  // 현재 연결된 상대방 심박수를 실시간으로 받는 스트림
  Stream<int> get opponentBpmStream;

  // 현재 방 ID (null이면 미접속)
  String? get currentRoomId;

  // 방 생성 (내가 호스트) → 생성된 방 코드(6자리) 반환
  Future<String> createRoom(String myUserId);

  // 방 참가 (상대방이 만든 방 코드 입력)
  Future<void> joinRoom(String roomCode, String myUserId);

  // 내 심박수를 상대방과 동기화 (게임 루프에서 주기적으로 호출)
  Future<void> pushMyBpm(int bpm);

  // 방 퇴장 및 연결 종료
  Future<void> leaveRoom();
}
