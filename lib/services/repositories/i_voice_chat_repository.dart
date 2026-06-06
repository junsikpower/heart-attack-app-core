// ── 음성 통화 인터페이스 ──
// 구현체: AgoraVoiceChatServiceImpl
// Agora를 쓰든, WebRTC 자체 서버를 쓰든 이 인터페이스를 implement하면 됨.

abstract class IVoiceChatRepository {
  // 통화 채널 입장 (roomId를 채널명으로 사용)
  Future<void> joinChannel(String roomId);

  // 통화 채널 퇴장
  Future<void> leaveChannel();

  // 마이크 음소거 토글
  Future<void> toggleMute();

  // 현재 음소거 상태
  bool get isMuted;

  // ── 객체지향 설계를 위한 리소스 완전 해제 명세 ──
  Future<void> dispose();
}
