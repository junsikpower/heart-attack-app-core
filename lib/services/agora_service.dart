import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'repositories/i_voice_chat_repository.dart';

class AgoraVoiceChatServiceImpl implements IVoiceChatRepository {
  RtcEngine? _engine;
  bool _muted = false;
  
  bool _isInitialized = false;
  Future<void>? _initFuture;
  String? _currentChannelId;
  Future<void>? _joinFuture; 

  @override
  bool get isMuted => _muted;

  // ── 1. 엔진 초기화 ──
  Future<void> _initializeEngine(String appId) {
    _initFuture ??= _doInitializeEngine(appId);
    return _initFuture!;
  }

  Future<void> _doInitializeEngine(String appId) async {
    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(appId: appId));
      await _engine!.enableAudio();
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      
      // [수정] 타이밍 충돌을 일으키는 setEnableSpeakerphone 대신, 초기화 단계에서 글로벌 스피커폰 경로 고정
      await _engine!.setDefaultAudioRouteToSpeakerphone(true); 

      _isInitialized = true;
    } catch (e) {
      _initFuture = null;
      _isInitialized = false;
      rethrow;
    }
  }

  // ── 2. 채널 입장 브릿지 ──
  @override
  Future<void> joinChannel(String roomId) async {
    if (_joinFuture != null) return _joinFuture!;
    
    _joinFuture = _doJoinChannel(roomId);
    try {
      await _joinFuture;
    } finally {
      _joinFuture = null;
    }
  }

  // ── 2-A. 실제 채널 입장 로직 ──
  Future<void> _doJoinChannel(String roomId) async {
    final appId = dotenv.env['AGORA_APP_ID'] ?? '';
    if (appId.isEmpty) throw Exception('AGORA_APP_ID가 없습니다.');

    if (_currentChannelId != null) {
      if (_currentChannelId == roomId) {
        debugPrint('[AgoraService] 이미 방 $roomId 에 입장해 있으므로 스킵합니다.');
        return;
      } else {
        // [데드락 완벽 해결] 내부 로직에서는 대기가 없는 순수 퇴장 함수를 호출하여 순환 의존성 파괴
        await _pureLeaveChannel(); 
      }
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('마이크 권한이 거부되었습니다. 통화를 위해 설정에서 권한을 허용해주세요.');
    }

    if (!_isInitialized) {
      await _initializeEngine(appId);
    }

    await _engine!.joinChannel(
      token: '',
      channelId: roomId,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishCameraTrack: false,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
      ),
    );

    // 🚫 [원인 제거] 네이티브 -3 크래시를 유발하여 아래 코드 실행을 막던 범인을 제거함
    // await _engine!.setEnableSpeakerphone(true);

    // 이제 크래시 없이 무조건 도달하므로 상태 변경이 안전하게 보장됨 (연쇄 -17 에러 봉쇄)
    _currentChannelId = roomId;
  }

  // ── 3. 공용 채널 퇴장 (UI 등 외부 호출 시) ──
  @override
  Future<void> leaveChannel() async {
    // 유저가 외부에서 입장 취소를 요청할 때만 대기하여 고스트 커넥션을 방어함
    if (_joinFuture != null) {
      try {
        await _joinFuture;
      } catch (_) {}
    }
    await _pureLeaveChannel();
  }

  // ── 3-A. 내부 전용 순수 퇴장 로직 (대기 없음) ──
  Future<void> _pureLeaveChannel() async {
    if (_engine == null || _currentChannelId == null) return;
    await _engine!.leaveChannel();
    _currentChannelId = null;
    _muted = false;
  }

  @override
  Future<void> toggleMute() async {
    _muted = !_muted;
    await _engine?.muteLocalAudioStream(_muted);
  }

  @override
  Future<void> dispose() async {
    await leaveChannel();
    await _engine?.release();
    _engine = null;
    _isInitialized = false;
    _initFuture = null;
  }
}
